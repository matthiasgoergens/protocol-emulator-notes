(* Pin-vector streamer: executable specification.

   A generic bit-level output primitive for the protocol emulator. It knows nothing about any
   protocol: every [period] clocks it drives the next [width]-bit vector (width 1, 2 or 4) onto pins
   0..width-1, taking vectors LSB first from 16-bit words in a FIFO that the host fills directly (the
   SNES's HDMA in spirit). Protocol knowledge lives in precomputation: framing bits, clock phases and
   line codes are already in the words.

   Pins: out and oe, 4 bits each. A pin in [od_mask] is open drain: a 1 releases it (oe 0), a 0 drives
   it low. When the FIFO runs dry at a word boundary the streamer goes idle: pins take [idle_out] /
   [idle_oe] until a word arrives.

   Timing: [step] is one clock. A vector is driven in the first clock at which a word is available,
   then one every [period] clocks. Within a clock the FIFO is read before that clock's host write
   lands (the register semantics of the RTL), so a harness calls [step] and then [push]. *)

let depth = 4

type cfg = { period : int; width : int; od_mask : int; idle_out : int; idle_oe : int }

type t = {
  cfg : cfg;
  fifo : int Queue.t;
  mutable word : int;        (* current word, remaining vectors in its low bits *)
  mutable left : int;        (* vectors left in the current word; 0 = need a word *)
  mutable count : int;       (* clocks until the next vector *)
  mutable active : bool;
  mutable out : int;
  mutable oe : int;
  mutable underflows : int;
}

let create cfg = { cfg; fifo = Queue.create (); word = 0; left = 0; count = 0; active = false;
                   out = cfg.idle_out; oe = cfg.idle_oe; underflows = 0 }

let full s = Queue.length s.fifo >= depth
let push s w = if not (full s) then Queue.push (w land 0xFFFF) s.fifo

let mask w = (1 lsl w) - 1

let drive s v =
  let m = mask s.cfg.width in
  let v = v land m in
  let od = s.cfg.od_mask land m in
  (* push-pull pins drive v with oe 1; open-drain pins drive 0, released (oe 0) when v is 1 *)
  s.out <- (v land lnot od) land m;
  s.oe <- (m land lnot od) lor (od land lnot v)

(* one clock; returns unit, pins in s.out / s.oe after the clock *)
let step s =
  if s.count > 0 then s.count <- s.count - 1
  else begin
    if s.left = 0 then begin
      if Queue.is_empty s.fifo then begin
        if s.active then s.underflows <- s.underflows + 1;
        s.active <- false; s.out <- s.cfg.idle_out; s.oe <- s.cfg.idle_oe
      end else begin
        s.word <- Queue.pop s.fifo; s.left <- 16 / s.cfg.width
      end
    end;
    if s.left > 0 then begin
      s.active <- true;
      drive s s.word;
      s.word <- s.word lsr s.cfg.width;
      s.left <- s.left - 1;
      s.count <- s.cfg.period - 1
    end
  end
