(* Property monitors, written once over the interpreter's value domain, like the interpreter. The
   bounded model checker runs them on SMT terms; a counterexample is then replayed on integers
   through the same monitors and the same interpreter (Isa2.Spec), so a reported violation is one
   the executable specification itself exhibits.

   Each monitor is ghost state stepped once per clock, after the clock's instruction, and returns
   [bad], which holds when the property fails at that clock. *)

type wait_kind = Waitp of int * int (* pin, value *) | Waitd

(* addresses are 10-bit store addresses, {page, pc} *)
type contract = { thread : int; anchor : int; wait : int; fail : int; slots : int; kind : wait_kind }

module Make (V : Isa2.VALUE) = struct
  module S = Isa2.Make (V)
  open V

  let c w n = const ~w n
  let bit x i = eq (extract x ~hi:i ~lo:i) (c 1 1)
  let never = c 16 0xFFFF

  (* (a) Deadline waits. A contract says: thread [thread]'s wait at store address [wait] has a
     window of [slots] of the thread's own slots, opened when the thread executes the
     instruction at [anchor] (normally the LDD that loads the deadline). Each time the wait
     executes, the only allowed outcomes are:
       - the event is present on this slot's pin input: proceed to wait + 1;
       - no event, and this is slot [slots] of the window: take the fail branch;
       - no event, earlier in the window: stay.
     Anything else, including staying after the window, is a violation. A WAITD has no event and
     its "fail branch" is wait + 1. The event is read from the raw pin input, independently of the
     interpreter's own pin path, so the contract is meaningful only for programmes that do not set
     the round latch (cfg bit 7). *)
  (* [since]: own slots since the anchor last executed (1 on the slot after it); [never] before *)
  type deadline = { contract : contract; mutable since : t }

  let deadline contract = { contract; since = never }

  let deadline_step m ~addr_before ~addr_after ~(io : S.io) =
    let k = m.contract in
    let at a = eq addr_before (c 10 a) and goes a = eq addr_after (c 10 a) in
    let event = match k.kind with Waitp (p, v) -> eq (extract io.pin_in ~hi:p ~lo:p) (c 1 v) | Waitd -> ff in
    let due = eq m.since (c 16 k.slots) and early = ult m.since (c 16 k.slots) in
    let ok =
      match k.kind with
      | Waitp _ ->
        or_ (and_ event (goes (k.wait + 1)))
          (and_ (not_ event) (or_ (and_ due (goes k.fail)) (and_ early (goes k.wait))))
      | Waitd -> or_ (and_ due (goes (k.wait + 1))) (and_ early (goes k.wait)) in
    let bad = and_ (at k.wait) (not_ ok) in
    (* outcomes, for the non-vacuity covers *)
    let left_by_event = and_ (at k.wait) (and_ event (goes (k.wait + 1))) in
    let left_by_deadline = and_ (at k.wait) (and_ (not_ event) (and_ due (goes k.fail))) in
    m.since <- ite (at k.anchor) (c 16 1) (ite (eq m.since never) never (add ~w:16 m.since (c 16 1)));
    bad, left_by_event, left_by_deadline

  (* (b) Pin ownership: the pins each thread has written (SETP mask, SHO pin and pair partner);
     bad when two threads have written a common pin. *)
  type ownership = { written : t array }

  let ownership () = { written = Array.make Isa2.n_threads (c 8 0) }

  let ownership_step o ~thread ~(e : S.effects) =
    o.written.(thread) <- logor o.written.(thread) e.pins_written;
    let bad = ref ff in
    for t = 0 to Isa2.n_threads - 1 do
      for u = t + 1 to Isa2.n_threads - 1 do
        bad := or_ !bad (not_ (eq (logand o.written.(t) o.written.(u)) (c 8 0)))
      done
    done;
    !bad

  (* (c) Isolation: two copies of the machine differ on [pins] (level, output enable, or any of
     the four quarter-clock levels). *)
  let quarter_mask pins =
    let m = ref 0 in
    for i = 0 to 7 do if (pins lsr i) land 1 = 1 then m := !m lor (0xF lsl (4 * i)) done; !m

  let pins_differ ~pins (a : S.state) (b : S.state) =
    let m = c 8 pins and m4 = c 32 (quarter_mask pins) in
    let differ x y msk = not_ (eq (logand x msk) (logand y msk)) in
    or_ (differ a.pin_out b.pin_out m) (or_ (differ a.pin_oe b.pin_oe m) (differ a.pin_sub b.pin_sub m4))

  (* the assumption a thread outside the protocol obeys: it never writes [pins] *)
  let keeps_off ~pins (e : S.effects) = eq (logand e.pins_written (c 8 pins)) (c 8 0)

  (* (e) Ownership of the bank, the inboxes and the ports (ownership.ml). Bad when the clock's
     instruction touches a bank address, an inbox or a port that the executing thread's
     declaration does not give it. The touches are the interpreter's own effects. *)
  let in_ranges a ranges =
    List.fold_left (fun r (lo, hi) -> or_ r (and_ (not_ (ult a (c 10 lo))) (not_ (ult (c 10 hi) a)))) ff ranges

  (* some bit of the 4-bit mask [m] outside [allowed] *)
  let outside m allowed = not_ (eq (logand m (c 4 (lnot (Ownership.mask allowed) land 0xF))) (c 4 0))

  let disobeys (o : Ownership.thread) (e : S.effects) =
    let rd, ra = e.bank_read and wr, wa, _ = e.bank_write in
    List.fold_left or_ ff
      [ and_ rd (not_ (in_ranges ra o.bank_read)); and_ wr (not_ (in_ranges wa o.bank_write));
        outside e.inbox_send o.inbox_send; outside e.inbox_recv o.inbox_recv;
        outside e.port_out o.port_out; outside e.port_in o.port_in ]

  let resources_step (o : Ownership.t) ~thread ~(e : S.effects) = disobeys o.(thread) e

  (* the assumption a thread outside the protocol obeys: it keeps to its declaration *)
  let obeys (o : Ownership.thread) (e : S.effects) = not_ (disobeys o e)

  (* (d) A UART receiver, 8N1, lsb first, independent of the compiler: it watches the line (the
     pin's level when driven, 1 when released), starts at a falling edge while idle, and samples
     the middle of each bit, [bit_clocks] / 2 + k * [bit_clocks] clocks after the edge, k = 0..9.
     The intended frame is 0, the byte, 1, where the byte is the one the transmitting thread last
     took from the host (IN). Bad when a sample differs from the intended bit. *)
  type uart_rx = {
    pin : int; bit_clocks : int; tx_thread : int;
    mutable busy : t; mutable count : t; mutable byte : t; mutable frames : t;
  }

  let uart_rx ~pin ~bit_clocks ~tx_thread =
    assert (bit_clocks mod 2 = 0);
    { pin; bit_clocks; tx_thread; busy = c 1 0; count = c 16 0; byte = c 8 0; frames = c 8 0 }

  let uart_rx_step r ~thread ~(io : S.io) ~(e : S.effects) ~(st : S.state) =
    let line = ite (bit st.pin_oe r.pin) (extract st.pin_out ~hi:r.pin ~lo:r.pin) (c 1 1) in
    if thread = r.tx_thread then r.byte <- ite e.host_in_ready io.host_in r.byte;
    let busy = eq r.busy (c 1 1) in
    let count = ite busy (add ~w:16 r.count (c 16 1)) (c 16 0) in
    let half = r.bit_clocks / 2 in
    let bad = ref ff in
    for k = 0 to 9 do
      let expected = if k = 0 then c 1 0 else if k = 9 then c 1 1 else extract r.byte ~hi:(k - 1) ~lo:(k - 1) in
      let sample = and_ busy (eq count (c 16 (half + k * r.bit_clocks))) in
      bad := or_ !bad (and_ sample (not_ (eq line expected)))
    done;
    let last = and_ busy (eq count (c 16 (half + 9 * r.bit_clocks))) in
    r.busy <- ite (and_ (not_ busy) (eq line (c 1 0))) (c 1 1) (ite last (c 1 0) r.busy);
    r.frames <- ite last (add ~w:8 r.frames (c 8 1)) r.frames;
    r.count <- count;
    !bad
end
