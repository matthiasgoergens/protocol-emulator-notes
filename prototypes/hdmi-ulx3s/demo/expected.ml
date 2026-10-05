(* The expected HDMI frame of the demo, computed without the console RTL: [line_pixels] is the
   retro console's own reference model of a line (copied from ../../retro-console/main.ml, where it
   is checked in lockstep against the RTL), then the palette and the 2 x 2 scaling. *)
let line_pixels p =
  Array.init 256 (fun px ->
    let u0 = p.(2) lor (p.(3) lsl 8) and step = p.(4) lor (p.(5) lsl 8) in
    let v0 = p.(6) lor (p.(7) lsl 8) and vstep = p.(8) lor (p.(9) lsl 8) in
    let u = (u0 + px * step) land 0xFFFF and v = (v0 + px * vstep) land 0xFFFF in
    let c = ref (if ((u lsr 12) lxor (v lsr 12)) land 1 = 1 then p.(1) else p.(0)) in
    for i = 0 to Console.nspr - 1 do
      let sx = p.(10 + 3 * i) and bmp = p.(11 + 3 * i) and col = p.(12 + 3 * i) in
      let d = px - sx in
      if d >= 0 && d < 16 && (bmp lsr (7 - d / 2)) land 1 = 1 then c := col
    done; !c)

(* packets.(line - first_vis) for one field *)
let frame (packets : int array array) x y =
  if x < 64 || x >= 64 + 512 then 0, 0, 0
  else Console_hdmi.palette_rgb (line_pixels packets.(y / 2)).((x - 64) / 2)
