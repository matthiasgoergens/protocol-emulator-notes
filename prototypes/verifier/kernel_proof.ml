(* The kernel's abstract step against Isa2's interpreter, by z3 (README.md, section 4).

   [Kernel.Step] is the kernel's transfer function written once over a value domain; the kernel
   runs it on integers. Here the same code runs on SMT terms ([Smt_dom]), and so does Isa2's
   interpreter ([Isa2.Make (Smt.Value)], as in ../formal). For every instruction word (all 65,536)
   and every shape of abstract key (cnt known or not, acc known or not, the deadline register's
   upper bound given or not), one query asks z3 for a concrete state in the key, inputs, and a
   slot j of the instruction such that the interpreter's slot is covered neither by "the
   instruction is still waiting" nor by any outcome of the kernel's step. Unsatisfiable for
   every word and shape is the proof; a satisfying assignment is a counterexample.

   The concrete side. Thread 1's registers, the other threads' registers, the pins, the latch,
   the bank and every input are free variables; the key's pc, cnt and acc (when known) are thread
   1's registers themselves; the key's enables (kn, ko) constrain pin_oe on the known pins (A5:
   nothing else changes them). The deadline register at the instruction's first issue is d, in
   the key's interval [dlo, dhi]. Thread 0 differs only in reading the round latch from its own
   pin input, a special case of the free latch (README.md); the other threads only in which flag
   bits and inbox are theirs. The host does not move the pc (A2).

   Waits (WAITP, WAITD, IN, MBX, WAITC) take several slots. The query is an induction over the
   slot j of the wait: in slot j the pc is the wait's, dl is d - j (j <= d; for IN max(d - j, 0),
   any j), cnt, acc and the enables are those of the first issue, and for j > 0 a WAITC on acc or
   cnt has its condition false. Each slot either stays
   (pc unchanged, dl one less and j + 1 <= d, cnt, acc and the pins unchanged, no pin written,
   and a WAITC whose condition is on acc or cnt still not holding),
   which is slot j + 1 of the same wait, or leaves, and then must match an outcome of the kernel
   with elapsed j + 1 and its event at slot j. Every other instruction takes one slot: j = 0.

   An outcome r covers a slot that leaves when its guard holds and:
   - the next pc is r's; cnt and acc are r's where r knows them; dl is in r's interval; the
     enables r knows are those of the pins;
   - j + 1 is in r's elapsed, and j in r's event slot when r has an event;
   - its timing holds as [Kernel.step] uses it: Plain, By_due, Unbounded: dl afterwards is
     max(d - (j + 1), 0) (and By_due ends by d + 1); Load n: dl is n; Until_due: j + 1 = d + 1
     and dl is 0;
   - its events are the interpreter's: the pins written are exactly r's writes, each left at a
     level its Spec.level allows; an observation's pin read its value, a timeout's did not;
   - the quarter-clock levels (pin_sub) move from the old pins to the new at r's sub-slot q
     (added after the codex review: without it a wrong q in a certificate would go unseen). *)

module Sym = Isa2.Make (Smt.Value)

module Smt_dom = struct
  type v = Smt.term
  type b = Smt.term
  let k ~w n = Smt.k ~w n
  let add ~w x y = Smt.add ~w x y
  let sub ~w x y = Smt.sub ~w x y
  let logand = Smt.logand
  let logor = Smt.logor
  let lognot ~w x = Smt.lognot ~w x
  let shl ~w x s = Smt.shl ~w x (Smt.k ~w s)
  let lshr x s = Smt.lshr x (Smt.k ~w:(Smt.width x) s)
  let zext ~w x = Smt.zext ~w x
  let bit x i = Smt.eq (Smt.extract x ~hi:i ~lo:i) (Smt.k ~w:1 1)
  let eq = Smt.eq
  let ite = Smt.ite
  let tt = Smt.tt
  let not_ = Smt.not_
  let and_ = Smt.and_
  let or_ = Smt.or_
end

module S = Kernel.Step (Smt_dom)
open Smt

let t = 1                                         (* the thread under proof *)
let c w n = Smt.k ~w n
let bv name w = var name (Bv w)
let ule x y = not_ (ult y x)
let z16 x = zext ~w:16 x
let conj = List.fold_left and_ tt
let disj = List.fold_left or_ ff

type shape = { cnt_known : bool; acc_known : bool; hi_given : bool }

