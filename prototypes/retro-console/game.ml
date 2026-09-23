(* The demo game, as the CPU (the RP2040 on the demo board) would run it: game state updated once
   per field, and for every visible line a 54-byte packet built from precomputed tables.
   Original art and scene: a delta-wing fighter over a scrolling perspective checkerboard, a star
   field with parallax, saucers approaching from the horizon, lasers, explosions.
   Input: a scripted SNES pad (16-bit report, active high here for readability). *)

let col hue luma = (hue lsl 4) lor luma
let first = Console.first_vis
let horizon = 110                       (* first ground line *)
let last = Console.first_vis + Console.nvis - 1

(* precomputed on the host: depth of each ground line and the matching texture step *)
let depth y = 600.0 /. float (y - horizon + 2)
let step_of z = z *. 0.08               (* texture units per pixel at depth z *)

(* SNES report bits (the order the pad shifts them out) *)
let b_b = 0 and b_left = 6 and b_right = 7 and b_a = 8
let pad frame =
  let bit b = 1 lsl b in
  (if frame >= 10 && frame < 40 then bit b_right else 0)
  lor (if frame >= 55 && frame < 85 then bit b_left else 0)
  lor (if List.mem frame [ 20; 45; 70; 95; 105 ] then bit b_a else 0)
  lor (if frame >= 100 then bit b_b else 0)

let bits s = int_of_string ("0b" ^ s)
let ship_left = List.map bits [ "00000001"; "00000011"; "00000011"; "00000111"; "00001111"; "00011111";
                                "00111111"; "01111111"; "11111111"; "11110111"; "11100011"; "11000001" ]
let reverse8 x = let r = ref 0 in for i = 0 to 7 do if (x lsr i) land 1 = 1 then r := !r lor (1 lsl (7 - i)) done; !r
let ship_right = List.map reverse8 ship_left
let saucer_l = List.map bits [ "00011000"; "00111100"; "01111110"; "11011011"; "11111111"; "01111110"; "00100100"; "01000010" ]
let saucer_m = List.map bits [ "00011000"; "00111100"; "01111110"; "00100100" ]
let saucer_s = List.map bits [ "00011000"; "00111100" ]

type enemy = { mutable ex : float; mutable ez : float; mutable boom : int }
type shot = { mutable sx : float; mutable sz : float }

let rng = ref 12345
let rand () = rng := (!rng * 1103515245 + 12345) land 0x3FFFFFFF; !rng
let stars = Array.init 48 (fun _ -> (rand () mod 256, first + rand () mod (horizon - first - 4), rand () mod 3))

let frame = ref (-1)
let ship_x = ref 0.0 and cam = ref 0.0 and scroll = ref 0.0 and score = ref 0
let enemies = Array.init 4 (fun i -> { ex = float (i * 40 - 60); ez = 80.0 +. float (i * 60); boom = 0 })
let shots : shot list ref = ref []
let prev_pad = ref 0

let update f =
  frame := f;
  let p = pad f in
  if p land (1 lsl b_right) <> 0 then ship_x := !ship_x +. 1.5;
  if p land (1 lsl b_left) <> 0 then ship_x := !ship_x -. 1.5;
  cam := !cam +. (!ship_x -. !cam) *. 0.08;
  let speed = if p land (1 lsl b_b) <> 0 then 4.0 else 2.0 in       (* B: boost *)
  scroll := !scroll +. speed;
  if p land (1 lsl b_a) <> 0 && !prev_pad land (1 lsl b_a) = 0 then shots := { sx = !ship_x; sz = 6.0 } :: !shots;
  prev_pad := p;
  shots := List.filter (fun s -> s.sz <- s.sz +. 9.0; s.sz < 300.0) !shots;
  Array.iter (fun e ->
    if e.boom > 0 then (e.boom <- e.boom - 1; if e.boom = 0 then (e.ez <- 300.0; e.ex <- !ship_x +. float (rand () mod 120 - 60)))
    else begin
      e.ez <- e.ez -. speed *. 0.9;
      if e.ez < 4.5 then (e.ez <- 300.0; e.ex <- !ship_x +. float (rand () mod 120 - 60));
      List.iter (fun s ->
        if e.boom = 0 && Float.abs (s.sx -. e.ex) < 10.0 && Float.abs (s.sz -. e.ez) < 12.0 then
          (e.boom <- 16; s.sz <- 1000.0; incr score)) !shots
    end) enemies

(* screen position of a world point on the ground *)
let screen ~x ~z =
  let y = horizon - 2 + int_of_float (600.0 /. z) in
  let px = 128 + int_of_float ((x -. !cam) /. step_of z) in
  y, px

