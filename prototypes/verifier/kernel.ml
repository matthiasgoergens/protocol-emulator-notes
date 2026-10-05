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
     key   pc; the state of the specification automaton; cnt and acc, each a known value or Any
     value dl (the deadline register); since (slots since the last channel event, or since the
           thread's first slot); time (slots since the thread's first slot)
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
      and nothing here bounds FINE. *)

type known = Known of int | Any
type key = { pc : int; astate : int; cnt : known; acc : known }
type value = { dl : Interval.t; since : Interval.t; time : Interval.t }

let known_to_string = function Known n -> string_of_int n | Any -> "?"

let key_to_string k =
  Printf.sprintf "pc=%d state=%d cnt=%s acc=%s" k.pc k.astate (known_to_string k.cnt) (known_to_string k.acc)

let value_to_string v =
  Printf.sprintf "dl=%s since=%s time=%s" (Interval.to_string v.dl) (Interval.to_string v.since)
    (Interval.to_string v.time)

let value_leq a b = Interval.leq a.dl b.dl && Interval.leq a.since b.since && Interval.leq a.time b.time
let value_join a b = { dl = Interval.join a.dl b.dl; since = Interval.join a.since b.since;
                       time = Interval.join a.time b.time }
let value_equal a b = Interval.equal a.dl b.dl && Interval.equal a.since b.since && Interval.equal a.time b.time

(* a key in the table covers a key reached when they agree on pc and state and the table's cnt
   and acc are Any or equal *)
let known_covers ~table x = match table, x with Any, _ -> true | Known a, Known b -> a = b | Known _, Any -> false
let key_covers ~table k =
  table.pc = k.pc && table.astate = k.astate && known_covers ~table:table.cnt k.cnt
  && known_covers ~table:table.acc k.acc

(* ---- the abstract step ---- *)

(* What one instruction does from its first issue to the first issue of the next instruction. *)
type raw = {
  next_pc : int; cnt' : known; acc' : known; dl' : Interval.t;
  elapsed : Interval.t;            (* slots until the next instruction first issues *)
  at : Interval.t;                 (* the slot of the event, counted from the first issue *)
  ev : (int * Spec.kind) list;     (* pins this instruction touches, all eight, ascending *)
  q : int;                         (* quarter-clock sub-slot of a write (A4) *)
}

