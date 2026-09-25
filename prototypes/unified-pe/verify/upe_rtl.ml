(* Hardcaml implementation of upe_v1 and the segmented array (spec.ml).
   [bug] plants one fault by name, for the lockstep controls; "" is the correct design. *)
open Hardcaml
open Signal

let bug = ref ""
let is b = !bug = b

let bugs =
  [ "sat_off_by_one", "saturating add clamps to 0x7ffe";
    "sat_as_wrap", "saturating add wraps when the carry-in is the lane";
    "carry_bit15", "carry out taken from bit 15";
    "cin_ignored", "lane carry-in dropped";
    "max_unsigned", "max compares unsigned";
    "min_is_max", "min returns the larger";
    "max_loser_x", "max always reports X as the loser";
    "and_not", "AND computes X AND NOT Y";
    "or_is_xor", "OR computes XOR";
    "gate_inverted", "gating passes Y when g = 0";
    "neg_no_plus1", "negation without the +1";
    "gneg_always", "negate-by-g negates regardless of g";
    "bit_off_by_one", "bit test reads A[i+1]";
    "s15_xor_uses_s14", "S[15] ^ lane uses S[14]";
    "crc_pairlo_ignored", "CRC feedback ignores pairlo";
    "g_from_F_inverted", "g = F reads NOT F";
    "window_17", "window accepts d = 16";
    "window_bit_order", "window tests S[d] instead of S[15 - d]";
    "merge_colour_hi", "merge takes K[15:8] as colour";
    "g_in_zero", "g_in tied to 0 across the segment 2/3 cut";
    "shr_sin_bit14", "right shift inserts sin at bit 14";
    "sin_s15_uses_own", "sin = s15_in uses own S[15]";
    "swb_cond_inverted", "conditional writeback writes when g = 0";
    "pwb_loser_is_winner", "P <- loser gives the winner";
    "zero_on_x", "zero flag tests X";
    "lout_s15_old", "lane out S[15] registers the old S";
    "lane_bc_wrong_seg", "PEs of segment 3 take segment 2's broadcast bit";
    "stream_ignored", "stream mode steps every clock";
    "del_ignored", "deletion never drops";
    "follow_ignored", "follow steps every clock";
    "loop_from_prev", "segment 2's loop-back takes segment 1's end";
    "join_lane_zero", "join does not pass the lane";
    "feed_valid_sticky", "feed valid lasts two clocks";
    "fixed_swapped", "segment 3 takes segment 2's fixed port";
    "cfg_chain_order", "configuration bytes 2 and 3 swapped in the chain";
    "init_no_shift", "init chain overwrites S instead of shifting";
    "tap_always_s", "tap ignores tap_p";
    "pv_hold_on_stop", "valid clears when the segment stops";
    "yone_is_two", "Y = 1 gives 2";
    "xsel_a_is_s", "X = A gives S when the op is XOR" ]

(* per-PE ports *)
type pe_in = {
  run : t;
  a : t;
  av : t;
  alane : t;
  bcast : t;
  s15_in : t;
  cb_in : t;
  g_in : t;
  lstep_in : t;
  init_wr : t;
  init_in : t; (* 8 *)
  cfg_wr : t;
  cfg_in : t; (* 8 *)
}

type pe_out = {
  s : t;
  p : t;
  pv : t;
  f : t;
  l : t;
  g : t;
  step : t;
  cfg : t; (* 64 *)
  cfg_out : t;
  init_out : t;
  tap : t;
}

