(* Step the interpreter and (optionally) the RTL together on the same inputs, counting any cycle on
   which they disagree. The world models are driven from the interpreter's state and effects, which
   equal the RTL's on every cycle the counter does not move. *)

type t = {
  c : Isa_mb.cfg; mem : int array array; st : Isa_mb.state; h : Harness_mb.t option;
  mutable mismatches : int; mutable cycle : int;
}

let make ?(rtl = true) c mem =
  { c; mem; st = Isa_mb.init c; h = (if rtl then Some (Harness_mb.make c mem) else None); mismatches = 0; cycle = 0 }

let step d (io : Isa_mb.io) =
  let e = Isa_mb.step d.st ~mem:d.mem io in
  (match d.h with
   | Some h -> let o = Harness_mb.cycle h io in if not (Harness_mb.agrees o d.st e) then d.mismatches <- d.mismatches + 1
   | None -> ());
  d.cycle <- d.cycle + 1;
  e

let pin_out d = d.st.pin_out
let pin_oe d = d.st.pin_oe

(* A random neighbour programme confined to [pins] and its own inboxes [own]: SETP masks and
   SHO/SHI pins are restricted, mailbox channels are restricted to [own] (no ports), everything
   else, including branches and deadlines, is random. Used to show isolation. *)
let random_neighbour ~plen ~pins ~own =
  let pins_l = List.filter (fun p -> (pins lsr p) land 1 = 1) (List.init 8 Fun.id) in
  let pick l = List.nth l (Random.int (List.length l)) in
  Array.init plen (fun _ ->
    let w = Random.int 0x10000 in
    let op = w lsr 12 in
    let fail = Random.int plen in
    match op with
    | 1 -> (w land lnot (0xFF lsl 4)) lor ((((w lsr 4) land 0xFF) land pins) lsl 4)
    | 7 | 8 -> (w land lnot (7 lsl 9)) lor (pick pins_l lsl 9)
    | 14 -> if Random.bool () then Isa_mb.send ~ch:(pick own) ~fail else Isa_mb.recv ~ch:(pick own) ~fail
    | 15 -> let cond = Random.int 16 in
      let cond = if cond >= 8 && cond < 12 then 8 + pick own else cond in
      Isa_mb.waitc ~cond ~value:(Random.int 2) ~fail
    | 3 -> (3 lsl 12) lor Random.int 64
    | _ -> w)
