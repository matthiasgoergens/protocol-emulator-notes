(* What the host (the RP2350) knows about one scanline, the reference renderer that defines what the
   chip must draw from it, and the encoder that turns it into the line-buffer entries the chip's
   feeder plays into the PE array.

   Colour indices (the tail's lookup table, 64 entries of luma code, chroma phase and two chroma
   enables): 1-15 background tiles (palette * 4 + pixel, pixel 1-3), 17-31 sprites
   (16 + palette * 4 + pixel), 32-62 backdrop colours (a per-line choice: copper-style gradients),
   63 the colour burst. *)

let npix = 256
let kcells = 2              (* looped tile cells *)
let nspr = 16               (* sprite cells *)
let ntiles = 17             (* tile slices per line: 256 pixels with fine scroll need 17 *)

type tile = { pix : int array; (* 16 pixels, 0-3, 0 transparent *) pal : int; front : bool }
type sprite = { x : int; spix : int array; spal : int; flip : bool; behind : bool }
type line = { backdrop : int; fine : int; tiles : tile array; sprites : sprite list (* lowest priority first *) }

let blank_tile = { pix = Array.make 16 0; pal = 0; front = false }

(* the sprites the chip is given: on-screen ones, at most nspr, the highest-priority ones kept *)
let visible_sprites l =
  let v = List.filter (fun s -> s.x > -16 && s.x < npix && Array.exists (( <> ) 0) s.spix) l.sprites in
  let n = List.length v in
  if n > nspr then List.filteri (fun i _ -> i >= n - nspr) v else v

(* Reference: what each pixel must show, straight from the description. *)
let reference l =
  Array.init npix (fun px ->
    let xs = px + l.fine in
    let t = l.tiles.(xs / 16) in
    let v = t.pix.(xs mod 16) in
    let c = ref l.backdrop and opaque = ref false and front = ref false in
    if v <> 0 then (c := t.pal * 4 + v; opaque := true; front := t.front);
    List.iter (fun s ->
      let d = px - s.x in
      if d >= 0 && d < 16 then begin
        let v = s.spix.(if s.flip then 15 - d else d) in
        if v <> 0 && not !front && not (s.behind && !opaque) then c := 16 + s.spal * 4 + v
      end) (visible_sprites l);
    !c)

(* Line-buffer entries: 3-bit tag and 16-bit data. Tags 2/3 (6/7) are record words / last words
   of class 0 (1) and go onto the link unchanged. *)
let t_wait = 0 and t_pixels = 1 and t_word = 2 and t_last = 3 and t_end = 4
let t_word1 = 6 and t_last1 = 7

let pattern pix = Array.fold_left (fun (a, i) v -> (a lor (v lsl (30 - 2 * i)), i + 1)) (0, 0) pix |> fst
let m32 = 0xFFFFFFFF

let record ~cls words =
  let n = List.length words in
  List.mapi (fun i w ->
    let last = i = n - 1 in
    ((if cls = 1 then (if last then t_last1 else t_word1) else if last then t_last else t_word), w land 0xFFFF))
    words

(* a lookup-table update: start address, then the entries *)
let lut_record ~addr entries = record ~cls:1 (addr :: entries)

let encode ?(lut = []) l =
  let tile_attr t = ((0x01 lor (if t.front then 0x02 else 0)) lsl 8) lor (t.pal * 4) in
  let first_tiles = List.concat (List.init kcells (fun k ->
    let t = l.tiles.(k) in
    let a = pattern t.pix in
    let a = if k = 0 then (a lsl (2 * l.fine)) land m32 else a in
    record ~cls:0 [ tile_attr t; a lsr 16; a; l.fine - 16 * k; 0 ])) in
  let sprites = List.concat_map (fun s ->
    let a = pattern s.spix in
    let a = if s.x >= 0 then a else if s.flip then a lsr (2 * -s.x) else (a lsl (2 * -s.x)) land m32 in
    let attr2 = (if s.behind then 0x03 else 0x02) lor (if s.flip then 0x100 else 0) in
    record ~cls:0 [ 16 + s.spal * 4; a lsr 16; a; -s.x; attr2 ]) (visible_sprites l) in
  let later = List.concat (List.init (ntiles - kcells) (fun i ->
    let j = i + kcells in
    let t = l.tiles.(j) in
    let a = pattern t.pix in
    (t_wait, 16 * (j - kcells + 1)) :: record ~cls:0 [ tile_attr t; a lsr 16; a ])) in
  [ (t_pixels, l.backdrop) ] @ first_tiles @ sprites @ lut @ later @ [ (t_end, 0) ]

let encode_blank ?(lut = []) () = lut @ [ (t_end, 0) ]

(* random lines for the lockstep check *)
let random_line () =
  let rpix () = Array.init 16 (fun _ -> if Random.int 3 = 0 then 0 else Random.int 4) in
  { backdrop = 32 + Random.int 31; fine = Random.int 16;
    tiles = Array.init ntiles (fun _ ->
      if Random.int 5 = 0 then blank_tile else { pix = rpix (); pal = Random.int 4; front = Random.int 4 = 0 });
    sprites = List.init (Random.int 22) (fun _ ->
      { x = Random.int 290 - 20; spix = rpix (); spal = Random.int 4; flip = Random.bool (); behind = Random.int 3 = 0 }) }

(* directed lines for the edges: on line i, one sprite at x = -15 + i mod 16 and one at
   x = 240 + i mod 16, flipped on alternate groups of 16 lines, with asymmetric patterns, over
   tiles at fine scroll i mod 16 *)
let directed_line i =
  let pa = [| 1; 2; 3; 0; 1; 2; 3; 1; 0; 2; 3; 1; 2; 0; 3; 2 |] in
  let pb = [| 3; 0; 0; 1; 2; 2; 0; 3; 1; 1; 0; 2; 3; 3; 0; 1 |] in
  let flip = (i / 16) mod 2 = 1 in
  let tile j = { pix = Array.init 16 (fun p -> if (p + j) mod 5 = 0 then 0 else 1 + (p + 2 * j) mod 3);
                 pal = j mod 4; front = false } in
  { backdrop = 40; fine = i mod 16; tiles = Array.init ntiles tile;
    sprites = [ { x = -15 + i mod 16; spix = pa; spal = 1; flip; behind = false };
                { x = 240 + i mod 16; spix = pb; spal = 2; flip; behind = i mod 3 = 0 } ] }