let pe ?(pe_index = 0) spec (i : pe_in) =
  (* configuration chain: b.(0) takes the input byte *)
  let b = Array.make 8 (zero 8) in
  let prev = ref i.cfg_in in
  for j = 0 to 7 do
    let r = reg spec ~enable:i.cfg_wr !prev in
    b.(j) <- r;
    prev := r
  done;
  let b = if is "cfg_chain_order" then (let c = Array.copy b in c.(2) <- b.(3); c.(3) <- b.(2); c) else b in
  let cfg = concat_msb (List.rev (Array.to_list b)) in
  let k = select cfg 15 0 in
  let ob n = bit cfg (16 + n) in
  let of_ lo n = select cfg (16 + lo + n - 1) (16 + lo) in
  let xsel = of_ 0 2 and sinsel = of_ 2 2 and ysel = of_ 4 2 and ymod = of_ 6 2 in
  let gsel = of_ 8 3 and bitsel = of_ 11 4 and pairlo = ob 15 and alu = of_ 16 3 in
  let cin_lane = ob 19 and swb = of_ 20 2 and pwb = of_ 22 2 and fwb = of_ 24 2 in
  let lout = of_ 26 2 and lane_bc = ob 28 and del = ob 29 and stream = ob 30 and tap_p = ob 31 in
  let follow = ob 32 in
  let s = wire 16 and p = wire 16 and pv = wire 1 and f = wire 1 and l = wire 1 in
  let lane_in = mux2 lane_bc i.bcast i.alane in
  let s15 = msb s in
  (* window: A.hi - K.hi in 8 bits, then the bitmap read MSB first *)
  let d = select i.a 15 8 -: select k 15 8 in
  let in_win = if is "window_17" then d <=:. 16 else select d 7 4 ==:. 0 in
  let bitmap = if is "window_bit_order" then s else reverse s in
  let window = in_win &: mux (select d 3 0) (bits_lsb bitmap) in
  let crc_fb = mux2 (if is "crc_pairlo_ignored" then gnd else pairlo) i.cb_in s15 ^: lsb i.a in
  let bit_a = if is "bit_off_by_one" then mux bitsel (List.tl (bits_lsb i.a) @ [ gnd ]) else mux bitsel (bits_lsb i.a) in
  let s15_x = (if is "s15_xor_uses_s14" then bit s 14 else s15) ^: lane_in in
  let result = wire 16 in
  let f_src = if is "g_from_F_inverted" then ~:f else f in
  let g_in = if is "g_in_zero" && pe_index = 8 then gnd else i.g_in in
  let g = mux gsel [ vdd; bit_a; lane_in; s15_x; crc_fb; f_src; window; g_in ] in
  let sin = mux sinsel [ g; lane_in; (if is "sin_s15_uses_own" then s15 else i.s15_in); lsb i.a ] in
  let shl = concat_msb [ select s 14 0; sin ] in
  let shr = if is "shr_sin_bit14" then concat_msb [ gnd; sin; select s 14 1 ] else concat_msb [ sin; select s 15 1 ] in
  let x_a = if is "xsel_a_is_s" then mux2 (alu ==:. 4) s i.a else i.a in
  let x = mux xsel [ s; x_a; shl; shr ] in
  let yraw = mux ysel [ k; i.a; s; of_int ~width:16 (if is "yone_is_two" then 2 else 1) ] in
  let gate_off = (ymod ==:. 1) &: (if is "gate_inverted" then g else ~:g) in
  let yv = mux2 gate_off (zero 16) yraw in
  let n = (ymod ==:. 3) |: ((ymod ==:. 2) &: (if is "gneg_always" then vdd else g)) in
  let yn = yv ^: repeat n 16 in
  let c = mux2 (if is "cin_ignored" then gnd else cin_lane) lane_in (if is "neg_no_plus1" then gnd else n) in
  let sum = uresize x 17 +: uresize yn 17 +: uresize c 17 in
  let wsum = select sum 15 0 in
  let cout = if is "carry_bit15" then bit sum 15 else msb sum in
  let ovf = (msb x ==: msb yn) &: (msb wsum ^: msb x) in
  let ovf = if is "sat_as_wrap" then ovf &: ~:cin_lane else ovf in
  let smax = of_int ~width:16 (if is "sat_off_by_one" then 0x7ffe else 0x7fff) in
  let sat = mux2 ovf (mux2 (msb x) (of_int ~width:16 0x8000) smax) wsum in
  let x_ge = if is "max_unsigned" then x >=: yn else x >=+ yn in
  let x_le = x <=+ yn in
  let x_le = if is "min_is_max" then x_ge else x_le in
  let mx = mux2 x_ge x yn and mx_l = if is "max_loser_x" then x else mux2 x_ge yn x in
  let mn = mux2 x_le x yn and mn_l = mux2 x_le yn x in
  let land_ = if is "and_not" then x &: ~:yn else x &: yn in
  let lor_ = if is "or_is_xor" then x ^: yn else x |: yn in
  result <== mux alu [ sat; wsum; mx; mn; x ^: yn; land_; lor_; yn ];
  let loser = mux alu [ x; x; mx_l; mn_l; x; x; x; x ] in
  let loser = if is "pwb_loser_is_winner" then result else loser in
  let zero_ = (if is "zero_on_x" then x else result) ==:. 0 in
  let step_self = mux2 (if is "stream_ignored" then gnd else stream) i.av vdd in
  let step = i.run &: mux2 (if is "follow_ignored" then gnd else follow) i.lstep_in step_self in
  let cond_w = if is "swb_cond_inverted" then ~:g else g in
  let s_next = mux swb [ s; result; x; mux2 cond_w result s ] in
  let merge = mux2 g (concat_msb [ select i.a 15 8; (if is "merge_colour_hi" then select k 15 8 else select k 7 0) ]) i.a in
  let p_next = mux pwb [ i.a; result; loser; merge ] in
  let f_next = mux fwb [ f; g; zero_; f ] in
  let l_next = mux lout [ lane_in; (if is "lout_s15_old" then s15 else msb s_next); cout; g ] in
  let drop = (if is "del_ignored" then gnd else del) &: g in
  let pv_hold = if is "pv_hold_on_stop" then gnd else pv in
  pv <== reg spec (mux2 i.run (i.av &: ~:drop) pv_hold);
  let s_init =
    if is "init_no_shift" then concat_msb [ zero 8; i.init_in ] else concat_msb [ select s 7 0; i.init_in ]
  in
  s <== reg spec (mux2 i.init_wr s_init (mux2 step s_next s));
  p <== reg spec ~enable:step p_next;
  f <== reg spec ~enable:step f_next;
  l <== reg spec ~enable:step l_next;
  let tap = if is "tap_always_s" then s else mux2 tap_p p s in
  { s; p; pv; f; l; g; step; cfg; cfg_out = b.(7); init_out = select s 15 8; tap }

