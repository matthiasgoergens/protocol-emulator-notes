(* The trusted part of the verifier: the abstract one-instruction step of ISA v2 and the check of a
   certificate against it. The idea, a small kernel that re-checks what an untrusted analyser
   proposes, is MarcosAsh's (github.com/MarcosAsh/protocol-emulator, src/kernel.ml and
   src/analyser.ml, Apache-2.0); the ISA and the domain here are different and no code was copied.

   One thread is analysed at a time. Threads issue round-robin, one instruction per slot each
   (Isa2: thread t executes on clocks congruent to t mod 4), and no instruction stalls another
   thread, so a thread's timing is a function of its own programme and its inputs only. Time is
   counted in the thread's slots; slot s is clock 4s + t.

   The abstract state at the first issue of an instruction is a *key*, kept exactly, and a
   *value*, kept as intervals:
     key   pc; the state of the specification automaton; cnt and acc, each a known value or Any;
           the output enables (A5)
     value dl (the deadline register); since (slots since the last channel event, or since the
           thread's first slot); time (slots since the thread's first slot); due (since + dl:
           the slot, on the same scale as since, on which dl reaches 0, or now if it has)
   [due] is MarcosAsh's representation of the deadline as a point in time (their phase, now - t)
   kept beside the count-down register: two paths that load different counts at different times
   for one deadline join to one exact [due], where (since, dl) would join to two intervals whose
   correlation is lost. A WAITD then ends on slot due + 1 exactly.
   A *certificate* is a table of (key, value) entries. [check] accepts it when
   - the start state (pc 0, cnt = acc = dl = 0, time 0) lies in some entry;
   - every successor of every entry, by [transfer], lies in some entry (the table is closed);
   - every channel event a step makes is one the specification's current state accepts, with
     its gap inside the declared interval, and, where the transition declares the data it
     writes (Spec [data]), with exactly the declared level, known;
   - no entry's [since] can exceed its specification state's deadline.
   A closed table that contains the start contains every reachable state, so the four checks
   together prove the specification for every input. The analyser (analyser.ml) only finds a
   table; nothing it does is trusted.

   Assumptions, each stated where it is used:
   A1 (inputs) Every instruction whose outcome depends on the outside world (WAITP, WAITC on a
      flag, host, inbox or port condition, MBX, IN, SHI, LDB, SHO with capture) may see any
      value on any slot. WAITP, WAITC and MBX are therefore waits of input-dependent length,
      bounded by the deadline register: with dl = d on the first issue, they proceed on any of
      the slots 0..d of the wait, or reach their fail target after slot d. IN has no bound.
   A2 (host) The host does not use its control port (Isa2 [host_ctl]) to move the thread's pc.
   A3 (pages) The thread runs from pc 0 of one page, and the 256 words of that page are fixed.
      The page wraps at 256 words, as in Isa2.
   A4 (time) Timing is counted in whole slots. SETP and SHO quarter-clock sub-slots (q) and FINE
      offsets move an edge by less than one clock inside its slot; the certificate prints q,
      and nothing here bounds FINE.
   A5 (output enables) The output enables are 0 after reset, and those of the pins this thread
      writes change only by its own writes. The key keeps them, because a push-pull SHO changes
      a pin's level, not its enable: on a released pin it shows nothing. For a channel's pins
      [Main.compose] checks that no other thread writes them. *)

type known = Known of int | Any
type key = { pc : int; astate : int; cnt : known; acc : known;
             oe_known : int; oe : int }   (* A5: the enables known, as a mask, and their values *)
type value = { dl : Interval.t; since : Interval.t; time : Interval.t; due : Interval.t }

let known_to_string = function Known n -> string_of_int n | Any -> "?"

let key_to_string k =
  Printf.sprintf "pc=%d state=%d cnt=%s acc=%s oe=%02x/%02x" k.pc k.astate (known_to_string k.cnt)
    (known_to_string k.acc) k.oe k.oe_known

let value_to_string v =
  Printf.sprintf "dl=%s since=%s due=%s time=%s" (Interval.to_string v.dl) (Interval.to_string v.since)
    (Interval.to_string v.due) (Interval.to_string v.time)

let value_leq a b = Interval.leq a.dl b.dl && Interval.leq a.since b.since && Interval.leq a.time b.time
                    && Interval.leq a.due b.due
