(* The platformer as the host (the RP2350) runs it: level, physics, enemies, camera, score, pad,
   all updated once per field; then, for every scanline, a Scene.line (tile slices with fine
   scroll, the sprite cells covering that line, the backdrop colour) for the encoder.
   Original game: "Pip" runs through a meadow of blocks, pipes, burrbugs, a lanternsnail and a
   snapweed. Input is a scripted SNES pad. *)

let tile_px = 16
let hud_lines = 32                    (* two tile rows of score bar, never scrolled *)
let rows = 13                         (* play-field rows: 208 lines *)

(* ---- the colour table (lookup-table entries), as (hue, luma, saturation 0/1/2) ---- *)
let colours = Array.make 64 (0, 0, 0)
let () =
  let set i c = colours.(i) <- c in
  (* background palettes *)
  set 1 (5, 2, 2); set 2 (5, 5, 2); set 3 (8, 6, 2);           (* earth *)
  set 5 (5, 1, 2); set 6 (4, 4, 2); set 7 (6, 8, 2);           (* blocks *)
  set 9 (8, 2, 2); set 10 (8, 5, 2); set 11 (7, 8, 2);         (* plants *)
  set 13 (11, 7, 1); set 14 (6, 9, 2); set 15 (0, 10, 0);      (* sky things *)
  (* sprite palettes *)
  set 17 (2, 1, 1); set 18 (10, 5, 2); set 19 (5, 8, 1);       (* Pip *)
  set 21 (12, 1, 1); set 22 (2, 4, 2); set 23 (0, 10, 0);      (* burrbug *)
  set 25 (8, 1, 2); set 26 (5, 6, 2); set 27 (6, 9, 1);        (* snail, snapweed *)
  set 29 (5, 1, 2); set 30 (4, 5, 2); set 31 (6, 9, 2);        (* scarf, coin, bumped block *)
  (* backdrop: 32 the score bar, 33-62 the sky, darker blue at the top *)
  set 32 (12, 1, 1);
  for i = 0 to 29 do set (33 + i) ((if i < 12 then 12 else 11), 4 + i * 5 / 29, 1) done

let lut_entry (h, l, sat) =
  let code = 4 + max 0 (min 10 l) in
  if h = 0 || sat = 0 then code
  else code lor ((((h - 1) * 256 + 6) / 12) lsl 4) lor (1 lsl 12) lor (if sat = 2 then 1 lsl 13 else 0)

let frame = ref (-1)

(* palette cycling: the coin colour pulses *)
let lut () =
  Array.init 64 (fun i ->
    if i = 63 then Sim.burst_entry
    else if i = 14 then lut_entry (6, 7 + [| 0; 1; 2; 3; 2; 1 |].((max 0 !frame / 5) mod 6), 2)
    else lut_entry colours.(i))

(* ---- the level ---- *)
type cell = Empty | Top | Soil | Ledge | Brick | Bonus | Used | PipeTL | PipeTR | PipeL | PipeR
          | BushL | BushR | CloudL | CloudR | Coin

let width = 64
let map = Array.make_matrix width rows Empty
let () =
  let set c r v = if c >= 0 && c < width then map.(c).(r) <- v in
  for c = 0 to width - 1 do
    if not (c = 23 || c = 24 || c = 45 || c = 46) then (set c 11 Top; set c 12 Soil)
  done;
  (* clouds *)
  List.iter (fun (c, r) -> set c r CloudL; set (c + 1) r CloudR) [ 3, 2; 11, 1; 19, 3; 27, 1; 36, 2; 48, 1; 57, 2 ];
  (* bushes in front of the sprites *)
  List.iter (fun c -> set c 10 BushL; set (c + 1) 10 BushR) [ 1; 7; 38 ];
  (* coins in the air *)
  List.iter (fun c -> set c 8 Coin) [ 4; 5; 6 ];
  (* blocks *)
  set 9 7 Brick; set 10 7 Bonus; set 11 7 Brick;
  (* a pipe, three tiles high, with a snapweed *)
  set 14 8 PipeTL; set 15 8 PipeTR; set 14 9 PipeL; set 15 9 PipeR; set 14 10 PipeL; set 15 10 PipeR;
  (* ledge beyond the pit, with coins *)
  List.iter (fun c -> set c 7 Ledge) [ 26; 27; 28 ];
  List.iter (fun c -> set c 5 Coin) [ 26; 27 ];
  (* a short pipe and a staircase of blocks *)
  set 33 9 PipeTL; set 34 9 PipeTR; set 33 10 PipeL; set 34 10 PipeR;
  List.iteri (fun i c -> for r = 10 - i to 10 do set c r Used done) [ 40; 41; 42 ];
  List.iter (fun c -> set c 6 Brick) [ 50; 51; 52 ]; set 51 6 Bonus

