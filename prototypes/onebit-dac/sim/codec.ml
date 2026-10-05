(* Compressed audio in front of the one-bit DAC: IMA ADPCM (WAV blocks) and SBC (A2DP).

   These are the decoders as the chip would run them, written as models whose arithmetic is
   the arithmetic of the chosen blocks, and checked bit-exactly against ffmpeg and BlueZ's
   sbcdec (see ../README.md, section 8, for the mapping and what is not run on the blocks):
   - IMA ADPCM: tables in the data bank (thread LDB), the predictor in one PE as a chain of
     16-bit saturating adds of the selected step terms;
   - SBC: the frame CRC-8 runs on the PE array model itself (GF(2) configuration, below); the
     parser, bit allocation, dequantisation and the synthesis filterbank are the reference
     arithmetic (32-bit wrapping, as libsbc and ffmpeg compute it), with every operation
     counted so that its cost on the blocks can be stated. *)

let pr = Printf.printf
let read_file path = let ic = open_in_bin path in let s = really_input_string ic (in_channel_length ic) in close_in ic; s
let u8 s i = Char.code s.[i]
let s16le s i = let v = u8 s i lor (u8 s (i + 1) lsl 8) in if v >= 0x8000 then v - 0x10000 else v
let u32le s i = u8 s i lor (u8 s (i + 1) lsl 8) lor (u8 s (i + 2) lsl 16) lor (u8 s (i + 3) lsl 24)

let write_s16 path (pcm : int array) =
  let oc = open_out_bin path in
  Array.iter (fun v -> output_byte oc (v land 0xff); output_byte oc ((v asr 8) land 0xff)) pcm;
  close_out oc

(* ================= IMA ADPCM ================= *)
let step_table =
  [| 7; 8; 9; 10; 11; 12; 13; 14; 16; 17; 19; 21; 23; 25; 28; 31; 34; 37; 41; 45; 50; 55; 60; 66; 73; 80; 88; 97;
     107; 118; 130; 143; 157; 173; 190; 209; 230; 253; 279; 307; 337; 371; 408; 449; 494; 544; 598; 658; 724; 796;
     876; 963; 1060; 1166; 1282; 1411; 1552; 1707; 1878; 2066; 2272; 2499; 2749; 3024; 3327; 3660; 4026; 4428; 4871;
     5358; 5894; 6484; 7132; 7845; 8630; 9493; 10442; 11487; 12635; 13899; 15289; 16818; 18500; 20350; 22385; 24623;
     27086; 29794; 32767 |]

let index_delta = [| -1; -1; -1; -1; 2; 4; 6; 8 |]

(* the bank: step >> k for k = 0..3 (4 tables of 89 x 2 bytes) and the next index for each of
   the five delta classes (89 x 5 bytes): 1157 bytes, more than the 1024-byte bank, so the next
   index is computed instead (see README); kept here as the clamp *)
let next_index i n = max 0 (min 88 (i + index_delta.(n land 7)))

(* One PE step as the predictor PE performs it: S <- sat(S + (g ? -A : A)), A one step term
   from the bank, g the sign bit (ymod 2, Y = A, alu 0). The terms of one sample all have the
   same sign, so the partial sums are monotone and saturating each add equals clipping the
   total once (av_clip_int16 in the reference). [pe_steps] counts the PE steps. *)
let pe_steps = ref 0
let sat16 v = if v > 32767 then 32767 else if v < -32768 then -32768 else v

let expand (pred, idx) n =
  let step = step_table.(idx) in
  let terms = [ step asr 3 ] @ (if n land 4 <> 0 then [ step ] else []) @ (if n land 2 <> 0 then [ step asr 1 ] else [])
              @ (if n land 1 <> 0 then [ step asr 2 ] else []) in
  let neg = n land 8 <> 0 in
  let p = List.fold_left (fun p t -> incr pe_steps; sat16 (if neg then p - t else p + t)) pred terms in
  (p, next_index idx n)

