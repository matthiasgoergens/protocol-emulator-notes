(* Testbench and "CPU". Modes:
     check          lockstep check of the pixel pipeline against a reference model, random packets
     palette        one field showing all 16 hues x 11 lumas, pins dumped to out/palette.bin
     game N         N fields of the demo scene, pins dumped to out/frame_XXX.bin *)
open Hardcaml

let circuit = Console.circuit ()
let plen = Console.plen and nspr = Console.nspr and cpl = Console.cpl and lpf = Console.lpf

type sim = { sim : Cyclesim.t_port_list; din : Bits.t ref; strobe : Bits.t ref;
             luma : Bits.t ref; chroma : Bits.t ref; coe : Bits.t ref; c2oe : Bits.t ref;
             pcol : Bits.t ref; pvalid : Bits.t ref; h : Bits.t ref; v : Bits.t ref }

let make () =
  let sim = Cyclesim.create circuit in
  let i = Cyclesim.in_port sim and o = Cyclesim.out_port sim in
  let clear = i "clear" in
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  { sim; din = i "din"; strobe = i "strobe"; luma = o "luma"; chroma = o "chroma"; coe = o "chroma_oe";
    c2oe = o "chroma2_oe"; pcol = o "pix_col"; pvalid = o "pix_valid"; h = o "hcount"; v = o "vcount" }

(* Run [fields] fields. [packet line] gives the 54 bytes for a visible line (sent during the
   previous line). [on_cycle] sees every cycle's pin outputs. *)
let run s ~fields ~(packet : field:int -> line:int -> int array) ~on_cycle =
  let field = ref 0 in
  let pending = ref [||] in
  while !field < fields do
    let h = Bits.to_int !(s.h) and v = Bits.to_int !(s.v) in
    let next = (v + 1) mod lpf in
    let next_field = if next = 0 then !field + 1 else !field in
    if h = 1000 then pending := (if next >= Console.first_vis && next < Console.first_vis + Console.nvis
                                  then packet ~field:next_field ~line:next else [||]);
    let k = h - 1001 in
    if k >= 0 && k < Array.length !pending then (s.din := Bits.of_int ~width:8 !pending.(k); s.strobe := Bits.vdd)
    else s.strobe := Bits.gnd;
    Cyclesim.cycle s.sim;
    on_cycle s ~field:!field ~h ~v;
    if h = cpl - 1 && v = lpf - 1 then incr field
  done

(* reference model of one line *)
let reference p =
  Array.init 256 (fun px ->
    let u0 = p.(2) lor (p.(3) lsl 8) and step = p.(4) lor (p.(5) lsl 8) in
    let u = (u0 + px * step) land 0xFFFF in
    let c = ref (if (u lsr 12) land 1 = 1 then p.(1) else p.(0)) in
    for i = 0 to nspr - 1 do
      let sx = p.(6 + 3 * i) and bmp = p.(7 + 3 * i) and col = p.(8 + 3 * i) in
      let d = px - sx in
      if d >= 0 && d < 16 && (bmp lsr (7 - d / 2)) land 1 = 1 then c := col
    done; !c)

let check () =
  Random.init 7;
  let s = make () in
  let packets = Hashtbl.create 256 in
  let packet ~field ~line =
    let p = Array.init plen (fun _ -> Random.int 256) in
    Hashtbl.replace packets (field, line) p; p in
  let cur = Hashtbl.create 256 in           (* (field,line) -> collected pixel stream *)
  run s ~fields:3 ~packet ~on_cycle:(fun s ~field ~h:_ ~v ->
    if Bits.to_int !(s.pvalid) = 1 then begin
      let key = (field, v) in
      let l = try Hashtbl.find cur key with Not_found -> [] in
      Hashtbl.replace cur key (Bits.to_int !(s.pcol) :: l)
    end);
  let bad = ref 0 and lines = ref 0 in
  Hashtbl.iter (fun key samples ->
    match Hashtbl.find_opt packets key with
    | None -> ()
    | Some p ->
      incr lines;
      let samples = Array.of_list (List.rev samples) in
      let refp = reference p in
      if Array.length samples <> 256 * Console.pixc then (incr bad; Printf.printf "line %d: %d samples\n" (snd key) (Array.length samples))
      else Array.iteri (fun px c -> if samples.(px * Console.pixc + 5) <> c then incr bad) refp) cur;
  Printf.printf "lockstep: %d lines x 256 pixels checked against the reference, %d mismatches\n" !lines !bad;
  !bad = 0

let dump s ~fields ~packet ~name =
  let bufs = Array.init fields (fun _ -> Buffer.create (cpl * lpf)) in
  run s ~fields ~packet ~on_cycle:(fun s ~field ~h:_ ~v:_ ->
    if field < fields then
      Buffer.add_char bufs.(field) (Char.chr (Bits.to_int !(s.luma) lor (Bits.to_int !(s.chroma) lsl 4)
                                               lor (Bits.to_int !(s.coe) lsl 5) lor (Bits.to_int !(s.c2oe) lsl 6))));
  Array.iteri (fun i b ->
    let oc = open_out_bin (Printf.sprintf "out/%s_%03d.bin" name i) in
    Buffer.output_buffer oc b; close_out oc) bufs

let palette_packet ~field:_ ~line =
  let row = (line - Console.first_vis) * 11 / Console.nvis in
  Array.concat [ [| 0; 0; 0; 0; 0; 0 |];
                 Array.concat (List.init nspr (fun i -> [| i * 16; 0xFF; (i lsl 4) lor row |])) ]

let () =
  (try Unix.mkdir "out" 0o755 with _ -> ());
  match Array.to_list Sys.argv with
  | [ _; "check" ] -> exit (if check () then 0 else 1)
  | [ _; "verilog" ] -> let oc = open_out "retro_console.v" in Rtl.output ~output_mode:(To_channel oc) Verilog circuit; close_out oc
  | [ _; "palette" ] -> dump (make ()) ~fields:1 ~packet:palette_packet ~name:"palette"
  | [ _; "game"; n ] -> dump (make ()) ~fields:(int_of_string n) ~packet:Game.packet ~name:"frame"
  | _ -> prerr_endline "usage: main (check | palette | game N)"; exit 2