let shapes =
  List.concat_map (fun cnt_known -> List.concat_map (fun acc_known -> List.map (fun hi_given ->
      { cnt_known; acc_known; hi_given }) [ true; false ]) [ true; false ]) [ true; false ]

let shape_to_string s =
  Printf.sprintf "cnt %s, acc %s, dl %s" (if s.cnt_known then "known" else "any") (if s.acc_known then "known" else "any")
    (if s.hi_given then "[lo, hi]" else "[lo, ?]")

let is_wait op = List.mem op [ Isa2.op_waitp; Isa2.op_waitd; Isa2.op_in; Isa2.op_mbx; Isa2.op_waitc ]

(* the free state: every register of every thread, the pins, the latch and the bank *)
let free_state () : Sym.state =
  let arr name w = Array.init Isa2.n_threads (fun i -> bv (Printf.sprintf "%s%d" name i) w) in
  { pcs = arr "pc" 8; pages = arr "page" 2; accs = arr "acc" 8; cnts = arr "cnt" 12; dls = arr "dl" 12;
    bps = arr "bp" 10; fines = arr "fine" 8; armed = arr "armed" 1; cfgs = arr "cfg" 8; lsend = arr "lsend" 3;
    inbox = arr "inbox" 8; full = arr "full" 1; pin_out = bv "pin_out" 8; pin_oe = bv "pin_oe" 8; thread = t;
    pin_sub = bv "pin_sub" 32; latch = bv "latch" 8; bankmem = mem_var "bank" }

let free_io () : Sym.io =
  { pin_in = bv "pin_in" 8; pin_in4 = bv "pin_in4" 32; host_in = bv "host_in" 8; host_in_valid = var "host_in_valid" Bool;
    port_in = Array.init 4 (fun i -> bv (Printf.sprintf "port_in%d" i) 8);
    port_in_valid = Array.init 4 (fun i -> var (Printf.sprintf "port_in_valid%d" i) Bool);
    port_out_ready = Array.init 4 (fun i -> var (Printf.sprintf "port_out_ready%d" i) Bool);
    flags = bv "flags" 16; host_ctl = None }

let in_interval x (i : Smt.term Kernel.ginterval) =
  and_ (ule i.glo x) (match i.ghi with Some h -> ule x h | None -> tt)

let bit x i = eq (extract x ~hi:i ~lo:i) (c 1 1)

