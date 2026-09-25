(* The whole node: receive path -> match-and-rewrite engine -> transmit feeder -> sequencer
   firmware (tx_fw.ml) on the sequencer RTL, co-simulated clock by clock.

   The transmit feeder is the hardware counterpart of Tx_fw's reference feeder: a fixed bit
   permutation of the transmit buffer (preamble and SFD generated, the frame and FCS read), handed
   to each thread at its IN, plus the [start] and [end_t] pins. It also defers to the line: it
   raises [start] only after the receiver has seen no carrier for 9.6 us (half duplex, as a link
   partner without autonegotiation will run). [start] changes only when the next clock is a
   multiple of 4, so the four threads read it in the same round. *)
open Hardcaml
open Signal

let ipg_clocks = 576   (* 9.6 us at 60 MHz *)

type feeder_out = { host_in : Signal.t; host_in_valid : Signal.t; pin_in : Signal.t; tx_done : Signal.t; tx_raddr : Signal.t array }

let feeder ~clock ~clear ~tx_ready ~tx_len ~tx_rdata ~host_in_ready ~carrier ~tx_raddr_w =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let phase = Variable.reg spec ~width:2 in
  let active = Variable.reg spec ~width:1 and start = Variable.reg spec ~width:1 and ends = Variable.reg spec ~width:4 in
  let m = Array.init 4 (fun _ -> Variable.reg spec ~width:9) in
  let quiet = Variable.reg spec ~width:10 in
  let host_in = Variable.reg spec ~width:8 and host_in_valid = Variable.reg spec ~width:1 in
  let tx_done = Variable.wire ~default:gnd in
  let w = tx_len +:. 8 in                     (* wire bytes: preamble, SFD, frame, FCS *)
  let g = w +:. 2 in                          (* groups (bytes) per thread, as Tx_fw.streams *)
  let tn = phase.value +:. 1 in               (* the thread that executes next clock *)
  let mn = mux tn (Array.to_list (Array.map (fun v -> v.Variable.value) m)) in
  (* wire bytes mn and mn - 1 *)
  let wire_byte idx data = mux2 (idx <:. 7) (of_int ~width:8 0x55) (mux2 (idx ==:. 7) (of_int ~width:8 0xD5) data) in
  tx_raddr_w.(0) <== (mn -:. 8);
  tx_raddr_w.(1) <== (mn -:. 9);
  let b_m = wire_byte mn tx_rdata.(0) and b_m1 = wire_byte (mn -:. 1) tx_rdata.(1) in
  let level ~use_prev ~r =
    (* (is_pos, is_neg) of half-bit r of wire byte (use_prev ? mn - 1 : mn) *)
    let idx = if use_prev then mn -:. 1 else mn in
    let byte = if use_prev then b_m1 else b_m in
    let neg_idx = if use_prev then mn ==:. 0 else gnd in
    let in_data = idx <: w and at_tp = (idx ==: w) &: of_bool (r < 6) in
    let v = bit byte (r / 2) in
    let first = r mod 2 = 0 in
    let pos = in_data &: (if first then ~:v else v) |: at_tp in
    let neg = in_data &: (if first then v else ~:v) in
    (pos &: ~:neg_idx, neg &: ~:neg_idx) in
  let byte_for t =
    let k0 = Tx_fw.k0 t in
    concat_lsb (List.concat (List.init 4 (fun i ->
        let c = k0 + (4 * i) in
        let half c = if c - 4 >= 0 then level ~use_prev:false ~r:(c - 4) else level ~use_prev:true ~r:(c + 12) in
        let p0, _ = half c and _, n1 = half (c + 1) in
        [ p0; n1 ]))) in
  let next_byte = mux tn (List.init 4 byte_for) in
  let t = phase.value in
  let mt = mux t (Array.to_list (Array.map (fun v -> v.Variable.value) m)) in
  compile
    [ phase <-- phase.value +:. 1
    ; quiet <-- mux2 carrier (zero 10) (mux2 (quiet.value ==:. 1023) quiet.value (quiet.value +:. 1))
    ; host_in <-- next_byte
    ; host_in_valid <-- (active.value &: (mn <: g))
    ; when_ ((phase.value ==:. 3) &: tx_ready &: ~:(active.value) &: (quiet.value >=:. ipg_clocks))
        [ active <-- vdd; start <-- vdd; proc (Array.to_list (Array.map (fun v -> v <--. 0) m)) ]
    ; when_ (host_in_ready &: active.value)
        [ when_ start.value [ start <-- gnd; ends <--. 0 ]
        ; proc (List.init 4 (fun k -> when_ (t ==:. k) [ m.(k) <-- m.(k).value +:. 1 ]))
        ; when_ ((mt +:. 1) ==: g) [ ends <-- (ends.value |: mux t (List.init 4 (fun k -> of_int ~width:4 (1 lsl k)))) ] ]
    ; (* done once every thread has had all its groups *)
      when_ (active.value &: ~:(start.value)
             &: (Array.fold_left (fun acc v -> acc &: (v.Variable.value ==: g)) vdd m))
        [ active <-- gnd; tx_done <-- vdd ] ];
  let pin_in = concat_msb [ ends.value; zero 3; start.value ] in
  { host_in = host_in.value; host_in_valid = host_in_valid.value; pin_in; tx_done = tx_done.value; tx_raddr = tx_raddr_w }

