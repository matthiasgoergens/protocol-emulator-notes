(* Checks and sweeps for the 100BASE-X prototype. See README.md. *)
open Hardcaml
module R = Ref_model

let bit_list_of_int w x = List.init w (fun i -> (x lsr i) land 1)

(* Run the RTL transmitter over a list of frames; returns per-clock (code bits, line outputs) *)
let run_tx media frames ~extra =
  let sim = Cyclesim.create (Pcs.tx_circuit media) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port ~clock_edge:Before sim n in
  let clear = i "clear" and valid = i "tx_valid" and data = i "tx_data" and last = i "tx_last" in
  let ready = o "tx_ready" and code = o "code" in
  let outs = match media with Pcs.Fx -> [ "line" ] | Pcs.Tx -> [ "pin_a"; "pin_b"; "scrambled" ] in
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  let codes = ref [] and lines = ref [] in
  (* present the head byte; advance when tx_ready was high in that cycle *)
  let bytes = ref (List.concat_map (fun f -> List.mapi (fun j b -> (b, j = List.length f - 1)) f) frames) in
  let gap = ref 0 in
  while !bytes <> [] || !gap < extra do
    (match !bytes with
     | (b, l) :: _ -> valid := Bits.vdd; data := Bits.of_int ~width:8 b; last := Bits.of_bool l
     | [] -> valid := Bits.gnd; incr gap);
    (* output ports are sampled before the clock edge: this cycle's combinational values *)
    Cyclesim.cycle sim;
    let took = Bits.to_int !ready = 1 in
    codes := bit_list_of_int 2 (Bits.to_int !code) :: !codes;
    lines := List.map (fun n -> bit_list_of_int 2 (Bits.to_int !(o n))) outs :: !lines;
    if took then (match !bytes with _ :: r -> bytes := r | [] -> ())
  done;
  List.concat (List.rev !codes), List.rev !lines

let drop_to_first_j bits =
  let rec go = function
    | 1 :: 1 :: 0 :: 0 :: 0 :: 1 :: 0 :: 0 :: 0 :: 1 :: _ as l -> l
    | _ :: r -> go r | [] -> [] in go bits

let check name ok = Printf.printf "%-60s %s\n%!" name (if ok then "pass" else "FAIL")

let digital_checks () =
  let max0 = R.self_test () in
  check (Printf.sprintf "reference model self-test (longest run of zeros %d <= 3)" max0) (max0 <= 3);
  let rng = Random.State.make [| 1 |] in
  let frames = List.init 6 (fun i -> R.random_frame ~rng (64 + 290 * i)) in
  (* FX transmit: RTL code bits against the reference symbol stream *)
  let code, lines = run_tx Pcs.Fx frames ~extra:40 in
  let ref_bits = R.symbols_to_bits (R.stream ~gap:0 frames) in
  let got = drop_to_first_j code and want = drop_to_first_j ref_bits in
  (* compare frame by frame: decode both *)
  let dg = R.decode_stream got and dw = R.decode_stream want in
  check "FX tx: RTL code stream decodes to the same frames as the reference" (dg = dw && List.length dg = 6);
  if dg <> dw then List.iter2 (fun (a, _) (b, _) -> Printf.printf "  lengths %d %d equal %b\n   got  %s\n   want %s\n" (List.length a) (List.length b) (a = b)
    (String.concat " " (List.map (Printf.sprintf "%02x") (List.filteri (fun i _ -> i < 20) a)))
    (String.concat " " (List.map (Printf.sprintf "%02x") (List.filteri (fun i _ -> i < 20) b)))) dg dw;
  check "FX tx: every frame delimited and FCS correct" (List.for_all (fun (f, ok) -> ok && R.fcs_ok f) dg);
  let line = List.concat_map (function [ l ] -> l | _ -> assert false) lines in
  check "FX tx: NRZI line decodes to the code stream" (R.nrzi_decode line = code);
  (* TX transmit: scrambler + MLT-3 pins *)
  let code2, lines2 = run_tx Pcs.Tx frames ~extra:40 in
  let scr = List.concat_map (function [ _; _; s ] -> s | _ -> assert false) lines2 in
  let lvl = List.concat_map (function [ a; b; _ ] -> List.map2 ( - ) a b | _ -> assert false) lines2 in
  check "TX tx: scrambler output = reference keystream xor code" (scr = R.scramble ~seed:0x7FF code2);
  check "TX tx: pin pair A-B = reference MLT-3 of the scrambled stream" (lvl = R.mlt3_encode scr);
  let pa = List.concat_map (function [ a; _; _ ] -> a | _ -> assert false) lines2 in
  let pb = List.concat_map (function [ _; b; _ ] -> b | _ -> assert false) lines2 in
  let min_gap l = let last = ref (-100) and m = ref max_int and p = ref (List.hd l) in
    List.iteri (fun i x -> if x <> !p then (m := min !m (i - !last); last := i; p := x)) l; !m in
  Printf.printf "  TX pins: minimum spacing between edges on one pin: A %d UI, B %d UI\n" (min_gap pa) (min_gap pb);
  code, frames

(* the CDR used for a given oversampling ratio: the edge-decoding loop, or for osr = 2 the
   grid classifier (CDR2=0 selects the loop there too, to compare) *)
let make_cdr ~n ~osr =
  if osr = 2 && Cdr.env "CDR2" 1 = 1 then (let c = Cdr.Osr2.create ~n () in fun x -> Cdr.Osr2.step c x)
  else (let c = Cdr.create ~n ~osr () in fun x -> Cdr.step c x)

(* ---------- receive harness ---------- *)
type rx = { sim : Cyclesim.t_port_list; count : Bits.t ref; levels : Bits.t ref; byte : Bits.t ref; bv : Bits.t ref;
            fe : Bits.t ref; ok : Bits.t ref; media : Pcs.media;
            mutable cur : int list; mutable got : (int list * bool) list; mutable overflow : int }

let rx_create media =
  let sim = Cyclesim.create (Pcs.rx_circuit media) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port ~clock_edge:Before sim n in
  let clear = i "clear" in
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  { sim; count = i "count"; levels = i "levels"; byte = o "rx_byte"; bv = o "byte_valid"; fe = o "frame_end";
    ok = o "crc_ok"; media; cur = []; got = []; overflow = 0 }

let trace = ref 0
(* feed one clock's recovered UIs (0..3 of them; values: FX level 0/1, TX level -1/0/+1) *)
let rx_clock r (uis : int list) =
  let uis = if List.length uis > 3 then (r.overflow <- r.overflow + 1; List.filteri (fun i _ -> i < 3) uis) else uis in
  let enc v = match r.media with Pcs.Fx -> v | Pcs.Tx -> (match v with 1 -> 1 | -1 -> 2 | _ -> 0) in
  let w = match r.media with Pcs.Fx -> 1 | Pcs.Tx -> 2 in
  let lv = List.fold_left (fun (acc, sh) v -> (acc lor (enc v lsl sh), sh + w)) (0, 0) uis |> fst in
  r.count := Bits.of_int ~width:2 (List.length uis);
  r.levels := Bits.of_int ~width:(3 * w) lv;
  (* output ports are sampled before the clock edge (see rx_create) *)
  Cyclesim.cycle r.sim;
  if !trace > 0 then begin
    decr trace;
    let o n = Bits.to_int !(Cyclesim.out_port ~clock_edge:Before r.sim n) in
    if o "dbg_gv" = 1 || o "dbg_found" = 1 || o "frame_end" = 1 then
      Printf.printf "[lv%d f%d id%d fe%d] " (Bits.to_int !(r.levels)) (o "dbg_found") (o "dbg_id") (o "frame_end")
  end;
  if Bits.to_int !(r.bv) = 1 then r.cur <- Bits.to_int !(r.byte) :: r.cur;
  if Bits.to_int !(r.fe) = 1 then (r.got <- (List.rev r.cur, Bits.to_int !(r.ok) = 1) :: r.got; r.cur <- [])

(* compare received frames against sent frames (both with FCS). Returns
   (sent, received intact, false accepts, bit errors, bits compared) *)
let score sent got =
  let tbl = Hashtbl.create 64 in
  List.iteri (fun i f -> Hashtbl.replace tbl f i) sent;
  let intact = Hashtbl.create 64 and false_acc = ref 0 in
  List.iter (fun (f, ok) -> if ok then (match Hashtbl.find_opt tbl f with Some i -> Hashtbl.replace intact i () | None -> incr false_acc)) got;
  (* bit errors: pair each received frame, in order, with the next sent frame of the same length *)
  let errs = ref 0 and bits = ref 0 in
  let rest = ref sent in
  List.iter (fun (f, _) ->
      let rec find = function
        | [] -> None
        | s :: r -> if List.length s = List.length f then Some (s, r) else find r in
      match find !rest with
      | Some (s, r) ->
        let d = List.fold_left2 (fun a x y -> let z = ref (x lxor y) and c = ref 0 in while !z <> 0 do incr c; z := !z land (!z - 1) done; a + !c) 0 s f in
        if d * 10 < 8 * List.length s then (errs := !errs + d; bits := !bits + 8 * List.length s; rest := r)
      | None -> ()) (List.rev got |> List.rev);
  List.length sent, Hashtbl.length intact, !false_acc, !errs, !bits

let sizes_default = [ 64; 128; 512; 1518 ]

(* 100BASE-FX receive through the behavioural line and front end *)
let fx_trial ~seed ~osr ~nframes ~sizes ?(rj = 0.0) ?(dcd = 0.0) ?(ddr = 0.0) ?(ppm = 0.0) ?(tap_mis = 0.0) ?(sj = 0.0) () =
  let rng = Random.State.make [| seed |] in
  let frames = List.init nframes (fun i -> R.random_frame ~rng (List.nth sizes (i mod List.length sizes))) in
  (* 4000 idle symbols (20 000 UI, 160 us) first: a link idles before traffic, and the osr = 2
     receiver learns the direction of the frequency offset in idle *)
  let syms = List.init 4000 (fun _ -> R.I) @ R.stream ~gap:24 frames in
  let levels = Array.of_list (R.nrzi_encode (R.symbols_to_bits syms)) in
  let line = Line.make ~rng ~ui:8.0 ~rj ~dcd ~ddr levels in
  let n = 2 * osr in
  let tap_err = Array.init n (fun _ -> tap_mis *. (Random.State.float rng 2.0 -. 1.0)) in
  let smp = Line.sampler ~rng ~line ~n ~ppm ~tap_err ~sj () in
  let cdr = make_cdr ~n ~osr in
  let r = rx_create Pcs.Fx in
  let tend = 8.0 *. float (Array.length levels) -. 40.0 in
  while Line.end_time smp < tend do rx_clock r (cdr (Line.clock smp)) done;
  let sent = List.map R.with_fcs frames in
  let ns, ok, fa, errs, bits = score sent (List.rev r.got) in
  ns, ok, fa, errs, bits, r.overflow

let fx_sweep oc =
  let pr fmt = Printf.ksprintf (fun s -> print_string s; output_string oc s; flush oc) fmt in
  pr "# 100BASE-FX receive: frame loss vs oversampling, jitter and frequency offset\n";
  pr "# frames of %s bytes in rotation; loss = 1 - intact/sent; false accepts must be 0;\n" (String.concat "/" (List.map string_of_int sizes_default));
  pr "# BER over frames of the right length (slipped frames are loss, not bits)\n";
  pr "osr ppm rj_ns dcd_ns ddr_ns tap_mis_ns | sent intact loss%% false_acc bit_err bits BER overflow\n";
  let cell ~osr ~ppm ~rj ~dcd ~ddr ~tap_mis ~nf =
    let s, ok, fa, e, b, ov = fx_trial ~seed:(osr * 1000 + int_of_float (rj *. 100.) + int_of_float ppm) ~osr ~nframes:nf ~sizes:sizes_default ~rj ~dcd ~ddr ~ppm ~tap_mis () in
    pr "%d %+.0f %.2f %.2f %.2f %.2f | %d %d %.1f %d %d %d %.2e %d\n" osr ppm rj dcd ddr tap_mis s ok (100.0 *. float (s - ok) /. float s) fa e b
      (if b = 0 then nan else float e /. float b) ov in
  let nf = try int_of_string (Sys.getenv "NF") with Not_found -> 80 in
  List.iter (fun osr ->
      List.iter (fun ppm ->
          List.iter (fun rj -> cell ~osr ~ppm ~rj ~dcd:0.0 ~ddr:0.0 ~tap_mis:0.0 ~nf) [ 0.0; 0.25; 0.5; 0.75; 1.0 ])
        [ 0.0; 200.0; -200.0 ]) [ 1; 2; 3; 4 ];
  (* realistic budget: DCD from the receive threshold, the DDR transmitter's duty error, tap mismatch *)
  List.iter (fun osr ->
      List.iter (fun (dcd, ddr, tap) -> cell ~osr ~ppm:200.0 ~rj:0.3 ~dcd ~ddr ~tap_mis:tap ~nf)
        [ (0.5, 0.0, 0.0); (1.0, 0.0, 0.0); (2.0, 0.0, 0.0); (1.0, 0.5, 0.0); (1.0, 1.0, 0.0); (1.0, 0.5, 0.3); (1.0, 0.5, 0.6) ])
    [ 2; 3; 4 ]

let () =
  let _ = digital_checks () in
  match Sys.argv with
  | [| _; "fx" |] -> let oc = open_out "results/fx_sweep.txt" in fx_sweep oc; close_out oc
  | [| _; "fx1"; osr; ppm; rj |] ->
    let s, ok, fa, e, b, ov = fx_trial ~seed:1 ~osr:(int_of_string osr) ~nframes:20 ~sizes:sizes_default ~rj:(float_of_string rj) ~ppm:(float_of_string ppm) () in
    Printf.printf "sent %d intact %d false %d errs %d/%d overflow %d\n" s ok fa e b ov
  | [| _; "ideal" |] ->
    let rng = Random.State.make [| 3 |] in
    let frames = List.init 4 (fun i -> R.random_frame ~rng (64 + 100 * i)) in
    let levels = R.nrzi_encode (R.symbols_to_bits (List.init 20 (fun _ -> R.I) @ R.stream frames)) in
    let r = rx_create Pcs.Fx in
    trace := 0;
    let o n = Cyclesim.out_port r.sim n in
    let rec go k = function a :: b :: rest -> rx_clock r [ a; b ];
      ignore o; ignore k;
      go (k + 1) rest | _ -> () in
    let go = go 0 in
    go levels;
    List.iter2 (fun s (g, ok) -> Printf.printf "sent %d got %d ok %b equal %b\n  s %s\n  g %s\n" (List.length s) (List.length g) ok (s = g)
      (String.concat " " (List.map (Printf.sprintf "%02x") (List.filteri (fun i _ -> i < 12) s)))
      (String.concat " " (List.map (Printf.sprintf "%02x") (List.filteri (fun i _ -> i < 12) g)))) (List.map R.with_fcs frames) (List.rev r.got)
  | [| _; "cdrdbg"; osr; ppm; rj |] ->
    (* CDR alone against the sent levels: count UIs out, and decision errors by aligning in
       windows (offset searched +-4 each window of 256 UIs) *)
    let osr = int_of_string osr in
    let rng = Random.State.make [| 5 |] in
    let lv = Array.of_list (R.nrzi_encode (R.symbols_to_bits (List.init 4000 (fun _ -> R.I) @ R.stream ~gap:24 (List.init 10 (fun _ -> R.random_frame ~rng 1518))))) in
    let line = Line.make ~rng ~ui:8.0 ~rj:(float_of_string rj) lv in
    let smp = Line.sampler ~rng ~line ~n:(2 * osr) ~ppm:(float_of_string ppm) () in
    let c = Cdr.create ~n:(2 * osr) ~osr () in
    let step = make_cdr ~n:(2 * osr) ~osr in
    let out = ref [] and th = ref [] in
    while Line.end_time smp < 8.0 *. float (Array.length lv) -. 40.0 do
      List.iter (fun v -> out := v :: !out) (step (Line.clock smp)); th := (c.Cdr.theta, c.Cdr.omega) :: !th done;
    let o = Array.of_list (List.rev !out) in
    Printf.printf "sent %d UIs, recovered %d\n" (Array.length lv) (Array.length o);
    let off = ref 0 and slips = ref 0 and errs = ref 0 in
    let w = 256 in
    let mism off base = let m = ref 0 in for i = base to base + w - 1 do
        let j = i + off in if j >= 0 && j < Array.length lv && i < Array.length o then (if o.(i) <> lv.(j) then incr m) else incr m done; !m in
    (* initial offset *)
    let best = ref (0, max_int) in for d = -40 to 40 do let m = mism d 0 in if m < snd !best then best := (d, m) done;
    off := fst !best;
    let b = ref 0 in
    while !b + w < Array.length o do
      let m = mism !off !b in
      if m > 8 then begin
        let best = ref (!off, m) in for d = !off - 4 to !off + 4 do let m = mism d !b in if m < snd !best then best := (d, m) done;
        if fst !best <> !off then (incr slips; Printf.printf "  slip at UI %d: offset %d -> %d (mismatch %d -> %d)\n" !b !off (fst !best) m (snd !best));
        off := fst !best; errs := !errs + snd !best
      end else errs := !errs + m;
      b := !b + w done;
    (* first mismatch in detail *)
    (try for i = 300 to Array.length o - 1 do
         let j = i + !off in
         if j < Array.length lv && o.(i) <> lv.(j) then begin
           Printf.printf "first mismatch at out %d (sent %d): sent %s\n                                 got  %s\n" i j
             (String.concat "" (List.init 30 (fun k -> string_of_int lv.(j - 15 + k))))
             (String.concat "" (List.init 30 (fun k -> string_of_int o.(i - 15 + k)))); raise Exit end done with Exit -> ());
    Printf.printf "slips %d, decision errors %d, voter flips %d vote %d\n" !slips !errs c.Cdr.flips c.Cdr.vote;
    Printf.printf "lone-sample position histogram (8 bins of a UI, 0 = data sample): %s\n" (String.concat " " (Array.to_list (Array.map string_of_int c.Cdr.hist)));
    let ths = Array.of_list (List.rev !th) in
    Array.iteri (fun i (t, om) -> if i mod 500 = 0 then Printf.printf "  clk %d theta %d omega %d\n" i t om) ths
  | _ -> ()
