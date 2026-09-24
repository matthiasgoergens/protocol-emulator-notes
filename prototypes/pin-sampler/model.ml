(* Pin sampler: executable specification. The receive-side mirror of the pin-vector streamer, and
   just as protocol-agnostic.

   It samples [width] pins (1, 2 or 4, pins 0..width-1 of its group), packs the vectors LSB first
   into 16-bit words, and pushes each word with its vector count (0 = full) into a four-entry output
   FIFO that the host drains. Two modes:

   - timed: armed until the trigger pin [trig_pin] reaches [trig_val] (an edge: it had the other
     value on the previous clock). Then, [offset] + 1 clocks after the edge, the first sample; then
     one every [period] clocks; after [frame_len] vectors the partial word is flushed and the sampler
     re-arms. UART receive: trigger on the falling start edge, offset half a bit, 10 vectors.
   - clocked: a sample on every edge of [trig_pin] to [trig_val], taken in the clock where the edge
     is seen. SPI's MISO on SCK rising, I2C's SDA on SCL rising. [frame_len] vectors make a frame.

   [frame_len] = 0 means no frames: only full words are pushed.
   A push into a full FIFO is dropped and counted in [overflows]. *)

let depth = 4

type cfg = {
  clocked : bool; period : int; width : int; trig_pin : int; trig_val : int; offset : int; frame_len : int;
}

type t = {
  cfg : cfg;
  fifo : (int * int) Queue.t;
  mutable prev : int;         (* pins on the previous clock *)
  mutable primed : bool;      (* prev holds a real sample: no edge is seen on the first clock, so a
                                 line idling at trig_val is not mistaken for an edge after reset
                                 (found by the I2C check: SCL idles high) *)
  mutable armed : bool;       (* timed mode: waiting for the trigger *)
  mutable cnt : int;
  mutable word : int;
  mutable n : int;            (* vectors in the current word *)
  mutable taken : int;        (* vectors in the current frame *)
  mutable overflows : int;
}

let create cfg = { cfg; fifo = Queue.create (); prev = 0; primed = false; armed = true; cnt = 0; word = 0; n = 0; taken = 0; overflows = 0 }

let per s = 16 / s.cfg.width

let push s =
  if Queue.length s.fifo >= depth then s.overflows <- s.overflows + 1
  else Queue.push (s.word, if s.n = per s then 0 else s.n) s.fifo;
  s.word <- 0; s.n <- 0

let take s pins =
  s.word <- s.word lor ((pins land ((1 lsl s.cfg.width) - 1)) lsl (s.n * s.cfg.width));
  s.n <- s.n + 1;
  s.taken <- s.taken + 1;
  let frame_done = s.cfg.frame_len > 0 && s.taken >= s.cfg.frame_len in
  if s.n = per s || (frame_done && s.n > 0) then push s;
  if frame_done then begin s.taken <- 0; s.armed <- true end

(* one clock with the pins as they are during it; [pop] = the host takes the FIFO head this clock
   (read before this clock's push lands, as in the RTL) *)
let step s ~pins ~pop =
  let head = if pop && not (Queue.is_empty s.fifo) then Some (Queue.pop s.fifo) else None in
  let bit v = (v lsr s.cfg.trig_pin) land 1 in
  let edge = s.primed && bit pins = s.cfg.trig_val && bit s.prev <> s.cfg.trig_val in
  (if s.cfg.clocked then (if edge then take s pins)
   else if s.armed then (if edge then begin s.armed <- false; s.cnt <- s.cfg.offset end)
   else if s.cnt = 0 then begin take s pins; if not s.armed then s.cnt <- s.cfg.period - 1 end
   else s.cnt <- s.cnt - 1);
  s.prev <- pins;
  s.primed <- true;
  head
