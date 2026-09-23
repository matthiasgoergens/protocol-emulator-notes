(* Testbench: stream the configuration during vertical blanking and each line's 48 init bytes
   during horizontal blanking, as the RP2040 would, and either compare every visible pixel
   sample with the model (lockstep) or dump the pins for the software TV. *)
open Hardcaml

let config_bytes (c : Model.cfg) =
  let b24 v = let v = v land 0xFFFFFF in [| v lsr 16; (v lsr 8) land 255; v land 255 |] in
  Array.concat
    (List.init Model.n (fun i -> Array.append [| c.op.(i) lor (c.xs.(i) lsl 2) lor (c.ys.(i) lsl 5) |] (b24 c.k.(i)))
     @ [ c.pal; c.taps; c.lut; [| c.ramp_tap; c.ramp_shift |]; b24 c.ramp_base; [| c.ramp_max |] ])

let init_bytes s =
  Array.concat (Array.to_list (Array.map (fun v -> let v = v land 0xFFFFFF in [| v lsr 16; (v lsr 8) land 255; v land 255 |]) s))

let init_h = 3240   (* horizontal blanking, after the visible window ends at 3222 *)
let cfg_line = 300  (* vertical blanking line for the next field's configuration *)

let run ?fault ~fields ~on_cycle () =
  let sim = Cyclesim.create (Ring_rtl.circuit ?fault ()) in
  let i = Cyclesim.in_port sim and o = Cyclesim.out_port sim in
  let clear = i "clear" and cfg_in = i "cfg_in" and cfg_st = i "cfg_strobe" in
  let init_in = i "init_in" and init_st = i "init_strobe" in
  let hc = o "hcount" and vc = o "vcount" in
  let cfgb = Array.init (fields + 1) (fun f -> config_bytes (Model.cfg_at f)) in
  clear := Bits.vdd;
  Array.iter (fun b -> cfg_in := Bits.of_int ~width:8 b; cfg_st := Bits.vdd; Cyclesim.cycle sim) cfgb.(0);
  cfg_st := Bits.gnd;
  Cyclesim.cycle sim;
  clear := Bits.gnd;
  let field = ref 0 and pending = ref [||] in
  while !field < fields do
    let h = Bits.to_int !hc and v = Bits.to_int !vc in
    (* next line's init values *)
    if h = init_h - 1 then begin
      let nl = v + 1 - Model.first_vis in
      pending := init_bytes (if nl >= 0 && nl < Model.nvis then Model.inits_at !field nl else Array.make Model.n 0)
    end;
    let kk = h - init_h in
    if kk >= 0 && kk < 48 then (init_in := Bits.of_int ~width:8 !pending.(kk); init_st := Bits.vdd) else init_st := Bits.gnd;
    let cc = h - 100 in
    if v = cfg_line && cc >= 0 && cc < Ring_rtl.cfg_len then (cfg_in := Bits.of_int ~width:8 cfgb.(!field + 1).(cc); cfg_st := Bits.vdd)
    else cfg_st := Bits.gnd;
    Cyclesim.cycle sim;
    on_cycle ~field:!field ~line:v ~h sim;
    if h = Model.cpl - 1 && v = Model.lpf - 1 then incr field
  done

(* compare every visible pixel sample; returns (mismatches, samples) *)
let lockstep ?fault fields =
  let bad = ref 0 and tot = ref 0 in
  let imgs = Array.init fields (fun f -> Model.render (Model.cfg_at f) ~inits:(Model.inits_at f)) in
  let pals = Array.init fields (fun f -> (Model.cfg_at f).pal) in
  run ?fault ~fields ~on_cycle:(fun ~field ~line ~h sim ->
    let y = line - Model.first_vis and px = h - Model.vis_start in
    if y >= 0 && y < Model.nvis && px >= 0 && px < Model.npix * Model.pixc && px mod Model.pixc = 5 then begin
      let x = px / Model.pixc in
      let got = Bits.to_int !(Cyclesim.out_port sim "colour") in
      incr tot;
      if got <> pals.(field).(imgs.(field).(y).(x)) then incr bad
    end) ();
  !bad, !tot

let dump ~fields ~prefix =
  let buf = Buffer.create (Model.cpl * Model.lpf) in
  run ~fields ~on_cycle:(fun ~field ~line ~h sim ->
    let g p = Bits.to_int !(Cyclesim.out_port sim p) in
    Buffer.add_char buf (Char.chr (g "luma" lor (g "chroma" lsl 4) lor (g "chroma_oe" lsl 5) lor (g "chroma2_oe" lsl 6)));
    if h = Model.cpl - 1 && line = Model.lpf - 1 then begin
      let oc = open_out_bin (Printf.sprintf "out/%s_%03d.bin" prefix field) in
      Buffer.output_buffer oc buf; close_out oc; Buffer.clear buf
    end) ()
