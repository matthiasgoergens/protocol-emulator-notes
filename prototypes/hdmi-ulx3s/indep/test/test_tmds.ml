(* Tests for Tmds_indep, written against DVI 1.0 section 3.2/3.3 only. *)
open Tmds_indep

let failures = ref 0
let check name ok =
  Printf.printf "  [%s] %s\n%!" (if ok then "ok" else "FAIL") name;
  if not ok then incr failures

let () = Random.init 20261005

(* ---- Mutable encoder with optional planted bugs ------------------------- *)
type mutation =
  | M_none
  | M_tie_rule          (* XNOR rule drops the "N1==4 && D[0]==0" tie clause *)
  | M_cnt_q8_swap       (* inverted branch: 2*~q_m[8] instead of 2*q_m[8] *)
  | M_ctrl_swap         (* control codes for (C1,C0)=10 and 11 swapped *)
  | M_inv_ge            (* inversion test uses cnt>=0 instead of cnt>0 (via cnt=0 shortcut removed) *)
  | M_no_reset          (* cnt not reset to 0 on a control period *)
  | M_balanced_q9       (* balanced branch: q_out[9] = q_m[8] instead of ~q_m[8] *)
  | M_balanced_cnt      (* balanced branch: cnt update sign flipped *)
  | M_xor_tie_d0        (* tie clause uses D[0]==1 *)

let all_mutations =
  [ M_none; M_tie_rule; M_cnt_q8_swap; M_ctrl_swap; M_inv_ge; M_no_reset;
    M_balanced_q9; M_balanced_cnt; M_xor_tie_d0 ]

let mutation_name = function
  | M_none -> "none (control: faithful copy)"
  | M_tie_rule -> "xnor rule: tie clause dropped"
  | M_cnt_q8_swap -> "cnt: 2*q_m[8] term swapped"
  | M_ctrl_swap -> "control code 10/11 swapped"
  | M_inv_ge -> "inversion test cnt>=0 / cnt<=0"
  | M_no_reset -> "cnt not reset on control"
  | M_balanced_q9 -> "balanced branch q_out[9] wrong"
  | M_balanced_cnt -> "balanced branch cnt sign wrong"
  | M_xor_tie_d0 -> "xnor tie uses D[0]==1"

let popcount = let rec go x a = if x = 0 then a else go (x lsr 1) (a + (x land 1)) in fun x -> go x 0
let bit w i = (w lsr i) land 1

module Enc = struct
  type t = { m : mutation; mutable cnt : int }
  let create m = { m; cnt = 0 }

  let data t d =
    let n1d = popcount d in
    let use_xnor =
      match t.m with
      | M_tie_rule -> n1d > 4
      | M_xor_tie_d0 -> n1d > 4 || (n1d = 4 && bit d 0 = 1)
      | _ -> n1d > 4 || (n1d = 4 && bit d 0 = 0)
    in
    let qm = ref (d land 1) in
    for i = 1 to 7 do
      let x = bit !qm (i - 1) lxor bit d i in
      qm := !qm lor ((if use_xnor then 1 - x else x) lsl i)
    done;
    let qm = !qm in
    let q8 = if use_xnor then 0 else 1 in
    let n1 = popcount qm in
    let n0 = 8 - n1 in
    let inv = lnot qm land 0xff in
    let balanced =
      match t.m with
      | M_inv_ge -> n1 = n0
      | _ -> t.cnt = 0 || n1 = n0
    in
    if balanced then begin
      let q9 = if t.m = M_balanced_q9 then q8 else 1 - q8 in
      let lo = if q8 = 1 then qm else inv in
      let delta = if q8 = 0 then n0 - n1 else n1 - n0 in
      t.cnt <- t.cnt + (if t.m = M_balanced_cnt then -delta else delta);
      lo lor (q8 lsl 8) lor (q9 lsl 9)
    end
    else begin
      let invert =
        match t.m with
        | M_inv_ge -> (t.cnt >= 0 && n1 > n0) || (t.cnt < 0 && n0 > n1)
        | _ -> (t.cnt > 0 && n1 > n0) || (t.cnt < 0 && n0 > n1)
      in
      if invert then begin
        let q8t = if t.m = M_cnt_q8_swap then 1 - q8 else q8 in
        t.cnt <- t.cnt + (2 * q8t) + (n0 - n1);
        inv lor (q8 lsl 8) lor (1 lsl 9)
      end
      else begin
        t.cnt <- t.cnt - (2 * (1 - q8)) + (n1 - n0);
        qm lor (q8 lsl 8)
      end
    end

  let control t ~c0 ~c1 =
    if t.m <> M_no_reset then t.cnt <- 0;
    let c0, c1 =
      match (t.m, c1, c0) with
      | M_ctrl_swap, true, false -> (true, true)
      | M_ctrl_swap, true, true -> (false, true)
      | _ -> (c0, c1)
    in
    control_word ~c0 ~c1
