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
  cov : (Cov.obs * Bits.t ref) option;
}

(* With [coverage] set (before the first [create]), every register bit's toggles are recorded, per
   circuit, in [cov_accs] (Cov); Cov.enable must have been called before the circuit is built. *)
let coverage = ref false

(* The register file's entries are made in one loop (chip_rtl.ml), so they share a source line:
   they are the first registers the core creates, one per Regs.rw_addresses entry, in order. *)
let label_regfile (infos : Cov.reg array) =
  let core = List.filter (fun (i : Cov.reg) -> i.file = "chip_rtl.ml") (Array.to_list infos) in
  match core with
  | [] -> infos
  | first :: _ ->
    let rf = List.filter (fun (i : Cov.reg) -> i.loc = first.loc) core in
    if List.length rf <> List.length Regs.rw_addresses then infos
    else
      let tbl = Hashtbl.create 128 in
      List.iteri (fun k (i : Cov.reg) -> Hashtbl.replace tbl i.uid (List.nth Regs.rw_addresses k)) rf;
      Cov.relabel infos (fun i -> Option.map (fun a -> (Printf.sprintf "reg%02x" a, 0)) (Hashtbl.find_opt tbl i.uid))

let cache : (string * int array * int * bool, Circuit.t * Cov.acc option) Hashtbl.t = Hashtbl.create 8

let circuit_cov ?(cfg = Chip_spec.default_config) () =
  let key = (!Chip_rtl.bug, cfg.layout.start, cfg.prog_words, !coverage) in
  match Hashtbl.find_opt cache key with
  | Some c -> c
  | None ->
    let c = Chip_rtl.circuit ~cfg () in
    let c = if !coverage then (let c', infos = Cov.instrument c in (c', Some (Cov.create_acc ~source:c (label_regfile infos)))) else (c, None) in
    Hashtbl.replace cache key c;
    c

let circuit ?cfg () = fst (circuit_cov ?cfg ())

(* the coverage accumulated so far for the design (no planted bug) at [cfg] *)
let coverage_acc ?(cfg = Chip_spec.default_config) () =
  match Hashtbl.find_opt cache ("", cfg.layout.start, cfg.prog_words, true) with Some (_, a) -> a | None -> None

let create ?cfg () =
  let c, acc = circuit_cov ?cfg () in
  let sim = Cyclesim.create c in
  let i n = Cyclesim.in_port sim n in
  { sim; smp = i "smp"; reset = i "reset";
    pad_nib = Cyclesim.out_port ~clock_edge:Before sim "pad_nib";
    uio_oe = Cyclesim.out_port ~clock_edge:Before sim "uio_oe";
    after = (fun n -> Cyclesim.out_port ~clock_edge:After sim n);
    cov = Option.map (fun a -> (Cov.observer a, Cyclesim.out_port ~clock_edge:After sim Cov.tap_name)) acc }

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
  Option.iter (fun (o, p) -> Cov.observe o !p) t.cov;
  { pad_nib; uio_oe }

let get t n = Bits.to_int !(t.after n)
let get_bits t n = !(t.after n)
