(* Host-only preview: the game through the reference renderer (no RTL, no TV), for designing the
   level and the pad script quickly. Writes out/prev_NNN.idx (240 x 256 colour indices) and
   out/prev_lut.txt (index -> hue luma saturation). *)
let run ~fields ~every =
  for f = 0 to fields - 1 do
    let lines = Game.lines_for f in
    if Sys.getenv_opt "TRACE" <> None && f mod 4 = 0 then
      Printf.printf "f%d x %.0f y %.0f vx %.1f ground %b | %s\n" f !Game.px !Game.py !Game.vx !Game.on_ground
        (String.concat " " (List.map (fun e -> Printf.sprintf "%.0f,%.0f%s" e.Game.ex e.Game.ey (if e.Game.alive then "" else "x")) Game.enemies));
    if f mod every = 0 then begin
      let oc = open_out_bin (Printf.sprintf "out/prev_%03d.idx" f) in
      Array.iter (fun l -> Array.iter (fun c -> output_byte oc c) (Scene.reference l)) lines;
      close_out oc
    end
  done;
  let oc = open_out "out/prev_lut.txt" in
  Array.iteri (fun i (h, l, s) -> Printf.fprintf oc "%d %d %d %d\n" i h l s) Game.colours;
  close_out oc;
  List.iter print_endline (List.rev !Game.events);
  Printf.printf "after %d fields: x %.0f, camera %.0f, score %d, coins %d\n" fields !Game.px !Game.cam !Game.score !Game.coins
