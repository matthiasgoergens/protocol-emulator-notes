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
     its gap inside the declared interval;
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

(* [transfer w k dl] lists every outcome of the instruction word [w] at [k] whose deadline
   register is in [dl]. Each outcome's event, if any, happens in the last slot the instruction
   takes, so the next instruction issues one slot after it. *)
let transfer w (k : key) (dl : Interval.t) : raw list =
  let op = (w lsr 12) land 15 in
  let imm12 = w land 0xFFF and imm8 = w land 0xFF in
  let pin = (w lsr 9) land 7 and b8 = (w lsr 8) land 1 in
  let bit i = (w lsr i) land 1 = 1 in
  let pc1 = (k.pc + 1) land 0xFF in
  let dec = Interval.sub_sat dl 1 in
  let dec_cnt = match k.cnt with Known c -> Known ((c - 1) land 0xFFF) | Any -> Any in
  let one ?(ev = []) ?(q = 0) ?(cnt = k.cnt) ?(acc = k.acc) ?(dl' = dec) ?(oe = (k.oe_known, k.oe)) ?(timing = Plain) next_pc =
    { timing; next_pc; cnt' = cnt; acc' = acc; dl'; elapsed = Interval.exactly 1; at = Interval.exactly 0; ev; q;
      oe_known' = fst oe; oe' = snd oe } in
  let same_oe = (k.oe_known, k.oe) in
  let oe_known' = k.oe_known and oe' = k.oe in
  let dlo = dl.Interval.lo and dhi = match dl.hi with Some h -> h | None -> dl_max in
  (* A1: a wait that may proceed on any slot 0..d, or fail after slot d *)
  let proceed ?(ev = []) ?(acc = k.acc) () =
    { timing = By_due; next_pc = pc1; cnt' = k.cnt; acc' = acc; dl' = Interval.range 0 (max (dhi - 1) 0);
      elapsed = Interval.range 1 (if bug 1 then dhi else dhi + 1); at = Interval.range 0 dhi; ev; q = 0; oe_known'; oe' } in
  let fail ?(ev = []) () =
    { timing = Until_due; next_pc = imm8; cnt' = k.cnt; acc' = k.acc; dl' = Interval.exactly 0;
      elapsed = (if bug 2 then Interval.range dlo dhi else Interval.range (dlo + 1) (dhi + 1)); at = Interval.range dlo dhi; ev; q = 0; oe_known'; oe' } in
  (* a wait whose condition is known: it holds on its first slot or never (nothing it reads
     changes while it waits) *)
  let decided holds = if holds then [ one pc1 ] else [ fail () ] in
  match op with
  | 0 -> [ one pc1 ]                                            (* NOP *)
  | 1 ->                                                       (* SETP *)
    let mask = (w lsr 4) land 0xFF in
    let level = if bit 2 then (if bit 3 then Spec.H else Spec.L) else Spec.Z in
    let ev = List.filter_map (fun p -> if (mask lsr p) land 1 = 1 then Some (p, Spec.Write { level; data = false }) else None)
        [ 0; 1; 2; 3; 4; 5; 6; 7 ] in
    [ one ~ev ~q:(w land 3) ~oe:(k.oe_known lor mask, (k.oe land lnot mask) lor (if bit 2 then mask else 0)) pc1 ]
  | 2 -> [ one ~cnt:(Known imm12) pc1 ]                         (* LDC *)
  | 3 -> let n = if bug 3 then max 0 (imm12 - 1) else imm12 in [ one ~dl':(Interval.exactly n) ~timing:(Load n) pc1 ]              (* LDD: no decrement this slot *)
  | 4 -> [ one ~acc:(Known imm8) pc1 ]                          (* LDA *)
  | 5 ->                                                       (* WAITP *)
    [ proceed ~ev:[ (pin, Spec.Observe b8) ] (); fail ~ev:[ (pin, Spec.Expire b8) ] () ]
  | 6 ->                                                       (* WAITD: stays until dl = 0 *)
    [ { timing = Until_due; next_pc = pc1; cnt' = k.cnt; acc' = k.acc; dl' = Interval.exactly 0;
        elapsed = (if bug 7 then Interval.range dlo dhi else Interval.range (dlo + 1) (dhi + 1)); at = Interval.exactly 0;
        ev = []; q = 0; oe_known'; oe' } ]
  | 7 ->                                                       (* SHO *)
    let msb = b8 = 1 and od = bit 7 and pair = bit 6 and psel = bit 5 and cap = bit 4 in
    let p2 = (pin + 1) land 7 in
    (* push-pull: the level is the data where the enable is known 1, released where it is known
       0, unknown otherwise (A5); open drain: the enable is the inverted data *)
    let pp_level p v =
      if bug 6 then (match v with Some v -> level_of ~od:false v | None -> Spec.LH)
      else if (k.oe_known lsr p) land 1 = 0 then Spec.X
      else if (k.oe lsr p) land 1 = 0 then Spec.Z
      else match v with Some v -> level_of ~od:false v | None -> Spec.LH in
    let od_level v = match v with Some v -> level_of ~od:true v | None -> Spec.LZ in
    let b0, b1, acc =
      match k.acc with
      | Known a ->
        let b0 = if msb then (a lsr 7) land 1 else a land 1 in
        let b1 = if psel then (if msb then (a lsr 6) land 1 else (a lsr 1) land 1) else 1 - b0 in
        let sh = if pair && psel then 2 else 1 in
        Some b0, Some b1, (if cap then Any else Known (if msb then (a lsl sh) land 0xFF else a lsr sh))
      | Any -> None, None, Any in
    let written = (pin, b0) :: (if pair then [ (p2, b1) ] else []) in
    let ev = List.map (fun (p, v) -> (p, Spec.Write { level = (if od then od_level v else pp_level p v); data = true })) written in
    let oe = if not od then same_oe else
        List.fold_left (fun (kn, o) (p, v) -> match v with
            | Some v -> (kn lor (1 lsl p), if v = 0 then o lor (1 lsl p) else o land lnot (1 lsl p))
            | None -> (kn land lnot (1 lsl p), o land lnot (1 lsl p))) same_oe written in
    [ one ~ev:(List.sort compare ev) ~q:(if od then 0 else w land 3) ~cnt:dec_cnt ~acc ~oe pc1 ]
  | 8 -> [ one ~ev:[ (pin, Spec.Sample) ] ~cnt:dec_cnt ~acc:Any pc1 ]   (* SHI *)
  | 9 -> [ one imm8 ]                                           (* JMP; HALT is JMP self *)
  | 10 ->                                                      (* JNZ *)
    (match k.cnt with
     | Known 0 -> [ one pc1 ]
     | Known c when bug 4 && c = 1 -> [ one pc1 ]
     | Known _ -> [ one imm8 ]
     | Any -> [ one imm8; one ~cnt:(Known 0) pc1 ])
  | 11 -> [ one pc1 ]                                           (* OUT *)
  | 12 ->                                                      (* IN: A1, no bound *)
    [ { timing = Unbounded; next_pc = pc1; cnt' = k.cnt; acc' = Any; dl' = Interval.range 0 (max (dhi - 1) 0);
        elapsed = Interval.at_least 1; at = Interval.exactly 0; ev = []; q = 0; oe_known'; oe' } ]
  | 13 ->                                                      (* MBX: A1 *)
    let recv = bit 11 in
    [ proceed ~acc:(if recv then Any else k.acc) (); fail () ]
  | 14 ->                                                      (* WAITC *)
    let cond = (w lsr 8) land 15 in
    (match cond, k.acc, k.cnt with
     | c, Known a, _ when c < 8 -> decided ((a lsr c) land 1 = 1)
     | 8, _, Known n -> decided (n land 7 = 0)
     | _ -> [ proceed (); fail () ])
  | _ ->                                                       (* EXT *)
    (match (w lsr 8) land 15 with
     | 0 | 1 as sub ->                                         (* SKNE, SKEQ *)
       let skip_if_equal = sub = 1 in
       let pc2 = (k.pc + 2) land 0xFF in
       (match k.acc with
        | Known a -> [ one (if ((a = imm8) = skip_if_equal) <> bug 5 then pc2 else pc1) ]
        | Any -> [ one pc1; one pc2 ])
     | 3 -> [ one ~cnt:(match k.acc with Known a -> Known a | Any -> Any) pc1 ]   (* CNTA *)
     | 4 -> [ one ~acc:Any pc1 ]                                (* LDB: A1 *)
     | _ -> [ one pc1 ])                                        (* FINE STB BANK CFG reserved *)

(* ---- one step against the specification ---- *)

type violation =
  | Unexpected of { from : key; value : value; event : Spec.event; gap : Interval.t }
  | Bad_gap of { from : key; value : value; event : Spec.event; gap : Interval.t; tr : Spec.transition }
  | Deadline of { at : key; value : value; deadline : int }
  | Not_closed of { from : key; reached : key; value : value }
  | No_start

(* A pin write or sample the thread makes, for the certificate: on any pin, with its time. *)
type prediction = {
  p_pc : int; p_word : int; p_from : int; p_to : int option;
  p_ev : (int * Spec.kind) list; p_time : Interval.t; p_gap : Interval.t option; p_q : int;
  p_allowed : Interval.t option;
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
      let pred ?to_ ?gap ?allowed () =
        if r.ev = [] then [] else
          [ { p_pc = k.pc; p_word = words.(k.pc); p_from = k.astate; p_to = to_; p_ev = r.ev; p_time = time_ev;
              p_gap = gap; p_q = r.q; p_allowed = allowed } ] in
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
           ({ s_key = key' tr.dst; s_value = after; s_event = true } :: succs,
            viols, pred ~to_:tr.dst ~gap ~allowed:tr.gap () @ preds)))
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
  | Deadline { at; value; deadline } ->
    Printf.sprintf "pc %d: %s slots may pass without an event in state %s, whose deadline is %d"
      at.pc (Interval.to_string value.since) (spec.Spec.state_name at.astate) deadline
  | Not_closed { from; reached; value } ->
    Printf.sprintf "certificate not closed: from pc %d the step reaches %s %s, which no entry contains"
      from.pc (key_to_string reached) (value_to_string value)
  | No_start -> "certificate does not contain the start state"

let violation_key = function
  | Unexpected { from; _ } | Bad_gap { from; _ } | Not_closed { from; _ } -> Some from
  | Deadline { at; _ } -> Some at
  | No_start -> None