(* WAV with format 0x11, 4 bits; returns interleaved PCM *)
let adpcm_decode path =
  let s = read_file path in
  let find tag = let rec go i = if String.sub s i 4 = tag then i else go (i + 1) in go 12 in
  let f = find "fmt " in
  let ch = u8 s (f + 10) lor (u8 s (f + 11) lsl 8) in
  let align = u8 s (f + 20) lor (u8 s (f + 21) lsl 8) in
  let d = find "data" in
  let len = u32le s (d + 4) in
  let data = d + 8 in
  let per_block = ((align - (4 * ch)) * 2 / ch) + 1 in
  let out = ref [] in
  let nblocks = len / align in
  for b = 0 to nblocks - 1 do
    let base = data + (b * align) in
    let st = Array.init ch (fun c -> (s16le s (base + (4 * c)), u8 s (base + (4 * c) + 2))) in
    let blk = Array.make_matrix ch per_block 0 in
    for c = 0 to ch - 1 do blk.(c).(0) <- fst st.(c) done;
    for n = 0 to ((per_block - 1) / 8) - 1 do
      for c = 0 to ch - 1 do
        for m = 0 to 3 do
          let v = u8 s (base + (4 * ch) + (n * 4 * ch) + (c * 4) + m) in
          List.iteri
            (fun j nib ->
              let p, i = expand st.(c) nib in
              st.(c) <- (p, i);
              blk.(c).(1 + (n * 8) + (2 * m) + j) <- p)
            [ v land 0xf; v lsr 4 ]
        done
      done
    done;
    for k = 0 to per_block - 1 do for c = 0 to ch - 1 do out := blk.(c).(k) :: !out done done
  done;
  (ch, Array.of_list (List.rev !out), nblocks, per_block)

