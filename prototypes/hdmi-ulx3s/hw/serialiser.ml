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
   arms the loader: the words are captured at that edge and then every [n] cycles after it, by a
   free-running counter.  The capture therefore happens 2 to 3 fast cycles after the words changed,
   and at least n - 3 cycles before they change again: at 250 MHz that is 8 ns of settling and
   28 ns of hold margin; at 125 MHz 16 ns and 16 ns.  The first flip-flop may go metastable when a
   toggle edge lands on a fast edge; that can only move the arming by one cycle, which the window
   above absorbs.  After arming, every further toggle change is compared with the counter, and a
   mismatch sets the sticky [slip] flag (an LED on the board). *)
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
  let at_load = count ==:. 0 in
  let load = mux2 armed at_load edge in
  armed <== reg spec (armed |: edge);
  count <== reg spec (mux2 load (of_int ~width:cw (1 % n)) (mux2 (count ==:. n - 1) (zero cw) (count +:. 1)));
  (* After arming, toggle edges arrive exactly every n cycles, on the cycle the counter is 0. *)
  let slip = wire 1 in
  slip <== reg spec (slip |: (armed &: edge &: ~:at_load));
  let lane word =
    let sr = wire 10 in
    sr <== reg spec (mux2 load word (srl sr k));
    select sr (k - 1) 0
  in
  let words = words @ [ of_int ~width:10 clock_word ] in
  { lanes = List.map words ~f:lane; armed; slip }