end

(* ---- Spec-derived expectations, restated here independently --------------- *)
let spec_control_strings =
  [ ((false, false), "0010101011"); ((true, false), "1101010100");
    ((false, true), "0010101010"); ((true, true), "1101010101") ]
(* key = (c0, c1); Figure 3-5 "case (C1, C0)": 00, 01 (C0=1), 10 (C1=1), 11. *)

let word_of_string s =
  let w = ref 0 in
  String.iteri (fun i c -> if c = '1' then w := !w lor (1 lsl i)) s; !w

(* ---- The individual checks, parametrised by encoder -------------------- *)
(* Each takes an encoder as three closures so the same code runs on the
   reference and on mutants. *)
type encoder = {
  set_cnt : int -> unit; get_cnt : unit -> int;
  enc_data : int -> int; enc_control : c0:bool -> c1:bool -> int;
}

let of_ref () =
  let e = Ref_encoder.create () in
  { set_cnt = Ref_encoder.set_cnt e; get_cnt = (fun () -> Ref_encoder.cnt e);
    enc_data = Ref_encoder.data e; enc_control = Ref_encoder.control e }

let of_mut m =
  let e = Enc.create m in
  { set_cnt = (fun v -> e.Enc.cnt <- v); get_cnt = (fun () -> e.Enc.cnt);
    enc_data = Enc.data e; enc_control = Enc.control e }

let cnt_range = List.init 41 (fun i -> i - 20)     (* all of -20..20, odd too *)

(* C1: decode (encode x) = x for all x and all starting cnt. *)
let c_roundtrip mk =
  List.for_all (fun c ->
    List.for_all (fun x ->
      let e = mk () in
      e.set_cnt c;
      decode (e.enc_data x) = Data x) (List.init 256 Fun.id)) cnt_range

(* Reachable cnt values of the reference encoder, by closure from cnt = 0
   (computed here, not taken from the library). *)
let reachable =
  let seen = Hashtbl.create 16 in
  let rec go c =
    if not (Hashtbl.mem seen c) then begin
      Hashtbl.add seen c ();
      for d = 0 to 255 do
        let e = Ref_encoder.create () in
        Ref_encoder.set_cnt e c;
        ignore (Ref_encoder.data e d);
        go (Ref_encoder.cnt e)
      done
    end in
  go 0;
  List.sort compare (Hashtbl.fold (fun c () a -> c :: a) seen [])

(* Words the reference encoder emits from the given starting cnt values. *)
let emitted_words cnts =
  let a = Array.make 1024 false in
  List.iter (fun c ->
    for d = 0 to 255 do
      let e = Ref_encoder.create () in
      Ref_encoder.set_cnt e c;
      a.(Ref_encoder.data e d) <- true
    done) cnts;
  a

