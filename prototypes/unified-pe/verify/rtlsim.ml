(* The Hardcaml array under Cyclesim, behind the same interface as the model. *)
open Hardcaml
open Spec

type t = {
  sim : Cyclesim.t_port_list;
  ins : (string, Bits.t ref) Hashtbl.t;
  outs : (string, Bits.t ref) Hashtbl.t;
}

let circuit_cache : (string, Circuit.t) Hashtbl.t = Hashtbl.create 8

let create () =
  let c =
    match Hashtbl.find_opt circuit_cache !Upe_rtl.bug with
    | Some c -> c
    | None ->
      let c = Upe_rtl.array_circuit () in
      Hashtbl.replace circuit_cache !Upe_rtl.bug c;
      c
  in
  let sim = Cyclesim.create ~config:Cyclesim.Config.default c in
  let ins = Hashtbl.create 64 and outs = Hashtbl.create 256 in
  List.iter (fun (n, r) -> Hashtbl.replace ins n r) (Cyclesim.inputs sim);
  List.iter (fun (n, r) -> Hashtbl.replace outs n r) (Cyclesim.outputs sim);
  { sim; ins; outs }

(* a planted bug can leave an input unused, and Hardcaml then drops the port *)
let set t n w v = match Hashtbl.find_opt t.ins n with Some r -> r := Bits.of_int ~width:w v | None -> ()
let setb t n b = set t n 1 (if b then 1 else 0)
let get t n = Bits.to_int !(Hashtbl.find t.outs n)
let getb t n = get t n = 1

let cycle t (i : inputs) =
  setb t "mbx_wr" i.mbx_wr; set t "mbx_seg" 2 i.mbx_seg; set t "mbx_sel" 2 i.mbx_sel;
  set t "mbx_byte" 8 i.mbx_byte; setb t "cfg_wr" i.cfg_wr; set t "cfg_seg" 2 i.cfg_seg;
  set t "cfg_byte" 8 i.cfg_byte; setb t "init_wr" i.init_wr; set t "init_seg" 2 i.init_seg;
  set t "init_byte" 8 i.init_byte;
  for j = 0 to 3 do
    set t (Printf.sprintf "fixed_d%d" j) 16 i.fixed_d.(j);
    setb t (Printf.sprintf "fixed_v%d" j) i.fixed_v.(j)
  done;
  Cyclesim.cycle t.sim

let state t : state =
  let pe i : pe_state =
    let c = !(Hashtbl.find t.outs (Printf.sprintf "cfg%d" i)) in
    { s = get t (Printf.sprintf "s%d" i); p = get t (Printf.sprintf "p%d" i);
      pv = getb t (Printf.sprintf "pv%d" i); f = getb t (Printf.sprintf "f%d" i);
      l = getb t (Printf.sprintf "l%d" i);
      cfg = Array.init 8 (fun j -> Bits.to_int (Bits.select c ((8 * j) + 7) (8 * j))) }
  in
  let seg j : seg_state =
    { flo = get t (Printf.sprintf "flo%d" j); fhi = get t (Printf.sprintf "fhi%d" j);
      fv = getb t (Printf.sprintf "fv%d" j); ctrl = get t (Printf.sprintf "ctrl%d" j) }
  in
  let tap j =
    { td = get t (Printf.sprintf "tap_d%d" j); tv = getb t (Printf.sprintf "tap_v%d" j);
      tf = getb t (Printf.sprintf "tap_f%d" j) }
  in
  { pes = Array.init n_pe pe; segs = Array.init 4 seg; taps = Array.init 4 tap }
