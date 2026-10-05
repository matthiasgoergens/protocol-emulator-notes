(* PE-X: the generic 16-bit PE of ../pe-synth (pe16) with four generic extensions, as an
   executable specification. pex.ml is the RTL and must match this cycle for cycle.

   pe16, unchanged: a 16-bit state s, updated when a step arrives by
     s <- sat (op x y), op in {add, sub, max, min} (signed, saturating),
     x = s or the neighbour's data, y = the constant k or s,
   a byte-wide configuration chain, and a pipeline register passing the neighbour's word on.
   pe16's "en" input becomes a tag on the word itself (a step is a word tagged STEP).

   The extensions:
   1. A tagged link. Each word carries a 3-bit tag: bits 1:0 = 0 none, 1 step, 2 record word,
      3 last word of a record (like AXI-stream's TLAST); bit 2 = a record class.
   2. Record loading ("the first empty cell takes it"). A PE with load_en set and not loaded
      consumes record words of its class as they pass (they leave as tag none) and writes them to
      R0 attr, R1 a[31:16], R2 a[15:0], R3 s, R4 attr2 (9 bits) in that order; the last word sets
      loaded. A PE releases (loaded <- 0) on a step whose data has bit 15 set (end of run) if
      rel_eol, or on the first step outside its window after one inside it if rel_win.
   3. A window predicate on s: p = ((s >> w) & (2^n - 1)) = 0, so n = 0 means always.
   4. A 32-bit shift register a, shifting (or rotating) by b = 1, 2, 4 or 8 bits on every step
      inside the window while loaded, MSB first, or LSB first when attr2 bit 8 (dir) is set. The
      field shifted out is the top (or bottom) b bits.
   5. A conditional write into the passing word, split into an 8-bit value lane (bits 7:0) and an
      8-bit flag lane (bits 15:8): on a step with write_en, loaded, p, field <> 0 and
      (flags & attr2[7:0]) = 0, value <- attr[7:0] | field and flags <- flags | attr[15:8].

   Configuration bytes (shifted in first to last):
     c0: [1:0] alu op, [2] y = k (else s), [3] x = s (else neighbour data), [4] step s,
         [5] load_en, [6] class, [7] rotate a (else shift in zeros)
     c1, c2: k, high byte first
     c3: [1:0] log2 b, [5:2] w, [6] rel_win, [7] rel_eol
     c4: [3:0] n, [4] write_en *)

let tag_none = 0 and tag_step = 1 and tag_word = 2 and tag_last = 3

type cfg = {
  op : int; ysel_k : bool; xsel_s : bool; s_en : bool; load_en : bool; cls : int; rot : bool;
  k : int; lb : int; w : int; rel_win : bool; rel_eol : bool; n : int; write_en : bool;
}

let cfg_of_bytes (c : int array) =
  let b x i = (x lsr i) land 1 = 1 in
  { op = c.(0) land 3; ysel_k = b c.(0) 2; xsel_s = b c.(0) 3; s_en = b c.(0) 4; load_en = b c.(0) 5;
    cls = (c.(0) lsr 6) land 1; rot = b c.(0) 7; k = (c.(1) lsl 8) lor c.(2);
    lb = c.(3) land 3; w = (c.(3) lsr 2) land 15; rel_win = b c.(3) 6; rel_eol = b c.(3) 7;
    n = c.(4) land 15; write_en = b c.(4) 4 }

type t = {
  cfg : cfg;
  mutable s : int; mutable a : int; mutable attr : int; mutable attr2 : int;
  mutable loaded : bool; mutable widx : int; mutable pprev : bool;
  mutable out_tag : int; mutable out_data : int;
}

let create cfg = { cfg; s = 0; a = 0; attr = 0; attr2 = 0; loaded = false; widx = 0; pprev = false;
                   out_tag = 0; out_data = 0 }

let m16 = 0xFFFF and m32 = 0xFFFFFFFF
let signed16 v = if v land 0x8000 <> 0 then v - 0x10000 else v

(* pe16's ALU, 16 bits: 0 add, 1 sub (saturating), 2 max, 3 min (signed) *)
let alu op x y =
  let x = signed16 x and y = signed16 y in
  let sat v = if v > 32767 then 32767 else if v < -32768 then -32768 else v in
  let r = match op with 0 -> sat (x + y) | 1 -> sat (x - y) | 2 -> max x y | _ -> min x y in
  r land m16

let window c s = c.n = 0 || ((s lsr c.w) land ((1 lsl c.n) - 1)) = 0

let step t ~tag ~data =
  let c = t.cfg in
  let kind = tag land 3 and cls_in = (tag lsr 2) land 1 in
  let is_step = kind = tag_step in
  let is_rec = kind >= tag_word && cls_in = c.cls in
  let p = window c t.s in
  let b = 1 lsl c.lb in
  let bm = (1 lsl b) - 1 in
  let dir = (t.attr2 lsr 8) land 1 = 1 in
  let field = if dir then t.a land bm else (t.a lsr (32 - b)) land bm in
  let flags = (data lsr 8) land 0xFF in
  let blocked = flags land (t.attr2 land 0xFF) <> 0 in
  let write = is_step && c.write_en && t.loaded && p && field <> 0 && not blocked in
  let consume = is_rec && c.load_en && not t.loaded in
  (* outputs, registered *)
  let out_data =
    if write then ((flags lor (t.attr lsr 8)) lsl 8) lor (((t.attr land 0xFF) lor field) land 0xFF)
    else data in
  let out_tag = if consume then tag_none else tag in
  (* next state, all from the old values *)
  let s' = ref t.s and a' = ref t.a and attr' = ref t.attr and attr2' = ref t.attr2 in
  let loaded' = ref t.loaded and widx' = ref t.widx and pprev' = ref t.pprev in
  if is_step then begin
    if c.s_en then begin
      let x = if c.xsel_s then t.s else data and y = if c.ysel_k then c.k else t.s in
      s' := alu c.op x y
    end;
    if t.loaded && p then begin
      let a = t.a in
      a' := (if dir then
               (a lsr b) lor (if c.rot then (a land bm) lsl (32 - b) else 0)
             else
               ((a lsl b) land m32) lor (if c.rot then (a lsr (32 - b)) land bm else 0))
    end;
    let eol = flags land 0x80 <> 0 in
    if t.loaded && ((c.rel_eol && eol) || (c.rel_win && t.pprev && not p)) then loaded' := false;
    pprev' := (if eol then false else p)
  end;
  if consume then begin
    (match t.widx with
     | 0 -> attr' := data
     | 1 -> a' := (t.a land 0xFFFF) lor (data lsl 16)
     | 2 -> a' := (t.a land 0xFFFF0000) lor data
     | 3 -> s' := data
     | 4 -> attr2' := data land 0x1FF
     | _ -> ());
    if kind = tag_last then (loaded' := true; widx' := 0) else widx' := min 7 (t.widx + 1)
  end;
  t.s <- !s'; t.a <- !a'; t.attr <- !attr'; t.attr2 <- !attr2'; t.loaded <- !loaded';
  t.widx <- !widx'; t.pprev <- !pprev'; t.out_tag <- out_tag; t.out_data <- out_data

(* Configuration byte helpers *)
let c0 ?(op = 0) ?(ysel_k = false) ?(xsel_s = false) ?(s_en = false) ?(load_en = false) ?(cls = 0)
    ?(rot = false) () =
  let b v i = if v then 1 lsl i else 0 in
  op lor b ysel_k 2 lor b xsel_s 3 lor b s_en 4 lor b load_en 5 lor (cls lsl 6) lor b rot 7
let c3 ~lb ~w ?(rel_win = false) ?(rel_eol = false) () =
  lb lor (w lsl 2) lor (if rel_win then 0x40 else 0) lor (if rel_eol then 0x80 else 0)
let c4 ~n ?(write_en = false) () = n lor (if write_en then 0x10 else 0)
let bytes ~c0 ~k ~c3 ~c4 = [| c0; (k lsr 8) land 0xFF; k land 0xFF; c3; c4 |]

(* The two video configurations used by the platformer. Both count steps (s <- s + 1) and draw
   2 bits per pixel from a 16-pixel window; they differ in the window test and when they let go. *)
let counter_c0 = c0 ~op:0 ~ysel_k:true ~xsel_s:true ~s_en:true ~load_en:true ()
(* a looped tile cell in a set of [kcells] (a power of two): window when s mod 16 kcells < 16 *)
let tile_cfg ~kcells =
  let rec log2 x = if x <= 1 then 0 else 1 + log2 (x / 2) in
  bytes ~c0:counter_c0 ~k:1 ~c3:(c3 ~lb:1 ~w:4 ~rel_win:true ~rel_eol:true ()) ~c4:(c4 ~n:(log2 kcells) ~write_en:true ())
(* a sprite cell: window when 0 <= s < 16 *)
let sprite_cfg = bytes ~c0:counter_c0 ~k:1 ~c3:(c3 ~lb:1 ~w:4 ~rel_eol:true ()) ~c4:(c4 ~n:12 ~write_en:true ())
