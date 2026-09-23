(* "Interference": an original game in the Fourier idea space. What you see is the sum of the
   waves. Invaders are frequencies whose waves slowly grow stronger; one left at full strength
   too long costs a life. The player owns one wave and cancels an invader by matching its
   frequency and phase with the opposite sign: destructive interference, visible as the
   invader's pattern fading while the player closes in.
   This is the CPU side (the RP2040 on the demo board): state updated once per field, and for
   every visible line a 66-byte packet. The pad is played by an autopilot for the demo. *)

let col hue luma = (hue lsl 4) lor luma
type w = { mutable kx : int; mutable ky : int; mutable phi : int; mutable omega : int; mutable shift : int; mutable age : int }

let rng = ref 4711
let rand m = rng := (!rng * 1103515245 + 12345) land 0x3FFFFFFF; (!rng lsr 8) mod m
let wavevec () =
  (* coarse waves only: wavelengths of about 40 to 120 pixels, so they survive composite colour *)
  let len = 550 + rand 1100 and ang = float (rand 360) *. Float.pi /. 180.0 in
  (int_of_float (float len *. cos ang), int_of_float (float len *. sin ang))
let spawn () = let kx, ky = wavevec () in
  { kx; ky; phi = rand 65536; omega = (if rand 2 = 0 then 1 else -1) * (300 + rand 700); shift = 3; age = 0 }

let enemies = ref [ spawn (); spawn () ]
let player = { kx = 0; ky = 900; phi = 0; omega = 0; shift = 3; age = 0 }
let flash = ref 0 and hurt = ref 0 and score = ref 0 and lives = ref 3 and cur = ref (-1)

let approach a b step = if abs (b - a) <= step then b else if b > a then a + step else a - step
let wrapdiff a b = let d = (b - a) land 0xFFFF in if d > 32768 then d - 65536 else d

let update field =
  cur := field;
  List.iter (fun e ->
    e.phi <- (e.phi + e.omega) land 0xFFFF; e.age <- e.age + 1;
    if e.age mod 110 = 0 && e.shift > 0 then e.shift <- e.shift - 1;
    if e.shift = 0 && e.age mod 110 = 100 then (hurt := 12; decr lives; e.shift <- 2)) !enemies;
  if field mod 140 = 70 && List.length !enemies < 5 then enemies := spawn () :: !enemies;
  (* autopilot: lock on to the strongest invader, then steer frequency, then phase *)
  (match List.sort (fun a b -> compare a.shift b.shift) !enemies with
   | target :: _ ->
     player.shift <- target.shift;
     player.kx <- approach player.kx target.kx 40;
     player.ky <- approach player.ky target.ky 40;
     let close = abs (player.kx - target.kx) + abs (player.ky - target.ky) < 80 in
     if close then player.phi <- (player.phi + (let d = wrapdiff player.phi target.phi in if abs d < 1400 then d else if d > 0 then 1400 else -1400)) land 0xFFFF
     else player.phi <- (player.phi + target.omega) land 0xFFFF;
     if player.kx = target.kx && player.ky = target.ky && abs (wrapdiff player.phi target.phi) < 300 then begin
       enemies := List.filter (fun e -> e != target) !enemies; incr score; flash := 10;
       if !enemies = [] then enemies := [ spawn () ]
     end
   | [] -> ());
  if !flash > 0 then decr flash; if !hurt > 0 then decr hurt

let palette () =
  Array.init 16 (fun i ->
    let v = i - 8 in
    let l = min 10 (1 + abs v * 9 / 7) in
    if !hurt > 0 && !hurt mod 4 < 2 then col 4 l                (* red flash: a life lost *)
    else if v = 0 then col 0 (if !flash > 0 then 6 else 1)     (* cancelled: dark, bright flash on a kill *)
    else if v < 0 then col (if v < -3 then 10 else 12) l      (* cool troughs *)
    else col (if v > 3 then 6 else 5) l)                      (* warm crests *)

let packet ~field ~line =
  if field <> !cur then update field;
  let y = line - Wave.first_vis in
  let wave_bytes w ~neg =
    let ph = (w.phi + w.ky * y) land 0xFFFF and st = w.kx land 0xFFFF in
    [| ph land 0xFF; ph lsr 8; st land 0xFF; st lsr 8; 0x80 lor (if neg then 0x40 else 0) lor w.shift |] in
  let ws = wave_bytes player ~neg:true :: List.map (fun e -> wave_bytes e ~neg:false) !enemies in
  let ws = ws @ List.init (Wave.nw - List.length ws) (fun _ -> [| 0; 0; 0; 0; 0 |]) in
  Array.concat (palette () :: ws)
