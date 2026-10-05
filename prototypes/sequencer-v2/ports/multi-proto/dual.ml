(* Replacement for ../../../multi-proto/dual.ml: the interpreter (Isa_mb over v2) and, optionally,
   the v2 RTL stepped together; a clock counts as a mismatch when any effect or any architectural
   state differs (the full v2 comparison of ../../lockstep2.ml, stronger than multi-proto's). *)

type t = {
  c : Isa_mb.cfg; mem : int array array; st : Isa_mb.state; h : Harness2.t option;
  mutable mismatches : int; mutable cycle : int;
}

let make ?(rtl = true) c mem =
  let st = Isa_mb.init c in
  { c; mem; st; h = (if rtl then Some (Harness2.make_f ~boot:Compat.boot_by_thread ~fetch:(Isa_mb.fetch_of mem) ()) else None);
    mismatches = 0; cycle = 0 }

let same_state (a : Isa2.state) (b : Isa2.state) =
  a.pcs = b.pcs && a.pages = b.pages && a.accs = b.accs && a.cnts = b.cnts && a.dls = b.dls && a.bps = b.bps
  && a.fines = b.fines && a.armed = b.armed && a.cfgs = b.cfgs && a.lsend = b.lsend && a.inbox = b.inbox
  && a.full = b.full && a.pin_out = b.pin_out && a.pin_oe = b.pin_oe && a.pin_sub = b.pin_sub
  && a.thread = b.thread && a.latch = b.latch

let step d (io : Isa_mb.io) =
  let e = Isa_mb.step d.st ~mem:d.mem io in
  (match d.h with
   | Some h ->
     let o = Harness2.cycle h (Isa_mb.to_v2_io io) in
     let ok = Option.map snd o.host_out = e.host_out && o.host_in_ready = e.host_in_ready
              && o.port_pop = e.port_pop && o.port_push = e.port_push
              && same_state d.st.v (Harness2.state h o) in
     if not ok then d.mismatches <- d.mismatches + 1
   | None -> ());
  d.cycle <- d.cycle + 1;
  e

let pin_out d = d.st.pin_out
let pin_oe d = d.st.pin_oe

(* A random v2 neighbour confined to [pins] and its own inboxes [own]: SETP masks and SHO/SHI pins
   are restricted (a paired SHO only when pin+1 is in [pins] too), mailbox channels are restricted
   to [own] (no ports); everything else, branches, deadlines and the EXT operations, is random. *)
let random_neighbour ~plen ~pins ~own =
  let pins_l = List.filter (fun p -> (pins lsr p) land 1 = 1) (List.init 8 Fun.id) in
  let pick l = List.nth l (Random.int (List.length l)) in
  let p = Array.init plen (fun _ ->
    let fail = Random.int plen in
    match Random.int 16 with
    | 1 -> Isa2.setp ~q:(Random.int 4) ~mask:(Random.int 256 land pins) ~value:(Random.int 2) ~oe:(Random.int 2) ()
    | 7 ->
      let pin = pick pins_l in
      let pair = if (pins lsr ((pin + 1) land 7)) land 1 = 1 then Random.int 2 else 0 in
      Isa2.sho ~od:(Random.int 2) ~pair ~psel:(Random.int 2) ~cap:(Random.int 2) ~pin ~msb:(Random.int 2) ()
    | 8 -> Isa2.shi ~quad:(Random.int 2) ~pin:(pick pins_l) ~msb:(Random.int 2) ()
    | 13 -> if Random.bool () then Isa2.send ~ch:(pick own) ~fail else Isa2.recv ~ch:(pick own) ~fail
    | 14 -> Isa2.waitc ~cond:(Random.int 16) ~fail
    | 15 -> Isa2.ext (Random.int 16) (Random.int 256)
    | 3 -> Isa2.ldd (Random.int 64)
    | 5 -> Isa2.waitp ~pin:(Random.int 8) ~value:(Random.int 2) ~fail
    | 9 -> Isa2.jmp (Random.int plen)
    | 10 -> Isa2.jnz (Random.int plen)
    | op -> (op lsl 12) lor Random.int 0x1000) in
  Asm.register p