let solid = function
  | Top | Soil | Brick | Bonus | Used | PipeTL | PipeTR | PipeL | PipeR -> true
  | _ -> false

let cell c r = if c < 0 || c >= width || r < 0 then Empty else if r >= rows then Empty else map.(c).(r)

(* tile art, palette, front priority *)
let tile_of = function
  | Empty -> None
  | Top -> Some (Art.ground_top, 0, false) | Soil -> Some (Art.ground, 0, false)
  | Ledge -> Some (Art.ledge, 0, false)
  | Brick -> Some (Art.brick, 1, false) | Bonus -> Some (Art.bonus, 1, false) | Used -> Some (Art.used, 1, false)
  | PipeTL -> Some (Art.pipe_top_l, 2, false) | PipeTR -> Some (Art.pipe_top_r, 2, false)
  | PipeL -> Some (Art.pipe_l, 2, false) | PipeR -> Some (Art.pipe_r, 2, false)
  | BushL -> Some (Art.bush_l, 2, true) | BushR -> Some (Art.bush_r, 2, true)
  | CloudL -> Some (Art.cloud_l, 3, false) | CloudR -> Some (Art.cloud_r, 3, false)
  | Coin -> Some (Art.coin, 3, false)

(* ---- game state ---- *)
type enemy = { kind : [ `Bug | `Snail ]; mutable ex : float; mutable ey : float; mutable evx : float;
               mutable evy : float; mutable flat : int; mutable alive : bool }