(* C2: every word emitted (from every reachable cnt) is a word the spec
   encoder can emit; the library's is_valid_data is the oracle. *)
let c_valid_words mk =
  List.for_all (fun c ->
    List.for_all (fun x ->
      let e = mk () in
      e.set_cnt c;
      is_valid_data (e.enc_data x)) (List.init 256 Fun.id)) reachable

(* C3: control words equal the four spec words. *)
let c_control mk =
  List.for_all (fun ((c0, c1), s) ->
    let e = mk () in
    e.enc_control ~c0 ~c1 = word_of_string s) spec_control_strings

(* A mixed stream: bursts of data bytes separated by control periods.  Returns
   the list of (word, cnt after, was_control). *)
let mixed_stream mk n =
  let e = mk () in
  let out = ref [] in
  let remaining = ref n in
  while !remaining > 0 do
    let burst = 1 + Random.int 40 in
    for _ = 1 to min burst !remaining do
      let w = e.enc_data (Random.int 256) in
      out := (w, e.get_cnt (), false) :: !out
    done;
    remaining := !remaining - burst;
    for _ = 1 to 1 + Random.int 5 do
      let w = e.enc_control ~c0:(Random.bool ()) ~c1:(Random.bool ()) in
      out := (w, e.get_cnt (), true) :: !out
    done
  done;
  List.rev !out

(* C4a: cnt equals the sum of emitted-word disparities since the last control
   period (disparity computed with ones_minus_zeros, NOT from cnt). *)
let c_cnt_tracks mk =
  let acc = ref 0 and ok = ref true in
  List.iter (fun (w, cnt, is_ctl) ->
    if is_ctl then acc := 0 else acc := !acc + ones_minus_zeros w;
    if cnt <> !acc then ok := false) (mixed_stream mk 20000);
  !ok

(* C4b: running disparity of a long continuous data stream stays within the
   reference bound (measured below). *)
let running_disparity_extent mk n =
  let e = mk () in
  let acc = ref 0 and lo = ref 0 and hi = ref 0 in
  for _ = 1 to n do
    acc := !acc + ones_minus_zeros (e.enc_data (Random.int 256));
    if !acc < !lo then lo := !acc;
    if !acc > !hi then hi := !acc
  done;
  (!lo, !hi)

(* ---- The report ---------------------------------------------------------- *)
let () =
  print_endline "== Reference encoder and decoder ==";
  (* Control codes *)
  check "four control words equal the spec table"
    (List.for_all (fun ((c0, c1), s) -> control_word ~c0 ~c1 = word_of_string s) spec_control_strings);
  check "control words decode back"
    (List.for_all (fun ((c0, c1), s) -> decode (word_of_string s) = Control { c0; c1 }) spec_control_strings);
  (* Not all control words are balanced: C1,C0 = 10 has disparity -2 and 11 has
     +2.  That is why the spec resets cnt to 0 on a control period rather than
     tracking it. *)
  check "control words all distinct; disparities are 0, 0, -2, +2 for (c1,c0) = 00, 01, 10, 11"
    (let ws = List.map (fun (_, s) -> word_of_string s) spec_control_strings in
     List.length (List.sort_uniq compare ws) = 4
     && List.map ones_minus_zeros ws = [ 0; 0; -2; 2 ]);
  Printf.printf "  info: first-transmitted bits of control words (bit0 first): %s\n"
    (String.concat " " (List.map snd spec_control_strings));

  (* Reachable cnt *)
  Printf.printf "  info: reachable cnt values: %s\n"
    (String.concat " " (List.map string_of_int reachable));
  check "cnt is always even (all reachable values even)" (List.for_all (fun c -> c land 1 = 0) reachable);

  (* roundtrip *)
  check "decode(encode x) = x, all 256 x, every start cnt in -20..20 (odd and even)"
    (c_roundtrip (fun () -> of_ref ()));

  (* No data word decodes as control *)
  let all_data = emitted_words (List.init 81 (fun i -> i - 40)) in
  let reach_data = emitted_words reachable in
  let ctl_ws = List.map (fun (_, s) -> word_of_string s) spec_control_strings in
  check "no data word (from any cnt in -40..40) is a control word"
    (List.for_all (fun w -> not (all_data.(w) && List.mem w ctl_ws)) (List.init 1024 Fun.id));
  check "no emitted data word decodes as Control"
    (List.for_all (fun w -> not all_data.(w) || (match decode w with Control _ -> false | _ -> true)) (List.init 1024 Fun.id));

  (* is_valid_data *)
  let count a = Array.fold_left (fun n b -> if b then n + 1 else n) 0 a in
  Printf.printf "  info: distinct data words from reachable cnt: %d; from all cnt -40..40: %d\n"
    (count reach_data) (count all_data);
  check "is_valid_data = words emitted by reference encoder (reachable cnt)"
    (List.for_all (fun w -> is_valid_data w = reach_data.(w)) (List.init 1024 Fun.id));
  check "exactly 460 distinct data words" (count reach_data = 460);
  check "is_valid_data rejects control words" (List.for_all (fun w -> not (is_valid_data w)) ctl_ws);
  check "decode never returns Invalid; decode_strict does for non-words"
    (List.for_all (fun w -> match decode w with Invalid _ -> false | _ -> true) (List.init 1024 Fun.id)
     && List.for_all (fun w -> (decode_strict w = Invalid w) = (not (is_valid_data w) && not (List.mem w ctl_ws)))
          (List.init 1024 Fun.id));

  (* Disparity bound *)
  let lo, hi = running_disparity_extent (fun () -> of_ref ()) 1_000_000 in
  let rmin = List.fold_left min 0 reachable and rmax = List.fold_left max 0 reachable in
  Printf.printf "  info: 10^6 random bytes: running disparity (ones-zeros) min %d max %d; reachable cnt range %d..%d\n"
    lo hi rmin rmax;
  check "running disparity within reachable-cnt range (spec bound implied by Figure 3-5)"
    (lo >= rmin && hi <= rmax);
  check "cnt = sum of word disparities since last control (mixed stream)"
    (c_cnt_tracks (fun () -> of_ref ()));
  (* Per-word: max |word disparity| *)
  let maxw = ref 0 in
  Array.iteri (fun w b -> if b then maxw := max !maxw (abs (ones_minus_zeros w))) reach_data;
  Printf.printf "  info: max |disparity| of one data word: %d\n" !maxw;
  let bound = max (abs lo) (abs hi) in

  (* ---- Alignment, frames, timing ---------------------------------------- *)
  print_endline "== Alignment, frames, timing (synthetic 640x480@60) ==";
  let h_active = 640 and h_front = 16 and h_sync = 96 and h_back = 48 in
  let v_active = 480 and v_front = 10 and v_sync = 2 and v_back = 33 in
  let h_total = h_active + h_front + h_sync + h_back
  and v_total = v_active + v_front + v_sync + v_back in
  let pixel f x y = ((x * 3 + y + f * 17) land 255, (x + y * 5 + f) land 255, (x * y + f * 29) land 255) in
  (* One stream of words per lane (list of 10-bit words), via Ref_encoder. *)
  let gen ~hpol ~vpol ~nframes =
    let eb = Ref_encoder.create () and eg = Ref_encoder.create () and er = Ref_encoder.create () in
    let n = nframes * h_total * v_total in
    let wb = Array.make n 0 and wg = Array.make n 0 and wr = Array.make n 0 in
    let i = ref 0 in
    for f = 0 to nframes - 1 do
      for y = 0 to v_total - 1 do
        (* Vertical position of the line: active lines first, then front porch,
           sync, back porch (VESA order within a frame). *)
        let vs_on = y >= v_active + v_front && y < v_active + v_front + v_sync in
        for x = 0 to h_total - 1 do
          let hs_on = x >= h_active + h_front && x < h_active + h_front + h_sync in
          if y < v_active && x < h_active then begin
            let r, g, b = pixel f x y in
            wb.(!i) <- Ref_encoder.data eb b;
            wg.(!i) <- Ref_encoder.data eg g;
            wr.(!i) <- Ref_encoder.data er r
          end else begin
            let hs = if hpol then hs_on else not hs_on
            and vs = if vpol then vs_on else not vs_on in
            wb.(!i) <- Ref_encoder.control eb ~c0:hs ~c1:vs;
            wg.(!i) <- Ref_encoder.control eg ~c0:false ~c1:false;
            wr.(!i) <- Ref_encoder.control er ~c0:false ~c1:false
          end;
          incr i
        done
      done
    done;
    (wb, wg, wr)
  in
  let bits_of_words ws =
    Array.concat (Array.to_list (Array.map (fun w -> Array.init 10 (fun j -> (w lsr j) land 1 = 1)) ws)) in
  let syms ws = Array.map decode ws in

  (* Alignment: random garbage prefix of 0..9 bits (random content). *)
  let wb, wg, wr = gen ~hpol:false ~vpol:false ~nframes:3 in
  let all_ok = ref true in
  let short ws = Array.sub ws 0 3000 in      (* ~3.75 lines: data and blanking *)
  List.iter (fun ws ->
    for off = 0 to 9 do
      let prefix = Array.init off (fun _ -> Random.bool ()) in
      let bits = Array.append prefix (bits_of_words ws) in
      (* a prefix of [off] bits means word boundaries lie at bit index [off] *)
      let expect = off in
      if find_alignment bits <> Some expect then begin
        all_ok := false;
        Printf.printf "    alignment mismatch: off=%d expect %d got %s\n" off expect
          (match find_alignment bits with Some o -> string_of_int o | None -> "None")
      end
      else begin
        let w' = words_of_bits bits ~offset:expect in
        (* drop-in check: recovered words equal the originals *)
        if Array.length w' <> Array.length ws || w' <> ws then all_ok := false
      end
    done) [ short wb; short wg; short wr ];
  (let off = Random.int 10 in
   let bits = Array.append (Array.init off (fun _ -> Random.bool ())) (bits_of_words wb) in
   if find_alignment bits <> Some off then all_ok := false);
  check "find_alignment recovers all 10 offsets on blue/green/red lanes (and words_of_bits round-trips)" !all_ok;
  (* Negative: pure data (no control run) must give None *)
  let rnd_bits = bits_of_words (let e = Ref_encoder.create () in Array.init 5000 (fun _ -> Ref_encoder.data e (Random.int 256))) in
  check "find_alignment = None on a data-only stream" (find_alignment rnd_bits = None);

  (* Frames and timing, both polarities *)
  List.iter (fun (hpol, vpol) ->
    let wb, wg, wr = gen ~hpol ~vpol ~nframes:3 in
    let blue = syms wb and green = syms wg and red = syms wr in
    let frames = frames_of_lanes ~blue ~green ~red in
    let name = Printf.sprintf "hsync %s / vsync %s" (if hpol then "high" else "low") (if vpol then "high" else "low") in
    check (name ^ ": two complete frames recovered") (List.length frames = 2);
    check (name ^ ": frame images exact (frames 1 and 2 of the generator)")
      (List.length frames = 2 &&
       List.for_all2 (fun fr f ->
         fr.width = h_active && fr.height = v_active &&
         (let ok = ref true in
          for y = 0 to v_active - 1 do for x = 0 to h_active - 1 do
            if fr.rgb.(y * h_active + x) <> pixel f x y then ok := false
          done done; !ok)) frames [ 1; 2 ]);
    let t = measure_timing ~blue ~green ~red in
    Printf.printf "  info: measured %s: H %d/%d/%d/%d (tot %d) V %d/%d/%d/%d (tot %d) hs_high=%b vs_high=%b\n"
      name t.h_active t.h_front t.h_sync t.h_back t.h_total t.v_active t.v_front t.v_sync t.v_back t.v_total
      t.hsync_active_high t.vsync_active_high;
    check (name ^ ": measure_timing = VESA 640x480@60 (H 16/96/48, V 10/2/33) and polarity")
      (t.h_active = 640 && t.h_front = 16 && t.h_sync = 96 && t.h_back = 48 && t.h_total = 800
       && t.v_active = 480 && t.v_front = 10 && t.v_sync = 2 && t.v_back = 33 && t.v_total = 525
       && t.hsync_active_high = hpol && t.vsync_active_high = vpol)) [ (false, false); (true, true); (false, true) ];

  (* Loud failures *)
  let wb, wg, wr = gen ~hpol:false ~vpol:false ~nframes:3 in
  let blue = syms wb and green = syms wg and red = syms wr in
  let fails f = match f () with exception Failure _ -> true | _ -> false in
  let green' = Array.copy green in
  green'.(100) <- Control { c0 = false; c1 = false };
  check "frames_of_lanes fails loudly when lanes disagree on data enable"
    (fails (fun () -> frames_of_lanes ~blue ~green:green' ~red));
  let blue' = Array.copy blue in
  blue'.(700) <- Invalid 0x155;
  check "frames_of_lanes fails loudly on an Invalid symbol"
    (fails (fun () -> frames_of_lanes ~blue:blue' ~green ~red));

  (* ---- Mutants ------------------------------------------------------------ *)
  print_endline "== Planted-bug controls ==";
  Printf.printf "  reference disparity bound used by the stream check: |running disparity| <= %d\n" bound;
  let checks_of m =
    let mk () = of_mut m in
    let rt = c_roundtrip mk in
    let vw = c_valid_words mk in
    let ct = c_control mk in
    let tr = c_cnt_tracks mk in
    let lo, hi = running_disparity_extent mk 200_000 in
    let bd = lo >= rmin && hi <= rmax in
    (* exact differential against the reference on identical input *)
    let r = Ref_encoder.create () and e = Enc.create m in
    let same = ref true in
    for _ = 1 to 20000 do
      if Random.int 20 = 0 then begin
        let c0 = Random.bool () and c1 = Random.bool () in
        if Ref_encoder.control r ~c0 ~c1 <> Enc.control e ~c0 ~c1 then same := false
      end else begin
        let d = Random.int 256 in
        if Ref_encoder.data r d <> Enc.data e d then same := false
      end
    done;
    (rt, vw, ct, tr, bd, !same)
  in
  Printf.printf "  %-36s %-9s %-9s %-9s %-9s %-9s %s\n" "mutant" "roundtrip" "validword" "control" "cnt=sum" "disp-bnd" "differs-from-ref";
  let flag ok = if ok then "pass" else "CAUGHT" in
  List.iter (fun m ->
    let rt, vw, ct, tr, bd, same = checks_of m in
    Printf.printf "  %-36s %-9s %-9s %-9s %-9s %-9s %s\n" (mutation_name m)
      (flag rt) (flag vw) (flag ct) (flag tr) (flag bd) (if same then "no" else "yes");
    let caught = not (rt && vw && ct && tr && bd) in
    if m = M_none then check "control mutant (faithful copy) passes every check and equals reference" (not caught && same)
    else begin
      check (Printf.sprintf "mutant '%s' caught by at least one spec-derived check" (mutation_name m)) caught;
      if rt then Printf.printf "    note: NOT caught by decode-roundtrip alone\n"
    end) all_mutations;

  if !failures > 0 then begin
    Printf.printf "\n%d FAILURE(S)\n" !failures;
    exit 1
  end else print_endline "\nall checks passed"
