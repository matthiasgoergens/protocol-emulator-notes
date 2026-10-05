(* The sequencer as a symbolic transition system: Isa2's interpreter instantiated with SMT terms
   ([Sym]), plus the concrete replay of a counterexample on Isa2.Spec.

   Each thread runs either the concrete programme in the store ([Fixed]) or an unconstrained
   instruction word every slot ([Havoc]: "whatever the other threads do"). For a Fixed thread the
   fetch address is a tree of constants (an ite over the addresses the thread can be at), so the
   clock is split by address: the interpreter runs once per possible address on a constant
   instruction word, where nearly everything folds, and the results are merged under
   "fetch address = a". *)

module Sym = Isa2.Make (Smt.Value)
module P = Props.Make (Smt.Value)
module PC = Props.Make (Isa2.Int_value)

type code = Fixed | Havoc

type t = {
  prefix : string;                   (* names this copy's own variables (miters have two copies) *)
  mutable st : Sym.state;
  store : int array;                 (* the programme store, Isa2.store_len words *)
  code : code array;
  reach : int list option array;     (* per thread, the addresses it can be at, when its pc is
                                        not a tree of constants (a state variable, lustre.ml) *)
}

(* [bank]: the data bank's initial contents, (address, byte) pairs; every other byte is 0 *)
let create ?(prefix = "") ?(boot = Compat.boot_by_thread) ?(bank = []) ~store ~code () =
  let bank = List.fold_left (fun m (a, v) -> Smt.store m (Smt.k ~w:10 a) (Smt.k ~w:8 v)) (Smt.mem_zero ()) bank in
  let boot = Array.map (fun (pg, pc) -> (Smt.k ~w:2 pg, Smt.k ~w:8 pc)) boot in
  { prefix; st = Sym.reset ~boot ~bank; store; code; reach = Array.make Isa2.n_threads None }

(* the inputs of clock [k]: every one a fresh variable *)
let io ~k : Sym.io =
  let v name sort = Smt.var (Printf.sprintf "%s@%d" name k) sort in
  let bv name w = v name (Smt.Bv w) and bl name = v name Smt.Bool in
  { pin_in = bv "pin_in" 8; pin_in4 = bv "pin_in4" 32; host_in = bv "host_in" 8;
    host_in_valid = bl "host_in_valid";
    port_in = Array.init 4 (fun i -> bv (Printf.sprintf "port_in%d" i) 8);
    port_in_valid = Array.init 4 (fun i -> bl (Printf.sprintf "port_in_valid%d" i));
    port_out_ready = Array.init 4 (fun i -> bl (Printf.sprintf "port_out_ready%d" i));
    flags = bv "flags" 16; host_ctl = None }

let instr_name m ~thread ~k = Printf.sprintf "%sinstr%d@%d" m.prefix thread k

(* the constant leaves of an ite tree, or None if the term is not one *)
let leaves t =
  let seen = Hashtbl.create 64 and out = ref [] and ok = ref true in
  let rec go (t : Smt.term) =
    if !ok && not (Hashtbl.mem seen t.id) then begin
      Hashtbl.replace seen t.id ();
      match t.node with
      | K n -> out := n :: !out
      | App ("ite", _, [ _; x; y ]) -> go x; go y
      | _ -> ok := false
    end in
  go t;
  if !ok then Some (List.sort_uniq compare !out) else None

let merge_effects g (x : Sym.effects) (y : Sym.effects) : Sym.effects =
  let i = Smt.ite g in
  let two (a, b) (a', b') = (i a a', i b b') and three (a, b, c) (a', b', c') = (i a a', i b b', i c c') in
  { host_out = three x.host_out y.host_out; host_in_ready = i x.host_in_ready y.host_in_ready;
    port_pop = two x.port_pop y.port_pop; port_push = three x.port_push y.port_push;
    bank_write = three x.bank_write y.bank_write; bank_read = two x.bank_read y.bank_read;
    fine_out = two x.fine_out y.fine_out; pins_written = i x.pins_written y.pins_written;
    inbox_send = i x.inbox_send y.inbox_send; inbox_recv = i x.inbox_recv y.inbox_recv;
    port_out = i x.port_out y.port_out; port_in = i x.port_in y.port_in }

(* One clock. Returns the thread that executed, its fetch address before the clock, and the
   clock's effects; [m.st] becomes the state after the clock. *)
let clock m ~k (io : Sym.io) =
  let t = m.st.thread in
  let before = m.st in
  let addr = Sym.fetch_addr before t in
  match m.code.(t) with
  | Havoc ->
    let st = Sym.copy before in
    let e = Sym.exec st ~instr:(Smt.var (instr_name m ~thread:t ~k) (Smt.Bv 16)) io in
    m.st <- st; (t, addr, e)
  | Fixed ->
    let consts what x = match leaves x with
      | Some l -> l
      | None -> failwith (Printf.sprintf "thread %d's %s is not a tree of constants" t what) in
    let addrs =
      match leaves before.pcs.(t), leaves before.pages.(t), m.reach.(t) with
      | Some pcs, Some pages, _ -> List.concat_map (fun pg -> List.map (fun pc -> (pg lsl Isa2.pc_bits) lor pc) pcs) pages
      | _, _, Some r -> r
      | _ -> ignore (consts "pc" before.pcs.(t)); consts "page" before.pages.(t) in
    let run a =
      let st = Sym.copy before in
      (* under "fetch address = a" the thread's pc and page are constants *)
      st.pcs.(t) <- Smt.k ~w:8 (a land 0xFF); st.pages.(t) <- Smt.k ~w:2 (a lsr Isa2.pc_bits);
      let e = Sym.exec st ~instr:(Smt.k ~w:16 m.store.(a)) io in
      (a, st, e) in
    (match List.rev (List.map run addrs) with
     | [] -> assert false
     | (_, st_d, e_d) :: rest ->
       let st, e = List.fold_left (fun (st, e) (a, st_a, e_a) ->
           let g = Smt.and_ (Smt.eq before.pcs.(t) (Smt.k ~w:8 (a land 0xFF)))
               (Smt.eq before.pages.(t) (Smt.k ~w:2 (a lsr Isa2.pc_bits))) in
           (Sym.merge g st_a st, merge_effects g e_a e)) (st_d, e_d) rest in
       m.st <- st; (t, addr, e))

(* Cut the state after clock [k]: every register that is not a constant becomes a fresh variable,
   and the equation "variable = its expression" is returned, to be asserted as an assumption.
   The unrolling then grows linearly with the depth, instead of each clock's terms nesting the
   previous clock's: without the cut, programmes whose control flow follows their inputs (bridge
   A's UART receiver) double their term graph every few dozen clocks. A Fixed thread's pc keeps
   its split: the addresses it can be at (the leaves of its expression) become [reach]. The bank
   is left as it is. *)
(* [cut_value ~prefix ~k name x eqs]: [x] itself if it is a constant or a variable, else a fresh
   variable, with "variable = x" added to [eqs]; for ghost state that should be cut too *)
let cut_value ~prefix ~k name (x : Smt.term) eqs =
  match x.node with
  | Smt.K _ | Smt.B _ | Smt.Var _ -> x
  | Smt.App _ ->
    let v = Smt.var (Printf.sprintf "%scut.%s@%d" prefix name k) x.sort in
    let same = match x.sort with
      | Smt.Bool -> Smt.or_ (Smt.and_ v x) (Smt.and_ (Smt.not_ v) (Smt.not_ x))
      | Smt.Bv _ | Smt.Mem -> Smt.eq v x in
    eqs := same :: !eqs; v

let cut m ~k =
  let eqs = ref [] in
  let fresh name x = cut_value ~prefix:m.prefix ~k name x eqs in
  let st = m.st in
  let arr name a = Array.iteri (fun i x -> a.(i) <- fresh (Printf.sprintf "%s%d" name i) x) a in
  Array.iteri (fun t x ->
      match x.Smt.node, st.pages.(t).Smt.node, leaves x with
      | Smt.App _, Smt.K page, Some l ->
        m.reach.(t) <- Some (List.map (fun pc -> (page lsl Isa2.pc_bits) lor pc) l);
        st.pcs.(t) <- fresh (Printf.sprintf "pc%d" t) x
      | _ -> ()) st.pcs;
  arr "acc" st.accs; arr "cnt" st.cnts; arr "dl" st.dls; arr "bp" st.bps; arr "fine" st.fines;
  arr "armed" st.armed; arr "cfg" st.cfgs; arr "lsend" st.lsend; arr "inbox" st.inbox; arr "full" st.full;
  st.pin_out <- fresh "pin_out" st.pin_out; st.pin_oe <- fresh "pin_oe" st.pin_oe;
  st.pin_sub <- fresh "pin_sub" st.pin_sub; st.latch <- fresh "latch" st.latch;
  !eqs

(* ---- concrete replay ---- *)

(* a model: variable name -> value; variables the solver never saw are unconstrained, take 0 *)
type model = (string, int) Hashtbl.t

let model_of (pairs : (Smt.term * int) list) : model =
  let h = Hashtbl.create 1024 in
  List.iter (fun ((t : Smt.term), v) -> match t.node with Var n -> Hashtbl.replace h n v | _ -> ()) pairs; h

let get (m : model) name = Option.value (Hashtbl.find_opt m name) ~default:0

let concrete_io (m : model) ~k : Isa2.io =
  let g name = get m (Printf.sprintf "%s@%d" name k) in
  { pin_in = g "pin_in"; pin_in4 = g "pin_in4"; host_in = g "host_in"; host_in_valid = g "host_in_valid" = 1;
    port_in = Array.init 4 (fun i -> g (Printf.sprintf "port_in%d" i));
    port_in_valid = Array.init 4 (fun i -> g (Printf.sprintf "port_in_valid%d" i) = 1);
    port_out_ready = Array.init 4 (fun i -> g (Printf.sprintf "port_out_ready%d" i) = 1);
    flags = g "flags"; host_ctl = None }

type concrete = { cprefix : string; cst : Isa2.state; cstore : int array; ccode : code array }

let concrete ?(prefix = "") ?(boot = Compat.boot_by_thread) ?(bank = []) ~store ~code () =
  let bank = let b = Array.make Isa2.bank_len 0 in List.iter (fun (a, v) -> b.(a) <- v) bank; b in
  { cprefix = prefix; cst = Isa2.init ~boot ~bank (); cstore = store; ccode = code }

(* one clock of the replay: (thread, fetch address, instruction word, effects) *)
let concrete_clock c (model : model) ~k (io : Isa2.io) =
  let t = c.cst.thread in
  let addr = Isa2.fetch_addr c.cst t in
  let instr = match c.ccode.(t) with
    | Fixed -> c.cstore.(addr)
    | Havoc -> get model (Printf.sprintf "%sinstr%d@%d" c.cprefix t k) in
  let e = Isa2.Spec.exec c.cst ~instr io in
  (t, addr, instr, e)
