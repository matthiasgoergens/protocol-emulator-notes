(* Circuits for synthesis: the generic parts of the platformer chip, each with its memories cut
   out as ports (they are gain-cell banks, sized separately). *)
open Hardcaml
open Signal

let pex ?(lean = false) () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let cfg_in = input "cfg_in" 8 and cfg_strobe = input "cfg_strobe" 1 in
  let tag = input "tag_in" 3 and data = input "data_in" 16 in
  let o = Pex.create ~lean ~clock ~clear ~cfg_in ~cfg_strobe ~tag ~data () in
  Circuit.create_exn ~name:(if lean then "pex_lean" else "pex")
    [ output "tag_out" o.tag; output "data_out" o.data; output "s" o.s; output "cfg_out" o.cfg_out ]

let feeder () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let line_go_n = input "line_go_n" 1 and rdata = input "rdata" Video.entry_bits and hw_en = input "hw_en" 1 in
  let go, rbank, rptr, tag, data = Video.feeder ~spec ~line_go_n ~rdata in
  let wptr = reg_fb spec ~width:Video.bank_bits ~f:(fun p -> mux2 go (zero Video.bank_bits) (mux2 hw_en (p +:. 1) p)) in
  Circuit.create_exn ~name:"feeder"
    [ output "raddr" (concat_msb [ rbank; rptr ]); output "waddr" (concat_msb [ ~:rbank; wptr ])
    ; output "tag" tag; output "data" data ]

(* the output port with the 64 x 14 table outside (read data in, write port out) *)
let outport () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let tag = input "tag" 3 and data = input "data" 16 and seq_pins = input "seq_pins" 8 in
  let entry = input "lut_rdata" 14 in
  let open Always in
  let in_rec = Variable.reg spec ~width:1 and waddr = Variable.reg spec ~width:6 in
  let idx = Variable.reg spec ~width:6 and hold = Variable.reg spec ~width:4 in
  let kind = select tag 1 0 in
  let rec1 = bit kind 1 &: bit tag 2 in
  let is_last = kind ==:. 3 in
  compile
    [ when_ rec1
        [ if_ in_rec.value [ waddr <-- waddr.value +:. 1; when_ is_last [ in_rec <-- gnd ] ]
            [ waddr <-- select data 5 0; in_rec <-- ~:is_last ] ]
    ; if_ (kind ==:. 1) [ idx <-- select data 5 0; hold <--. Video.period ]
        [ when_ (hold.value <>:. 0) [ hold <-- hold.value -:. 1 ] ] ];
  let burst = bit seq_pins 7 and vs = bit seq_pins 6 in
  let showing = hold.value <>:. 0 in
  let use = showing |: burst in
  let luma = mux2 showing (select entry 3 0) (select seq_pins 3 0) in
  let phase = select entry 11 4 in
  let phase = mux2 vs (of_int ~width:8 Video.reflect -: phase) phase in
  let acc = reg_fb spec ~width:32 ~f:(fun a -> a +:. Video.nco_inc) in
  let level = ~:(msb (acc +:. Video.nco_acc0 +: concat_msb [ phase; zero 24 ])) in
  Circuit.create_exn ~name:"outport"
    [ output "pins" (reg spec (concat_msb [ use &: bit entry 13; use &: bit entry 12; level; luma ]))
    ; output "lut_raddr" (mux2 burst (ones 6) idx.value); output "lut_waddr" waddr.value
    ; output "lut_we" (rec1 &: in_rec.value); output "lut_wdata" (select data 13 0) ]

(* the special-purpose console, for a like-for-like comparison *)
let all = [ "retro_console", Console.circuit; "deadline_sequencer", Sequencer.circuit; "pex", pex ~lean:false; "pex_lean", pex ~lean:true; "pex_row18", Pex.row 18; "feeder", feeder; "outport", outport ]

let write name =
  let c = (List.assoc name all) () in
  (try Unix.mkdir "rtl" 0o755 with _ -> ());
  let oc = open_out (Printf.sprintf "rtl/%s.v" name) in
  Rtl.output ~output_mode:(To_channel oc) Verilog c; close_out oc
