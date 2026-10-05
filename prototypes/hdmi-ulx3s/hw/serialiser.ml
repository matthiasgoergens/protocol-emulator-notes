(* The 10:1 serialiser, in the fast (bit) clock domain.

   Four lanes in gpdi order: 0 blue, 1 green, 2 red, 3 clock.  The clock lane is the constant word
   0b00000_11111 sent through the same shift registers as the data, so it is high for the first
   five bit times of every pixel and the sink sees the pixel clock with the same delay as the data.
   (Gergo Erdi's HDMI.hs routes the pixel clock itself to the pin through a black box instead.)

   [bits_per_cycle] is 1 (single-edge, fast clock = 10 x pixel clock, 250 MHz) or 2 (fast clock =
   5 x pixel clock, 125 MHz, and the two bits of each cycle go to an ECP5 ODDRX1F, first bit [d0]).

   Crossing from the pixel domain.  Both clocks come from one PLL, but nextpnr does not relate
   them, so the transfer is made safe by construction instead of by timing analysis.  The pixel
   domain flips [toggle] on every pixel clock, on the same edge that updates the three words.  Here
   [toggle] passes two flip-flops; the first fast cycle in which the synchronised value has changed
   arms the loader: the words are captured one cycle later and then every [n] cycles after that,
   by a free-running counter.  The capture therefore happens 3 to 4 fast cycles after the words
   changed, and at least n - 4 cycles before they change again: at 250 MHz that is 12 ns of
   settling and 24 ns of margin; at 125 MHz 24 ns and 8 ns.  The first flip-flop may go metastable when a
   toggle edge lands on a fast edge; that can only move the arming by one cycle, which the window
   above absorbs.  After arming, every further toggle change is compared with the counter, and one
   more than a cycle away from the expected place sets the sticky [slip] flag (an LED on the
   board).  The PLL also offsets the pixel clock by half a bit-clock period (ecppll's --phase1), so
   the race should not arise at all; the design does not depend on that. *)
open! Base
open Hardcaml
open Signal

let clock_word = 0b00000_11111

type t = { lanes : Signal.t list; (** per lane, [bits_per_cycle] bits, bit 0 first in time *)
           armed : Signal.t; slip : Signal.t }

let create ~spec ~bits_per_cycle ~toggle ~words =
  let k = bits_per_cycle in
  assert (k = 1 || k = 2);
  let n = 10 / k in
  let s1 = reg spec toggle in
  let s2 = reg spec s1 in
  let s3 = reg spec s2 in
  let edge = s2 ^: s3 in
  let cw = num_bits_to_represent (n - 1) in
  let count = wire cw and armed = wire 1 in
  armed <== reg spec (armed |: edge);
  (* The first edge restarts the count at 0 on the next cycle; from then on [load] is high on the
     cycle after each count of n - 1, i.e. every n cycles.  [load] is a register, so the select of
     the forty shift-register multiplexers comes straight from a flip-flop. *)
  let last = count ==:. n - 1 in
  count <== reg spec (mux2 (~:armed &: edge) (zero cw) (mux2 last (zero cw) (count +:. 1)));
  let load = reg spec (mux2 armed last edge) in
  (* After arming, toggle edges arrive every n cycles, when the count is n - 1, or one cycle
     either side of it if the first synchroniser stage resolved differently this time. *)
  let slip = wire 1 in
  let expected = last |: (count ==:. n - 2) |: (count ==:. 0) in
  slip <== reg spec (slip |: (armed &: edge &: ~:expected));
  (* The shift registers need no clear: they are loaded before their output means anything. *)
  let spec_noclear = Reg_spec.override spec ~clear:gnd in
  let lane word =
    let sr = wire 10 in
    sr <== reg spec_noclear (mux2 load word (srl sr k));
    select sr (k - 1) 0
  in
  let words = words @ [ of_int ~width:10 clock_word ] in
  { lanes = List.map words ~f:lane; armed; slip }
