(* debugging aid: a control read against the firmware device at a given host clock error,
   tracing thread argv.(2) from clock argv.(3) *)
let () =
  let ppm = int_of_string Sys.argv.(1) in
  let th = try int_of_string Sys.argv.(2) with _ -> -1 and from = try int_of_string Sys.argv.(3) with _ -> 0 in
  let trace cyc ~dp ~dm (m : Fw_sys.Model.t) (sys : Dut_fw.sys) =
    if th = 9 && cyc >= from && cyc < from + 3000 then Printf.printf "%7d line %d%d\n" cyc dp dm;
    let t = (m.st.thread + 3) mod 4 in   (* the thread that just executed *)
    if t = th && cyc >= from then begin
      let prog = match th with 0 -> sys.img.p0 | 1 -> sys.img.p1 | _ -> sys.img.p2 in
      let pc = m.st.pcs.(t) in
      let lab = Hashtbl.fold (fun k v acc -> if v = pc then k :: acc else acc) prog.labels [] in
      Printf.printf "%7d T%d next pc %3d %-12s acc %02x cnt %d dl %d pin_in %02x out %02x oe %02x\n" cyc th pc
        (String.concat "," lab) m.st.accs.(t) m.st.cnts.(t) m.st.dls.(t) m.s2 m.st.pin_out m.st.pin_oe
    end in
  let dut, a, _ = Dut_fw.make ~trace () in
  let b = Bench.create ~verbose:true ~ppm dut in
  Bench.idle b 100;
  if Array.length Sys.argv > 4 then begin
    Bench.control_read b ~addr:0 (Bench.get_descriptor ~typ:1 ~len:64 ());
    Bench.bus_reset b 600_000; Bench.idle_bits b 20.0;
    Bench.control_nodata b ~addr:0 [ 0x00; 0x05; 42; 0x00; 0x00; 0x00; 0x00; 0x00 ] end
  else Bench.control_read b ~addr:0 (Bench.get_descriptor ~typ:1 ~len:64 ());
  Bench.idle b 2000;
  print_endline (Buffer.contents a.ctl.log);
  List.iter print_endline (List.rev b.errors)
