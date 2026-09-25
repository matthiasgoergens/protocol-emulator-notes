(* The hardened low-speed device: directed enumeration and reports, packets it must ignore,
   constrained random sessions with the host clock off by up to +-1.5 %, and the controls, each
   of which must fail. Writes usb_ls_device.v. *)
open Hardcaml

let run_directed ?(verbose = false) ~ppm dut =
  let b = Bench.create ~verbose ~ppm dut in
  Scenario.directed b ~addr:42;
  b

let run_random ~seed ~ppm ~n dut =
  let b = Bench.create ~seed ~ppm dut in
  Scenario.random_session b ~n;
  b

let report b =
  print_endline ("  " ^ Bench.summary b);
  List.iter (fun e -> print_endline ("    " ^ e)) (List.rev b.Bench.errors);
  b.Bench.errors = []

let () =
  Ls_host.self_check ();
  print_endline "host model self-checks pass";
  let dut, circ = Dut_hard.make () in
  let oc = open_out "usb_ls_device.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog circ; close_out oc;
  let ok = ref true in
  print_endline "== hardened device: directed, host clock exact";
  ok := report (run_directed ~verbose:true ~ppm:0 dut) && !ok;
  List.iter (fun ppm ->
    let dut, _ = Dut_hard.make () in
    ok := report (run_directed ~ppm dut) && !ok) [ -15000; 15000 ];
  print_endline "== hardened device: constrained random sessions";
  let nseeds = try int_of_string Sys.argv.(1) with _ -> 8 in
  for seed = 1 to nseeds do
    let rng = Random.State.make [| seed; 77 |] in
    let ppm = Random.State.int rng 30001 - 15000 in
    let dut, _ = Dut_hard.make () in
    ok := report (run_random ~seed ~ppm ~n:120 dut) && !ok
  done;
  print_endline "== controls: each must FAIL";
  let control name mk =
    let dut, _ = mk () in
    let b = run_directed ~ppm:0 dut in
    let failed = b.Bench.errors <> [] in
    Printf.printf "  %-44s %s (%d errors; first: %s)\n" name (if failed then "caught" else "NOT CAUGHT")
      (List.length b.errors) (match List.rev b.errors with e :: _ -> e | [] -> "-");
    if not failed then ok := false in
  control "J and K swapped (full-speed polarity)" (fun () -> Dut_hard.make ~name:"jk-swapped" ~ls:false ());
  control "reply 4 bit times late" (fun () -> Dut_hard.make ~name:"late" ~resp_delay:(190 + 160) ());
  control "reply 1.5 bit times early" (fun () -> Dut_hard.make ~name:"early" ~resp_delay:(190 - 60) ());
  control "CRC16 check disabled" (fun () -> Dut_hard.make ~name:"no-crc" ~check_crc:false ());
  print_endline (if !ok then "HARDENED LS DEVICE PASS" else "HARDENED LS DEVICE FAIL");
  exit (if !ok then 0 else 1)
