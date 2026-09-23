open Hardcaml

let circuit = lazy (Wave.circuit ())

let run ~fields ~(packet : field:int -> line:int -> int array) ~on_cycle =
  let sim = Cyclesim.create (Lazy.force circuit) in
  let i = Cyclesim.in_port sim and o = Cyclesim.out_port sim in
  let clear = i "clear" and din = i "din" and strobe = i "strobe" in
  let hc = o "hcount" and vc = o "vcount" in
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  let field = ref 0 and pending = ref [||] in
  while !field < fields do
    let h = Bits.to_int !hc and v = Bits.to_int !vc in
    let nl = (v + 1) mod Wave.lpf in
    if h = 1000 then pending := (if nl >= Wave.first_vis && nl < Wave.first_vis + Wave.nvis
                                 then packet ~field:(if nl = 0 then !field + 1 else !field) ~line:nl else [||]);
    let k = h - 1001 in
    if k >= 0 && k < Array.length !pending then (din := Bits.of_int ~width:8 !pending.(k); strobe := Bits.vdd) else strobe := Bits.gnd;
    Cyclesim.cycle sim;
    on_cycle sim ~field:!field ~line:v;
    if h = Wave.cpl - 1 && v = Wave.lpf - 1 then incr field
  done

let check () =
  Random.init 3;
  let packets = Hashtbl.create 512 and got = Hashtbl.create 512 in
  let packet ~field ~line =
    let p = Array.init Wave.plen (fun _ -> Random.int 256) in
    Hashtbl.replace packets (field, line) p; p in
  run ~fields:2 ~packet ~on_cycle:(fun sim ~field ~line ->
    if Bits.to_int !(Cyclesim.out_port sim "pix_new") = 1 then begin
      let key = (field, line) in
      Hashtbl.replace got key (Bits.to_int !(Cyclesim.out_port sim "pix") :: (try Hashtbl.find got key with Not_found -> []))
    end);
  let bad = ref 0 and lines = ref 0 in
  Hashtbl.iter (fun key p ->
    incr lines;
    let g = Array.of_list (List.rev (try Hashtbl.find got key with Not_found -> [])) in
    let r = Wave.reference p in
    if Array.length g <> Wave.npix then (incr bad; Printf.printf "line %d: %d pixels\n" (snd key) (Array.length g))
    else Array.iteri (fun px c -> if g.(px) <> c then incr bad) r) packets;
  Printf.printf "lockstep: %d lines x 256 pixels against the reference, %d mismatches\n" !lines !bad;
  !bad = 0

let dump ~fields ~name =
  let bufs = Array.init fields (fun _ -> Buffer.create (Wave.cpl * Wave.lpf)) in
  run ~fields ~packet:Game.packet ~on_cycle:(fun sim ~field ~line:_ ->
    let g n = Bits.to_int !(Cyclesim.out_port sim n) in
    if field < fields then
      Buffer.add_char bufs.(field) (Char.chr (g "luma" lor (g "chroma" lsl 4) lor (g "chroma_oe" lsl 5) lor (g "chroma2_oe" lsl 6))));
  Array.iteri (fun i b -> let oc = open_out_bin (Printf.sprintf "out/%s_%03d.bin" name i) in Buffer.output_buffer oc b; close_out oc) bufs

let () =
  match Array.to_list Sys.argv with
  | [ _; "check" ] -> exit (if check () then 0 else 1)
  | [ _; "game"; n ] -> dump ~fields:(int_of_string n) ~name:"game"; Printf.printf "score %d, lives %d\n" !Game.score !Game.lives
  | [ _; "verilog" ] -> let oc = open_out "wave_engine.v" in Rtl.output ~output_mode:(To_channel oc) Verilog (Lazy.force circuit); close_out oc
  | _ -> prerr_endline "usage: main (check | game N | verilog)"; exit 2
