(* The untrusted half of the verifier: finds a certificate (kernel.ml) by abstract
   interpretation. A worklist runs [Kernel.step] from the start state to a fixpoint, joining the
   values that reach one key and widening a key's value after [widen_after] visits, as
   MarcosAsh's src/analyser.ml does for its own ISA (github.com/MarcosAsh/protocol-emulator,
   Apache-2.0; the idea, not the code).

   Precision comes from the keys. cnt and acc stay exact while they are known, so a counted loop
   (LDC 8 ... JNZ) is unrolled into one key per pass and its exit is decided, and the
   specification's state is part of the key, so the same pc in two places of a protocol (data bit
   3 and data bit 4) is analysed apart. To keep the table finite on any programme, a (pc, state)
   that already holds [key_limit] keys sends further keys to cnt = acc = Any.

   The analyser also keeps, for each key, the key it was first reached from, so that a violation
   can be reported with a path from pc 0. The path is through the abstract states; on an
   imprecise analysis it can be one no execution takes (README, "Soundness gaps"). *)

open Kernel

let widen_after = 4
let key_limit = 512

let widen ~old v =
  { dl = Interval.widen_to ~ceil:dl_max ~floor:0 ~old:old.dl v.dl;
    since = Interval.widen_to ~floor:0 ~old:old.since v.since;
    time = Interval.widen_to ~floor:0 ~old:old.time v.time;
    due = Interval.widen_to ~floor:0 ~old:old.due v.due }

type result = {
  cert : certificate;
  parent : (key, key) Hashtbl.t;
  visits : int;
}

let analyse spec (words : int array) =
  assert (Array.length words = Isa2.page_len);
  let table : (key, value * int) Hashtbl.t = Hashtbl.create 1024 in
  let per_site : (int * int, int) Hashtbl.t = Hashtbl.create 256 in
  let parent = Hashtbl.create 1024 in
  let work = Queue.create () in
  let visits = ref 0 in
  let general k =
    if Hashtbl.mem table k then k
    else
      let n = try Hashtbl.find per_site (k.pc, k.astate) with Not_found -> 0 in
      if n < key_limit then k else { k with cnt = Any; acc = Any; oe_known = 0; oe = 0 } in
  let visit ~from k v =
    incr visits;
    let k = general k in
    match Hashtbl.find_opt table k with
    | None ->
      Hashtbl.replace table k (v, 1);
      Hashtbl.replace per_site (k.pc, k.astate) (1 + try Hashtbl.find per_site (k.pc, k.astate) with Not_found -> 0);
      (match from with Some f -> Hashtbl.replace parent k f | None -> ());
      Queue.add k work
    | Some (old, n) ->
      let j = value_join old v in
      if not (value_equal j old) then begin
        let j = if n >= widen_after then widen ~old j else j in
        Hashtbl.replace table k (j, n + 1);
        Queue.add k work
      end in
  visit ~from:None (start_key spec) start_value;
  while not (Queue.is_empty work) do
    let k = Queue.pop work in
    let v, _ = Hashtbl.find table k in
    let succs, _, _ = step spec words (k, v) in
    List.iter (fun s -> visit ~from:(Some k) s.s_key s.s_value) succs
  done;
  let cert = Hashtbl.fold (fun k (v, _) acc -> (k, v) :: acc) table [] in
  let cert = List.sort (fun (a, _) (b, _) -> compare a b) cert in
  { cert; parent; visits = !visits }

(* the keys from the start to [k], first to last *)
let path r k =
  let rec go k acc n =
    if n > 100_000 then acc
    else match Hashtbl.find_opt r.parent k with
      | Some p -> go p (k :: acc) (n + 1)
      | None -> k :: acc in
  go k [] 0

let value_of r k = List.assoc_opt k r.cert
