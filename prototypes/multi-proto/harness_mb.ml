(* Cyclesim harness for the mailbox variant, with a one-cycle-latency instruction memory, as
   ../deadline-sequencer/harness.ml does for the base core. *)
open Hardcaml

type t = {
  c : Isa_mb.cfg; sim : Cyclesim.t_port_list; mem : int array array;
  i : string -> Bits.t ref; o : string -> Bits.t ref;
  mutable pending_addr : int; mutable current_addr : int;
}

let circuits : (int * int * [ `Full_never | `Wrong_slot | `None ] option, Circuit.t) Hashtbl.t = Hashtbl.create 4
let circuit ?mutant (c : Isa_mb.cfg) =
  let key = (c.pc_bits, c.depth, mutant) in
  match Hashtbl.find_opt circuits key with
  | Some x -> x
  | None -> let x = Sequencer_mb.circuit ?mutant ~debug:true c in Hashtbl.replace circuits key x; x

let make ?mutant (c : Isa_mb.cfg) mem =
  let sim = Cyclesim.create (circuit ?mutant c) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  let s = { c; sim; mem; i; o; pending_addr = 0; current_addr = 0 } in
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  s.current_addr <- 0;
  s.pending_addr <- Bits.to_int !(o "imem_addr");
  s

let fetch s addr = s.mem.(addr lsr s.c.pc_bits).(addr land (Isa_mb.prog_len s.c - 1))

type observed = {
  pin_out : int; pin_oe : int; host_out : int option; host_in_ready : bool; pcs : int list;
  port_push : (int * int) option; port_pop : int option; counts : int list;
  accs : int list; cnts : int list; dls : int list; inboxes : int list list; thread : int;
}

let bits_of_bools a = Array.fold_left (fun (acc, k) b -> ((if b then acc lor (1 lsl k) else acc), k + 1)) (0, 0) a |> fst

let cycle s (io : Isa_mb.io) =
  let bi w v = Bits.of_int ~width:w v in
  s.i "imem_data" := bi 16 (fetch s s.current_addr);
  s.i "pin_in" := bi 8 io.pin_in;
  s.i "host_in" := bi 8 io.host_in;
  s.i "host_in_valid" := bi 1 (if io.host_in_valid then 1 else 0);
  Array.iteri (fun k v -> s.i (Printf.sprintf "port_in%d" k) := bi 8 v) io.port_in;
  s.i "port_in_valid" := bi 4 (bits_of_bools io.port_in_valid);
  s.i "port_out_ready" := bi 4 (bits_of_bools io.port_out_ready);
  s.i "flags" := bi 4 io.flags;
  Cyclesim.cycle s.sim;
  s.current_addr <- s.pending_addr;
  s.pending_addr <- Bits.to_int !(s.o "imem_addr");
  let g n = Bits.to_int !(s.o n) in
  let pov = g "port_out_valid" in
  let pb = s.c.pc_bits in
  { pin_out = g "pin_out"; pin_oe = g "pin_oe";
    host_out = (if g "host_out_valid" = 1 then Some (g "host_out") else None);
    host_in_ready = g "host_in_ready" = 1;
    pcs = List.init Isa_mb.n_threads (fun t -> (g "pcs" lsr (t * pb)) land ((1 lsl pb) - 1));
    port_push = (if pov = 0 then None else Some ((match pov with 1 -> 0 | 2 -> 1 | 4 -> 2 | 8 -> 3 | _ -> -1), g "port_out_data"));
    port_pop = (match g "port_in_ready" with 0 -> None | 1 -> Some 0 | 2 -> Some 1 | 4 -> Some 2 | 8 -> Some 3 | _ -> Some (-1));
    counts = List.init 4 (fun k -> (g "mb_counts" lsr (3 * k)) land 7);
    accs = List.init 4 (fun t -> (g "dbg_acc" lsr (8 * t)) land 0xFF);
    cnts = List.init 4 (fun t -> (g "dbg_cnt" lsr (12 * t)) land 0xFFF);
    dls = List.init 4 (fun t -> (g "dbg_dl" lsr (12 * t)) land 0xFFF);
    inboxes = (let d = s.c.depth in
               let slots = !(s.o "dbg_slots") and heads = g "dbg_heads" in
               let hw = max 1 (Sequencer_mb.log2 d) in
               List.init 4 (fun i ->
                 let n = (g "mb_counts" lsr (3 * i)) land 7 and h = (heads lsr (hw * i)) land ((1 lsl hw) - 1) in
                 List.init n (fun k -> let j = (h + k) mod d in
                               Bits.to_int (Bits.select slots ((((i * d) + j) * 8) + 7) (((i * d) + j) * 8)))));
    thread = g "dbg_thread" }

(* Compare one cycle of RTL against the interpreter's step on the same inputs. *)
let agrees (o : observed) (st : Isa_mb.state) (e : Isa_mb.effects) =
  o.pin_out = st.pin_out && o.pin_oe = st.pin_oe && o.host_out = e.host_out && o.host_in_ready = e.host_in_ready
  && o.pcs = Array.to_list st.pcs && o.port_push = e.port_push && o.port_pop = e.port_pop
  && o.counts = Array.to_list (Isa_mb.counts st)
  && o.accs = Array.to_list st.accs && o.cnts = Array.to_list st.cnts && o.dls = Array.to_list st.dls
  && o.inboxes = Array.to_list st.inbox && o.thread = st.thread