(* ================= SBC ================= *)
let wrap32 v = Int32.to_int (Int32.of_int v)        (* two's complement 32-bit *)
let ( *% ) a b = wrap32 (a * b)                       (* unsigned multiply mod 2^32 *)
let ( +% ) a b = wrap32 (a + b)

let ss8 v = Int32.to_int (Int32.shift_right (Int32.of_int v) 14)
let ss4 v = Int32.to_int (Int32.shift_right (Int32.of_int v) 12)
let sn v = Int32.to_int (Int32.shift_right (Int32.of_int v) 14)  (* 11 + 1 + 2 *)

let proto8m0 = Array.map ss8 [| 0x00000000; 0xfe8d1970; 0xee979f00; 0x11686100; 0x0172e690; 0xfff5bd1a; 0xfdf1c8d4; 0xeac182c0;
  0x0d9daee0; 0x00e530da; 0xffe9811d; 0xfd52986c; 0xe7054ca0; 0x0a00d410; 0x006c1de4; 0xffdba705; 0xfcbc98e8; 0xe3889d20;
  0x06af2308; 0x000bb7db; 0xffca00ed; 0xfc3fbb68; 0xe071bc00; 0x03bf7948; 0xffc4e05c; 0xffb54b3b; 0xfbedadc0; 0xdde26200;
  0x0142291c; 0xff960e94; 0xff9f3e17; 0xfbd8f358; 0xdbf79400; 0xff405e01; 0xff7d4914; 0xff8b1a31; 0xfc1417b8; 0xdac7bb40;
  0xfdbb828c; 0xff762170 |]
let proto8m1 = Array.map ss8 [| 0xff7c272c; 0xfcb02620; 0xda612700; 0xfcb02620; 0xff7c272c; 0xff762170; 0xfdbb828c; 0xdac7bb40;
  0xfc1417b8; 0xff8b1a31; 0xff7d4914; 0xff405e01; 0xdbf79400; 0xfbd8f358; 0xff9f3e17; 0xff960e94; 0x0142291c; 0xdde26200;
  0xfbedadc0; 0xffb54b3b; 0xffc4e05c; 0x03bf7948; 0xe071bc00; 0xfc3fbb68; 0xffca00ed; 0x000bb7db; 0x06af2308; 0xe3889d20;
  0xfcbc98e8; 0xffdba705; 0x006c1de4; 0x0a00d410; 0xe7054ca0; 0xfd52986c; 0xffe9811d; 0x00e530da; 0x0d9daee0; 0xeac182c0;
  0xfdf1c8d4; 0xfff5bd1a |]
let proto4m0 = Array.map ss4 [| 0x00000000; 0xffa6982f; 0xfba93848; 0x0456c7b8; 0x005967d1; 0xfffb9ac7; 0xff589157; 0xf9c2a8d8;
  0x027c1434; 0x0019118b; 0xfff3c74c; 0xff137330; 0xf81b8d70; 0x00ec1b8b; 0xfff0b71a; 0xffe99b00; 0xfef84470; 0xf6fb4370;
  0xffcdc351; 0xffe01dc7 |]
let proto4m1 = Array.map ss4 [| 0xffe090ce; 0xff2c0475; 0xf694f800; 0xff2c0475; 0xffe090ce; 0xffe01dc7; 0xffcdc351; 0xf6fb4370;
  0xfef84470; 0xffe99b00; 0xfff0b71a; 0x00ec1b8b; 0xf81b8d70; 0xff137330; 0xfff3c74c; 0x0019118b; 0x027c1434; 0xf9c2a8d8;
  0xff589157; 0xfffb9ac7 |]
let sm4 = Array.map (Array.map sn) [|
  [| 0x05a82798; 0xfa57d868; 0xfa57d868; 0x05a82798 |]; [| 0x030fbc54; 0xf89be510; 0x07641af0; 0xfcf043ac |];
  [| 0; 0; 0; 0 |]; [| 0xfcf043ac; 0x07641af0; 0xf89be510; 0x030fbc54 |];
  [| 0xfa57d868; 0x05a82798; 0x05a82798; 0xfa57d868 |]; [| 0xf89be510; 0xfcf043ac; 0x030fbc54; 0x07641af0 |];
  [| 0xf8000000; 0xf8000000; 0xf8000000; 0xf8000000 |]; [| 0xf89be510; 0xfcf043ac; 0x030fbc54; 0x07641af0 |] |]
let sm8 = Array.map (Array.map sn) [|
  [| 0x05a82798; 0xfa57d868; 0xfa57d868; 0x05a82798; 0x05a82798; 0xfa57d868; 0xfa57d868; 0x05a82798 |];
  [| 0x0471ced0; 0xf8275a10; 0x018f8b84; 0x06a6d988; 0xf9592678; 0xfe70747c; 0x07d8a5f0; 0xfb8e3130 |];
  [| 0x030fbc54; 0xf89be510; 0x07641af0; 0xfcf043ac; 0xfcf043ac; 0x07641af0; 0xf89be510; 0x030fbc54 |];
  [| 0x018f8b84; 0xfb8e3130; 0x06a6d988; 0xf8275a10; 0x07d8a5f0; 0xf9592678; 0x0471ced0; 0xfe70747c |];
  [| 0; 0; 0; 0; 0; 0; 0; 0 |];
  [| 0xfe70747c; 0x0471ced0; 0xf9592678; 0x07d8a5f0; 0xf8275a10; 0x06a6d988; 0xfb8e3130; 0x018f8b84 |];
  [| 0xfcf043ac; 0x07641af0; 0xf89be510; 0x030fbc54; 0x030fbc54; 0xf89be510; 0x07641af0; 0xfcf043ac |];
  [| 0xfb8e3130; 0x07d8a5f0; 0xfe70747c; 0xf9592678; 0x06a6d988; 0x018f8b84; 0xf8275a10; 0x0471ced0 |];
  [| 0xfa57d868; 0x05a82798; 0x05a82798; 0xfa57d868; 0xfa57d868; 0x05a82798; 0x05a82798; 0xfa57d868 |];
  [| 0xf9592678; 0x018f8b84; 0x07d8a5f0; 0x0471ced0; 0xfb8e3130; 0xf8275a10; 0xfe70747c; 0x06a6d988 |];
  [| 0xf89be510; 0xfcf043ac; 0x030fbc54; 0x07641af0; 0x07641af0; 0x030fbc54; 0xfcf043ac; 0xf89be510 |];
  [| 0xf8275a10; 0xf9592678; 0xfb8e3130; 0xfe70747c; 0x018f8b84; 0x0471ced0; 0x06a6d988; 0x07d8a5f0 |];
  [| 0xf8000000; 0xf8000000; 0xf8000000; 0xf8000000; 0xf8000000; 0xf8000000; 0xf8000000; 0xf8000000 |];
  [| 0xf8275a10; 0xf9592678; 0xfb8e3130; 0xfe70747c; 0x018f8b84; 0x0471ced0; 0x06a6d988; 0x07d8a5f0 |];
  [| 0xf89be510; 0xfcf043ac; 0x030fbc54; 0x07641af0; 0x07641af0; 0x030fbc54; 0xfcf043ac; 0xf89be510 |];
  [| 0xf9592678; 0x018f8b84; 0x07d8a5f0; 0x0471ced0; 0xfb8e3130; 0xf8275a10; 0xfe70747c; 0x06a6d988 |] |]

let offset4 = [| [| -1; 0; 0; 0 |]; [| -2; 0; 0; 1 |]; [| -2; 0; 0; 1 |]; [| -2; 0; 0; 1 |] |]
let offset8 = [| [| -2; 0; 0; 0; 0; 0; 0; 1 |]; [| -3; 0; 0; 0; 0; 0; 1; 2 |]; [| -4; 0; 0; 0; 0; 0; 1; 2 |];
                 [| -4; 0; 0; 0; 0; 0; 1; 2 |] |]

(* operation counters, for the cost on the blocks *)
let n_alloc_ops = ref 0 and n_mac = ref 0 and n_div = ref 0 and n_frames = ref 0 and n_crc_bits = ref 0

type frame = {
  freq : int; blocks : int; mode : int; channels : int; alloc : int; subbands : int; bitpool : int;
  mutable joint : int; sf : int array array; bits : int array array; sb : int array array array; (* blk ch sb *)
}

(* CRC-8, polynomial x^8 + x^4 + x^3 + x^2 + 1, init 0x0F, MSB first: the textbook loop *)
let crc8_ref (bits : int list) =
  List.fold_left (fun crc b -> let fb = ((crc lsr 7) land 1) lxor b in ((crc lsl 1) land 0xff) lxor (if fb = 1 then 0x1d else 0)) 0x0f bits

(* the planted faults of the controls *)
let fault = ref ""

let calc_bits fr =
  let op () = incr n_alloc_ops in
  let sbn = fr.subbands in
  let bits = Array.make_matrix 2 8 0 in
  let bitneed = Array.make_matrix 2 8 0 in
  let offs = if sbn = 4 then offset4.(fr.freq) else offset8.(fr.freq) in
  let need ch sb =
    op ();
    if fr.alloc = 1 then fr.sf.(ch).(sb)
    else if fr.sf.(ch).(sb) = 0 then -5
    else begin
      let l = fr.sf.(ch).(sb) - offs.(sb) - (if !fault = "alloc_offset" && sb = 0 then 1 else 0) in
      if l > 0 then l / 2 else l
    end
  in
  let alloc_group chans =
    let maxn = ref 0 in
    List.iter (fun ch -> for sb = 0 to sbn - 1 do bitneed.(ch).(sb) <- need ch sb; op (); if bitneed.(ch).(sb) > !maxn then maxn := bitneed.(ch).(sb) done) chans;
    let bitcount = ref 0 and slicecount = ref 0 and bitslice = ref (!maxn + 1) in
    let continue = ref true in
    while !continue do
      decr bitslice;
      bitcount := !bitcount + !slicecount;
      slicecount := 0;
      List.iter (fun ch -> for sb = 0 to sbn - 1 do
        op ();
        let bn = bitneed.(ch).(sb) in
        if bn > !bitslice + 1 && bn < !bitslice + 16 then incr slicecount
        else if bn = !bitslice + 1 then slicecount := !slicecount + 2 done) chans;
      if !bitcount + !slicecount >= fr.bitpool then continue := false
    done;
    if !bitcount + !slicecount = fr.bitpool then (bitcount := !bitcount + !slicecount; decr bitslice);
    List.iter (fun ch -> for sb = 0 to sbn - 1 do
      op ();
      if bitneed.(ch).(sb) < !bitslice + 2 then bits.(ch).(sb) <- 0
      else bits.(ch).(sb) <- min 16 (bitneed.(ch).(sb) - !bitslice) done) chans;
    let order = List.concat (List.init sbn (fun sb -> List.map (fun ch -> (ch, sb)) chans)) in
    List.iter (fun (ch, sb) -> if !bitcount < fr.bitpool then begin
      op ();
      if bits.(ch).(sb) >= 2 && bits.(ch).(sb) < 16 then (bits.(ch).(sb) <- bits.(ch).(sb) + 1; incr bitcount)
      else if bitneed.(ch).(sb) = !bitslice + 1 && fr.bitpool > !bitcount + 1 then (bits.(ch).(sb) <- 2; bitcount := !bitcount + 2) end) order;
    List.iter (fun (ch, sb) -> if !bitcount < fr.bitpool then begin
      op ();
      if bits.(ch).(sb) < 16 then (bits.(ch).(sb) <- bits.(ch).(sb) + 1; incr bitcount) end) order
  in
  if fr.mode = 0 || fr.mode = 1 then (for ch = 0 to fr.channels - 1 do alloc_group [ ch ] done) else alloc_group [ 0; 1 ];
  bits

exception Bad_frame of string

(* parse one frame at [pos]; [crc] computes the CRC-8 of the bit list (reference or PE) *)
let unpack s pos ~crc =
  let len = String.length s - pos in
  if len < 4 then raise (Bad_frame "short");
  let d i = u8 s (pos + i) in
  if d 0 <> 0x9c then raise (Bad_frame "sync");
  let freq = (d 1 lsr 6) land 3 and blocks = (4 * ((d 1 lsr 4) land 3)) + 4 and mode = (d 1 lsr 2) land 3 in
  let alloc = (d 1 lsr 1) land 1 and subbands = if d 1 land 1 = 1 then 8 else 4 and bitpool = d 2 in
  let channels = if mode = 0 then 1 else 2 in
  let fr = { freq; blocks; mode; channels; alloc; subbands; bitpool; joint = 0; sf = Array.make_matrix 2 8 0;
             bits = [||]; sb = Array.init blocks (fun _ -> Array.make_matrix 2 8 0) } in
  let consumed = ref 32 in
  let bit_at c = (d (c lsr 3) lsr (7 - (c land 7))) land 1 in
  let crc_bits = ref [] in
  let push_bits c n = for k = 0 to n - 1 do crc_bits := bit_at (c + k) :: !crc_bits done in
  push_bits 8 16;    (* header bytes 1 and 2 *)
  if mode = 3 then begin
    for sb = 0 to subbands - 2 do fr.joint <- fr.joint lor (bit_at (32 + sb) lsl sb) done;
    push_bits 32 subbands;
    consumed := !consumed + subbands
  end;
  for ch = 0 to channels - 1 do
    for sb = 0 to subbands - 1 do
      fr.sf.(ch).(sb) <- (d (!consumed lsr 3) lsr (4 - (!consumed land 7))) land 0xf;
      push_bits !consumed 4;
      consumed := !consumed + 4
    done
  done;
  let bl = List.rev !crc_bits in
  n_crc_bits := !n_crc_bits + List.length bl;
  if crc bl <> d 3 then raise (Bad_frame "crc");
  let bits = calc_bits fr in
  let fr = { fr with bits } in
  for blk = 0 to blocks - 1 do
    for ch = 0 to channels - 1 do
      for sb = 0 to subbands - 1 do
        let nb = bits.(ch).(sb) in
        if nb = 0 then fr.sb.(blk).(ch).(sb) <- 0
        else begin
          let levels = (1 lsl nb) - 1 in
          let shift = fr.sf.(ch).(sb) + 1 + 2 in
          let a = ref 0 in
          for _ = 1 to nb do a := (!a lsl 1) lor bit_at !consumed; incr consumed done;
          incr n_div;
          (* uint64 numerator, unsigned division, then int32 *)
          fr.sb.(blk).(ch).(sb) <- wrap32 (((((!a lsl 1) lor 1) lsl shift) / levels) - (1 lsl shift))
        end
      done
    done
  done;
  if mode = 3 then
    for blk = 0 to blocks - 1 do
      for sb = 0 to subbands - 1 do
        if fr.joint land (1 lsl sb) <> 0 then begin
          let a = fr.sb.(blk).(0).(sb) and b = fr.sb.(blk).(1).(sb) in
          fr.sb.(blk).(0).(sb) <- a +% b;
          fr.sb.(blk).(1).(sb) <- wrap32 (a - b)
        end
      done
    done;
  let c = !consumed in
  (fr, (c + 7) / 8)

(* synthesis state per channel, as the reference keeps it: V 170 words and 16 offsets *)
type syn = { v : int array array; off : int array array }
let syn_create () = { v = Array.make_matrix 2 170 0; off = Array.init 2 (fun _ -> Array.init 16 (fun i -> (10 * i) + 10)) }
let clip16 v = if v > 32767 then 32767 else if v < -32768 then -32768 else v
let asr15 v = wrap32 v asr 15

let synth st fr ch blk out =
  let v = st.v.(ch) and off = st.off.(ch) in
  let n = fr.subbands in
  let nn = 2 * n in
  let wrapto = if n = 8 then 159 else 79 in
  let sm = if n = 8 then sm8 else sm4 in
  let m0 = if n = 8 then proto8m0 else proto4m0 and m1 = if n = 8 then proto8m1 else proto4m1 in
  for i = 0 to nn - 1 do
    off.(i) <- off.(i) - 1;
    if off.(i) < 0 then (off.(i) <- wrapto; Array.blit v 0 v (wrapto + 1) 9);
    let acc = ref 0 in
    for k = 0 to n - 1 do incr n_mac; acc := !acc +% (sm.(i).(k) *% fr.sb.(blk).(ch).(k)) done;
    v.(off.(i)) <- asr15 !acc
  done;
  for i = 0 to n - 1 do
    let k = (i + n) land 0xf in
    let idx = 5 * i in
    let acc = ref 0 in
    for j = 0 to 4 do
      n_mac := !n_mac + 2;
      acc := !acc +% (v.(off.(i) + (2 * j)) *% m0.(idx + j)) +% (v.(off.(k) + (2 * j) + 1) *% m1.(idx + j))
    done;
    out (clip16 (asr15 !acc))
  done

(* decode a stream; returns (channels, interleaved pcm, frames decoded, frames rejected) *)
let sbc_decode ?(crc = crc8_ref) s =
  let st = syn_create () in
  let pos = ref 0 and pcm = ref [] and nch = ref 2 and good = ref 0 and bad = ref 0 in
  (try
     while !pos < String.length s do
       match unpack s !pos ~crc with
       | fr, len ->
         incr n_frames;
         incr good;
         nch := fr.channels;
         let per = Array.make_matrix fr.channels (fr.blocks * fr.subbands) 0 in
         for ch = 0 to fr.channels - 1 do
           for blk = 0 to fr.blocks - 1 do
             let j = ref 0 in
             synth st fr ch blk (fun x -> per.(ch).((blk * fr.subbands) + !j) <- x; incr j)
           done
         done;
         for t = 0 to (fr.blocks * fr.subbands) - 1 do for ch = 0 to fr.channels - 1 do pcm := per.(ch).(t) :: !pcm done done;
         pos := !pos + len
       | exception Bad_frame "crc" ->
         (* a frame with a bad CRC is dropped whole (length from its header); the sync is kept *)
         incr bad;
         let d1 = u8 s (!pos + 1) and bp = u8 s (!pos + 2) in
         let sbn = if d1 land 1 = 1 then 8 else 4 and blocks = (4 * ((d1 lsr 4) land 3)) + 4 and mode = (d1 lsr 2) land 3 in
         let ch = if mode = 0 then 1 else 2 in
         let bitsum = if mode = 0 || mode = 1 then blocks * ch * bp else (if mode = 3 then sbn else 0) + (blocks * bp) in
         pos := !pos + 4 + ((4 * sbn * ch) / 8) + ((bitsum + 7) / 8)
     done
   with Bad_frame _ -> ());
  (!nch, Array.of_list (List.rev !pcm), !good, !bad)

(* ---- the CRC-8 on the PE array model: PE 0, segment 0, GF(2) configuration ----
   S holds the CRC in its high byte: S <- ((S << 1) | lane) XOR (g ? 0x1D00 : 0), g = S[15] ^ A[0],
   the data bit on A[0]; the lane (the segment's broadcast, 0) fills bit 0, so the low byte
   stays 0. Init 0x0F00 through the init chain; one feed word per bit. *)
open Spec

let crc_op = { nop with xsel = 2; sinsel = 1; ysel = 0; ymod = 1; gsel = 4; alu = 4; swb = 1; stream = true; k = 0x1d00 }

module Pe_crc (S : SIM) = struct
  let sim = ref None
  let other = ref None   (* a second simulator in lockstep (the RTL), compared every clock *)
  let clocks = ref 0
  let mismatch = ref None

  let cyc i =
    let s = Option.get !sim in
    S.cycle s i;
    incr clocks;
    match !other with
    | Some (f, st) -> f i; if !mismatch = None && Spec.diff (S.state s) (st ()) <> [] then mismatch := Some !clocks
    | None -> ()

  let setup () =
    sim := Some (S.create ());
    let b = bytes_of_op crc_op in
    for j = 7 downto 0 do cyc { idle with cfg_wr = true; cfg_seg = 0; cfg_byte = b.(j) } done;
    cyc { idle with mbx_wr = true; mbx_seg = 0; mbx_sel = 2; mbx_byte = 2 lor 16 }   (* feed, run *)

  let crc bits =
    if !sim = None then setup ();
    cyc { idle with init_wr = true; init_seg = 0; init_byte = 0x0f };
    cyc { idle with init_wr = true; init_seg = 0; init_byte = 0x00 };
    List.iter (fun b ->
        cyc { idle with mbx_wr = true; mbx_seg = 0; mbx_sel = 0; mbx_byte = b };
        cyc { idle with mbx_wr = true; mbx_seg = 0; mbx_sel = 1; mbx_byte = 0 })
      bits;
    cyc idle;
    let v = (S.state (Option.get !sim)).pes.(0).s lsr 8 in
    if !fault = "crc_poly" then v lxor 1 else v
end
