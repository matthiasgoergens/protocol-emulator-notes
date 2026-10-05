(* REFERENCE COPY, frozen: hw/ or demo/ as of emulator 7cf2f05, before the Delayed rewrite.
   Used only by test/test_latency.ml to show the rewrite is cycle-identical. Do not edit. *)
(* The test pattern, as hardware and as a software reference (used to build the expected PNG).
   Combinational in (x, y), so it is aligned with the syncs of the same cycle.

   Bands, top to bottom, for 640 x 480 (other sizes scale the bands by height):
   - y < 160: eight colour bars of 80 pixels (white, yellow, cyan, green, magenta, red, blue,
     black), the classic order;
   - 160 <= y < 320: r = x mod 256, g = y mod 256, b = (x xor y) mod 256: every byte value occurs on
     every channel, so the encoder sees all 256 inputs in many disparity states;
   - y >= 320: a one-pixel checkerboard in the left half (catches pixel slips and pairs of bits
     swapped in the serialiser) and a grey ramp in the right half.
   - A one-pixel white border round the whole active area: an off-by-one in the porches shows as a
     missing or doubled edge.

   [mode] picks the visible width and height. *)
open! Base
open Hardcaml
open Signal

let reference ~width ~height x y =
  let band1 = height / 3 and band2 = 2 * height / 3 in
  if x = 0 || y = 0 || x = width - 1 || y = height - 1 then 255, 255, 255
  else if y < band1 then
    let i = x * 8 / width in
    let on b = if b then 255 else 0 in
    (* white yellow cyan green magenta red blue black: r = bars 0,1,4,5; g = 0..3; b = 0,2,4,6 *)
    on (i = 0 || i = 1 || i = 4 || i = 5), on (i < 4), on (i % 2 = 0 && i < 7)
  else if y < band2 then x land 255, y land 255, (x lxor y) land 255
  else if x < width / 2 then
    let v = if (x + y) land 1 = 0 then 255 else 0 in
    v, v, v
  else
    let g = ((x - width / 2) * 205 / 256) land 255 in
    g, g, g

(* Hardware version.  The bar index x * 8 / width is a count of precomputed thresholds, so no
   divider is needed. *)
let create ~width ~height ~x ~y =
  let band1 = height / 3 and band2 = 2 * height / 3 in
  let w = width (* for readability below *) in
  let border = x ==:. 0 |: (y ==:. 0) |: (x ==:. w - 1) |: (y ==:. height - 1) in
  let ff = ones 8 and z = zero 8 in
  let sel b = mux2 b ff z in
  let bar_index =
    (* number of bar boundaries at or left of x: i = x * 8 / width *)
    List.init 7 ~f:(fun k ->
        let threshold = ((k + 1) * w + 7) / 8 (* smallest x with x * 8 / w >= k + 1 *) in
        uresize (x >=:. threshold) 3)
    |> List.reduce_exn ~f:( +: )
  in
  let i_is l = List.map l ~f:(fun k -> bar_index ==:. k) |> List.reduce_exn ~f:( |: ) in
  let bars = sel (i_is [ 0; 1; 4; 5 ]), sel (bar_index <:. 4), sel (i_is [ 0; 2; 4; 6 ]) in
  let lo8 s = uresize s 8 in
  let gradient = lo8 x, lo8 y, lo8 (x ^: uresize y (Signal.width x)) in
  let half = w / 2 in
  let check = sel (~:(lsb x ^: lsb y)) in
  (* ramp: g = (x - half) * 205 / 256, about (x - half) * 0.8, so 0 .. 255 over the 320 pixels
     of the right half at width 640; a constant multiply is a few adders *)
  let xr = uresize (x -:. half) 16 in
  let ramp = select (uresize (xr *: of_int ~width:8 205) 24) 15 8 in
  let r, g, b =
    let pick a b c d =
      mux2 border ff (mux2 (y <:. band1) a (mux2 (y <:. band2) b (mux2 (x <:. half) c d)))
    in
    let (br, bg, bb), (gr, gg, gb) = bars, gradient in
    pick br gr check ramp, pick bg gg check ramp, pick bb gb check ramp
  in
  r, g, b
