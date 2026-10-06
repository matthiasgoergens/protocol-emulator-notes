(* The chip core's RTL under Cyclesim, behind the specification's interface: [step] presents one
   clock's samples and returns the outputs as they were during that clock. *)
open Hardcaml

type t = {
  sim : Cyclesim.t_port_list;
  smp : Bits.t ref;
  reset : Bits.t ref;
  pad_nib : Bits.t ref;   (* before the edge *)
  uio_oe : Bits.t ref;
  after : string -> Bits.t ref;
}

let cache : (string * int array * int, Circuit.t) Hashtbl.t = Hashtbl.create 8

let circuit ?(cfg = Chip_spec.default_config) () =
  let key = (!Chip_rtl.bug, cfg.layout.start, cfg.prog_words) in
  match Hashtbl.find_opt cache key with
  | Some c -> c
  | None ->
    let c = Chip_rtl.circuit ~cfg () in
    Hashtbl.replace cache key c;
    c

let create ?cfg () =
  let sim = Cyclesim.create (circuit ?cfg ()) in
  let i n = Cyclesim.in_port sim n in
  { sim; smp = i "smp"; reset = i "reset";
    pad_nib = Cyclesim.out_port ~clock_edge:Before sim "pad_nib";
    uio_oe = Cyclesim.out_port ~clock_edge:Before sim "uio_oe";
    after = (fun n -> Cyclesim.out_port ~clock_edge:After sim n) }

let pack_smp smp = Bits.concat_lsb (Array.to_list (Array.map (fun v -> Bits.of_int ~width:4 v) smp))

let step t ~smp ~reset : Chip_spec.outputs =
  t.smp := pack_smp smp;
  t.reset := Bits.of_bool reset;
  Cyclesim.cycle_check t.sim;
  Cyclesim.cycle_before_clock_edge t.sim;
  let p = !(t.pad_nib) in
  let pad_nib = Array.init Regs.n_pads (fun i -> Bits.to_int (Bits.select p ((4 * i) + 3) (4 * i))) in
  let uio_oe = Bits.to_int !(t.uio_oe) in
  Cyclesim.cycle_at_clock_edge t.sim;
  Cyclesim.cycle_after_clock_edge t.sim;
  { pad_nib; uio_oe }

let get t n = Bits.to_int !(t.after n)
let get_bits t n = !(t.after n)
