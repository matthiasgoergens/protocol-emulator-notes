(* A demo reel of raster effects, as the CPU would run it: one line packet per scanline, nothing
   stored per pixel anywhere. Three original scenes, 180 fields each:
     A  copper bars behind a sine-wave text scroller (the scroller fills all 16 sprite slots)
     B  a rotozoomer: a checkerboard rotating and zooming, made by the two background accumulators
     C  a 3D star field flying out of the screen, with a pulsing title *)

let col hue luma = (hue lsl 4) lor luma
let first = Console.first_vis
let last = Console.first_vis + Console.nvis - 1
let cy = (first + last) / 2
let pi = 4.0 *. atan 1.0

let clip (x, bmp, c) =
  if x >= 256 || x <= -16 then None
  else if x >= 0 then Some (x, bmp, c)
  else let sh = (-x + 1) / 2 in let b = (bmp lsl sh) land 0xFF in if b = 0 then None else Some (0, b, c)

let w16 x = (int_of_float (Float.round x)) land 0xFFFF
let bg_solid c = [| c; c; 0; 0; 0; 0; 0; 0; 0; 0 |]

let packet_of bg sprites =
  let spr = List.filter_map clip sprites in
  let n = List.length spr in
  let spr = Array.of_list (if n > Console.nspr then List.filteri (fun i _ -> i >= n - Console.nspr) spr else spr) in
  let slot i = if i < Array.length spr then let (x, b, c) = spr.(i) in [| x; b; c |] else [| 0; 0; 0 |] in
  Array.concat (bg :: List.init Console.nspr slot)

(* text drawn with sprites: one glyph per sprite, rows doubled *)
let text_sprites ~line ~top ~x0 ~colour s =
  let r = (line - top) / 2 in
  if line < top || r >= 11 then []
  else List.init (String.length s) (fun i -> (x0 + 16 * i, (Font.glyph s.[i]).(r), colour i r))

(* ---------- scene A: copper bars and a sine scroller ---------- *)
let scroll_text = "     RACING THE BEAM ON A TINY TAPEOUT CHIP * NO FRAME BUFFER * SIXTEEN SPRITES PER LINE * HELLO JANE STREET *     "
let hues = [| 4; 5; 6; 8; 10; 12; 1; 3 |]

let scene_a t line =
  let tf = float t in
  let bar = ref (col 12 1) in
  Array.iteri (fun i h ->
    let y = float cy +. 92.0 *. sin (tf *. 0.045 +. float i *. 0.62) in
    let d = Float.abs (float line -. y) in
    if d <= 4.5 then bar := col h (10 - 2 * int_of_float d)) hues;
  let s = t * 2 in
  let first_glyph = s / 16 and sub = s mod 16 in
  let spr = ref [] in
  for i = 0 to 16 do
    let x = i * 16 - sub in
    let k = (first_glyph + i) mod String.length scroll_text in
    let top = cy - 11 + int_of_float (34.0 *. sin (tf *. 0.09 +. float x *. 0.028)) in
    let r = (line - top) / 2 in
    if line >= top && r < 11 then
      spr := (x, (Font.glyph scroll_text.[k]).(r), col (1 + (first_glyph + i) mod 12) (10 - r / 3)) :: !spr
  done;
  packet_of (bg_solid !bar) (List.rev !spr)

(* ---------- scene B: rotozoomer ---------- *)
let scene_b t line =
  let tf = float t in
  let th = tf *. 0.028 and s = 1.2 +. 0.75 *. sin (tf *. 0.033) in
  let c = cos th and sn = sin th in
  let dy = float (line - cy) in
  let ou = tf *. 1.7 and ov = tf *. 0.9 in
  let u px = ((float px -. 128.0) *. c -. dy *. sn) *. s +. ou in
  let v px = ((float px -. 128.0) *. sn +. dy *. c) *. s +. ov in
  let h1 = 1 + ((t / 6 + (line - first) / 28) mod 12) in
  let h2 = 1 + ((t / 6 + (line - first) / 28 + 6) mod 12) in
  let bg = [| col h1 3; col h2 8; w16 (u 0 *. 256.0) land 0xFF; w16 (u 0 *. 256.0) lsr 8;
              w16 (s *. c *. 256.0) land 0xFF; w16 (s *. c *. 256.0) lsr 8;
              w16 (v 0 *. 256.0) land 0xFF; w16 (v 0 *. 256.0) lsr 8;
              w16 (s *. sn *. 256.0) land 0xFF; w16 (s *. sn *. 256.0) lsr 8 |] in
  let msg = "NO MULTIPLIER" in
  let x0 = 128 - 8 * String.length msg in
  packet_of bg (text_sprites ~line ~top:(cy - 11) ~x0 ~colour:(fun _ _ -> col 0 10) msg)

(* ---------- scene C: 3D star field ---------- *)
let rng = ref 99
let rand () = rng := (!rng * 1103515245 + 12345) land 0x3FFFFFFF; float !rng /. float 0x3FFFFFFF
let stars = Array.init 220 (fun _ -> [| rand () *. 2.0 -. 1.0; rand () *. 2.0 -. 1.0; 0.05 +. rand () *. 0.95 |])
let star_frame = ref (-1)

let advance_stars t =
  if t <> !star_frame then begin
    star_frame := t;
    Array.iter (fun s ->
      s.(2) <- s.(2) -. 0.011;
      if s.(2) < 0.04 then (s.(0) <- rand () *. 2.0 -. 1.0; s.(1) <- rand () *. 2.0 -. 1.0; s.(2) <- 1.0)) stars
  end

let scene_c t line =
  advance_stars t;
  let spr = ref [] in
  Array.iter (fun s ->
    let z = s.(2) in
    let px = 128 + int_of_float (s.(0) /. z *. 70.0) and y = cy + int_of_float (s.(1) /. z *. 60.0) in
    let near = z < 0.25 in
    if line = y || (near && line = y + 1) then
      spr := (z, (px, (if near then 0xC0 else 0x80), col (if z < 0.5 then 0 else 12) (max 2 (10 - int_of_float (z *. 9.0))))) :: !spr) stars;
  let stars_sorted = List.map snd (List.sort (fun (a, _) (b, _) -> compare b a) !spr) in
  let msg = "TINY TAPEOUT" in
  let x0 = 128 - 8 * String.length msg in
  let pulse = 6 + int_of_float (4.0 *. sin (float t *. 0.15)) in
  let title = text_sprites ~line ~top:(cy - 11) ~x0 ~colour:(fun i _ -> col (1 + (i + t / 4) mod 12) pulse) msg in
  packet_of (bg_solid (col 0 0)) (stars_sorted @ title)

let scene_len = 180
let packet ~field ~line =
  let s = field / scene_len and t = field mod scene_len in
  match s mod 3 with
  | 0 -> scene_a t line
  | 1 -> scene_b t line
  | _ -> scene_c t line