(* the query for word [w] and [shape]: the formula whose satisfiability is a counterexample *)
let query w shape =
  let op = (w lsr 12) land 15 in
  let st = free_state () and io = free_io () in
  let pc = st.pcs.(t) and cnt = st.cnts.(t) and acc = st.accs.(t) in
  let kn = bv "kn" 8 and ko = bv "ko" 8 in
  let d = bv "d" 12 and j = bv "j" 16 and dlo = bv "dlo" 16 and dhi = bv "dhi" 16 in
  let key = { Kernel.gpc = pc; gcnt = (if shape.cnt_known then GKnown cnt else GAny);
              gacc = (if shape.acc_known then GKnown acc else GAny); goe_known = kn; goe = ko } in
  let dl_i = { Kernel.glo = dlo; ghi = (if shape.hi_given then Some dhi else None) } in
  let d16 = z16 d in
  let wait = is_wait op in
  let sat_minus x n = ite (ult x n) (c 16 0) (sub ~w:16 x n) in      (* max (x - n) 0 on 16 bits *)
  (* a WAITC on a bit of acc or on cnt's low three bits waits on state that does not change while
     it waits: in a slot j > 0 that condition was false at slot j - 1, so it is false now. The
     hypothesis says so, and a stay must keep it (without it, the induction admits a slot j > 0
     of a wait whose condition already holds, which no execution reaches: the first run of this
     proof stopped there, 2026-10-06) *)
  let static_cond =
    if op <> Isa2.op_waitc then None
    else let cond = (w lsr 8) land 15 in
      if cond < 8 then Some (bit acc cond)
      else if cond = 8 then Some (eq (extract cnt ~hi:2 ~lo:0) (c 3 0))
      else None in
  let still_waiting = match static_cond with Some h -> not_ h | None -> tt in
  let pre = conj [
      eq (logand st.pin_oe kn) (logand ko kn);
      ule dlo d16; (if shape.hi_given then and_ (ule d16 dhi) (ule dhi (c 16 Kernel.dl_max)) else tt);
      (if not wait then and_ (eq j (c 16 0)) (eq st.dls.(t) d)
       else if op = Isa2.op_in then and_ (ult j (c 16 0xFFFF)) (eq (z16 st.dls.(t)) (sat_minus d16 j))
       else and_ (ule j d16) (eq (z16 st.dls.(t)) (sub ~w:16 d16 j)));
      (if wait then or_ (eq j (c 16 0)) still_waiting else tt) ] in
  (* the pins this slot reads (Isa2: the round latch when cfg bit 7 is set) *)
  let pins = ite (bit st.cfgs.(t) 7) st.latch io.pin_in in
  let pre_out = st.pin_out and pre_oe = st.pin_oe in
  let outcomes = S.transfer w key dl_i in
  let e = Sym.exec st ~instr:(c 16 w) io in
  let pc' = st.pcs.(t) and cnt' = st.cnts.(t) and acc' = st.accs.(t) and dl' = z16 st.dls.(t) in
  let j1 = add ~w:16 j (c 16 1) in
  let stay =
    if not wait then ff
    else conj [ eq pc' pc; eq cnt' cnt; eq acc' acc; eq st.pin_out pre_out; eq st.pin_oe pre_oe; still_waiting;
                eq e.pins_written (c 8 0);
                (if op = Isa2.op_in then eq dl' (sat_minus d16 j1) else and_ (ule j1 d16) (eq dl' (sub ~w:16 d16 j1))) ] in
  let level_ok p (l : Spec.level) =
    let oe = bit st.pin_oe p and out = bit st.pin_out p in
    match l with
    | Spec.L -> and_ oe (not_ out) | H -> and_ oe out | Z -> not_ oe | LH -> oe
    | LZ -> or_ (and_ oe (not_ out)) (not_ oe) | X -> tt in
  let covers (r : (Smt.term, Smt.term) Kernel.graw) =
    let known x = function Kernel.GKnown v -> eq x v | GAny -> tt in
    let writes = List.fold_left (fun m (p, kd) -> match kd with Spec.Write _ -> m lor (1 lsl p) | _ -> m) 0 r.gev in
    let events = conj (eq e.pins_written (c 8 writes) :: List.map (fun (p, kd) -> match kd with
        | Spec.Write { level; _ } -> level_ok p level
        | Spec.Observe v -> eq (extract pins ~hi:p ~lo:p) (c 1 v)
        | Spec.Expire v -> not_ (eq (extract pins ~hi:p ~lo:p) (c 1 v))
        | Spec.Sample -> tt) r.gev) in
    let timing = match r.gtiming with
      | Kernel.Plain | Unbounded -> eq dl' (sat_minus d16 j1)
      | By_due -> and_ (eq dl' (sat_minus d16 j1)) (ule j1 (add ~w:16 d16 (c 16 1)))
      | Load n -> eq dl' (c 16 n)
      | Until_due -> and_ (eq j1 (add ~w:16 d16 (c 16 1))) (eq dl' (c 16 0)) in
    (* the quarter-clock view: the pins move at sub-slot r.gq (A4: FINE is not bounded) *)
    let subslot = eq st.pin_sub (Sym.sub_of ~old_:pre_out ~new_:st.pin_out ~q:(c 2 r.gq)) in
    conj [ r.guard; eq pc' r.gnext_pc; known cnt' r.gcnt'; known acc' r.gacc'; in_interval dl' r.gdl'; subslot;
           eq (logand st.pin_oe r.goe_known') (logand r.goe' r.goe_known');
           in_interval j1 r.gelapsed;
           (* the event slot means something only with an event: Kernel.step uses [at] for the
              time and gap of events alone, and WAITD's outcome says at = 0 while it leaves at
              slot d (the first run of this proof found that, 2026-10-06) *)
           (if r.gev = [] then tt else in_interval j r.gat); events; timing ] in
  and_ pre (not_ (or_ stay (disj (List.map covers outcomes)))), pre, List.length outcomes

let op_name w =
  let op = (w lsr 12) land 15 in
  if op = 15 then (match (w lsr 8) land 15 with
      | 0 -> "SKNE" | 1 -> "SKEQ" | 2 -> "FINE" | 3 -> "CNTA" | 4 -> "LDB" | 5 -> "STB" | 6 -> "BANK" | 7 -> "CFG"
      | n -> Printf.sprintf "EXT%d" n)
  else [| "NOP"; "SETP"; "LDC"; "LDD"; "LDA"; "WAITP"; "WAITD"; "SHO"; "SHI"; "JMP"; "JNZ"; "OUT"; "IN"; "MBX"; "WAITC"; "EXT" |].(op)

(* Prove every word in [first, last]: one line per opcode (or EXT sub-operation) with the
   number of queries, how many were unsatisfiable (proved), folded to false before reaching the
   solver, and counterexamples; the first counterexample of each group is printed. *)
let run ~first ~last =
  let s = Solver.start ?log:(Sys.getenv_opt "KERNEL_Z3_LOG") () in
  let groups = Hashtbl.create 32 and order = ref [] in
  let stat name = match Hashtbl.find_opt groups name with
    | Some x -> x
    | None -> let x = ref (0, 0, 0, 0, 0) in Hashtbl.replace groups name x; order := name :: !order; x in
  let shown = Hashtbl.create 8 in
  let check_one w shape bad g =
    let n, proved, folded, cex, unk = !g in
    if bad == ff then g := (n + 1, proved + 1, folded + 1, cex, unk)
    else begin
      Solver.ensure s bad; Solver.push s; Solver.assert_ s bad;
      (match Solver.check s with
       | `Unsat -> g := (n + 1, proved + 1, folded, cex, unk)
       | `Sat ->
         g := (n + 1, proved, folded, cex + 1, unk);
         if not (Hashtbl.mem shown (op_name w)) then begin
           Hashtbl.replace shown (op_name w) ();
           let names = [ "pc1"; "cnt1"; "acc1"; "dl1"; "d"; "j"; "dlo"; "dhi"; "kn"; "ko"; "pin_oe"; "pin_out"; "pin_in"; "latch"; "cfg1" ] in
           (* only variables the solver has seen *)
           let terms = List.filter (fun t -> List.memq t s.Solver.vars)
               (List.filter_map (fun nm -> Hashtbl.find_opt Smt.table (Smt.KVar nm)) names) in
           let vals = Solver.get_values s terms in
           (* the reader stops at the closing parenthesis: drop the rest of its line *)
           if terms <> [] then ignore (input_line s.Solver.ic);
           Printf.printf "COUNTEREXAMPLE %04x (%s), %s: %s\n%!" w (Isa2.disasm w) (shape_to_string shape)
             (String.concat " " (List.map (fun ((x : Smt.term), v) -> Printf.sprintf "%s=%d" (Smt.name x) v) vals))
         end
       | `Unknown r -> g := (n + 1, proved, folded, cex, unk + 1); Printf.printf "UNKNOWN %04x: %s\n%!" w r);
      Solver.pop s
    end in
  for w = first to last do
    let g = stat (op_name w) in
    let qs = List.map (fun shape -> let bad, pre, _ = query w shape in (shape, bad, pre)) shapes in
    (* the precondition must be satisfiable, or the proof says nothing; checked for the first
       word of each opcode, every shape *)
    let n0, _, _, _, _ = !g in
    if n0 = 0 then
      List.iter (fun (shape, _, pre) ->
          (* definitions outside the push, which would otherwise discard them *)
          Solver.ensure s pre; Solver.push s; Solver.assert_ s pre;
          (match Solver.check s with
           | `Sat -> ()
           | _ -> Printf.printf "%s: precondition unsatisfiable for %s (VACUOUS)\n%!" (op_name w) (shape_to_string shape));
          Solver.pop s) qs;
    (* one query for the eight shapes of a word; only if it is satisfiable, one per shape, to
       name the counterexample *)
    let any = List.fold_left (fun a (_, bad, _) -> or_ a bad) ff qs in
    let all_unsat =
      if any == ff then true
      else begin
        Solver.ensure s any; Solver.push s; Solver.assert_ s any;
        let r = Solver.check s in
        Solver.pop s;
        r = `Unsat
      end in
    if all_unsat then begin
      let n, proved, folded, cex, unk = !g in
      let nf = List.length (List.filter (fun (_, bad, _) -> bad == ff) qs) in
      g := (n + List.length qs, proved + List.length qs, folded + nf, cex, unk)
    end else List.iter (fun (shape, bad, _) -> check_one w shape bad g) qs
  done;
  Solver.close s;
  List.iter (fun name ->
      let n, proved, folded, cex, unk = !(Hashtbl.find groups name) in
      Printf.printf "OPCODE %-6s %6d queries (words x %d key shapes): %6d unsatisfiable (%d folded before the solver), %d counterexamples, %d unknown -> %s\n%!"
        name n (List.length shapes) proved folded cex unk
        (if cex = 0 && unk = 0 && proved = n then "PROVED" else if cex > 0 then "FAILED" else "UNDECIDED"))
    (List.rev !order)
