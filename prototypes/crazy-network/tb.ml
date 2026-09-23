(* Testbench for the network RTL: load a program, feed per-line seeds as the CPU would, and
   either compare every visible pixel sample with the model (lockstep) or dump the pins. *)
open Hardcaml

let circuit = lazy (Crazy_rtl.circuit ())

let config_bytes (p : Model.prog) =
  Array.concat [ [| p.p; p.tap; (if p.reset then 1 else 0) |]; p.pal;
                 Array.concat (List.init Model.n (fun i -> [| p.ops.(i); p.ks.(i) |])) ]

(* [on_cycle ~field ~line ~h sim] is called after every cycle; h and line are the counters
   during that cycle. *)
let run (prog : Model.prog) ~fields ~on_cycle =
  let sim = Cyclesim.create (Lazy.force circuit) in
  let i = Cyclesim.in_port sim and o = Cyclesim.out_port sim in
  let clear = i "clear" and cfg_in = i "cfg_in" and cfg_st = i "cfg_strobe" and seed_in = i "seed_in" and seed_st = i "seed_strobe" in
  let hc = o "hcount" and vc = o "vcount" in
  (* load config and the first line's seeds while held in clear, so the state starts at zero *)
  clear := Bits.vdd;
  Array.iter (fun b -> cfg_in := Bits.of_int ~width:8 b; cfg_st := Bits.vdd; Cyclesim.cycle sim) (config_bytes prog);
  cfg_st := Bits.gnd;
  Array.iter (fun b -> seed_in := Bits.of_int ~width:8 b; seed_st := Bits.vdd; Cyclesim.cycle sim) (Model.seeds prog ~line:0 ~frame:0);
  seed_st := Bits.gnd;
  Cyclesim.cycle sim;
  clear := Bits.gnd;
  let field = ref 0 in
  let pending = ref [||] in
  while !field < fields do
    let h = Bits.to_int !hc and v = Bits.to_int !vc in
    if h = 1000 then begin
      let nl = (v + 1) mod Model.lpf in
      let nf = if nl = 0 then !field + 1 else !field in
      pending := Model.seeds prog ~line:nl ~frame:nf
    end;
    let kk = h - 1001 in
    if kk >= 0 && kk < 4 then (seed_in := Bits.of_int ~width:8 !pending.(kk); seed_st := Bits.vdd) else seed_st := Bits.gnd;
    Cyclesim.cycle sim;
    on_cycle ~field:!field ~line:v ~h sim;
    if h = Model.cpl - 1 && v = Model.lpf - 1 then incr field
  done

let lockstep prog ~fields =
  let expected = Model.render prog ~frames:fields ~keep:(fun _ -> true) in
  let bad = ref 0 and checked = ref 0 in
  run prog ~fields ~on_cycle:(fun ~field ~line ~h sim ->
    let y = line - Model.first_vis and dx = h - Model.vis_start in
    if y >= 0 && y < Model.nvis && dx >= 0 && dx < Model.npix * Model.pixc && dx mod Model.pixc = 5 then begin
      let img = List.assoc field expected in
      let want = prog.pal.(img.(y).(dx / Model.pixc)) in
      let got = Bits.to_int !(Cyclesim.out_port sim "colour") in
      incr checked; if got <> want then incr bad
    end);
  !checked, !bad

let dump prog ~fields ~name =
  let bufs = Array.init fields (fun _ -> Buffer.create (Model.cpl * Model.lpf)) in
  run prog ~fields ~on_cycle:(fun ~field ~line:_ ~h:_ sim ->
    let g n = Bits.to_int !(Cyclesim.out_port sim n) in
    if field < fields then
      Buffer.add_char bufs.(field) (Char.chr (g "luma" lor (g "chroma" lsl 4) lor (g "chroma_oe" lsl 5) lor (g "chroma2_oe" lsl 6))));
  Array.iteri (fun i b -> let oc = open_out_bin (Printf.sprintf "out/%s_%03d.bin" name i) in Buffer.output_buffer oc b; close_out oc) bufs
