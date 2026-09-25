(* Cyclesim harness for the v2 core: the shared programme store (one-cycle synchronous read) and
   the data bank (one-cycle synchronous read and write) around the RTL.

   Each clock is split: combinational outputs that depend on this clock's instruction (fetch
   address, bank strobes, the ready pulses) are read before the clock edge; the bank's read data
   is presented after the edge, as a synchronous SRAM's output would change; registered outputs
   and the debug view of all architectural state are read after the edge. *)
open Hardcaml

type t = {
  sim : Cyclesim.t_port_list;
  mem : int array;                 (* programme store, Isa2.store_len words *)
  bankmem : int array;
  inp : string -> Bits.t ref;
  before : string -> Bits.t ref;
  after : string -> Bits.t ref;
  mutable fetch_addr : int;        (* address presented during the last clock *)
  mutable rdata : int;
  mutable cycles : int;
}

let circuit_cache = Hashtbl.create 4

let circuit ?bug () =
  match Hashtbl.find_opt circuit_cache bug with
  | Some c -> c
  | None -> let c = Sequencer2.circuit ?bug () in Hashtbl.replace circuit_cache bug c; c

let set (r : Bits.t ref) ~width v = r := Bits.of_int ~width v

let make ?bug ?(boot = Array.make Isa2.n_threads (0, 0)) ?bank (mem : int array) =
  assert (Array.length mem = Isa2.store_len);
  let sim = Cyclesim.create (circuit ?bug ()) in
  let inp n = Cyclesim.in_port sim n in
  let before n = Cyclesim.out_port ~clock_edge:Before sim n in
  let after n = Cyclesim.out_port ~clock_edge:After sim n in
  let s = { sim; mem; bankmem = (match bank with Some b -> Array.copy b | None -> Array.make Isa2.bank_len 0); inp; before; after; fetch_addr = 0;
            rdata = 0; cycles = 0 } in
  let bp = Array.fold_left (fun (acc, i) (pg, _) -> (acc lor ((pg land 3) lsl (2 * i)), i + 1)) (0, 0) boot |> fst in
  let bpc = Array.fold_left (fun (acc, i) (_, pc) -> (acc lor ((pc land 0xFF) lsl (8 * i)), i + 1)) (0, 0) boot |> fst in
  set (inp "boot_page") ~width:8 bp;
  set (inp "boot_pc") ~width:32 bpc;
  inp "clear" := Bits.vdd;
  Cyclesim.cycle sim;
  inp "clear" := Bits.gnd;
  let pg0, pc0 = boot.(0) in
  s.fetch_addr <- (pg0 lsl Isa2.pc_bits) lor pc0;
  s

type observed = {
  pin_out : int; pin_oe : int; pin_sub : int;
  host_out : (int * int) option; host_in_ready : bool;
  port_pop : int option; port_push : (int * int) option;
  bank_write : (int * int) option; fine_out : int option; cfg_out : int;
}

let onehot_index v = let rec f i = if i >= 4 then None else if (v lsr i) land 1 = 1 then Some i else f (i + 1) in f 0

let cycle s (io : Isa2.io) =
  let g r = Bits.to_int !r in
  set (s.inp "imem_data") ~width:16 s.mem.(s.fetch_addr);
  set (s.inp "bank_rdata") ~width:8 s.rdata;
  set (s.inp "pin_in") ~width:8 io.pin_in;
  s.inp "pin_in4" := Bits.of_int ~width:32 io.pin_in4;
  set (s.inp "host_in") ~width:8 io.host_in;
  set (s.inp "host_in_valid") ~width:1 (Bool.to_int io.host_in_valid);
  Array.iteri (fun i v -> set (s.inp (Printf.sprintf "port_in%d" i)) ~width:8 v) io.port_in;
  let bits4 a = Array.fold_left (fun (acc, i) b -> (acc lor (Bool.to_int b lsl i), i + 1)) (0, 0) a |> fst in
  set (s.inp "port_in_valid") ~width:4 (bits4 io.port_in_valid);
  set (s.inp "port_out_ready") ~width:4 (bits4 io.port_out_ready);
  set (s.inp "flags") ~width:16 io.flags;
  (match io.host_ctl with
   | Some (t, pg, pc) ->
     set (s.inp "ctl_valid") ~width:1 1; set (s.inp "ctl_thread") ~width:2 t;
     set (s.inp "ctl_page") ~width:2 pg; set (s.inp "ctl_pc") ~width:8 pc
   | None -> set (s.inp "ctl_valid") ~width:1 0);
  Cyclesim.cycle_check s.sim;
  Cyclesim.cycle_before_clock_edge s.sim;
  let next_addr = g (s.before "imem_addr") in
  let we = g (s.before "bank_we") = 1 and re = g (s.before "bank_re") = 1 in
  let baddr = g (s.before "bank_addr") and bw = g (s.before "bank_wdata") in
  let host_in_ready = g (s.before "host_in_ready") = 1 in
  let port_pop = onehot_index (g (s.before "port_in_ready")) in
  Cyclesim.cycle_at_clock_edge s.sim;
  if re then s.rdata <- s.bankmem.(baddr);
  if we then s.bankmem.(baddr) <- bw;
  Cyclesim.cycle_after_clock_edge s.sim;
  s.fetch_addr <- next_addr;
  s.cycles <- s.cycles + 1;
  let pov = g (s.after "port_out_valid") in
  { pin_out = g (s.after "pin_out"); pin_oe = g (s.after "pin_oe"); pin_sub = g (s.after "pin_sub");
    host_out = (if g (s.after "host_out_valid") = 1 then Some (g (s.after "host_tag"), g (s.after "host_out")) else None);
    host_in_ready; port_pop;
    port_push = (match onehot_index pov with Some p -> Some (p, g (s.after "port_out_data")) | None -> None);
    bank_write = (if we then Some (baddr, bw) else None);
    fine_out = (if g (s.after "fine_valid") = 1 then Some (g (s.after "fine_out")) else None);
    cfg_out = g (s.after "cfg_out") }

(* The architectural state as the RTL holds it, in the interpreter's representation. *)
let field s name ~width t = (Bits.to_int !(s.after name) lsr (width * t)) land ((1 lsl width) - 1)
let per s name width = Array.init Isa2.n_threads (fun t -> field s name ~width t)

let state s (o : observed) : Isa2.state =
  let accs = per s "dbg_acc" 8 in
  let pend = Bits.to_int !(s.after "dbg_pend") in
  (* an LDB's byte is on the bank's output and enters the accumulator at the next edge *)
  if pend land 4 <> 0 then accs.(pend land 3) <- s.rdata;
  { pcs = per s "dbg_pc" 8; pages = per s "dbg_page" 2; accs;
    cnts = per s "dbg_cnt" 12; dls = per s "dbg_dl" 12; bps = per s "dbg_bp" 10;
    fines = per s "dbg_fine" 8; armed = per s "dbg_armed" 1; cfgs = per s "dbg_cfg" 8;
    lsend = per s "dbg_lsend" 3; inbox = per s "dbg_inbox" 8; full = per s "dbg_full" 1;
    pin_out = o.pin_out; pin_oe = o.pin_oe; thread = Bits.to_int !(s.after "dbg_thread");
    pin_sub = o.pin_sub; latch = Bits.to_int !(s.after "dbg_latch"); bankmem = s.bankmem }