let dl_max = 4095

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
  let one ?(ev = []) ?(q = 0) ?(cnt = k.cnt) ?(acc = k.acc) ?(dl' = dec) next_pc =
    { next_pc; cnt' = cnt; acc' = acc; dl'; elapsed = Interval.exactly 1; at = Interval.exactly 0; ev; q } in
  let dlo = dl.Interval.lo and dhi = match dl.hi with Some h -> h | None -> dl_max in
  (* A1: a wait that may proceed on any slot 0..d, or fail after slot d *)
  let proceed ?(ev = []) ?(acc = k.acc) () =
    { next_pc = pc1; cnt' = k.cnt; acc' = acc; dl' = Interval.range 0 (max (dhi - 1) 0);
      elapsed = Interval.range 1 (dhi + 1); at = Interval.range 0 dhi; ev; q = 0 } in
  let fail ?(ev = []) () =
    { next_pc = imm8; cnt' = k.cnt; acc' = k.acc; dl' = Interval.exactly 0;
      elapsed = Interval.range (dlo + 1) (dhi + 1); at = Interval.range dlo dhi; ev; q = 0 } in
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
    [ one ~ev ~q:(w land 3) pc1 ]
  | 2 -> [ one ~cnt:(Known imm12) pc1 ]                         (* LDC *)
  | 3 -> [ one ~dl':(Interval.exactly imm12) pc1 ]              (* LDD: no decrement this slot *)
  | 4 -> [ one ~acc:(Known imm8) pc1 ]                          (* LDA *)
  | 5 ->                                                       (* WAITP *)
    [ proceed ~ev:[ (pin, Spec.Observe b8) ] (); fail ~ev:[ (pin, Spec.Expire b8) ] () ]
  | 6 ->                                                       (* WAITD: stays until dl = 0 *)
    [ { next_pc = pc1; cnt' = k.cnt; acc' = k.acc; dl' = Interval.exactly 0;
        elapsed = Interval.range (dlo + 1) (dhi + 1); at = Interval.exactly 0; ev = []; q = 0 } ]
  | 7 ->                                                       (* SHO *)
    let msb = b8 = 1 and od = bit 7 and pair = bit 6 and psel = bit 5 and cap = bit 4 in
    let p2 = (pin + 1) land 7 in
    let ev, acc =
      match k.acc with
      | Known a ->
        let b0 = if msb then (a lsr 7) land 1 else a land 1 in
        let b1 = if psel then (if msb then (a lsr 6) land 1 else (a lsr 1) land 1) else 1 - b0 in
        let sh = if pair && psel then 2 else 1 in
        let acc = if cap then Any else Known (if msb then (a lsl sh) land 0xFF else a lsr sh) in
        let w v = Spec.Write { level = level_of ~od v; data = true } in
        ((pin, w b0) :: (if pair then [ (p2, w b1) ] else [])), acc
      | Any ->
        let w = Spec.Write { level = (if od then Spec.LZ else Spec.LH); data = true } in
        ((pin, w) :: (if pair then [ (p2, w) ] else [])), Any in
    [ one ~ev:(List.sort compare ev) ~q:(if od then 0 else w land 3) ~cnt:dec_cnt ~acc pc1 ]
  | 8 -> [ one ~ev:[ (pin, Spec.Sample) ] ~cnt:dec_cnt ~acc:Any pc1 ]   (* SHI *)
  | 9 -> [ one imm8 ]                                           (* JMP; HALT is JMP self *)
  | 10 ->                                                      (* JNZ *)
    (match k.cnt with
     | Known 0 -> [ one pc1 ]
     | Known _ -> [ one imm8 ]
     | Any -> [ one imm8; one ~cnt:(Known 0) pc1 ])
  | 11 -> [ one pc1 ]                                           (* OUT *)
  | 12 ->                                                      (* IN: A1, no bound *)
    [ { next_pc = pc1; cnt' = k.cnt; acc' = Any; dl' = Interval.range 0 (max (dhi - 1) 0);
        elapsed = Interval.at_least 1; at = Interval.exactly 0; ev = []; q = 0 } ]
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
        | Known a -> [ one (if (a = imm8) = skip_if_equal then pc2 else pc1) ]
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
      let after = { dl = r.dl'; since = Interval.plus v.since r.elapsed; time = Interval.plus v.time r.elapsed } in
      let key' astate = { pc = r.next_pc; astate; cnt = r.cnt'; acc = r.acc' } in
      let pred ?to_ ?gap ?allowed () =
        if r.ev = [] then [] else
          [ { p_pc = k.pc; p_word = words.(k.pc); p_from = k.astate; p_to = to_; p_ev = r.ev; p_time = time_ev;
              p_gap = gap; p_q = r.q; p_allowed = allowed } ] in
      match channel_event spec r.ev with
      | [] -> ({ s_key = key' k.astate; s_value = after; s_event = false } :: succs, viols, pred () @ preds)
      | ev ->
        let gap = Interval.plus v.since r.at in
        (match Spec.next spec k.astate ev with
         | None ->
           (succs, Unexpected { from = k; value = v; event = ev; gap } :: viols, pred ~gap () @ preds)
         | Some tr ->
           let viols = if Interval.leq gap tr.gap then viols
             else Bad_gap { from = k; value = v; event = ev; gap; tr } :: viols in
           ({ s_key = key' tr.dst; s_value = { after with since = Interval.exactly 1 }; s_event = true } :: succs,
            viols, pred ~to_:tr.dst ~gap ~allowed:tr.gap () @ preds)))
    ([], [], []) raws

let deadline_violation spec (k, v) =
  match Spec.deadline spec k.astate with
  | Some d when not (Interval.leq v.since (Interval.range 0 d)) -> Some (Deadline { at = k; value = v; deadline = d })
  | _ -> None

let start_key spec = { pc = 0; astate = spec.Spec.start; cnt = Known 0; acc = Known 0 }
let start_value = { dl = Interval.exactly 0; since = Interval.exactly 0; time = Interval.exactly 0 }

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