(* sprites covering [line], lowest priority first: (x, bitmap, colour) *)
let sprites line =
  let out = ref [] in
  let add x bmp c = if bmp <> 0 then out := (x, bmp, c) :: !out in
  if line < horizon then
    Array.iter (fun (sx, sy, tw) ->
      if sy = line then begin
        let x = (sx - int_of_float (!cam *. 0.6)) land 255 in
        let lum = if (!frame + tw * 7) mod 24 < 3 then 4 else 9 - tw * 2 in
        add x 0x80 (col 0 lum)
      end) stars;
  let objs = List.sort (fun (a, _) (b, _) -> compare b a)
      (Array.to_list (Array.map (fun e -> (e.ez, `E e)) enemies) @ List.map (fun s -> (s.sz, `S s)) !shots) in
  List.iter (fun (_, o) ->
    match o with
    | `E e ->
      let y, px = screen ~x:e.ex ~z:e.ez in
      let art, rep = if e.ez > 120.0 then saucer_s, 1 else if e.ez > 40.0 then saucer_m, 1 else saucer_l, 2 in
      let h = List.length art * rep in
      let r = line - (y - h + 1) in
      if r >= 0 && r < h then begin
        let c = if e.boom > 0 then (if e.boom mod 4 < 2 then col 15 10 else col 14 8)
          else if r / rep = 3 && rep = 2 then col 0 10 else col 13 (if e.ez > 120.0 then 5 else 7) in
        let bmp = if e.boom > 0 then List.nth art (r / rep) lxor (if e.boom mod 2 = 0 then 0x5A else 0xA5) else List.nth art (r / rep) in
        add (px - 8) bmp c
      end
    | `S s ->
      let y, px = screen ~x:s.sx ~z:s.sz in
      let h = if s.sz < 30.0 then 4 else 2 in
      if line > y - h && line <= y then add (px - 8) (if s.sz < 60.0 then 0x18 else 0x10) (col 12 10)) objs;
  (* the ship: two mirrored halves, cockpit and engine flame on top *)
  let top = last - 27 in
  let r = (line - top) / 2 in
  let sx = 128 + int_of_float ((!ship_x -. !cam) /. step_of (depth (last - 4))) - 16 in
  if line >= top && r < 12 then begin
    add sx (List.nth ship_left r) (col 0 8);
    add (sx + 16) (List.nth ship_right r) (col 0 8);
    if r >= 4 && r <= 7 then add (sx + 8) 0x3C (col 6 (if r = 4 then 9 else 6))
  end;
  if line >= top + 24 && line < top + 28 then add (sx + 8) (if !frame mod 4 < 2 then 0x18 else 0x3C) (col 14 (if !frame mod 3 = 0 then 10 else 8));
  let l = List.rev !out in
  let n = List.length l in
  if n > Console.nspr then List.filteri (fun i _ -> i >= n - Console.nspr) l else l

let clip (x, bmp, c) =
  if x >= 256 || x <= -16 then None
  else if x >= 0 then Some (x, bmp, c)
  else let sh = (-x + 1) / 2 in let b = (bmp lsl sh) land 0xFF in if b = 0 then None else Some (0, b, c)

let packet ~field ~line =
  if field <> !frame then update field;
  let bg =
    if line < horizon - 1 then
      let t = line - first in
      let lum = 1 + t * 4 / (horizon - first) in
      let hue = if t < 30 then 8 else 7 in
      [| col hue lum; col hue lum; 0; 0; 0; 0 |]
    else if line = horizon - 1 then [| col 14 6; col 14 6; 0; 0; 0; 0 |]
    else begin
      let z = depth line in
      let st = step_of z in
      let stepi = int_of_float (st *. 256.0) land 0xFFFF in
      let u0 = int_of_float ((!cam -. 128.0 *. st) *. 256.0) land 0xFFFF in
      let fog = min 7 (2 + (line - horizon) / 18) in
      let checker = int_of_float (Float.floor ((z +. !scroll) /. 20.0)) land 1 in
      let a = col 2 fog and b = col 3 (max 1 (fog - 2)) in
      let a, b = if checker = 1 then b, a else a, b in
      [| a; b; u0 land 0xFF; u0 lsr 8; stepi land 0xFF; stepi lsr 8 |]
    end in
  let spr = List.filter_map clip (sprites line) in
  let spr = Array.of_list spr in
  let slot i = if i < Array.length spr then let (x, b, c) = spr.(i) in [| x; b; c |] else [| 0; 0; 0 |] in
  Array.concat (bg :: List.init Console.nspr slot)
