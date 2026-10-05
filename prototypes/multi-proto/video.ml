(* NTSC composite generation on generic blocks, at 17 x fsc = 60.852 MHz.

   Division of labour (nothing here is video-specific hardware):
   - A sequencer thread chases the beam: it drives four luma pins (a resistor DAC, code/14 of full
     scale) with SETP for sync and blanking, and sends segment commands (burst on/off, play a
     line, start of field) to the pin stage through an out-port, each on an exact slot.
   - The pin stage's NCO: a free-running phase counter mod 17. Two chroma pins each output a
     square wave of the subcarrier with a per-pixel phase offset (pin A high for 9 of 17 phases,
     pin B for 8, so their sum always averages exactly one: the DC level never depends on colour).
     The mean phase is the hue, the phase difference d sets saturation (fundamental amplitude
     proportional to |cos(pi d / 17)|). Outside burst and pixels the pins sit at A = 1, B = 0,
     which adds nothing.
   - The memory streamer reads the current line's row of the line buffer (4 bits per pixel,
     64 pixels, 48 clocks each), through a 16-entry lookup table (the palette: luma code, phase,
     phase difference) into the luma and chroma pins.
   Composite model at the summing node: V = code/14 + beta (A + B - 1): sync 0, blank code 4
   (0.286 = 40 IRE), white code 14. *)

let fsc = 315e6 /. 88.
let fclk = 17. *. fsc
let beta = 0.3
let blank_code = 4
let black = 47.5 /. 140. and white = 1.0
let kk = white -. black
let pix_clocks = 48 and n_pix = 64

(* palette entry: luma code 0..15, chroma phase 0..16, phase difference 0..16, chroma on *)
type entry = { code : int; th : int; d : int; col : bool }

(* chroma pins at clock n for an entry *)
let chroma_ab n e =
  if not e.col then (1, 0)
  else
    let ph = n mod 17 in
    let a = if (ph - e.th + 34) mod 17 < 9 then 1 else 0 in
    let b = if (ph - e.th - e.d + 51) mod 17 < 8 then 1 else 0 in
    (a, b)

let composite ~code ~a ~b = float code /. 14. +. beta *. float (a + b - 1)

