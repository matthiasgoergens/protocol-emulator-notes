(* Executable specification of upe_v1 and its segmented array (spec.ml), in plain integer
   arithmetic. It shares no code with rtl.ml beyond the encoding. *)
open Spec

type pe = {
  mutable s : int;
  mutable p : int;
  mutable pv : bool;
  mutable f : bool;
  mutable l : bool;
  cfg : int array;
}

type seg = { mutable flo : int; mutable fhi : int; mutable fv : bool; mutable ctrl : int }
type t = { pe : pe array; seg : seg array; cov : (string, int) Hashtbl.t }

let create () =
  { pe = Array.init n_pe (fun _ -> { s = 0; p = 0; pv = false; f = false; l = false; cfg = Array.make 8 0 });
    seg = Array.init 4 (fun _ -> { flo = 0; fhi = 0; fv = false; ctrl = 0 });
    cov = Hashtbl.create 64 }

(* shared-specification faults: set together with the same-named Upe_rtl.bug, lockstep cannot
   see them, and only the cells' independent references can *)
let bug = ref ""
let is b = !bug = b

let hit t name = Hashtbl.replace t.cov name (1 + Option.value ~default:0 (Hashtbl.find_opt t.cov name))
let bit v i = (v lsr i) land 1 = 1
let signed v = if v >= 0x8000 then v - 0x10000 else v
let u16 v = v land 0xffff

(* the combinational part of one PE, from its inputs and current state *)
type comb = {
  g : bool;
  step : bool;
  s' : int;
  p' : int;
  pv' : bool;
  f' : bool;
  l' : bool;
}

let pe_comb t (e : pe) ~run ~a ~av ~alane ~bcast ~s15_in ~cb_in ~g_in ~lstep_in =
  let o = op_of_bytes e.cfg in
  let lane_in = if o.lane_bc then bcast else alane in
  let window =
    let d = ((a lsr 8) - (o.k lsr 8)) land 0xff in
    d < 16 && bit e.s (if is "window_bit_order" then d else 15 - d)
  in
  let g =
    match o.gsel with
    | 0 -> true
    | 1 -> bit a o.bitsel
    | 2 -> lane_in
    | 3 -> bit e.s 15 <> lane_in
    | 4 -> (if o.pairlo then cb_in else bit e.s 15) <> bit a 0
    | 5 -> e.f
    | 6 -> window
    | _ -> g_in
  in
  let sin = match o.sinsel with 0 -> g | 1 -> lane_in | 2 -> (if is "sin_s15_uses_own" then bit e.s 15 else s15_in) | _ -> bit a 0 in
  let sinv = if sin then 1 else 0 in
  let x =
    match o.xsel with
    | 0 -> e.s
    | 1 -> a
    | 2 -> u16 ((e.s lsl 1) lor sinv)
    | _ -> (e.s lsr 1) lor (sinv lsl 15)
  in
  let yraw = match o.ysel with 0 -> o.k | 1 -> a | 2 -> e.s | _ -> 1 in
  let yv = if o.ymod = 1 && not g then 0 else yraw in
  let n = o.ymod = 3 || (o.ymod = 2 && g) in
  let yn = if n then u16 (lnot yv) else yv in
  let c = if o.cin_lane then (if lane_in then 1 else 0) else if n && not (is "neg_no_plus1") then 1 else 0 in
  let usum = x + yn + c in
  let cout = if is "carry_bit15" then usum land 0x8000 <> 0 else usum > 0xffff in
  let ssum = signed x + signed yn + c in
  let result, loser =
    match o.alu with
    | 0 -> (u16 (max (-0x8000) (min 0x7fff ssum)), x)
    | 1 -> (u16 usum, x)
    | 2 -> if (if is "max_unsigned" then x >= yn else signed x >= signed yn) then (x, yn) else (yn, x)
    | 3 -> if signed x <= signed yn then (x, yn) else (yn, x)
    | 4 -> (x lxor yn, x)
    | 5 -> (x land yn, x)
    | 6 -> (x lor yn, x)
    | _ -> (yn, x)
  in
  let step = run && (if o.follow then lstep_in else if o.stream then av else true) in
  let s' = match o.swb with 0 -> e.s | 1 -> result | 2 -> x | _ -> if g then result else e.s in
  let p' =
    match o.pwb with
    | 0 -> a
    | 1 -> result
    | 2 -> loser
    | _ -> if g then (a land 0xff00) lor (if is "merge_colour_hi" then o.k lsr 8 else o.k land 0xff) else a
  in
  let f' = match o.fwb with 1 -> g | 2 -> result = 0 | _ -> e.f in
  let l' = match o.lout with 0 -> lane_in | 1 -> bit s' 15 | 2 -> cout | _ -> g in
  let pv' = if run then av && not (o.del && g) else e.pv in
  if step then begin
    (* coverage of the events that plain random stimulus may never produce *)
    if o.alu = 0 && ssum <> signed result then hit t "saturated";
    if o.alu = 1 && cout then hit t "wrap_carry";
    if o.cin_lane && lane_in && o.alu <= 1 then hit t "carry_in";
    if (o.alu = 2 || o.alu = 3) && loser = x && x <> yn then hit t "maxmin_swap";
    if o.alu >= 4 && o.alu <= 6 then hit t "logic";
    if o.ymod = 1 && not g && yraw <> 0 then hit t "gated_off";
    if o.ymod = 2 && g then hit t "negated_by_g";
    if o.gsel = 1 && g then hit t "bit_test";
    if o.gsel = 3 then hit t "s15_xor_lane";
    if o.gsel = 4 && o.pairlo then hit t "crc_pairlo";
    if o.gsel = 4 && not o.pairlo && g then hit t "crc_feedback";
    if o.gsel = 5 && g then hit t "g_from_F";
    if o.gsel = 6 && g then hit t "window_hit";
    if o.gsel = 6 && g && o.pwb = 3 then hit t "merge";
    if o.gsel = 7 && g then hit t "g_in";
    if o.xsel >= 2 && sin then hit t "shift_in_one";
    if o.fwb = 2 && result = 0 then hit t "zero_flag";
    if o.follow then hit t "follow_step";
    if o.lout = 2 && cout then hit t "lane_carry_out";
    if o.swb = 3 && not g then hit t "cond_hold"
  end;
  if run && o.del && av && g then hit t "deleted";
  { g; step; s'; p'; pv'; f'; l' }

let src_of ctrl = ctrl land 7
let bcast_of ctrl = bit ctrl 3
let run_of ctrl = bit ctrl 4

(* the effective broadcast bit: control bit 5 (proposed) takes the previous segment's *)
let rec bcast_eff t sg =
  let c = t.seg.(sg).ctrl in
  if sg > 0 && bit c 5 then bcast_eff t (sg - 1) else bcast_of c

let cycle t (inp : inputs) =
  let pe = t.pe in
  let g = Array.make n_pe false and step = Array.make n_pe false in
  let res = Array.make n_pe None in
  for i = 0 to n_pe - 1 do
    let sg = seg_of i in
    let ctrl = t.seg.(sg).ctrl in
    let a, av, alane =
      if i = seg_start.(sg) then begin
        let from_end e = (pe.(e).p, pe.(e).pv, pe.(e).l) in
        match src_of ctrl with
        | 0 -> if sg = 0 then (0, false, false) else (hit t "join"; from_end seg_end.(sg - 1))
        | 1 -> hit t "loop"; from_end seg_end.(sg)
        | 2 ->
          let s = t.seg.(sg) in
          if s.fv then hit t "feed_valid";
          ((s.fhi lsl 8) lor s.flo, s.fv, bcast_eff t sg)
        | 3 -> hit t "fixed"; (inp.fixed_d.(sg), inp.fixed_v.(sg), false)
        | _ -> (0, false, false)
      end
      else (pe.(i - 1).p, pe.(i - 1).pv, pe.(i - 1).l)
    in
    let c =
      pe_comb t pe.(i) ~run:(run_of ctrl) ~a ~av ~alane ~bcast:(bcast_eff t sg)
        ~s15_in:(i > 0 && bit pe.(i - 1).s 15)
        ~cb_in:(i < n_pe - 1 && bit pe.(i + 1).s 15)
        ~g_in:(i > 0 && g.(i - 1))
        ~lstep_in:(i > 0 && step.(i - 1))
    in
    g.(i) <- c.g;
    step.(i) <- c.step;
    res.(i) <- Some c
  done;
  (* chains read the old state, so compute them before committing *)
  let old_s = Array.map (fun e -> e.s) pe in
  let old_cfg7 = Array.map (fun e -> e.cfg.(7)) pe in
  for i = 0 to n_pe - 1 do
    let c = Option.get res.(i) in
    let e = pe.(i) in
    let sg = seg_of i in
    let first = i = seg_start.(sg) in
    if c.step then begin
      e.s <- c.s';
      e.p <- c.p';
      e.f <- c.f';
      e.l <- c.l'
    end;
    e.pv <- c.pv';
    if inp.init_wr && inp.init_seg = sg then begin
      let byte_in = if first then inp.init_byte else old_s.(i - 1) lsr 8 in
      e.s <- u16 ((old_s.(i) lsl 8) lor byte_in)
    end;
    if inp.cfg_wr && inp.cfg_seg = sg then begin
      for j = 7 downto 1 do e.cfg.(j) <- e.cfg.(j - 1) done;
      e.cfg.(0) <- (if first then inp.cfg_byte else old_cfg7.(i - 1))
    end
  done;
  Array.iteri
    (fun j s ->
      let mine = inp.mbx_wr && inp.mbx_seg = j in
      s.fv <- mine && inp.mbx_sel = 1;
      if mine then
        match inp.mbx_sel with
        | 0 -> s.flo <- inp.mbx_byte
        | 1 -> s.fhi <- inp.mbx_byte
        | 2 -> s.ctrl <- inp.mbx_byte land 0x3f
        | _ -> ())
    t.seg

let state t : state =
  { pes = Array.map (fun (e : pe) -> ({ s = e.s; p = e.p; pv = e.pv; f = e.f; l = e.l; cfg = Array.copy e.cfg } : pe_state)) t.pe;
    segs = Array.map (fun (s : seg) -> ({ flo = s.flo; fhi = s.fhi; fv = s.fv; ctrl = s.ctrl } : seg_state)) t.seg;
    taps =
      Array.map
        (fun e ->
          let x = t.pe.(e) in
          let o = op_of_bytes x.cfg in
          { td = (if o.tap_p then x.p else x.s); tv = x.pv; tf = x.f })
        seg_end }
