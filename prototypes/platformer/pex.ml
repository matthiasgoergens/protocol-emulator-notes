(* PE-X RTL: pe16 (../pe-synth/pe_rtl.ml) plus the generic extensions specified in pex_model.ml.
   [fault] plants a bug for the lockstep controls: 1 ignores dir (no horizontal flip), 2 ignores
   the flag block, 3 releases on the window's first step instead of after it. *)
open Hardcaml
open Signal

let chain spec ~enable ~din len =
  let regs = Array.make len (zero 8) in
  let prev = ref din in
  for j = 0 to len - 1 do
    let r = reg spec ~enable !prev in
    regs.(j) <- r;
    prev := r
  done;
  (fun k -> regs.(len - 1 - k)), !prev

let sat16 v =
  let over = msb v ^: bit v 15 in
  mux2 over (mux2 (msb v) (of_int ~width:16 (-32768)) (of_int ~width:16 32767)) (select v 15 0)

(* pe16's ALU *)
let alu op x y =
  let is_add = op ==:. 0 in
  let y1 = sresize y 17 in
  let t = sresize x 17 +: mux2 is_add y1 ~:y1 +: uresize ~:is_add 17 in
  let lt = msb t in
  mux op [ sat16 t; sat16 t; mux2 lt y x; mux2 lt x y ]

type out = { tag : Signal.t; data : Signal.t; s : Signal.t; cfg_out : Signal.t }

let create ?(fault = 0) ?(lean = false) ~clock ~clear ~cfg_in ~cfg_strobe ~tag ~data () =
  let spec = Reg_spec.create ~clock ~clear () in
  let cfg, cfg_out = chain (Reg_spec.create ~clock ()) ~enable:cfg_strobe ~din:cfg_in 5 in
  let c0 = cfg 0 and k = concat_msb [ cfg 1; cfg 2 ] and c3 = cfg 3 and c4 = cfg 4 in
  let op = select c0 1 0 and ysel_k = bit c0 2 and xsel_s = bit c0 3 and s_en = bit c0 4 in
  let load_en = bit c0 5 and cls = bit c0 6 and rot = bit c0 7 in
  let lb = select c3 1 0 and w = select c3 5 2 and rel_win = bit c3 6 and rel_eol = bit c3 7 in
  (* lean: only what the video configurations use (2 bits per step, window above bit 4, no
     rotate); those configuration bits are then ignored *)
  let lb = if lean then of_int ~width:2 1 else lb and w = if lean then of_int ~width:4 4 else w in
  let rot = if lean then gnd else rot in
  let n = select c4 3 0 and write_en = bit c4 4 in
  let open Always in
  let s = Variable.reg spec ~width:16 and a = Variable.reg spec ~width:32 in
  let attr = Variable.reg spec ~width:16 and attr2 = Variable.reg spec ~width:9 in
  let loaded = Variable.reg spec ~width:1 and widx = Variable.reg spec ~width:3 in
  let pprev = Variable.reg spec ~width:1 in
  let otag = Variable.reg spec ~width:3 and odata = Variable.reg spec ~width:16 in
  let kind = select tag 1 0 in
  let is_step = kind ==:. 1 in
  let is_rec = bit kind 1 &: (bit tag 2 ==: cls) in
  let consume = is_rec &: load_en &: ~:(loaded.value) in
  (* window predicate *)
  let mask = mux n (List.init 16 (fun i -> of_int ~width:16 ((1 lsl i) - 1))) in
  let p = ((if lean then srl s.value 4 else log_shift srl s.value w) &: mask) ==:. 0 in
  (* field and shift, b = 1 lsl lb *)
  let dir = if fault = 1 then gnd else bit attr2.value 8 in
  let av = a.value in
  let bm = mux lb (List.map (of_int ~width:8) [ 1; 3; 15; 255 ]) in
  let field = mux2 dir (select av 7 0 &: bm)
      (mux lb [ uresize (select av 31 31) 8; uresize (select av 31 30) 8;
                uresize (select av 31 28) 8; select av 31 24 ]) in
  let bits_list = [ 1; 2; 4; 8 ] in
  let shifted_left = mux lb (List.map (fun b -> mux2 rot (rotl av b) (sll av b)) bits_list) in
  let shifted_right = mux lb (List.map (fun b -> mux2 rot (rotr av b) (srl av b)) bits_list) in
  let flags = select data 15 8 in
  let blocked = if fault = 2 then gnd else (flags &: select attr2.value 7 0) <>:. 0 in
  let write = is_step &: write_en &: loaded.value &: p &: (field <>:. 0) &: ~:blocked in
  let written = concat_msb [ flags |: select attr.value 15 8; select attr.value 7 0 |: field ] in
  let eol = bit data 15 in
  let release =
    if fault = 3 then loaded.value &: ((rel_eol &: eol) |: (rel_win &: ~:(pprev.value) &: p))
    else loaded.value &: ((rel_eol &: eol) |: (rel_win &: pprev.value &: ~:p)) in
  let x = mux2 xsel_s s.value data and y = mux2 ysel_k k s.value in
  compile
    [ odata <-- mux2 write written data
    ; otag <-- mux2 consume (zero 3) tag
    ; when_ is_step
        [ when_ s_en [ s <-- alu op x y ]
        ; when_ (loaded.value &: p) [ a <-- mux2 dir shifted_right shifted_left ]
        ; when_ release [ loaded <-- gnd ]
        ; pprev <-- mux2 eol gnd p ]
    ; when_ consume
        [ switch widx.value
            [ of_int ~width:3 0, [ attr <-- data ]
            ; of_int ~width:3 1, [ a <-- concat_msb [ data; select av 15 0 ] ]
            ; of_int ~width:3 2, [ a <-- concat_msb [ select av 31 16; data ] ]
            ; of_int ~width:3 3, [ s <-- data ]
            ; of_int ~width:3 4, [ attr2 <-- select data 8 0 ] ]
        ; if_ (kind ==:. 3) [ loaded <-- vdd; widx <--. 0 ]
            [ when_ (widx.value <>:. 7) [ widx <-- widx.value +:. 1 ] ] ] ];
  { tag = otag.value; data = odata.value; s = s.value; cfg_out }

(* a row of n PE-Xs, the link and the configuration chain running through them *)
let row ?(fault = 0) ?(lean = false) n () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let cfg_in = input "cfg_in" 8 and cfg_strobe = input "cfg_strobe" 1 in
  let tag = ref (input "tag_in" 3) and data = ref (input "data_in" 16) and cfg = ref cfg_in in
  let outs = List.concat (List.init n (fun i ->
    let o = create ~fault ~lean ~clock ~clear ~cfg_in:!cfg ~cfg_strobe ~tag:!tag ~data:!data () in
    tag := o.tag; data := o.data; cfg := o.cfg_out;
    [ output (Printf.sprintf "s%d" i) o.s ])) in
  Circuit.create_exn ~name:(Printf.sprintf "pex_row%d" n)
    (outs @ [ output "tag_out" !tag; output "data_out" !data; output "cfg_out" !cfg ])