(* burst: phase 0, difference 6 (amplitude ~0.17, NTSC's is 0.143) *)
let burst = { code = blank_code; th = 0; d = 6; col = true }

(* The host's precomputation: predict what a TV decodes for an entry, from one subcarrier period.
   This mirrors the standard decoder's arithmetic (burst phase reference, U = -Im, V = Re), not its
   filters or sync handling, and is used only to choose the palette. *)
let phasor f =
  let re = ref 0. and im = ref 0. in
  for n = 0 to 16 do
    let v = f n and w = 2. *. Float.pi *. float n /. 17. in
    re := !re +. v *. cos w; im := !im -. v *. sin w
  done;
  (2. *. !re /. 17., 2. *. !im /. 17.)

let predict e =
  let lvl n = let a, b = chroma_ab n e in composite ~code:e.code ~a ~b in
  let bl n = let a, b = chroma_ab n burst in composite ~code:burst.code ~a ~b -. (4. /. 14.) in
  let br, bi = phasor bl in
  let th = atan2 bi br in
  let zr, zi = phasor lvl in
  let rr = cos (Float.pi /. 2. -. th) and ri = sin (Float.pi /. 2. -. th) in
  let wr = zr *. rr -. zi *. ri and wi = zr *. ri +. zi *. rr in
  let u = -. wi /. kk and v = wr /. kk in
  let y = (float e.code /. 14. -. black) /. kk in
  let r = y +. v /. 0.877 and b = y +. u /. 0.493 in
  let g = (y -. 0.299 *. r -. 0.114 *. b) /. 0.587 in
  let cl x = Float.max 0. (Float.min 1. x) in
  (cl r, cl g, cl b)

let dist (r1, g1, b1) (r2, g2, b2) = sqrt (((r1 -. r2) ** 2.) +. ((g1 -. g2) ** 2.) +. ((b1 -. b2) ** 2.))

let choose target =
  let best = ref ({ code = blank_code; th = 0; d = 0; col = false }, infinity) in
  for code = 4 to 15 do
    let e = { code; th = 0; d = 0; col = false } in
    let dd = dist (predict e) target in if dd < snd !best then best := (e, dd);
    for th = 0 to 16 do for d = 0 to 16 do
      let e = { code; th; d; col = true } in
      let dd = dist (predict e) target in if dd < snd !best then best := (e, dd)
    done done
  done;
  fst !best

let targets = [|
  (0.0, 0.0, 0.0); (1.0, 1.0, 1.0); (0.5, 0.5, 0.5); (0.8, 0.1, 0.1); (0.1, 0.7, 0.1); (0.15, 0.2, 0.9);
  (0.9, 0.9, 0.1); (0.1, 0.8, 0.8); (0.8, 0.1, 0.8); (0.95, 0.55, 0.1); (0.45, 0.1, 0.6); (0.25, 0.25, 0.25);
  (0.5, 0.3, 0.1); (1.0, 0.6, 0.7); (0.1, 0.1, 0.45); (0.75, 0.75, 0.75) |]

let palette = lazy (Array.map choose targets)
let refs () = Array.map predict (Lazy.force palette)

(* Line buffer: K rows of 32 bytes in gain-cell memory with a lifetime contract. Each byte carries
   the clock of its last write; a read later than [life] clocks after it returns the byte with
   every 1 decayed to 0 (the cells' one-sided failure), and is counted. With [refresh], the first
   of a line's two reads writes the byte back, which is how the cells are refreshed: a read
   followed by a write. *)
type buf = {
  k : int; data : int array array; tw : int array array; tag : int array; valid : bool array;
  mutable cur : int; mutable pending : int; mutable wptr : int; mutable commits : int;
  life : int; refresh : bool; mutable violations : int; mutable max_interval : int; mutable reads : int;
}

let make_buf ~k ~life ~refresh =
  { k; data = Array.make_matrix k 32 0; tw = Array.make_matrix k 32 0; tag = Array.make k (-1); valid = Array.make k false;
    cur = 0; pending = 0; wptr = 0; commits = 0; life; refresh; violations = 0; max_interval = 0; reads = 0 }

let buf_select b v = b.cur <- v mod b.k; b.valid.(b.cur) <- false; b.pending <- v; b.wptr <- 0
let buf_data b ~now v = if b.wptr < 32 then (b.data.(b.cur).(b.wptr) <- v; b.tw.(b.cur).(b.wptr) <- now; b.wptr <- b.wptr + 1)
let buf_commit b v = if v land 1 = 1 && b.wptr = 32 then (b.valid.(b.cur) <- true; b.tag.(b.cur) <- b.pending; b.commits <- b.commits + 1)

let buf_read b ~now ~line ~byte ~first =
  let r = line mod b.k in
  if not (b.valid.(r) && b.tag.(r) = line) then None
  else begin
    let iv = now - b.tw.(r).(byte) in
    b.reads <- b.reads + 1;
    if iv > b.max_interval then b.max_interval <- iv;
    (* past its lifetime every stored 1 has decayed; a refresh then writes the decayed value back *)
    let v = if iv > b.life then (b.violations <- b.violations + 1; b.data.(r).(byte) <- 0; 0) else b.data.(r).(byte) in
    if first && b.refresh then b.tw.(r).(byte) <- now;
    Some v
  end

(* Pin stage + streamer. Commands (bytes on the stage's out-port): *)
let cmd_field = 1 and cmd_burst_on = 2 and cmd_burst_off = 3 and cmd_active = 4

type stage = {
  mutable burst_on : bool; mutable playing : bool; mutable play_start : int;
  mutable src : int; mutable phase : int; mutable underruns : int; mutable lines_played : int;
  mutable cur : entry; mutable row : int array option;
}

let make_stage () = { burst_on = false; playing = false; play_start = 0; src = 0; phase = 0; underruns = 0;
                      lines_played = 0; cur = { code = 0; th = 0; d = 0; col = false }; row = None }

let stage_cmd s ~now v =
  if v = cmd_field then (s.src <- 0; s.phase <- 0)
  else if v = cmd_burst_on then s.burst_on <- true
  else if v = cmd_burst_off then s.burst_on <- false
  else if v = cmd_active then (s.playing <- true; s.play_start <- now)

(* one clock: returns (luma code, a, b) *)
let stage_clock s b ~now ~seq_code =
  if s.playing then begin
    let k = (now - s.play_start) / pix_clocks in
    if k >= n_pix then begin
      s.playing <- false; s.row <- None; s.lines_played <- s.lines_played + 1;
      if s.phase = 1 then (s.phase <- 0; s.src <- s.src + 1) else s.phase <- 1
    end
  end;
  if s.playing then begin
    let k = (now - s.play_start) / pix_clocks in
    let first_clock_of_pixel = (now - s.play_start) mod pix_clocks = 0 in
    if first_clock_of_pixel then begin
      let byte = k / 2 in
      let v = if k mod 2 = 0 then begin
          (match buf_read b ~now ~line:s.src ~byte ~first:(s.phase = 0) with
           | Some v -> s.row <- Some [| v |]; Some v
           | None -> if k = 0 then s.underruns <- s.underruns + 1; s.row <- None; None)
        end else (match s.row with Some r -> Some r.(0) | None -> None) in
      let pal = Lazy.force palette in
      s.cur <- (match v with
        | Some v -> pal.(if k mod 2 = 0 then v lsr 4 else v land 15)
        | None -> { code = blank_code; th = 0; d = 0; col = false })
    end;
    let a, bb = chroma_ab now s.cur in
    (s.cur.code, a, bb)
  end else begin
    let a, bb = if s.burst_on then chroma_ab now burst else (1, 0) in
    (seq_code, a, bb)
  end
