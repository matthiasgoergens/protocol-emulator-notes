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
    let g = (x - width / 2) * 256 / (width / 2) in
    g, g, g

(* Hardware version.  The bar index x * 8 / width and the ramp need constants only: both are
   compared against precomputed thresholds rather than divided. *)
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
  (* ramp g = (x - half) * 256 / half; for width 640 that is (x - 320) * 4 / 5, done as a lookup of
     thresholds would be large, so we compute (x - half) * 256 with a constant multiplier and
     compare: g is the number of k in 1..255 with (x - half) * 256 >= k * half. *)
  let xr = x -:. half in
  let ramp =
    let prod = uresize xr (Signal.width x + 9) *: of_int ~width:9 256 |> fun p -> uresize p (Signal.width x + 9) in
    (* g = floor(prod / half): binary long division by a constant, unrolled over 8 result bits *)
    let rec divide bitpos rem acc =
      if bitpos < 0 then acc
      else
        let d = of_int ~width:(Signal.width rem) (half lsl bitpos) in
        let ge = rem >=: d in
        divide (bitpos - 1) (mux2 ge (rem -: d) rem) (acc |: sll (uresize ge 8) bitpos)
    in
    divide 7 prod (zero 8)
  in
  let r, g, b =
    let pick a b c d =
      mux2 border ff (mux2 (y <:. band1) a (mux2 (y <:. band2) b (mux2 (x <:. half) c d)))
    in
    let (br, bg, bb), (gr, gg, gb) = bars, gradient in
    pick br gr check ramp, pick bg gg check ramp, pick bb gb check ramp
  in
  r, g, b
