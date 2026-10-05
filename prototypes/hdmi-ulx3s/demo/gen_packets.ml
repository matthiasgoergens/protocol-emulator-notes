(* gen_packets.exe FIRST N OUT.hex: the line packets of game fields FIRST .. FIRST+N-1, in ROM
   order (field, then visible line, then byte), one hex byte per line.  game.ml keeps state from
   field to field, so every field from 0 is generated in order and only the window is kept. *)
open Hdmi_demo

let () =
  let first = int_of_string Sys.argv.(1) and n = int_of_string Sys.argv.(2) in
  let oc = open_out Sys.argv.(3) in
  for field = 0 to first + n - 1 do
    for line = Console.first_vis to Console.first_vis + Console.nvis - 1 do
      let p = Game.packet ~field ~line in
      assert (Array.length p = Console.plen);
      if field >= first then Array.iter (fun b -> Printf.fprintf oc "%02x\n" b) p
    done
  done;
  close_out oc
