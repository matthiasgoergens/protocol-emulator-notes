(* CAN bus to TV: a standalone CAN analyser with composite video output and no PC.

   Screen (240 active lines, 64 pixels per line):
     header        a colour bar; the whole band flashes red for 30 fields after an error frame
     waveform      the last 64 bits on the bus, scrolling, as three two-level traces (bus, node A's
                   TXD, node B's TXD); stuff bits yellow on the bus trace; the bit where a node lost
                   arbitration red on that node's trace
     ID table      8 rows: the last identifier seen in each slot (ID10..ID8), with RTR, IDE, r0 and
                   DLC, as white/grey bits; an activity bar, +32 per frame, -4 per field

   Capacity split, all generic blocks:
     (T3)  CAN receive: the proto-ps2-can branch's RX thread, whose tagged reports become mailbox
           messages; here a behavioural stand-in (can_standin.ml) feeds the two in-ports directly,
           and T3 runs an unrelated UART transmitter to show isolation.
     T0    bit renderer: in-port 0 (one code per bit) -> the waveform ring row, 2 instructions per
           bit, about 7 % of its slots at 500 kbit/s.
     T2    frame renderer: in-port 1 (frame events) -> selects the ID row by a branch tree on
           ID10..ID8, writes the header bits through the expanding write port, bumps the slot's
           counter, flashes the header on an error. Its own inbox holds two bytes while it
           branches (the mailbox as scratch storage).
     T1    video timing, identical to Ethernet-to-TV (video_fw.ml).
     stage memory rows (64 nibbles), a per-line descriptor list (row, palette bank, bar), palette
           banks, a ring-mode row, eight PE counters (saturating add/sub) for the bars; chroma as
           in video.ml.
   The expected screen comes from a separate reference analyser that sees only the stand-in's
   event history, never the stage's state. *)

let fclk = Video.fclk
let bit_clocks = 120                          (* 507 kbit/s at 60.852 MHz *)
let n_fields = 3
let play_clock line = 1 + (4 * ((Video_fw.line_slots * line) + Video_fw.active_slot)) + 1
(* the stage's field tick (counters decay, flash counts down) is the first playback of a field *)
let tick f = play_clock ((f * Video_fw.n_lines) + Video_fw.first_active)
let clocks = (n_fields * Video_fw.field_clocks) + 2000

(* palette indices (video.ml targets) *)
let black = 0 and white = 1 and red = 3 and yellow = 6 and cyan = 7 and magenta = 8 and orange = 9 and dgrey = 11

(* ---------------- memory rows ---------------- *)
let row_ring = 0 and row_id k = 1 + k and row_hdr = 9 and row_blank = 10
let n_rows = 11
let header_pattern = Array.init 64 (fun x -> [| 5; 7; 4; 6; 9; 3; 8; 1 |].(x / 8))

(* palette banks: nibble -> palette index *)
let bank_hdr = 0 and bank_flash = 1 and bank_bus_hi = 2 and bank_bus_lo = 3 and bank_a_hi = 4 and bank_a_lo = 5
and bank_b_hi = 6 and bank_b_lo = 7 and bank_id = 8 and bank_blank = 9
let bank_colour bank c =
  let bus = c land 1 and ta = (c lsr 1) land 1 and tb = (c lsr 2) land 1 and sp = (c lsr 3) land 1 in
  match bank with
  | 0 -> c
  | 1 -> red
  | 2 -> if bus = 1 then (if sp = 1 then yellow else white) else black
  | 3 -> if bus = 0 then (if sp = 1 then yellow else white) else black
  | 4 -> if ta = 1 then (if sp = 1 && bus = 0 then red else cyan) else black
  | 5 -> if ta = 0 then cyan else black
  | 6 -> if tb = 1 then (if sp = 1 && bus = 0 then red else magenta) else black
  | 7 -> if tb = 0 then magenta else black
  | 8 -> if c = 1 then white else if c = 0 then dgrey else black
  | _ -> black

(* the descriptor list: active line -> (row, bank, bar slot option); the header's bank is switched
   to the flash bank while the flash counter runs *)
let descriptor i =
  if i < 20 then (row_hdr, bank_hdr, None)
  else if i >= 28 && i < 76 then (row_ring, [| bank_bus_hi; bank_bus_lo; bank_a_hi; bank_a_lo; bank_b_hi; bank_b_lo |].((i - 28) / 8), None)
  else if i >= 84 && i < 212 && (i - 84) mod 16 < 12 then (let k = (i - 84) / 16 in (row_id k, bank_id, Some k))
  else (row_blank, bank_blank, None)

let bar_start = 32
let bar_len state = min 32 (state / 8)

(* ---------------- the analyser's generic blocks (model) ---------------- *)
type amem = {
  rows : int array array; tw : int array array; mutable head : int; mutable sel : int; mutable col : int;
  mutable max_interval : int;
}
let make_amem () =
  let rows = Array.make_matrix n_rows 64 0 in
  Array.blit header_pattern 0 rows.(row_hdr) 0 64;
  { rows; tw = Array.make_matrix n_rows 64 0; head = 0; sel = 0; col = 0; max_interval = 0 }

type astage = {
  mutable burst_on : bool; mutable playing : bool; mutable play_start : int; mutable line : int;
  mutable first_active : bool; pe : int array; mutable flash : int; mutable cur : Video.entry;
  mutable shown : (int * int array) list;          (* the last field: (line, 64 palette indices) *)
}
let make_astage () = { burst_on = false; playing = false; play_start = 0; line = 0; first_active = false;
                       pe = Array.make 8 0; flash = 0; cur = { Video.code = 0; th = 0; d = 0; col = false }; shown = [] }

let stage_cmd s ~now v =
  if v = Video.cmd_field then (s.line <- 0; s.first_active <- true)
  else if v = Video.cmd_burst_on then s.burst_on <- true
  else if v = Video.cmd_burst_off then s.burst_on <- false
  else if v = Video.cmd_active then begin
    if s.first_active then begin
      (* once per field: the counters decay, the flash counts down *)
      if Sys.getenv_opt "DEBUG" <> None then Printf.printf "stage tick at %d (reference tick times %d %d %d)\n" now (tick 0) (tick 1) (tick 2);
      s.first_active <- false;
      Array.iteri (fun k x -> s.pe.(k) <- max 0 (x - 4)) s.pe;
      if s.flash > 0 then s.flash <- s.flash - 1;
      s.shown <- []
    end;
    s.playing <- true; s.play_start <- now
  end
  else if v land 0xF0 = 0x20 then s.pe.(v land 7) <- min 255 (s.pe.(v land 7) + 32)
  else if v = 0x40 then s.flash <- 30

let pixel_colour s m ~now i x =
  let row, bank, bar = descriptor i in
  let bank = if row = row_hdr && s.flash > 0 then bank_flash else bank in
  let idx = if row = row_ring then (m.head + x) mod 64 else x in
  let iv = now - m.tw.(row).(idx) in
  if iv > m.max_interval && row <> row_blank then m.max_interval <- iv;
  m.tw.(row).(idx) <- now;                                   (* refresh on read *)
  match bar with
  | Some k when x >= bar_start -> if x - bar_start < bar_len s.pe.(k) then orange else black
  | _ -> bank_colour bank m.rows.(row).(idx)

let stage_clock s m ~now ~seq_code =
  if s.playing && (now - s.play_start) / Video.pix_clocks >= Video.n_pix then begin
    s.playing <- false; s.line <- s.line + 1
  end;
  if s.playing then begin
    let off = now - s.play_start in
    let x = off / Video.pix_clocks in
    if off mod Video.pix_clocks = 0 then begin
      let pal = Lazy.force Video.palette in
      let c = pixel_colour s m ~now s.line x in
      (match s.shown with
       | (l, a) :: _ when l = s.line -> a.(x) <- c
       | _ -> let a = Array.make 64 0 in a.(x) <- c; s.shown <- (s.line, a) :: s.shown);
      s.cur <- pal.(c)
    end;
    let a, b = Video.chroma_ab now s.cur in
    (s.cur.code, a, b)
  end else begin
    let a, b = if s.burst_on then Video.chroma_ab now Video.burst else (1, 0) in
    (seq_code, a, b)
  end

(* write ports: 0 row select (column 0), 1 ring data (a nibble at the ring head), 2 expanding write
   (a byte becomes eight nibbles, 1 or 0, msb first) *)
let mem_write m ~now p v =
  match p with
  | 0 -> m.sel <- v mod n_rows; m.col <- 0
  | 1 -> m.rows.(row_ring).(m.head) <- v land 15; m.tw.(row_ring).(m.head) <- now; m.head <- (m.head + 1) mod 64
  | 2 -> for j = 0 to 7 do
      if m.col < 64 then (m.rows.(m.sel).(m.col) <- (v lsr (7 - j)) land 1; m.tw.(m.sel).(m.col) <- now; m.col <- m.col + 1)
    done
  | _ -> ()

(* ---------------- the renderer programmes ---------------- *)
let bit_renderer () =
  let b = Asm.create () in
  let open Asm in
  label b "top"; block_recv b 4; block_send b 5; emit b (jmp "top");
  assemble b

let frame_renderer () =
  let b = Asm.create () in
  let open Asm in
  label b "top";
  block_recv b 5;                                   (* tag *)
  emit b (br_set 1 "end_ev");
  block_recv b 5; block_send b 2;                   (* c1 = 0 0 0 0 0 SOF ID10 ID9, kept in own inbox *)
  emit b (br_set 1 "id1x"); emit b (br_set 0 "id01");
  let leaf2 a0 a1 = block_recv b 5; block_send b 2; emit b (br_set 7 a1); emit b (jmp a0) in
  leaf2 "s0" "s1";
  label b "id01"; leaf2 "s2" "s3";
  label b "id1x"; emit b (br_set 0 "id11"); leaf2 "s4" "s5";
  label b "id11"; leaf2 "s6" "s7";
  for k = 0 to 7 do
    label b (Printf.sprintf "s%d" k);
    emit b (W (Isa.lda (row_id k))); block_send b 4;
    emit b (W (Isa.lda (0x20 + k))); block_send b 7;
    if k < 7 then emit b (jmp "wr")
  done;
  label b "wr";
  block_recv b 2; block_send b 6; block_recv b 2; block_send b 6; block_recv b 5; block_send b 6;
  emit b (jmp "top");
  label b "end_ev";
  (* any non-zero end code (stuff 1, CRC 2, form 3, ...) flashes the header *)
  block_recv b 5; List.iter (fun k -> emit b (br_set k "flash")) [ 0; 1; 2; 3 ]; emit b (jmp "top");
  label b "flash";
  emit b (W (Isa.lda 0x40)); block_send b 7; emit b (jmp "top");
  assemble b

(* ---------------- traffic ---------------- *)
let ids = [| 0x0A5; 0x1B2; 0x23C; 0x341; 0x4F0; 0x512; 0x6AA; 0x7C3 |]      (* slot = ID10..ID8 *)

(* What the analyser's in-ports receive, from either source: per-bit codes (bus, TXD A, TXD B,
   mark) and frame events (0xA1 c1 c2 c3 after the header; 0xA2 status at the end), timed in
   clocks of this simulation. *)
type events = { bits : (int * int) list; fevs : (int * int list) list; ntrans : int; contests : int; source : string }

(* the stand-in: frames during the first two fields; the third is quiet and is the one judged *)
let traffic ~seed ~error_frame =
  let rnd = Random.State.make [| seed |] in
  let t = ref 20_000 and bits_acc = ref [] and fevs_acc = ref [] and ntrans = ref 0 and contests = ref 0 in
  let quiet_from = (n_fields - 1) * Video_fw.field_clocks - 40_000 in
  let k = ref 0 in
  let last_contest = ref false in
  while !t < quiet_from do
    if !t > quiet_from - 30_000 then last_contest := true;
    (* keep frame events clear of the field ticks: the renderer's few slots of latency must not
       change the order of an increment and a decay between the stage and the reference *)
    let near = List.exists (fun f -> !t > tick f - 30_000 && !t < tick f + 2_000) (List.init n_fields Fun.id) in
    if near then t := !t + 4_000 else begin
    let mk id err = { Can_standin.id; rtr = 0; data = List.init (Random.State.int rnd 9) (fun _ -> Random.State.int rnd 256);
                      stuff_error_at = (if err then Some 0 else None) } in
    (* skewed activity: slot s is picked with weight 8 - s *)
    let pick () = let r = Random.State.int rnd 36 in let rec go s acc = if r < acc + (8 - s) then s else go (s + 1) (acc + 8 - s) in go 0 0 in
    let a, bb =
      if !last_contest then
        (* the last transmission: a short contest, so the whole of it, arbitration included, is in
           the 64-bit waveform when the bus goes quiet *)
        (Some { (mk ids.(1) false) with data = [] }, Some { (mk ids.(2) false) with data = [] })
      else if !k mod 7 = 3 then (Some (mk ids.(1) false), Some (mk ids.(2) false))          (* an arbitration contest *)
      else if error_frame && !k = 23 then (None, Some { (mk ids.(5) true) with data = [ 0xFF; 0xFF; 0x00 ] })
      else if Random.State.bool rnd then (Some (mk ids.(pick ()) false), None) else (None, Some (mk ids.(pick ()) false)) in
    let bits, fevs, _ = Can_standin.transmit ?a ?b:bb () in
    if a <> None && bb <> None then incr contests;
    incr ntrans;
    fevs_acc := List.rev_append (List.map (fun (i, bs) -> (!t + ((i + 1) * bit_clocks), bs)) fevs) !fevs_acc;
    bits_acc := List.rev_append (List.mapi (fun i e -> (!t + ((i + 1) * bit_clocks) - (bit_clocks / 3), Can_standin.code e)) bits) !bits_acc;
    t := if !last_contest then quiet_from else !t + ((List.length bits + 20 + Random.State.int rnd 200) * bit_clocks);
    incr k
    end
  done;
  { bits = List.rev !bits_acc; fevs = List.rev !fevs_acc; ntrans = !ntrans; contests = !contests; source = "stand-in" }

(* the real firmware: the log written by can_events.exe (master's CAN RX thread, raw mode, on its
   bus model). Its tagged reports become the frame events: after SOF the first three DATA bytes
   are c1 c2 c3 (0xA1 c1 c2 c3), END v is 0xA2 v; RAW/STUFF reports with the TXD probes are the
   bit codes. Times are converted from the branch's femtoseconds to this simulation's clocks. *)
let load_log path =
  let ic = open_in path in
  let cyc t_fs = int_of_float (float t_fs *. 1e-15 *. fclk) in
  let bits = ref [] and fevs = ref [] and hdr = ref [] and ntrans = ref 0 and contests = ref 0 in
  let a_drove = ref false and b_drove = ref false in
  (try while true do
      match String.split_on_char ' ' (input_line ic) with
      | [ "B"; t; l; ta; tb; mark ] ->
        let l = int_of_string l and ta = int_of_string ta and tb = int_of_string tb and mark = int_of_string mark in
        if ta = 0 then a_drove := true; if tb = 0 then b_drove := true;
        bits := (cyc (int_of_string t), l lor (ta lsl 1) lor (tb lsl 2) lor ((if mark > 0 then 1 else 0) lsl 3)) :: !bits
      | [ "F"; t; tag; v ] ->
        let t = cyc (int_of_string t) and tag = int_of_string tag and v = int_of_string v in
        if tag = 1 then begin
          hdr := []; incr ntrans;
          if !a_drove && !b_drove then incr contests; a_drove := false; b_drove := false
        end
        else if tag = 0 then begin
          if List.length !hdr < 3 then hdr := !hdr @ [ v ];
          if List.length !hdr = 3 then
            (* the first DATA byte carries three bits (SOF ID10 ID9); its upper five bits are whatever
               the RX thread's accumulator held before (ones from the idle bus: 0xF8..0xFB), which the
               branch's own decoder masks too *)
            (match !hdr with [ c1; c2; c3 ] -> fevs := (t, [ 0xA1; c1 land 7; c2; c3 ]) :: !fevs; hdr := [ c1; c2; c3; -1 ] | _ -> ())
        end
        else if tag = 4 then fevs := (t, [ 0xA2; v ]) :: !fevs
      | _ -> ()
    done with End_of_file -> ());
  close_in ic;
  if !a_drove && !b_drove then incr contests;
  { bits = List.rev !bits; fevs = List.rev !fevs; ntrans = !ntrans; contests = !contests; source = "CAN RX firmware (" ^ path ^ ")" }

(* ---------------- the reference analyser: from events alone ---------------- *)
let reference_screen ev ~judged_field =
  (* field ticks happen at the first playback of each field *)
  let pe = Array.make 8 0 and flash = ref 0 in
  let ticks = List.init (judged_field + 1) (fun f -> (tick f, [ -1 ])) in
  let all = List.stable_sort (fun (a, _) (b, _) -> compare a b) (ev.fevs @ ticks) in
  let last_hdr = Array.make 8 None in
  List.iter (fun (_, bs) ->
    match bs with
    | [ -1 ] -> Array.iteri (fun k x -> pe.(k) <- max 0 (x - 4)) pe; if !flash > 0 then decr flash
    | 0xA1 :: c1 :: c2 :: c3 :: _ -> let k = ((c1 land 3) lsl 1) lor (c2 lsr 7) in pe.(k) <- min 255 (pe.(k) + 32); last_hdr.(k) <- Some (c1, c2, c3)
    | [ 0xA2; st ] -> if st <> 0 then flash := 30
    | _ -> ()) all;
  let arr = Array.of_list (List.map snd ev.bits) in
  let nb = Array.length arr in
  let ring = Array.init 64 (fun x -> let i = nb - 64 + x in if i >= 0 then arr.(i) else 0) in
  Array.init 240 (fun i ->
    let row, bank, bar = descriptor i in
    Array.init 64 (fun x ->
      match bar with
      | Some k when x >= bar_start -> if x - bar_start < bar_len pe.(k) then orange else black
      | _ ->
        let bank = if row = row_hdr && !flash > 0 then bank_flash else bank in
        let nib =
          if row = row_ring then ring.(x)
          else if row = row_hdr then header_pattern.(x)
          else if row = row_blank then 0
          else (let k = row - 1 in match last_hdr.(k) with
            | None -> 0
            | Some (c1, c2, c3) -> if x < 24 then (((c1 lsl 16) lor (c2 lsl 8) lor c3) lsr (23 - x)) land 1 else 0) in
        bank_colour bank nib)), pe, !flash

(* ---------------- the run ---------------- *)
type opts = { rtl : bool; neigh : [ `Compiled | `Random of int | `None ]; ev : events option; out : string option }

let run o =
  let c = Isa_mb.cfg ~pc_bits:7 ~depth:2 () in
  let halt = Array.make 128 Isa.halt in
  let analyser = o.ev <> None in
  let t0 = if analyser then (let p, _, _ = bit_renderer () in p) else halt in
  let t2 = if analyser then (let p, _, _ = frame_renderer () in p) else halt in
  let t1 = if analyser then fst (Video_fw.video_programme ()) else halt in
  let t3 = match o.neigh with
    | `Compiled -> Asm.of_base ~loop:true (Compiler.uart_tx { upin = 7; bit_slots = 13; ubytes = [ 0x43; 0x41; 0x4E ]; stretch = None }) ~plen:128
    | `Random s -> Random.init s; Dual.random_neighbour ~plen:128 ~pins:0x80 ~own:[ 3 ]
    | `None -> halt in
  let d = Dual.make ~rtl:o.rtl c [| t0; t1; t2; t3 |] in
  let bitq = ref (match o.ev with Some e -> e.bits | None -> []) and fq = ref (match o.ev with Some e -> e.fevs | None -> []) in
  let p0 = Queue.create () and p1 = Queue.create () in
  let overflow = ref 0 in
  let m = make_amem () and s = make_astage () in
  let pending = ref [] in
  let oc = Option.map open_out_bin o.out in
  let fb = Bytes.create 4 in
  let comp_hash = ref 0 and neigh_hash = ref 0 in
  for n = 0 to clocks - 1 do
    (match !bitq with (t, cd) :: r when t <= n -> (if Queue.length p0 < 4 then Queue.push cd p0 else incr overflow); bitq := r | _ -> ());
    (match !fq with (t, bs) :: r when t <= n -> List.iter (fun x -> if Queue.length p1 < 8 then Queue.push x p1 else incr overflow) bs; fq := r | _ -> ());
    let io = { Isa_mb.idle_io with
               pin_in = Dual.pin_out d;
               port_in = [| (if Queue.is_empty p0 then 0 else Queue.peek p0); (if Queue.is_empty p1 then 0 else Queue.peek p1); 0; 0 |];
               port_in_valid = [| not (Queue.is_empty p0); not (Queue.is_empty p1); false; false |];
               port_out_ready = [| true; true; true; true |] } in
    let e = Dual.step d io in
    (match e.port_pop with Some 0 -> ignore (Queue.pop p0) | Some 1 -> ignore (Queue.pop p1) | _ -> ());
    List.iter (fun (p, v) -> if p = 3 then stage_cmd s ~now:n v else mem_write m ~now:n p v) !pending;
    pending := (match e.port_push with Some pv -> [ pv ] | None -> []);
    let po = Dual.pin_out d and oe = Dual.pin_oe d in
    let code, a, b = stage_clock s m ~now:n ~seq_code:(po land oe land 0x0F) in
    comp_hash := Hashtbl.hash (!comp_hash, code, a, b);
    neigh_hash := Hashtbl.hash (!neigh_hash, po land 0x80, oe land 0x80);
    (match oc with Some oc -> Bytes.set_int32_le fb 0 (Int32.bits_of_float (Video.composite ~code ~a ~b)); output_bytes oc fb | None -> ())
  done;
  Option.iter close_out oc;
  (d, s, m, !overflow, !comp_hash, !neigh_hash)

let () =
  let dir = "/var/tmp/multi-proto" in
  let t_start = Unix.gettimeofday () in
  let pr = Printf.printf in
  let _, n0, _ = bit_renderer () and _, n2, _ = frame_renderer () in
  pr "programmes: T0 bit renderer %d words, T2 frame renderer %d words, T1 video timing %d words\n" n0 n2 (snd (Video_fw.video_programme ()));
  let judge_and_write name tag ev ~rtl =
    let (d, s, m, overflow, ch, nh) = run { rtl; neigh = `Compiled; ev = Some ev; out = Some (Printf.sprintf "%s/cantv_%s.f32" dir tag) } in
    let expected, pe, flash = reference_screen ev ~judged_field:(n_fields - 1) in
    let shown = Array.make 240 [||] in
    List.iter (fun (l, a) -> if l < 240 then shown.(l) <- a) s.shown;
    let diff = ref 0 in
    Array.iteri (fun i a -> if Array.length a = 64 then Array.iteri (fun x c -> if c <> expected.(i).(x) then incr diff) a else diff := !diff + 64) shown;
    pr "%s [%s]: %d frames (%d arbitration contests), RTL/interp mismatches %d, port overflow %d; \
        stage vs reference analyser: %d of 15360 pixels differ; counters %s (reference %s); flash %d (reference %d); \
        longest interval between refreshes of a displayed row %.2f ms\n%!"
      name ev.source ev.ntrans ev.contests d.Dual.mismatches overflow !diff
      (String.concat "," (Array.to_list (Array.map string_of_int s.pe))) (String.concat "," (Array.to_list (Array.map string_of_int pe)))
      s.flash flash (float m.max_interval /. fclk *. 1e3);
    let oc = open_out (Printf.sprintf "%s/cantv_%s_expect.txt" dir tag) in
    Array.iteri (fun i (rr, g, b) -> Printf.fprintf oc "P %d %.4f %.4f %.4f\n" i rr g b) (Video.refs ());
    Array.iteri (fun i a -> Printf.fprintf oc "S %d %s\n" i (String.concat " " (Array.to_list (Array.map string_of_int a)))) expected;
    Printf.fprintf oc "G play_offset_clocks %d pix_clocks %d fclk %.3f\n" (4 * Video_fw.active_slot) Video.pix_clocks fclk;
    close_out oc;
    ch, nh in
  let fw = "results/can_events.log" and fw_noerr = "results/can_events_noerr.log" in
  let have_fw = Sys.file_exists fw && Sys.file_exists fw_noerr in
  let main_ev = if have_fw then load_log fw else traffic ~seed:3 ~error_frame:true in
  let ch, nh = judge_and_write "main (RTL + interpreter)" "main" main_ev ~rtl:true in
  ignore (judge_and_write "no error frame" "noerr" (if have_fw then load_log fw_noerr else traffic ~seed:3 ~error_frame:false) ~rtl:false);
  ignore (judge_and_write "stand-in, error frame" "standin" (traffic ~seed:3 ~error_frame:true) ~rtl:false);
  (* isolation *)
  let (_, _, _, _, ch2, _) = run { rtl = false; neigh = `None; ev = Some main_ev; out = None } in
  let (_, _, _, _, _, nh2) = run { rtl = false; neigh = `Compiled; ev = None; out = None } in
  let same = ref 0 in
  for sd = 1 to 3 do
    let (_, _, _, _, chr, _) = run { rtl = false; neigh = `Random sd; ev = Some main_ev; out = None } in
    if chr = ch then incr same
  done;
  pr "isolation: composite identical without the neighbour %b, under 3 random neighbours %d/3; neighbour pin identical without the analyser %b\n"
    (ch2 = ch) !same (nh2 = nh);
  pr "elapsed %.0f s\n" (Unix.gettimeofday () -. t_start)