(* The single PE as a circuit, for synthesis against the area probe. *)
let pe_circuit () =
  let clock = input "clock" 1 in
  let spec = Reg_spec.create ~clock () in
  let inp n w = input n w in
  let i =
    { run = inp "run" 1; a = inp "a" 16; av = inp "av" 1; alane = inp "alane" 1; bcast = inp "bcast" 1;
      s15_in = inp "s15_in" 1; cb_in = inp "cb_in" 1; g_in = inp "g_in" 1; lstep_in = inp "lstep_in" 1;
      init_wr = inp "init_wr" 1; init_in = inp "init_in" 8; cfg_wr = inp "cfg_wr" 1; cfg_in = inp "cfg_in" 8 }
  in
  let o = pe spec i in
  Circuit.create_exn ~name:"upe_v1"
    [ output "p" o.p; output "pv" o.pv; output "l" o.l; output "g" o.g; output "step" o.step;
      output "s15" (msb o.s); output "cfg_out" o.cfg_out; output "init_out" o.init_out;
      output "tap" o.tap; output "f" o.f ]

(* The array: 16 PEs, segments 2|2|4|8, feed and control registers, taps. *)
let array_circuit ?(state_ports = true) () =
  let open Spec in
  let clock = input "clock" 1 in
  let spec = Reg_spec.create ~clock () in
  let mbx_wr = input "mbx_wr" 1 and mbx_seg = input "mbx_seg" 2 and mbx_sel = input "mbx_sel" 2 in
  let mbx_byte = input "mbx_byte" 8 in
  let cfg_wr = input "cfg_wr" 1 and cfg_seg = input "cfg_seg" 2 and cfg_byte = input "cfg_byte" 8 in
  let init_wr = input "init_wr" 1 and init_seg = input "init_seg" 2 and init_byte = input "init_byte" 8 in
  let fixed_d = Array.init 4 (fun j -> input (Printf.sprintf "fixed_d%d" j) 16) in
  let fixed_v = Array.init 4 (fun j -> input (Printf.sprintf "fixed_v%d" j) 1) in
  let segregs =
    Array.init 4 (fun j ->
        let mine = mbx_wr &: (mbx_seg ==:. j) in
        let flo = reg spec ~enable:(mine &: (mbx_sel ==:. 0)) mbx_byte in
        let fhi = reg spec ~enable:(mine &: (mbx_sel ==:. 1)) mbx_byte in
        let fv0 = reg spec (mine &: (mbx_sel ==:. 1)) in
        let fv = if is "feed_valid_sticky" then fv0 |: reg spec fv0 else fv0 in
        let ctrl = reg spec ~enable:(mine &: (mbx_sel ==:. 2)) (select mbx_byte 4 0) in
        (flo, fhi, fv, fv0, ctrl))
  in
  let ctrl j = let _, _, _, _, c = segregs.(j) in c in
  let wires () : pe_out =
    { s = wire 16; p = wire 16; pv = wire 1; f = wire 1; l = wire 1; g = wire 1; step = wire 1;
      cfg = wire 64; cfg_out = wire 8; init_out = wire 8; tap = wire 16 }
  in
  let w = Array.init n_pe (fun _ -> wires ()) in
  for i = 0 to n_pe - 1 do
    let sg = seg_of i in
    let first = i = seg_start.(sg) in
    let c = ctrl sg in
    let src = select c 2 0 in
    let a, av, alane =
      if first then begin
        let e_prev = if sg = 0 then None else Some w.(seg_end.(sg - 1)) in
        let e_own = if is "loop_from_prev" && sg = 2 then w.(seg_end.(1)) else w.(seg_end.(sg)) in
        let flo, fhi, fv, _, _ = segregs.(sg) in
        let fx = if is "fixed_swapped" && sg = 3 then 2 else sg in
        let jd, jv, jl =
          match e_prev with
          | None -> (zero 16, gnd, gnd)
          | Some (e : pe_out) -> (e.p, e.pv, if is "join_lane_zero" then gnd else e.l)
        in
        let pick f0 f1 f2 f3 z = mux src [ f0; f1; f2; f3; z; z; z; z ] in
        ( pick jd e_own.p (concat_msb [ fhi; flo ]) fixed_d.(fx) (zero 16),
          pick jv e_own.pv fv fixed_v.(fx) gnd,
          pick jl e_own.l (bit c 3) gnd gnd )
      end
      else (w.(i - 1).p, w.(i - 1).pv, w.(i - 1).l)
    in
    let bseg = if is "lane_bc_wrong_seg" && sg = 3 then 2 else sg in
    let o =
      pe ~pe_index:i spec
        { run = bit c 4; a; av; alane; bcast = bit (ctrl bseg) 3;
          s15_in = (if i > 0 then msb w.(i - 1).s else gnd);
          cb_in = (if i < n_pe - 1 then msb w.(i + 1).s else gnd);
          g_in = (if i > 0 then w.(i - 1).g else gnd);
          lstep_in = (if i > 0 then w.(i - 1).step else gnd);
          init_wr = init_wr &: (init_seg ==:. sg);
          init_in = (if first then init_byte else w.(i - 1).init_out);
          cfg_wr = cfg_wr &: (cfg_seg ==:. sg);
          cfg_in = (if first then cfg_byte else w.(i - 1).cfg_out) }
    in
    let (t : pe_out) = w.(i) in
    t.s <== o.s; t.p <== o.p; t.pv <== o.pv; t.f <== o.f; t.l <== o.l; t.g <== o.g;
    t.step <== o.step; t.cfg <== o.cfg; t.cfg_out <== o.cfg_out; t.init_out <== o.init_out;
    t.tap <== o.tap
  done;
  let outs = ref [] in
  let add n x = outs := output n x :: !outs in
  Array.iteri
    (fun j e ->
      add (Printf.sprintf "tap_d%d" j) w.(e).tap;
      add (Printf.sprintf "tap_v%d" j) w.(e).pv;
      add (Printf.sprintf "tap_f%d" j) w.(e).f)
    seg_end;
  if state_ports then begin
    Array.iteri
      (fun i (t : pe_out) ->
        add (Printf.sprintf "s%d" i) t.s; add (Printf.sprintf "p%d" i) t.p;
        add (Printf.sprintf "pv%d" i) t.pv; add (Printf.sprintf "f%d" i) t.f;
        add (Printf.sprintf "l%d" i) t.l; add (Printf.sprintf "cfg%d" i) t.cfg)
      w;
    Array.iteri
      (fun j (flo, fhi, _fv, fv0, ctrl) ->
        add (Printf.sprintf "flo%d" j) flo; add (Printf.sprintf "fhi%d" j) fhi;
        (* the architectural feed valid is the register; the sticky bug shows through the PE *)
        add (Printf.sprintf "fv%d" j) fv0; add (Printf.sprintf "ctrl%d" j) ctrl)
      segregs
  end;
  Circuit.create_exn ~name:"upe_array" (List.rev !outs)