let value_join a b = { dl = Interval.join a.dl b.dl; since = Interval.join a.since b.since;
                       time = Interval.join a.time b.time; due = Interval.join a.due b.due }
let value_equal a b = Interval.equal a.dl b.dl && Interval.equal a.since b.since && Interval.equal a.time b.time
                      && Interval.equal a.due b.due

(* a key in the table covers a key reached when they agree on pc and state and the table's cnt
   and acc are Any or equal *)
let known_covers ~table x = match table, x with Any, _ -> true | Known a, Known b -> a = b | Known _, Any -> false
let key_covers ~table k =
  table.pc = k.pc && table.astate = k.astate && known_covers ~table:table.cnt k.cnt
  && known_covers ~table:table.acc k.acc
  && table.oe_known land k.oe_known = table.oe_known && table.oe land table.oe_known = k.oe land table.oe_known

(* ---- the abstract step ---- *)

(* How an outcome's duration relates to the deadline register, for [due]:
   Plain       one slot, dl counts down (or is unchanged at 0)
   Load n      one slot, dl <- n (LDD)
   Until_due   ends on the slot after dl reaches 0 (WAITD; a wait that times out)
   By_due      ends no later than that (a wait that proceeds)
   Unbounded   any time (IN) *)
type timing = Plain | Load of int | Until_due | By_due | Unbounded

(* What one instruction does from its first issue to the first issue of the next instruction. *)
type raw = {
  timing : timing;
  next_pc : int; cnt' : known; acc' : known; dl' : Interval.t; oe_known' : int; oe' : int;
  elapsed : Interval.t;            (* slots until the next instruction first issues *)
  at : Interval.t;                 (* the slot of the event, counted from the first issue *)
  ev : (int * Spec.kind) list;     (* pins this instruction touches, all eight, ascending *)
  q : int;                         (* quarter-clock sub-slot of a write (A4) *)
}

let dl_max = 4095