type counters = { drops : Signal.t array; replies : Signal.t }

let circuit ?(n = 1) ?(clock_hz = 60e6) () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let samples = input "samples" n and active = input "active" 1 in
  let cfg_in = input "cfg_in" 1 and cfg_shift = input "cfg_shift" 1 in
  let host_in_ready = input "host_in_ready" 1 in
  let scfg = Rx_path.eth_sampler_cfg ~clock_hz ~n in
  let rx = Rx_path.create ~clock ~clear ~n ~scfg ~samples ~active ~cfg_in ~cfg_shift () in
  let tx_raddr_w = [| wire 9; wire 9 |] in
  let tx_done_w = wire 1 in
  let e = Engine.create ~clock ~clear ~rx ~tx_raddr:tx_raddr_w ~tx_done:tx_done_w () in
  let f = feeder ~clock ~clear ~tx_ready:e.tx_ready ~tx_len:e.tx_len ~tx_rdata:e.tx_rdata ~host_in_ready ~carrier:rx.carrier ~tx_raddr_w in
  tx_done_w <== f.tx_done;
  Circuit.create_exn ~name:"eth10_node"
    ([ output "host_in" f.host_in; output "host_in_valid" f.host_in_valid; output "pin_in" f.pin_in;
       output "replies" e.replies; output "rx_frame_end" rx.frame_end; output "rx_frame_ok" rx.frame_ok ]
     @ Array.to_list (Array.mapi (fun k d -> output (Printf.sprintf "drop%d" k) d) e.drops))

(* ---- co-simulation ---- *)

type result = {
  runs : (int * int) list;             (* transmit differential, quarter clocks *)
  replies : int; drops : int array;
  rx_ends : (int * bool) list;         (* clock and ok of every received frame end *)
}

let simulate ?(n = 1) ?(clock_hz = 60e6) ?(mem = Array.init Isa.n_threads (fun t -> Tx_fw.program t)) ~cycles (bursts : Line.burst list) =
  let sim = Cyclesim.create (circuit ~n ~clock_hz ()) in
  let i nm = Cyclesim.in_port sim nm and o nm = Cyclesim.out_port sim nm in
  List.iter (fun b -> i "cfg_in" := Bits.of_int ~width:1 b; i "cfg_shift" := Bits.vdd; Cyclesim.cycle sim) (Model.cfg_bits (Rx_path.sfd_template ()));
  i "cfg_shift" := Bits.gnd;
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  let hs = Harness.make mem in
  let samples = Line.sample ~clock_hz ~n ~cycles bursts in
  let runs = ref [] and cur_lvl = ref 0 and cur_len = ref 0 in
  let push lvl = if lvl = !cur_lvl then incr cur_len else begin
      if !cur_len > 0 then runs := (!cur_lvl, !cur_len) :: !runs; cur_lvl := lvl; cur_len := 1 end in
  let rx_ends = ref [] in
  for c = 0 to cycles - 1 do
    let pin_in = Bits.to_int !(o "pin_in") and host_in = Bits.to_int !(o "host_in") and valid = Bits.to_int !(o "host_in_valid") = 1 in
    let so = Harness.cycle hs ~pin_in ~host_in ~host_in_valid:valid in
    let w, act = samples.(c) in
    i "samples" := Bits.of_int ~width:n w; i "active" := Bits.of_bool act;
    i "host_in_ready" := Bits.of_bool so.host_in_ready;
    Cyclesim.cycle sim;
    if Bits.to_int !(o "rx_frame_end") = 1 then rx_ends := (c, Bits.to_int !(o "rx_frame_ok") = 1) :: !rx_ends;
    for q = 0 to 3 do
      push (((so.pin_sub lsr q) land 1) - ((so.pin_sub lsr (4 + q)) land 1))
    done
  done;
  if !cur_len > 0 then runs := (!cur_lvl, !cur_len) :: !runs;
  { runs = List.rev !runs; replies = Bits.to_int !(o "replies");
    drops = Array.init 5 (fun k -> Bits.to_int !(o (Printf.sprintf "drop%d" k))); rx_ends = List.rev !rx_ends }