let enemies = [
  { kind = `Bug; ex = 21.0 *. 16.0; ey = 160.0; evx = -0.6; evy = 0.0; flat = 0; alive = true };
  { kind = `Bug; ex = 31.0 *. 16.0; ey = 160.0; evx = -0.6; evy = 0.0; flat = 0; alive = true };
  { kind = `Snail; ex = 35.0 *. 16.0; ey = 160.0; evx = -0.35; evy = 0.0; flat = 0; alive = true } ]

let px = ref 40.0 and py = ref 152.0 and vx = ref 0.0 and vy = ref 0.0
let on_ground = ref true and facing_left = ref false and anim = ref 0.0
let cam = ref 0.0
let score = ref 0 and coins = ref 0 and time_left = ref 300
let bumps : (int * int * int) list ref = ref []          (* column, row, frames left *)
let pops : (float * float * int) list ref = ref []       (* coin knocked out: x, y, frames left *)
let events : string list ref = ref []
let prev_pad = ref 0

(* SNES pad bits in shift order *)
let b_b = 0 and b_left = 6 and b_right = 7 and b_a = 8
(* the scripted pad: A presses (field, frames held), B (run) held over intervals, right held
   except over [coast] intervals. PAD_A / PAD_B / PAD_COAST override them ("f:n,f:n"), for tuning. *)
let intervals default name =
  match Sys.getenv_opt name with
  | None -> default
  | Some s -> List.map (fun p -> Scanf.sscanf p "%d:%d" (fun a b -> (a, b))) (String.split_on_char ',' s)
let script_a = intervals [ (12, 5); (76, 6); (100, 20); (172, 20); (218, 16) ] "PAD_A"
let script_b = intervals [ (150, 1000) ] "PAD_B"
let coast = intervals [] "PAD_COAST"
let pad f =
  let bit b = 1 lsl b in
  let within l = List.exists (fun (s, n) -> f >= s && f < s + n) l in
  (if f >= 4 && not (within coast) then bit b_right else 0)
  lor (if within script_b then bit b_b else 0)
  lor (if within script_a then bit b_a else 0)

(* player box: 12 wide, 22 high, inside the 16 x 24 sprite *)
let box_l () = !px +. 2.0 and box_r () = !px +. 13.0
let hits_solid x0 x1 y0 y1 =
  let c0 = int_of_float (Float.floor (x0 /. 16.0)) and c1 = int_of_float (Float.floor (x1 /. 16.0)) in
  let r0 = int_of_float (Float.floor (y0 /. 16.0)) and r1 = int_of_float (Float.floor (y1 /. 16.0)) in
  let hit = ref None in
  for c = c0 to c1 do for r = r0 to r1 do if solid (cell c r) && !hit = None then hit := Some (c, r) done done;
  !hit

let log fmt = Printf.ksprintf (fun s -> events := Printf.sprintf "field %d: %s" !frame s :: !events) fmt

let update f =
  frame := f;
  let p = pad f in
  let held b = p land (1 lsl b) <> 0 and pressed b = p land (1 lsl b) <> 0 && !prev_pad land (1 lsl b) = 0 in
  let maxv = if held b_b then 2.6 else 1.7 in
  if held b_right then (vx := Float.min maxv (!vx +. 0.12); facing_left := false)
  else if held b_left then (vx := Float.max (-.maxv) (!vx -. 0.12); facing_left := true)
  else vx := !vx *. 0.85;
  if pressed b_a && !on_ground then (vy := -5.6; on_ground := false);
  vy := Float.min 5.0 (!vy +. (if held b_a && !vy < 0.0 then 0.19 else 0.34));
  (* horizontal move and collision *)
  px := !px +. !vx;
  (match hits_solid (box_l ()) (box_r ()) (!py +. 2.0) (!py +. 23.0) with
   | Some (c, _) ->
     if !vx > 0.0 then px := float (c * 16) -. 14.0 else px := float ((c + 1) * 16) -. 2.0;
     vx := 0.0
   | None -> ());
  if !px < !cam then (px := !cam; vx := 0.0);
  (* vertical *)
  py := !py +. !vy;
  on_ground := false;
  (if !vy >= 0.0 then begin
     (* landing on solid tiles or on ledges (one-way) *)
     let feet = !py +. 23.9 in
     let r = int_of_float (feet /. 16.0) in
     let c0 = int_of_float (box_l () /. 16.0) and c1 = int_of_float (box_r () /. 16.0) in
     let land_ = ref false in
     for c = c0 to c1 do
       let k = cell c r in
       if solid k || (k = Ledge && feet -. !vy <= float (r * 16) +. 1.0) then land_ := true
     done;
     if !land_ then (py := float (r * 16) -. 24.0; vy := 0.0; on_ground := true)
   end else
     match hits_solid (box_l () +. 1.0) (box_r () -. 1.0) (!py +. 2.0) (!py +. 2.0) with
     | Some (c, r) ->
       py := float ((r + 1) * 16) -. 2.0; vy := 0.0;
       (* bump the block nearest the head's centre *)
       let cc = int_of_float ((!px +. 8.0) /. 16.0) in
       let c = if solid (cell cc r) then cc else c in
       (match cell c r with
        | Bonus -> map.(c).(r) <- Used; incr coins; score := !score + 200;
          pops := (float (c * 16), float (r * 16 - 16), 24) :: !pops; bumps := (c, r, 8) :: !bumps;
          log "bonus block at column %d" c
        | Brick -> bumps := (c, r, 8) :: !bumps; score := !score + 10; log "brick bumped at column %d" c
        | _ -> ())
     | None -> ());
  if !py > 260.0 then (log "fell into a pit"; py := 152.0; px := !cam +. 40.0; vy := 0.0);
  (* coins *)
  for c = int_of_float (box_l () /. 16.0) to int_of_float (box_r () /. 16.0) do
    for r = int_of_float ((!py +. 2.0) /. 16.0) to int_of_float ((!py +. 23.0) /. 16.0) do
      if cell c r = Coin then (map.(c).(r) <- Empty; incr coins; score := !score + 50; log "coin at %d,%d" c r)
    done
  done;
  anim := !anim +. Float.abs !vx *. 0.12;
  (* enemies *)
  List.iter (fun e ->
    if e.flat > 0 then (e.flat <- e.flat - 1; if e.flat = 0 then e.alive <- false)
    else if e.alive && Float.abs (e.ex -. !cam) < 400.0 then begin
      e.ex <- e.ex +. e.evx;
      let w = if e.kind = `Snail then 32.0 else 16.0 in
      (match hits_solid (e.ex +. 1.0) (e.ex +. w -. 2.0) (e.ey +. 4.0) (e.ey +. 14.0) with
       | Some _ -> e.ex <- e.ex -. e.evx; e.evx <- -.e.evx
       | None -> ());
      e.evy <- Float.min 4.0 (e.evy +. 0.3);
      e.ey <- e.ey +. e.evy;
      (match hits_solid (e.ex +. 2.0) (e.ex +. w -. 3.0) (e.ey +. 15.9) (e.ey +. 15.9) with
       | Some (_, r) -> e.ey <- float (r * 16) -. 16.0; e.evy <- 0.0
       | None -> ());
      if e.ey > 260.0 then e.alive <- false;
      (* the player *)
      let overlap = box_r () > e.ex +. 2.0 && box_l () < e.ex +. w -. 2.0 && !py +. 23.0 > e.ey +. 3.0 && !py < e.ey +. 14.0 in
      if overlap then begin
        if !vy > 0.0 && !py +. 23.0 < e.ey +. 10.0 then begin
          e.flat <- 30; vy := -4.0; score := !score + 100;
          log "stomped a %s" (if e.kind = `Snail then "lanternsnail" else "burrbug")
        end else log "touched a %s (no harm in the demo)" (if e.kind = `Snail then "lanternsnail" else "burrbug")
      end
    end) enemies;
  bumps := List.filter_map (fun (c, r, n) -> if n > 1 then Some (c, r, n - 1) else None) !bumps;
  pops := List.filter_map (fun (x, y, n) -> if n > 1 then Some (x, y -. 2.5, n - 1) else None) !pops;
  (* camera: scroll forward only, keep Pip left of centre *)
  cam := Float.max !cam (Float.min (float (width * 16 - 256)) (!px -. 100.0));
  if f mod 25 = 24 then decr time_left;
  prev_pad := p

(* ---- per-line output ---- *)
let hud_rows = [| "  PIP           COINS     TIME  "; "" |]
let glyph ch =
  let code = Char.code ch in
  try List.assoc code Font.glyphs with Not_found -> List.assoc 32 Font.glyphs

let hud_line y =
  let text = if y < 16 then hud_rows.(0)
    else Printf.sprintf "  %06d          X%02d       %03d  " !score !coins !time_left in
  let gy = (if y < 16 then y - 3 else y - 17) in
  let pixel_at x =
    (* glyph pixel with a one-pixel shadow down and to the right *)
    let on x gy =
      if gy < 0 || gy >= 11 || x < 0 || x >= 256 then false
      else let ch = if x / 8 < String.length text then text.[x / 8] else ' ' in
        ((glyph ch).(gy) lsr (7 - x mod 8)) land 1 = 1 in
    if on x gy then 3 else if on (x - 1) (gy - 1) then 1 else 0 in
  let tiles = Array.init Scene.ntiles (fun j ->
    { Scene.pix = Array.init 16 (fun i -> pixel_at (16 * j + i)); pal = 3; front = false }) in
  { Scene.backdrop = 32; fine = 0; tiles; sprites = [] }

let sprite_pieces () =
  (* (world x, world y top, rows (pixel arrays), palette, flip, behind), lowest priority first *)
  let pieces = ref [] in
  let add x y rows pal flip behind = pieces := (x, y, rows, pal, flip, behind) :: !pieces in
  (* snapweed in the first pipe, behind it: rises and sinks every 140 fields *)
  let t = (max 0 !frame) mod 140 in
  let rise = if t < 30 then t else if t < 70 then 30 else if t < 100 then 100 - t else 0 in
  if rise > 0 then
    add (14 * 16 + 8) (8 * 16 - rise) (if (!frame / 12) mod 2 = 0 then Art.weed_open else Art.weed_shut) 2 false true;
  List.iter (fun (x, y, n) ->
    let c = Art.coin_spin.((n / 3) mod 2) in
    add (int_of_float x) (int_of_float y) (Array.map (Array.map (fun v -> if v = 2 then 3 else v)) c) 3 false false) !pops;
  List.iter (fun e ->
    if e.alive then begin
      let x = int_of_float e.ex and y = int_of_float e.ey in
      match e.kind with
      | `Bug -> add x y (if e.flat > 0 then Art.bug_flat else if (!frame / 8) mod 2 = 0 then Art.bug1 else Art.bug2) 1 (e.evx > 0.0) false
      | `Snail ->
        let left = e.evx < 0.0 in
        (* facing left: head on the left, both cells mirrored *)
        if left then (add x y Art.snail_head 2 true false; add (x + 16) y Art.snail_shell 2 true false)
        else (add x y Art.snail_shell 2 false false; add (x + 16) y Art.snail_head 2 false false)
    end) enemies;
  List.iter (fun (c, r, n) ->
    let lift = [| 0; 2; 4; 6; 6; 4; 2; 0; 0 |].(8 - n) in
    add (c * 16) (r * 16 - lift) (match cell c r with Used -> Art.used | _ -> Art.brick) 3 false false) !bumps;
  let body =
    if not !on_ground then Art.pip_jump
    else if Float.abs !vx < 0.3 then Art.pip_stand
    else if int_of_float !anim mod 2 = 0 then Art.pip_run1 else Art.pip_run2 in
  let x = int_of_float !px and y = int_of_float !py in
  add x y body 0 !facing_left false;
  let scarf = if Float.abs !vx > 1.0 || not !on_ground then Art.scarf_run else Art.scarf_still in
  add x (y + 10) scarf 3 !facing_left false;
  List.rev !pieces

let bumped c r = List.exists (fun (bc, br, _) -> bc = c && br = r) !bumps

let play_line y pieces =
  let wy = y - hud_lines in
  let r = wy / 16 and ty = wy mod 16 in
  let ci = int_of_float !cam in
  let c0 = ci / 16 and fine = ci mod 16 in
  let tiles = Array.init Scene.ntiles (fun j ->
    let c = c0 + j in
    match (if bumped c r then None else tile_of (cell c r)) with
    | None -> Scene.blank_tile
    | Some (art, pal, front) -> { Scene.pix = art.(ty); pal; front }) in
  let sprites = List.filter_map (fun (x, top, rows, pal, flip, behind) ->
    let k = wy - top in
    if k >= 0 && k < Array.length rows then
      Some { Scene.x = x - ci; spix = rows.(k); spal = pal; flip; behind }
    else None) pieces in
  { Scene.backdrop = 33 + (wy * 29 / 207); fine; tiles; sprites }

(* the whole visible frame as scanline descriptions (y 0-239) *)
let frame_lines () =
  let pieces = sprite_pieces () in
  Array.init 240 (fun y -> if y < hud_lines then hud_line y else play_line y pieces)

let cache = ref (-1, [||])
let lines_for f =
  if f <> !frame then update f;
  if fst !cache <> f then cache := (f, frame_lines ());
  snd !cache

let desc ~field ~line =
  if line >= Sim.first_vis && line < Sim.first_vis + Sim.nvis then Some (lines_for field).(line - Sim.first_vis)
  else None

let packet ~field ~line =
  match desc ~field ~line with Some l -> Scene.encode l | None -> Scene.encode_blank ()
