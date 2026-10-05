(* SPDX-License-Identifier: Apache-2.0

   Integer intervals with an open upper end, for the timing verifier.

   Derived from src/interval.ml of github.com/MarcosAsh/protocol-emulator (commit 3333f0c,
   2026-10-04; author Marcos Ashton Iglesias), Apache-2.0. Changes made here: ported from Core to
   the OCaml standard library; the lower end is always finite (every quantity this verifier
   bounds, a count of slots or a register value, is at least zero), so [lo] is an [int]; [leq]
   (containment), [max_] and [widen_to] (widening to a known range instead of to no bound)
   added; [meet] returns [None] when empty; [clamp_low] and [disjoint] dropped, [minus] replaced
   by [sub_sat]. *)

type t = { lo : int; hi : int option }   (* [hi = None]: no upper bound *)

let exactly n = { lo = n; hi = Some n }
let range lo hi = assert (lo <= hi); { lo; hi = Some hi }
let at_least lo = { lo; hi = None }
let shift t n = { lo = t.lo + n; hi = Option.map (( + ) n) t.hi }

let join a b =
  { lo = min a.lo b.lo;
    hi = (match a.hi, b.hi with Some x, Some y -> Some (max x y) | _ -> None) }

let plus a b =
  { lo = a.lo + b.lo; hi = (match a.hi, b.hi with Some x, Some y -> Some (x + y) | _ -> None) }

(* the integers in both, if any *)
let meet a b =
  let lo = max a.lo b.lo in
  let hi = match a.hi, b.hi with Some x, Some y -> Some (min x y) | (Some _ as h), None | None, h -> h in
  match hi with Some h when h < lo -> None | _ -> Some { lo; hi }

(* [max x y] for x in [a] and y in [b] *)
let max_ a b =
  { lo = max a.lo b.lo; hi = (match a.hi, b.hi with Some x, Some y -> Some (max x y) | _ -> None) }

let at_most h = { lo = 0; hi = Some h }

(* [max (x - n) 0] for every x in [t]: a down-counter that stops at zero, after [n] steps *)
let sub_sat t n =
  { lo = max (t.lo - n) 0; hi = Option.map (fun h -> max (h - n) 0) t.hi }

(* every value of [a] is in [b] *)
let leq a b =
  a.lo >= b.lo && (match a.hi, b.hi with _, None -> true | None, Some _ -> false | Some x, Some y -> x <= y)

let contains t n = n >= t.lo && (match t.hi with None -> true | Some h -> n <= h)
let is_exact t = t.hi = Some t.lo

(* Widening: an end that moved since [old] goes to the end of the range ([floor] below, no bound
   above, or [ceil] above when the quantity has a known maximum). *)
let widen_to ?ceil ~floor ~old t =
  { lo = (if t.lo < old.lo then floor else t.lo);
    hi = (if t.hi = old.hi then t.hi else ceil) }

let equal a b = a.lo = b.lo && a.hi = b.hi

let to_string t =
  match t.hi with
  | Some h when h = t.lo -> string_of_int h
  | Some h -> Printf.sprintf "%d..%d" t.lo h
  | None -> Printf.sprintf "%d..?" t.lo