(* Planted kernel bugs, for [Main]'s kernel-bugs command only: each must make some check of the
   verifier fail (the interpreter cross-check, a planted programme accepted, ...). 0 is the
   kernel as specified; only [Main]'s --bug option sets another value. *)
let planted_bug = ref 0
let bug n = !planted_bug = n

let level_of ~od v = if od then (if v = 1 then Spec.Z else Spec.L) else (if v = 1 then Spec.H else Spec.L)

(* The step is written once over a domain of values (as Isa2's interpreter is), so that the same
   code is the trusted kernel on integers and, on SMT terms, is proved against Isa2's interpreter
   by z3 (kernel_proof.ml, README.md section 4). The instruction word is always a constant; the
   key's pc, its known cnt and acc, its enables and the deadline register's bounds are values.
   Where the step branches on a value it returns each branch under a guard; on integers the
   guards are decided and [transfer] keeps the outcomes whose guard holds. *)
module type DOM = sig
  type v                                       (* a bit vector; every value has a fixed width *)
  type b                                       (* a truth value *)
  val k : w:int -> int -> v
  val add : w:int -> v -> v -> v               (* modulo 2^w *)
  val sub : w:int -> v -> v -> v
  val logand : v -> v -> v
  val logor : v -> v -> v
  val lognot : w:int -> v -> v
  val shl : w:int -> v -> int -> v
  val lshr : v -> int -> v
  val zext : w:int -> v -> v                   (* zero-extended to w bits *)
  val bit : v -> int -> b
  val eq : v -> v -> b
  val ite : b -> v -> v -> v
  val tt : b
  val not_ : b -> b
  val and_ : b -> b -> b
  val or_ : b -> b -> b
end

type 'v gknown = GKnown of 'v | GAny
type 'v ginterval = { glo : 'v; ghi : 'v option }   (* bounds on 16 bits; None: no upper bound *)
type ('v, 'b) gkey = { gpc : 'v; gcnt : 'v gknown; gacc : 'v gknown; goe_known : 'v; goe : 'v }
type ('v, 'b) graw = {
  guard : 'b;
  gtiming : timing;
  gnext_pc : 'v; gcnt' : 'v gknown; gacc' : 'v gknown; gdl' : 'v ginterval; goe_known' : 'v; goe' : 'v;
  gelapsed : 'v ginterval; gat : 'v ginterval;
  gev : (int * Spec.kind) list; gq : int;
}

module Step (D : DOM) = struct
  open D
  let c16 n = k ~w:16 n
  let exactly n = { glo = n; ghi = Some n }
  let range lo hi = { glo = lo; ghi = Some hi }
  let max0_minus1 x = ite (eq x (c16 0)) (c16 0) (sub ~w:16 x (c16 1))   (* max (x - 1) 0 *)

  (* [transfer w k dl]: as [transfer] below, each outcome under its guard *)
  let transfer w (k : (v, b) gkey) (dl : v ginterval) : (v, b) graw list =
    let op = (w lsr 12) land 15 in
    let imm12 = w land 0xFFF and imm8 = w land 0xFF in
    let pin = (w lsr 9) land 7 and b8 = (w lsr 8) land 1 in
    let bit_w i = (w lsr i) land 1 = 1 in
    let pc1 = add ~w:8 k.gpc (D.k ~w:8 1) in
    let dec = { glo = max0_minus1 dl.glo; ghi = Option.map max0_minus1 dl.ghi } in
    let dec_cnt = match k.gcnt with GKnown c -> GKnown (sub ~w:12 c (D.k ~w:12 1)) | GAny -> GAny in
    let one ?(guard = tt) ?(ev = []) ?(q = 0) ?(cnt = k.gcnt) ?(acc = k.gacc) ?(dl' = dec) ?(oe = (k.goe_known, k.goe))
        ?(timing = Plain) next_pc =
      { guard; gtiming = timing; gnext_pc = next_pc; gcnt' = cnt; gacc' = acc; gdl' = dl'; gelapsed = exactly (c16 1);
        gat = exactly (c16 0); gev = ev; gq = q; goe_known' = fst oe; goe' = snd oe } in
    let same_oe = (k.goe_known, k.goe) in
    let dlo = dl.glo and dhi = match dl.ghi with Some h -> h | None -> c16 dl_max in
    (* A1: a wait that may proceed on any slot 0..d, or fail after slot d *)
    let proceed ?(ev = []) ?(acc = k.gacc) () =
      { guard = tt; gtiming = By_due; gnext_pc = pc1; gcnt' = k.gcnt; gacc' = acc; gdl' = range (c16 0) (max0_minus1 dhi);
        gelapsed = range (c16 1) (if bug 1 then dhi else add ~w:16 dhi (c16 1)); gat = range (c16 0) dhi; gev = ev; gq = 0;
        goe_known' = k.goe_known; goe' = k.goe } in
    let fail ?(guard = tt) ?(ev = []) () =
      { guard; gtiming = Until_due; gnext_pc = D.k ~w:8 imm8; gcnt' = k.gcnt; gacc' = k.gacc; gdl' = exactly (c16 0);
        gelapsed = (if bug 2 then range dlo dhi else range (add ~w:16 dlo (c16 1)) (add ~w:16 dhi (c16 1)));
        gat = range dlo dhi; gev = ev; gq = 0; goe_known' = k.goe_known; goe' = k.goe } in
    (* a wait whose condition is known: it holds on its first slot or never (nothing it reads
       changes while it waits) *)
    let decided holds = [ one ~guard:holds pc1; fail ~guard:(not_ holds) () ] in
    match op with
    | 0 -> [ one pc1 ]                                            (* NOP *)
    | 1 ->                                                       (* SETP *)
      let mask = (w lsr 4) land 0xFF in
      let level = if bit_w 2 then (if bit_w 3 then Spec.H else Spec.L) else Spec.Z in
      let ev = List.filter_map (fun p -> if (mask lsr p) land 1 = 1 then Some (p, Spec.Write { level; data = false }) else None)
          [ 0; 1; 2; 3; 4; 5; 6; 7 ] in
      let kmask = D.k ~w:8 mask in
      let oe' = logor (logand k.goe (lognot ~w:8 kmask)) (if bit_w 2 then kmask else D.k ~w:8 0) in
      [ one ~ev ~q:(w land 3) ~oe:(logor k.goe_known kmask, oe') pc1 ]
    | 2 -> [ one ~cnt:(GKnown (D.k ~w:12 imm12)) pc1 ]           (* LDC *)
    | 3 ->                                                       (* LDD: no decrement this slot *)
      let n = if bug 3 then max 0 (imm12 - 1) else imm12 in
      [ one ~dl':(exactly (c16 n)) ~timing:(Load n) pc1 ]
    | 4 -> [ one ~acc:(GKnown (D.k ~w:8 imm8)) pc1 ]             (* LDA *)
    | 5 ->                                                       (* WAITP *)
      [ proceed ~ev:[ (pin, Spec.Observe b8) ] (); fail ~ev:[ (pin, Spec.Expire b8) ] () ]
    | 6 ->                                                       (* WAITD: stays until dl = 0 *)
      [ { guard = tt; gtiming = Until_due; gnext_pc = pc1; gcnt' = k.gcnt; gacc' = k.gacc; gdl' = exactly (c16 0);
          gelapsed = (if bug 7 then range dlo dhi else range (add ~w:16 dlo (c16 1)) (add ~w:16 dhi (c16 1)));
          gat = exactly (c16 0); gev = []; gq = 0; goe_known' = k.goe_known; goe' = k.goe } ]
    | 7 ->                                                       (* SHO *)
      let msb = b8 = 1 and od = bit_w 7 and pair = bit_w 6 and psel = bit_w 5 and cap = bit_w 4 in
      let p2 = (pin + 1) land 7 in
      let written_pins = pin :: (if pair then [ p2 ] else []) in
      (* the data bits: with acc known, each value of b0 (and b1) under its guard *)
      let data_cases = match k.gacc with
        | GKnown a ->
          let i0 = if msb then 7 else 0 and i1 = if msb then 6 else 1 in
          List.concat_map (fun v0 ->
              let g0 = if v0 = 1 then bit a i0 else not_ (bit a i0) in
              if not psel then [ (g0, Some v0, Some (1 - v0)) ]
              else List.map (fun v1 -> (and_ g0 (if v1 = 1 then bit a i1 else not_ (bit a i1)), Some v0, Some v1)) [ 0; 1 ])
            [ 0; 1 ]
        | GAny -> [ (tt, None, None) ] in
      let acc = match k.gacc with
        | GKnown a ->
          let sh = if pair && psel then 2 else 1 in
          if cap then GAny else GKnown (if msb then shl ~w:8 a sh else lshr a sh)
        | GAny -> GAny in
      (* push-pull: the level is the data where the enable is known 1, released where it is known
         0, unknown otherwise (A5); each case of the written pins' enables under its guard *)
      let enable_cases =
        if od || bug 6 then [ (tt, List.map (fun p -> (p, `Driven)) written_pins) ]
        else
          List.fold_left (fun acc p ->
              let known = bit k.goe_known p and on = bit k.goe p in
              List.concat_map (fun (g, l) ->
                  [ (and_ g (not_ known), l @ [ (p, `Unknown) ]);
                    (and_ g (and_ known (not_ on)), l @ [ (p, `Released) ]);
                    (and_ g (and_ known on), l @ [ (p, `Driven) ]) ]) acc)
            [ (tt, []) ] written_pins in
      List.concat_map (fun (gd, b0, b1) ->
          List.map (fun (ge, en) ->
              let written = (pin, b0) :: (if pair then [ (p2, b1) ] else []) in
              let pp_level p v = match List.assoc p en with
                | `Unknown -> Spec.X
                | `Released -> Spec.Z
                | `Driven -> (match v with Some v -> level_of ~od:false v | None -> Spec.LH) in
              let od_level v = match v with Some v -> level_of ~od:true v | None -> Spec.LZ in
              let ev = List.map (fun (p, v) -> (p, Spec.Write { level = (if od then od_level v else pp_level p v); data = true })) written in
              let oe = if not od then same_oe else
                  List.fold_left (fun (kn, o) (p, v) ->
                      let m = D.k ~w:8 (1 lsl p) in
                      match v with
                      | Some v -> (logor kn m, if v = 0 then logor o m else logand o (lognot ~w:8 m))
                      | None -> (logand kn (lognot ~w:8 m), logand o (lognot ~w:8 m))) same_oe written in
              one ~guard:(and_ gd ge) ~ev:(List.sort compare ev) ~q:(if od then 0 else w land 3) ~cnt:dec_cnt ~acc ~oe pc1)
            enable_cases) data_cases
    | 8 -> [ one ~ev:[ (pin, Spec.Sample) ] ~cnt:dec_cnt ~acc:GAny pc1 ]   (* SHI *)
    | 9 -> [ one (D.k ~w:8 imm8) ]                                (* JMP; HALT is JMP self *)
    | 10 ->                                                      (* JNZ *)
      (match k.gcnt with
       | GKnown c ->
         let zero = eq c (D.k ~w:12 0) in
         let falls = if bug 4 then or_ zero (eq c (D.k ~w:12 1)) else zero in
         [ one ~guard:falls pc1; one ~guard:(not_ falls) (D.k ~w:8 imm8) ]
       | GAny -> [ one (D.k ~w:8 imm8); one ~cnt:(GKnown (D.k ~w:12 0)) pc1 ])
    | 11 -> [ one pc1 ]                                           (* OUT *)
    | 12 ->                                                      (* IN: A1, no bound *)
      [ { guard = tt; gtiming = Unbounded; gnext_pc = pc1; gcnt' = k.gcnt; gacc' = GAny; gdl' = range (c16 0) (max0_minus1 dhi);
          gelapsed = { glo = c16 1; ghi = None }; gat = exactly (c16 0); gev = []; gq = 0;
          goe_known' = k.goe_known; goe' = k.goe } ]
    | 13 ->                                                      (* MBX: A1 *)
      let recv = bit_w 11 in
      [ proceed ~acc:(if recv then GAny else k.gacc) (); fail () ]
    | 14 ->                                                      (* WAITC *)
      let cond = (w lsr 8) land 15 in
      (match cond, k.gacc, k.gcnt with
       | c, GKnown a, _ when c < 8 -> decided (bit a c)
       | 8, _, GKnown n -> decided (eq (logand n (D.k ~w:12 7)) (D.k ~w:12 0))
       | _ -> [ proceed (); fail () ])
    | _ ->                                                       (* EXT *)
      (match (w lsr 8) land 15 with
       | 0 | 1 as sub ->                                         (* SKNE, SKEQ *)
         let skip_if_equal = sub = 1 in
         let pc2 = add ~w:8 k.gpc (D.k ~w:8 2) in
         (match k.gacc with
          | GKnown a ->
            let equal = eq a (D.k ~w:8 imm8) in
            let skips = if skip_if_equal <> bug 5 then equal else not_ equal in
            [ one ~guard:skips pc2; one ~guard:(not_ skips) pc1 ]
          | GAny -> [ one pc1; one pc2 ])
       | 3 -> [ one ~cnt:(match k.gacc with GKnown a -> GKnown (zext ~w:12 a) | GAny -> GAny) pc1 ]   (* CNTA *)
       | 4 -> [ one ~acc:GAny pc1 ]                              (* LDB: A1 *)
       | _ -> [ one pc1 ])                                       (* FINE STB BANK CFG reserved *)
end

(* the integer domain: values are OCaml integers kept inside their width *)
module Int_dom = struct
  type v = int
  type b = bool
  let mask w = (1 lsl w) - 1
  let k ~w n = n land mask w
  let add ~w x y = (x + y) land mask w
  let sub ~w x y = (x - y) land mask w
  let logand = ( land )
  let logor = ( lor )
  let lognot ~w x = lnot x land mask w
  let shl ~w x s = (x lsl s) land mask w
  let lshr x s = x lsr s
  let zext ~w:_ x = x
  let bit x i = (x lsr i) land 1 = 1
  let eq = ( = )
  let ite s x y = if s then x else y
  let tt = true
  let not_ = not
  let and_ = ( && )
  let or_ = ( || )
end

module Int_step = Step (Int_dom)

let interval_of_g (g : int ginterval) = { Interval.lo = g.glo; hi = g.ghi }
let known_of_g = function GKnown v -> Known v | GAny -> Any

(* [transfer w k dl] lists every outcome of the instruction word [w] at [k] whose deadline
   register is in [dl]. Each outcome's event, if any, happens in the last slot the instruction
   takes, so the next instruction issues one slot after it. *)
let transfer w (k : key) (dl : Interval.t) : raw list =
  let gk = { gpc = k.pc; gcnt = (match k.cnt with Known c -> GKnown c | Any -> GAny);
             gacc = (match k.acc with Known a -> GKnown a | Any -> GAny); goe_known = k.oe_known; goe = k.oe } in
  List.filter_map (fun (r : (int, bool) graw) ->
      if not r.guard then None
      else Some { timing = r.gtiming; next_pc = r.gnext_pc; cnt' = known_of_g r.gcnt'; acc' = known_of_g r.gacc';
                  dl' = interval_of_g r.gdl'; oe_known' = r.goe_known'; oe' = r.goe'; elapsed = interval_of_g r.gelapsed;
                  at = interval_of_g r.gat; ev = r.gev; q = r.gq })
    (Int_step.transfer w gk { glo = dl.Interval.lo; ghi = dl.hi })

(* ---- one step against the specification ---- *)

type violation =
  | Unexpected of { from : key; value : value; event : Spec.event; gap : Interval.t }
  | Bad_gap of { from : key; value : value; event : Spec.event; gap : Interval.t; tr : Spec.transition }
  | Bad_data of { from : key; event : Spec.event; tr : Spec.transition; expected : Spec.level }
  | Deadline of { at : key; value : value; deadline : int }
  | Not_closed of { from : key; reached : key; value : value }
  | No_start

(* A pin write or sample the thread makes, for the certificate: on any pin, with its time. *)
type prediction = {
  p_pc : int; p_word : int; p_from : int; p_to : int option;
  p_ev : (int * Spec.kind) list; p_time : Interval.t; p_gap : Interval.t option; p_q : int;
  p_allowed : Interval.t option;
  p_data : (int * int) option;     (* the transition's declared data (Spec [data]) *)
}

type succ = { s_key : key; s_value : value; s_event : bool }

let channel_event spec ev = List.filter (fun (p, _) -> List.mem p spec.Spec.pins) ev

(* The successors of an entry, the violations its step can make, and its predictions. *)
let step spec (words : int array) (k, v) =
  let raws = transfer words.(k.pc) k v.dl in
  List.fold_left (fun (succs, viols, preds) r ->
      let time_ev = Interval.plus v.time r.at in
      (* since and due at the next instruction, with no event: both bounds on since are sound, so
         their meet is; an empty meet is a combination no execution reaches *)
      let since_plain = Interval.plus v.since r.elapsed in
      let since' = match r.timing with
        | Until_due -> Interval.meet since_plain (Interval.shift v.due 1)
        | By_due -> (match v.due.hi with
            | Some h -> Interval.meet since_plain (Interval.at_most (h + 1))
            | None -> Some since_plain)
        | Plain | Load _ | Unbounded -> Some since_plain in
      let after = Option.map (fun since ->
          let due_plain = Interval.plus since r.dl' in
          let due = match r.timing with
            | Load n -> Some (Interval.shift since n)
            | Until_due -> Some since
            | Plain | By_due | Unbounded -> Interval.meet due_plain (Interval.max_ v.due since) in
          Option.map (fun due -> { dl = r.dl'; since; time = Interval.plus v.time r.elapsed; due }) due) since'
                  |> Option.join in
      let key' astate = { pc = r.next_pc; astate; cnt = r.cnt'; acc = r.acc'; oe_known = r.oe_known'; oe = r.oe' } in
      let pred ?to_ ?gap ?allowed ?data () =
        if r.ev = [] then [] else
          [ { p_pc = k.pc; p_word = words.(k.pc); p_from = k.astate; p_to = to_; p_ev = r.ev; p_time = time_ev;
              p_gap = gap; p_q = r.q; p_allowed = allowed; p_data = data } ] in
      match channel_event spec r.ev, after with
      | [], None -> (succs, viols, pred () @ preds)
      | [], Some after -> ({ s_key = key' k.astate; s_value = after; s_event = false } :: succs, viols, pred () @ preds)
      | ev, _ ->
        (* after an event, since restarts at 1 and due is 1 + dl *)
        let after = { dl = r.dl'; since = Interval.exactly 1; time = Interval.plus v.time r.elapsed;
                      due = Interval.shift r.dl' 1 } in
        let gap = Interval.plus v.since r.at in
        (match Spec.next spec k.astate ev with
         | None ->
           (succs, Unexpected { from = k; value = v; event = ev; gap } :: viols, pred ~gap () @ preds)
         | Some tr ->
           let viols = if bug 10 || Interval.leq gap tr.gap then viols
             else Bad_gap { from = k; value = v; event = ev; gap; tr } :: viols in
           (* the declared data: the one data pin's level must be the declared one, and known *)
           let viols = match Spec.data_level spec tr with
             | Some expected when not (bug 11) ->
               let pin = fst (List.find (fun (_, pat) -> pat = Spec.Data_pp || pat = Spec.Data_od) tr.pats) in
               let ok = List.exists (fun (p, kd) -> p = pin && match kd with
                   | Spec.Write { level; data = true } -> level = expected | _ -> false) ev in
               if ok then viols else Bad_data { from = k; event = ev; tr; expected } :: viols
             | _ -> viols in
           ({ s_key = key' tr.dst; s_value = after; s_event = true } :: succs,
            viols, pred ~to_:tr.dst ~gap ~allowed:tr.gap ?data:tr.data () @ preds)))
    ([], [], []) raws

let deadline_violation spec (k, v) =
  match Spec.deadline spec k.astate with
  | Some d when not (bug 8) && not (Interval.leq v.since (Interval.range 0 d)) -> Some (Deadline { at = k; value = v; deadline = d })
  | _ -> None

let start_key spec = { pc = 0; astate = spec.Spec.start; cnt = Known 0; acc = Known 0; oe_known = 0xFF; oe = 0 }
let start_value = { dl = Interval.exactly 0; since = Interval.exactly 0; time = Interval.exactly 0; due = Interval.exactly 0 }

(* ---- the certificate check ---- *)

type certificate = (key * value) list

type report = {
  entries : int;
  events_checked : int;          (* channel events with an accepted transition *)
  violations : violation list;
  predictions : prediction list;
  written : int;                 (* pins any reachable write touches *)
  finals : int;                  (* entries in a final state of the specification *)
}

let index (cert : certificate) =
  let h = Hashtbl.create 1024 in
  List.iter (fun ((k, _) as e) -> Hashtbl.replace h (k.pc, k.astate) (e :: (try Hashtbl.find h (k.pc, k.astate) with Not_found -> []))) cert;
  h

let covered h k v =
  bug 9 ||
  List.exists (fun (tk, tv) -> key_covers ~table:tk k && value_leq v tv)
    (try Hashtbl.find h (k.pc, k.astate) with Not_found -> [])

let check spec words (cert : certificate) =
  let h = index cert in
  let viols = ref (if covered h (start_key spec) start_value then [] else [ No_start ]) in
  let preds = ref [] and events = ref 0 and written = ref 0 and finals = ref 0 in
  List.iter (fun ((k, _) as e) ->
      if Spec.final spec k.astate then incr finals;
      (match deadline_violation spec e with Some x -> viols := x :: !viols | None -> ());
      let succs, vs, ps = step spec words e in
      viols := vs @ !viols; preds := ps @ !preds;
      List.iter (fun p ->
          List.iter (fun (pin, kind) -> match kind with Spec.Write _ -> written := !written lor (1 lsl pin) | _ -> ()) p.p_ev) ps;
      List.iter (fun s ->
          if s.s_event then incr events;
          if not (covered h s.s_key s.s_value) then
            viols := Not_closed { from = k; reached = s.s_key; value = s.s_value } :: !viols) succs) cert;
  { entries = List.length cert; events_checked = !events; violations = List.rev !viols;
    predictions = List.rev !preds; written = !written; finals = !finals }

let violation_to_string spec = function
  | Unexpected { from; event; gap; _ } ->
    Printf.sprintf "pc %d: event %s (gap %s) is not one the specification accepts in state %s"
      from.pc (Spec.event_to_string event) (Interval.to_string gap) (spec.Spec.state_name from.astate)
  | Bad_gap { from; event; gap; tr; _ } ->
    Printf.sprintf "pc %d: event %s (%s) has gap %s slots, declared %s" from.pc (Spec.event_to_string event)
      tr.label (Interval.to_string gap) (Interval.to_string tr.gap)
  | Bad_data { from; event; tr; expected } ->
    Printf.sprintf "pc %d: event %s (%s) does not leave the declared data %s = %s"
      from.pc (Spec.event_to_string event) tr.label
      (match tr.data with Some d -> Spec.data_to_string d | None -> "?") (Spec.level_to_string expected)
  | Deadline { at; value; deadline } ->
    Printf.sprintf "pc %d: %s slots may pass without an event in state %s, whose deadline is %d"
      at.pc (Interval.to_string value.since) (spec.Spec.state_name at.astate) deadline
  | Not_closed { from; reached; value } ->
    Printf.sprintf "certificate not closed: from pc %d the step reaches %s %s, which no entry contains"
      from.pc (key_to_string reached) (value_to_string value)
  | No_start -> "certificate does not contain the start state"

let violation_key = function
  | Unexpected { from; _ } | Bad_gap { from; _ } | Bad_data { from; _ } | Not_closed { from; _ } -> Some from
  | Deadline { at; _ } -> Some at
  | No_start -> None
