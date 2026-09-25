(* Lockstep of the whole chip (sequencer, line buffer, feeder, PE-X row, output port) against the
   reference renderer: random scanline descriptions (random tiles with fine scroll and priority,
   0-21 random sprites with flip, behind-priority and clipping at both edges), encoded by the host
   code, played through the RTL; the colour index of every step arriving at the output port is
   compared with Scene.reference. *)
open Hardcaml

let palette_lut () =
  Array.init 64 (fun i -> if i = 63 then Sim.burst_entry else Sim.lut_entry ~hue:(i mod 13) ~luma:(i mod 11))

let run ?fault ?lean ~fields () =
  Random.init 5;
  let s = Sim.make ?fault ?lean () in
  let descs = Hashtbl.create 1024 and got = Hashtbl.create 1024 in
  let lut = palette_lut () in
  let packet ~field ~line =
    if line >= Sim.first_vis && line < Sim.first_vis + Sim.nvis then begin
      let l = Scene.random_line () in
      Hashtbl.replace descs (field, line) l;
      Scene.encode l
    end else Scene.encode_blank () in
  let st = Sim.run s ~fields ~lut:(fun () -> lut) ~packet ~on_cycle:(fun s ~field ~line ->
    if Bits.to_int !(s.Sim.arr_tag) = 1 then begin
      let key = (field, line) in
      let l = try Hashtbl.find got key with Not_found -> [] in
      Hashtbl.replace got key ((Bits.to_int !(s.arr_data) land 63) :: l)
    end) in
  let lines = ref 0 and bad_px = ref 0 and bad_lines = ref 0 in
  Hashtbl.iter (fun key l ->
    incr lines;
    let r = Scene.reference l in
    let g = Array.of_list (List.rev (try Hashtbl.find got key with Not_found -> [])) in
    if Array.length g <> Scene.npix then (incr bad_lines; bad_px := !bad_px + Scene.npix)
    else begin
      let b = ref 0 in
      Array.iteri (fun i c -> if g.(i) <> c then incr b) r;
      if !b > 0 then incr bad_lines;
      bad_px := !bad_px + !b
    end) descs;
  !lines, !bad_lines, !bad_px, st

let main () =
  let t0 = Unix.gettimeofday () in
  let lines, bl, bp, st = run ~fields:1 () in
  Printf.printf "chip lockstep: %d random lines x 256 pixels against the reference: %d lines, %d pixels differ (%.0f s)\n"
    lines bl bp (Unix.gettimeofday () -. t0);
  print_string (Sim.print_stats st);
  let lines, bl, bp_lean, _ = run ~lean:true ~fields:1 () in
  Printf.printf "  the same with the lean PE-X (2 bits per step, window above bit 4, no rotate): %d of %d lines, %d pixels differ\n"
    bl lines bp_lean;
  List.iter (fun (f, name) ->
    let lines, bl, bp, _ = run ~fault:f ~fields:1 () in
    Printf.printf "  planted fault %d (%s): %d of %d lines, %d pixels differ\n" f name bl lines bp)
    [ 1, "no horizontal flip"; 2, "flag block ignored"; 3, "release at window start" ];
  bp = 0 && bp_lean = 0
