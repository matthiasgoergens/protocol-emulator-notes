(* PS/2 checks: firmware against independent models, both roles, controls that must fail, and
   constrained random runs. Interpreter and RTL run in lockstep throughout. *)
open Ps2_bench

let us = Sim.us
let hello = [ 0x33; 0xF0; 0x33; 0x24; 0xF0; 0x24; 0x4B; 0xF0; 0x4B; 0x4B; 0xF0; 0x4B; 0x44; 0xF0; 0x44 ]

let () =
  let fails = ref 0 in
  let r ok = if not ok then incr fails in
  let dprog, dlen, _ = Ps2_fw.device { clk = 0; data = 1; req = 2 } timing in
  let hprog, hlen, _ = Ps2_fw.host { clk = 4; data = 5; req = 6 } timing in
  Printf.printf "PS/2 firmware: device %d words, host %d words; base instructions only: %b %b\n"
    dlen hlen (Sim.Asm.uses_only_base dprog dlen) (Sim.Asm.uses_only_base hprog hlen);
  print_endline "Scenarios:";
  let res, (_, app, responses) =
    device_vs_model_host ~name:"device fw vs model host: hello, 4 commands, 2 inhibits" ~seed:0 ~codes:hello
      ~cmds:[ us 2000., 0xFF, false; us 9000., 0xED, false; us 13000., 0x02, false; us 17000., 0xEE, false ]
      ~inhibits:[ us 5000., us 150.; us 10300., us 220. ] ~rise:(us 2.) () in
  report res; r res.ok;
  Printf.printf "      responses seen by the host: [%s]; LED arguments at the keyboard: [%s]; aborts reported: %d\n"
    (String.concat " " (List.map (Printf.sprintf "%02x") responses))
    (String.concat " " (List.map (Printf.sprintf "%02x") app.leds))
    (List.length (List.filter (fun (_, k) -> k = 4) app.events));
  let res, (dev, _) =
    host_vs_model_device ~name:"host fw vs model device (13 kHz): hello, 3 commands" ~codes:hello
      ~cmds:[ us 3000., 0xED; us 8000., 0x07; us 14000., 0xF2 ] ~dev_hz:13e3 ~rise:(us 2.) () in
  report res; r res.ok;
  Printf.printf "      model device LEDs [%s]\n" (String.concat " " (List.map (Printf.sprintf "%02x") dev.leds));
  let res, responses =
    device_vs_host_firmware ~name:"device fw vs host fw, one sequencer, two threads" ~codes:hello
      ~cmds:[ us 1500., 0xFF; us 6000., 0xED; us 9000., 0x04 ] ~rise:(us 1.) () in
  report res; r res.ok;
  Printf.printf "      responses at the host firmware: [%s]\n" (String.concat " " (List.map (Printf.sprintf "%02x") responses));
  (* ---- controls: each must be caught *)
  print_endline "Controls (each must be caught):";
  let caught name ok = Printf.printf "  %-70s %s\n" name (if ok then "caught" else "MISSED"); r ok in
  let short = [ 0x1C; 0xF0; 0x1C; 0x32 ] in
  let res, (dev, app) =
    host_vs_model_device ~name:"" ~codes:short ~cmds:[] ~dev_hz:12e3 ~rise:(us 1.) ~bad_parity_at:2 () in
  let flagged = List.filter_map (fun (_, v, k) -> if k = 2 then Some v else None) (List.rev app.events) in
  caught (Printf.sprintf "model device sends byte 3 with even parity -> host fw flags [%s]"
            (String.concat " " (List.map (Printf.sprintf "%02x") flagged)))
    (res.ok && flagged = [ 0x1C ] && List.length dev.sent = 4);
  let res, (_, app, responses) =
    device_vs_model_host ~name:"" ~seed:0 ~codes:short ~cmds:[ us 1500., 0xED, true ] ~inhibits:[] ~rise:(us 1.) () in
  let flagged = List.filter_map (fun (v, k) -> if k = 2 then Some v else None) (List.rev app.events) in
  caught (Printf.sprintf "model host sends a command with even parity -> device fw flags [%s], replies [%s]"
            (String.concat " " (List.map (Printf.sprintf "%02x") flagged)) (String.concat " " (List.map (Printf.sprintf "%02x") responses)))
    (flagged = [ 0xED ] && List.mem 0xFE responses && res.mismatches = 0);
  let res, _ = device_vs_model_host ~faults:{ Ps2_fw.no_faults with even_parity = true } ~name:"" ~seed:0 ~codes:short
      ~cmds:[] ~inhibits:[] ~rise:(us 1.) () in
  caught ("device fw mutated to even parity -> model host: " ^ String.sub res.detail 0 (min 40 (String.length res.detail))) (not res.ok);
  let res, _ = host_vs_model_device ~faults:{ Ps2_fw.no_faults with even_parity = true } ~name:"" ~codes:short
      ~cmds:[ us 1500., 0xF4 ] ~dev_hz:12e3 ~rise:(us 1.) () in
  caught ("host fw mutated to even parity -> model device: " ^ String.sub res.detail 0 (min 40 (String.index_opt res.detail '\n' |> Option.value ~default:(String.length res.detail)))) (not res.ok);
  let res, _ = device_vs_model_host ~timing:{ timing with half_us = 20.; setup_us = 10.; sample_us = 5. } ~name:"" ~seed:0
      ~codes:short ~cmds:[] ~inhibits:[] ~rise:(us 1.) () in
  caught ("device fw clocked at 25 kHz -> model host: " ^ String.sub res.detail 0 (min 50 (String.length res.detail))) (not res.ok);
  let res, _ = device_vs_model_host ~faults:{ Ps2_fw.no_faults with no_inhibit_check = true } ~name:"" ~seed:0
      ~codes:hello ~cmds:[] ~inhibits:[ us 2500., us 150.; us 6300., us 300. ] ~rise:(us 1.) () in
  caught ("device fw without the inhibit check -> " ^ String.sub res.detail 0 (min 50 (String.length res.detail))) (not res.ok);
  (* ---- constrained random *)
  let n = try int_of_string Sys.argv.(1) with _ -> 8 in
  Printf.printf "Constrained random (%d seeds per role):\n" n;
  let responses = [ 0xFA; 0xAA; 0xEE; 0xFE; 0xAB; 0x83 ] in
  let rand_codes () =
    List.init (6 + Random.int 10) (fun _ -> let rec g () = let b = Random.int 256 in if List.mem b responses then g () else b in g ()) in
  let rand_cmds ~start =
    let t = ref start in
    List.concat (List.init (1 + Random.int 3) (fun _ ->
      t := !t + us (3000. +. Random.float 4000.);
      match Random.int 5 with
      | 0 -> [ !t, 0xFF ] | 1 -> let a = !t in t := !t + us 3000.; [ a, 0xED; !t, Random.int 8 ]
      | 2 -> [ !t, 0xEE ] | 3 -> [ !t, 0xF2 ] | _ -> [ !t, 0xF4 ])) in
  let cycles = ref 0 and passed = ref 0 in
  for seed = 1 to n do
    Random.init (1000 + seed);
    let codes = rand_codes () and cmds = rand_cmds ~start:(us 500.) in
    let inhibits = List.sort compare (List.init (Random.int 4) (fun _ -> us (500. +. Random.float 15000.), us (100. +. Random.float 400.))) in
    let rise = us (0.3 +. Random.float 4.7) in
    let res, _ = device_vs_model_host ~name:(Printf.sprintf "device fw, seed %d: %d bytes, %d commands, %d inhibits, rise %.1fus"
                                              seed (List.length codes) (List.length cmds) (List.length inhibits) (float rise /. 1e9))
        ~seed ~codes ~cmds:(List.map (fun (t, b) -> t, b, false) cmds) ~inhibits ~rise () in
    report res; r res.ok; cycles := !cycles + res.cycles; if res.ok then incr passed;
    let codes = rand_codes () and cmds = rand_cmds ~start:(us 500.) in
    let dev_hz = 10.5e3 +. Random.float 6e3 and rise = us (0.3 +. Random.float 4.7) in
    let res, _ = host_vs_model_device ~name:(Printf.sprintf "host fw, seed %d: %d bytes, %d commands, device %.1f kHz, rise %.1fus"
                                              seed (List.length codes) (List.length cmds) (dev_hz /. 1e3) (float rise /. 1e9))
        ~codes ~cmds ~dev_hz ~rise () in
    report res; r res.ok; cycles := !cycles + res.cycles; if res.ok then incr passed
  done;
  Printf.printf "random: %d of %d runs pass, %d cycles in lockstep\n" !passed (2 * n) !cycles;
  print_endline (if !fails = 0 then "PS/2: ALL PASS" else Printf.sprintf "PS/2: %d FAILURES" !fails);
  exit (if !fails = 0 then 0 else 1)
