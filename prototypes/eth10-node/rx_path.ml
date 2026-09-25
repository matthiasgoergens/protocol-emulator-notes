(* The 10BASE-T receive path, assembled from generic blocks rather than written as an Ethernet
   receiver:

     pins (n samples per clock) -> edge sampler (Manchester mode) -> bits
       -> systolic matcher (enable = bit valid) finds the 16-bit end of preamble + SFD
       -> a delay line compensates the matcher's latency
       -> byte packer (LSB first) and the CRC unit (CRC-32 residue check)
       -> bytes, frame end, frame ok, length

   Nothing here knows Ethernet except the configuration: the sampler's holdoff and timeout, the
   matcher's template, the packer's bit order and the CRC unit's catalogue entry. The same chain
   with other constants receives biphase-mark or NRZ framings (a USB packet: NRZ sampler, NRZI and
   unstuffing, matcher on SYNC, CRC-16; CAN: NRZ, unstuffing, CRC-15).

   The matcher raises its hit N + 1 = 17 enabled steps after the newest bit of the template enters,
   and the packer starts on the step after it sees the hit, so it reads the bit stream through a delay line of
   [delay] steps. At the end of a burst the delay line is flushed by [delay] extra steps. *)
open Hardcaml
open Signal

let delay = 18

(* template: the last 16 bits before the frame (0x55 then 0xD5, LSB first), newest first *)
let sfd_template ?(bits = 16) () =
  let wire = List.concat_map Eth_model.bits_of_byte [ 0x55; 0xD5 ] in
  let a = Array.of_list (List.rev wire) in   (* a.(0) = newest = last bit of the SFD *)
  { Model.t = Array.init Model.n (fun j -> a.(j)); m = Array.init Model.n (fun j -> if j < bits then 1 else 0); thr = bits }

(* sampler settings for 10BASE-T at [clock_hz] with n samples per clock: a mid-bit edge is at
   least 3/4 of a bit after the previous one; the burst ends 2 bit times after the last *)
let eth_sampler_cfg ~clock_hz ~n =
  let sub_ns = 1e9 /. clock_hz /. float n in
  { Edge_sampler.mode = Manchester; holdoff = int_of_float (Float.round (75.0 /. sub_ns)); timeout = int_of_float (200.0 /. sub_ns);
    offset = 0; period = 0; invert = false }

let crc32 = Crc_unit.cfg_of (List.hd Crc_unit.catalogue)

(* for planted-fault controls only *)
let sampler_override : (Edge_sampler.cfg -> Edge_sampler.cfg) option ref = ref None
let crc_override : Crc_unit.cfg option ref = ref None

let crc_consts (c : Crc_unit.cfg) =
  { Crc_unit.s_poly = of_int ~width:32 c.poly; s_init = of_int ~width:32 c.init; s_mask = of_int ~width:32 (Crc_unit.mask_of c.width);
    s_refl = of_bool c.reflected; s_xorout = of_int ~width:32 c.xorout; s_residue = of_int ~width:32 c.residue }

type outputs = { byte : Signal.t; byte_valid : Signal.t; frame_end : Signal.t; frame_ok : Signal.t; length : Signal.t;
                 overrun : Signal.t; carrier : Signal.t }

let create ?(d = delay) ~clock ~clear ~n ~scfg ~samples ~active ~cfg_in ~cfg_shift () =
  let spec = Reg_spec.create ~clock ~clear () in
  let scfg = match !sampler_override with Some f -> f scfg | None -> scfg in
  let bit, valid, burst_end, overrun, in_burst = Edge_sampler.create ~clock ~clear ~n ~cfg:(Edge_sampler.cfg_consts scfg) ~samples ~active in
  let open Always in
  let flush = Variable.reg spec ~width:6 in            (* flush steps remaining *)
  let flushing = flush.value <>:. 0 in
  let step = valid |: flushing in
  let x = valid &: bit in
  let _, hit = Matcher_en.create ~clock ~clear ~enable:step ~x ~cfg_in ~cfg_shift in
  (* delay line: dl.(k) holds the bit that entered k+1 steps ago *)
  let dl = Array.make (d + 1) gnd in
  let prev = ref x in
  for k = 0 to d do let r = reg spec ~enable:step !prev in dl.(k) <- r; prev := r done;
  let dbit = dl.(d - 1) in
  let synced = Variable.reg spec ~width:1 and shift = Variable.reg spec ~width:8 and cnt = Variable.reg spec ~width:3 in
  let length = Variable.reg spec ~width:12 and last_ok = Variable.reg spec ~width:1 and pending = Variable.reg spec ~width:1 in
  let crc_start = Variable.wire ~default:gnd and crc_valid = Variable.wire ~default:gnd in
  let byte_valid = Variable.wire ~default:gnd and frame_end = Variable.wire ~default:gnd and frame_ok = Variable.wire ~default:gnd in
  let ending = Variable.reg spec ~width:2 in
  let _, _, crc_check = Crc_unit.create ~clock ~clear ~cfg:(crc_consts (Option.value !crc_override ~default:crc32)) ~start:crc_start.value ~bit:dbit ~valid:crc_valid.value in
  let shifted = concat_msb [ dbit; select shift.value 7 1 ] in
  compile
    [ when_ pending.value [ last_ok <-- crc_check; pending <-- gnd ]
    ; when_ burst_end [ flush <--. d + 1 ]
    ; when_ flushing [ flush <-- flush.value -:. 1; when_ (flush.value ==:. 1) [ ending <--. 2 ] ]
    ; when_ (ending.value ==:. 2) [ ending <--. 1 ]   (* one more cycle for [pending] *)
    ; when_ (ending.value ==:. 1)
        [ ending <--. 0; when_ synced.value [ frame_end <-- vdd; frame_ok <-- last_ok.value ]; synced <-- gnd ]
    ; if_ (~:(synced.value))
        [ when_ (step &: hit &: ~:flushing) [ synced <-- vdd; crc_start <-- vdd; cnt <--. 0; length <--. 0; last_ok <-- gnd ] ]
        [ when_ step
            [ crc_valid <-- vdd; shift <-- shifted; cnt <-- cnt.value +:. 1
            ; when_ (cnt.value ==:. 7) [ byte_valid <-- vdd; length <-- length.value +:. 1; pending <-- vdd ] ] ] ];
  { byte = shifted; byte_valid = byte_valid.value; frame_end = frame_end.value; frame_ok = frame_ok.value; length = length.value;
    overrun; carrier = in_burst |: flushing |: (ending.value <>:. 0) }

let circuit ?d ~n ~scfg () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let samples = input "samples" n and active = input "active" 1 in
  let cfg_in = input "cfg_in" 1 and cfg_shift = input "cfg_shift" 1 in
  let o = create ?d ~clock ~clear ~n ~scfg ~samples ~active ~cfg_in ~cfg_shift () in
  Circuit.create_exn ~name:"eth_rx_path"
    [ output "rx_byte" o.byte; output "byte_valid" o.byte_valid; output "frame_end" o.frame_end; output "frame_ok" o.frame_ok;
      output "length" o.length; output "overrun" o.overrun; output "carrier" o.carrier ]
