(* The crazy network: a ring of n cells with 8-bit state, stepped in lockstep. The wiring was
   "taped out" once from a fixed seed: every cell reads its left neighbour; 40 % also read a
   medium-range partner (distance 3..12 either way), 8 % a partner anywhere, the rest read
   themselves. Everything else is a program chosen by the host:
     ops.(i) : 0 add, 1 xor, 2 sub (left - partner), 3 max
     ks.(i)  : constant added after the operation
     tap     : the cell whose top nibble picks the pixel colour from the 16-entry palette
     p       : the network steps every p clocks (pixels are 10 clocks)
     reset   : whether the state is cleared at the start of every line
     scheme  : how the CPU's four per-line seed bytes are computed (XORed into cells 0..3)
   Timing is PAL, identical to the retro console: 3405 clocks per line, 312 lines. *)

let n = 64
let cpl = 3405 and lpf = 312 and vis_start = 662 and pixc = 10 and first_vis = 40 and nvis = 240 and npix = 256

let lcg = ref 2027
let rnd m = lcg := (!lcg * 1103515245 + 12345) land 0x3FFFFFFF; (!lcg lsr 8) mod m
let left = Array.init n (fun i -> (i + n - 1) mod n)
let partner = Array.init n (fun i ->
  let r = rnd 100 in
  if r < 40 then (let d = 3 + rnd 10 in if rnd 2 = 0 then (i + d) mod n else (i + n - d) mod n)
  else if r < 48 then rnd n else i)

type prog = { ops : int array; ks : int array; tap : int; p : int; reset : bool; scheme : int; pal : int array }

let n_schemes = 6
let seeds prog ~line ~frame =
  let v = match prog.scheme with
    | 0 -> [| line; frame; 0; 0 |]
    | 1 -> [| line; line * line; frame; 0 |]
    | 2 -> [| line * frame; line; frame * 3; 7 |]
    | 3 -> [| 0; 0; 0; 0 |]
    | 4 -> [| line lxor frame; line; frame; line * 3 |]
    | _ -> [| (line * 7 + frame) lsr 1; frame; line; frame lsr 2 |] in
  Array.map (fun x -> x land 255) v

let random_prog id =
  let st = Random.State.make [| id; 77 |] in
  let ri m = Random.State.int st m in
  let ks_zero = ri 3 in
  { ops = Array.init n (fun _ -> ri 4);
    ks = Array.init n (fun _ -> if ri 3 < ks_zero then 0 else ri 256);
    tap = ri n; p = [| 1; 2; 5; 10 |].(ri 4); reset = ri 2 = 0; scheme = ri n_schemes;
    pal = Array.init 16 (fun i -> ((1 + i mod 12) lsl 4) lor (1 + i * 9 / 15)) }

(* Run one field from [s] (updated in place). [f line h idx] is called for every visible pixel
   sample with the palette index (top nibble of the tap cell). *)
let run_field prog s ~frame ~(f : int -> int -> int -> unit) =
  let t = Array.make n 0 in
  for line = 0 to lpf - 1 do
    for h = 0 to cpl - 1 do
      let visible = line >= first_vis && line < first_vis + nvis && h >= vis_start && h < vis_start + npix * pixc
                    && (h - vis_start) mod pixc = 5 in
      if visible then f (line - first_vis) ((h - vis_start) / pixc) (s.(prog.tap) lsr 4);
      if h = 0 then begin
        if prog.reset then Array.fill s 0 n 0;
        let sd = seeds prog ~line ~frame in
        for j = 0 to 3 do s.(j) <- s.(j) lxor sd.(j) done
      end else if h mod prog.p = 0 then begin
        for i = 0 to n - 1 do
          let a = s.(left.(i)) and b = s.(partner.(i)) in
          let v = match prog.ops.(i) with 0 -> a + b | 1 -> a lxor b | 2 -> a - b | _ -> if a > b then a else b in
          t.(i) <- (v + prog.ks.(i)) land 255
        done;
        Array.blit t 0 s 0 n
      end
    done
  done

let render prog ~frames ~(keep : int -> bool) =
  let s = Array.make n 0 in
  let out = ref [] in
  for fr = 0 to frames - 1 do
    let img = Array.make_matrix nvis npix 0 in
    run_field prog s ~frame:fr ~f:(fun y x v -> img.(y).(x) <- v);
    if keep fr then out := (fr, img) :: !out
  done;
  List.rev !out

let write_pgm path img =
  let oc = open_out_bin path in
  Printf.fprintf oc "P5\n%d %d\n15\n" npix nvis;
  Array.iter (fun row -> Array.iter (fun v -> output_char oc (Char.chr v)) row) img;
  close_out oc
