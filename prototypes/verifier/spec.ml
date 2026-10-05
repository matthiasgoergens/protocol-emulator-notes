(* Timing specifications: what a programme declares about the pins of one channel.

   A channel is a set of pins that one thread owns. An *event* on the channel is one instruction
   doing something to some of its pins in one slot:
   - a write: SETP (a fixed level) or SHO (data from the accumulator), with the level each pin
     is left at (driven 0, driven 1, released) where the analysis knows it;
   - an observation: a WAITP on a channel pin that proceeds, i.e. saw the value it waited for;
   - an expiry: a WAITP on a channel pin whose deadline passed, so it jumped to its fail target;
   - a sample: SHI reading a channel pin.
   The time of an event is the slot in which its instruction issues (a slot is one instruction of
   one thread: four clocks). The *gap* of an event is the number of slots since the previous event
   on the channel, or since the thread's first slot for the first event.

   A specification is an automaton over events. Each transition names the event it accepts and
   the interval its gap must lie in; a state without transitions is final (the programme may do
   anything that is not a channel event, for ever). In any other state the next event must come
   within the largest upper gap bound of the state's transitions: that is the state's deadline,
   and a programme that can stay past it without an event (a HALT, an IN that never gets data, a
   loop) misses it. So one automaton states edge periods (gap = P), edge deadlines (gap <= D),
   input-bounded waits (gap in [1, D]) and the order of events, and a programme proves its
   specification when every event it can make is accepted with its gap inside the interval and no
   state's deadline can pass. *)

type level =
  | L    (* driven 0 *)
  | H    (* driven 1 *)
  | Z    (* released (output enable 0) *)
  | LH   (* driven, value from data, unknown here *)
  | LZ   (* open drain, value from data: driven 0 or released, unknown here *)
  | X    (* a push-pull write to a pin whose output enable is unknown: anything *)

type kind =
  | Write of { level : level; data : bool }   (* data: SHO (from the accumulator), else SETP *)
  | Observe of int                            (* WAITP proceeded, having seen this value *)
  | Expire of int                             (* WAITP for this value timed out *)
  | Sample                                    (* SHI read the pin *)

type event = (int * kind) list                (* the channel pins touched, in ascending order *)

let level_to_string = function L -> "0" | H -> "1" | Z -> "z" | LH -> "d" | LZ -> "dz" | X -> "x"

let kind_to_string = function
  | Write { level; data } -> (if data then "sho" else "set") ^ "=" ^ level_to_string level
  | Observe v -> Printf.sprintf "seen=%d" v
  | Expire v -> Printf.sprintf "timeout(%d)" v
  | Sample -> "sample"

let event_to_string (e : event) =
  String.concat " " (List.map (fun (p, k) -> Printf.sprintf "p%d:%s" p (kind_to_string k)) e)

(* Patterns that transitions match events with. *)
type pat =
  | Set of level      (* a SETP leaving exactly this level *)
  | Data_pp           (* a push-pull SHO: any of L, H, LH *)
  | Data_od           (* an open-drain SHO: any of L, Z, LZ *)
  | Seen of int
  | Timeout of int
  | Smp

let matches_kind pat k =
  match pat, k with
  | Set l, Write { level; data = false } -> l = level
  | Data_pp, Write { level = L | H | LH; data = true } -> true
  | Data_od, Write { level = L | Z | LZ; data = true } -> true
  | Seen v, Observe w -> v = w
  | Timeout v, Expire w -> v = w
  | Smp, Sample -> true
  | _ -> false

let matches (pats : (int * pat) list) (e : event) =
  List.length pats = List.length e
  && List.for_all2 (fun (p, pat) (q, k) -> p = q && matches_kind pat k)
       (List.sort compare pats) e

type transition = { src : int; pats : (int * pat) list; gap : Interval.t; dst : int; label : string }

type t = {
  name : string;
  pins : int list;                 (* the channel *)
  start : int;
  transitions : transition list;
  states : int;
  state_name : int -> string;
}

let outgoing s a = List.filter (fun tr -> tr.src = a) s.transitions

(* the transition an event takes, if any; specifications are deterministic (checked by
   [well_formed]) *)
let next s a e = List.find_opt (fun tr -> tr.src = a && matches tr.pats e) (outgoing s a)

let final s a = outgoing s a = []

(* the most slots the programme may spend in state [a] without an event; None: no limit *)
let deadline s a =
  match outgoing s a with
  | [] -> None
  | trs -> List.fold_left (fun acc tr -> match acc, tr.gap.Interval.hi with
      | Some x, Some y -> Some (max x y) | _ -> None) (Some 0) trs

let channel_mask s = List.fold_left (fun m p -> m lor (1 lsl p)) 0 s.pins

(* Two transitions from one state must not both match an event. Patterns are compared by their
   pins and by whether some event kind matches both. *)
let overlap a b =
  let some_kind pa pb =
    let kinds = [ Write { level = L; data = false }; Write { level = H; data = false };
                  Write { level = Z; data = false } ]
                @ List.concat_map (fun l -> [ Write { level = l; data = true } ]) [ L; H; Z; LH; LZ; X ]
                @ [ Observe 0; Observe 1; Expire 0; Expire 1; Sample ] in
    List.exists (fun k -> matches_kind pa k && matches_kind pb k) kinds in
  let sa = List.sort compare a and sb = List.sort compare b in
  List.length sa = List.length sb
  && List.for_all2 (fun (p, x) (q, y) -> p = q && some_kind x y) sa sb

let well_formed s =
  List.for_all (fun tr ->
      List.for_all (fun (p, _) -> List.mem p s.pins) tr.pats
      && List.for_all (fun tr' -> tr == tr' || tr'.src <> tr.src || not (overlap tr.pats tr'.pats))
           s.transitions) s.transitions

(* ---- building automata as scripts ---- *)

(* A builder appends states one transition at a time: [step b pats gap label] adds a transition
   from the current state to a fresh one and makes that current. [branch] adds a transition from
   a given state without moving the current one. *)
type builder = { mutable n : int; mutable cur : int; mutable trs : transition list;
                 mutable names : (int * string) list }

let builder () = { n = 1; cur = 0; trs = []; names = [ (0, "start") ] }

let fresh b name = let s = b.n in b.n <- b.n + 1; b.names <- (s, name) :: b.names; s

let add b ~src pats gap ~dst label = b.trs <- { src; pats; gap; dst; label } :: b.trs

let step b pats gap label =
  let s = fresh b label in
  add b ~src:b.cur pats gap ~dst:s label; b.cur <- s

let finish b ~name ~pins =
  let names = b.names in
  let s = { name; pins = List.sort_uniq compare pins; start = 0; transitions = List.rev b.trs;
            states = b.n;
            state_name = (fun a -> match List.assoc_opt a names with Some n -> n | None -> string_of_int a) } in
  if not (well_formed s) then failwith ("specification not deterministic or names a pin outside its channel: " ^ name);
  s

(* The trivial specification: no channel, so no event is checked and no deadline applies. The
   analysis still bounds every instruction's time; [Main] uses it for programmes without a
   specification and for the random-programme soundness check. *)
let unconstrained name = finish (builder ()) ~name ~pins:[]
