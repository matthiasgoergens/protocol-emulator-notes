(* Pin-level runs: timing measured on the RTL's pins, the palette field, and field dumps for the
   software TV (../composite-video via ../retro-console/console_tv.py's composite model). *)
open Hardcaml

let pins_byte s = Bits.to_int !(s.Sim.pins)

(* One field of the check scene; measure on the pins: sync falls, and where pixels start. *)
let timing () =
  let s = Sim.make () in
  let lut = Check.palette_lut () in
  let packet ~field:_ ~line =
    if line >= Sim.first_vis && line < Sim.first_vis + Sim.nvis then Scene.encode (Scene.random_line ())
    else Scene.encode_blank () in
  let cyc = ref 0 and prev_luma = ref 4 and last_fall = ref (-1) in
  let spacing = Hashtbl.create 8 and first_px = Hashtbl.create 8 and px_clocks = Hashtbl.create 8 in
  let bump h k = Hashtbl.replace h k (1 + try Hashtbl.find h k with Not_found -> 0) in
  let line_fall = ref 0 and seen_px = ref false and hold_count = ref 0 in
  let _ = Sim.run s ~fields:1 ~lut:(fun () -> lut) ~packet ~on_cycle:(fun s ~field:_ ~line:_ ->
    let luma = pins_byte s land 15 in
    if !prev_luma <> 0 && luma = 0 then begin
      if !last_fall >= 0 then bump spacing (!cyc - !last_fall);
      if !seen_px then bump px_clocks !hold_count;
      last_fall := !cyc; line_fall := !cyc; seen_px := false; hold_count := 0
    end;
    prev_luma := luma;
    (* the output port shows a step from two clocks after it arrives, for 10 clocks *)
    if Bits.to_int !(s.Sim.arr_tag) = 1 then begin
      if not !seen_px then bump first_px (!cyc + 2 - !line_fall);
      seen_px := true; hold_count := !hold_count + Video.period
    end;
    incr cyc) in
  let show h = Hashtbl.fold (fun k v acc -> Printf.sprintf "%s %d x%d" acc k v) h "" in
  Printf.sprintf "RTL pins, one field: sync-fall spacing (clocks):%s\nfirst pixel, clocks after the sync fall:%s\npixel clocks per line:%s\n"
    (show spacing) (show first_px) (show px_clocks)

(* Dump [fields] fields of pins, one file per field, starting each at line 0's sync. *)
let dump ~fields ~lut ~packet ~name =
  let s = Sim.make () in
  let bufs = Array.init (fields + 1) (fun _ -> Buffer.create (Sim.cpl * Sim.lpf)) in
  let st = Sim.run s ~fields ~lut ~packet ~on_cycle:(fun s ~field ~line:_ ->
    if field < fields then Buffer.add_char bufs.(field) (Char.chr (pins_byte s))) in
  for i = 0 to fields - 1 do
    let oc = open_out_bin (Printf.sprintf "out/%s_%03d.bin" name i) in
    Buffer.output_buffer oc bufs.(i); close_out oc
  done;
  st

(* The palette field: 13 columns of hue (0 = grey), 11 bands of luma, as ../retro-console's. *)
let hue_index = [| 1; 2; 3; 5; 6; 7; 9; 10; 11; 13; 14; 15; 17 |]
let palette () =
  let lut = Array.init 64 (fun i -> if i = 63 then Sim.burst_entry else 4) in
  let packet ~field:_ ~line =
    if line >= Sim.first_vis && line < Sim.first_vis + Sim.nvis then begin
      let row = (line - Sim.first_vis) * 11 / Sim.nvis in
      let entries = Array.make 15 4 in
      Array.iteri (fun h idx -> if idx < 16 then entries.(idx - 1) <- Sim.lut_entry ~hue:h ~luma:row) hue_index;
      let solid idx = { Scene.pix = Array.make 16 (idx mod 4); pal = idx / 4; front = false } in
      let l = { Scene.backdrop = 32; fine = 0;
                tiles = Array.init Scene.ntiles (fun j -> if j < 12 then solid hue_index.(j) else Scene.blank_tile);
                sprites = [ { x = 192; spix = Array.make 16 1; spal = 0; flip = false; behind = false } ] } in
      let lut_upd = Scene.lut_record ~addr:1 (Array.to_list entries)
                    @ Scene.lut_record ~addr:17 [ Sim.lut_entry ~hue:12 ~luma:row ]
                    @ Scene.lut_record ~addr:32 [ 4 ] in
      Scene.encode ~lut:lut_upd l
    end else Scene.encode_blank () in
  dump ~fields:1 ~lut:(fun () -> lut) ~packet ~name:"palette"
