(* Stall injection on the PS/2 firmware (after ../verif-oracles/stall/eth_stall.ml). Both roles
   read their byte with IN after the doorbell pin (req) says one is waiting:
   - device (ps2_fw.ml, "txgo"): IN after the 50 us clock-released check and the data-high check
     (no request to send from the host), before it pulls data low and starts clocking;
   - host ("hgot"): IN after the device has answered the request to send by clocking, so the
     device is already producing clock pulses when the byte is read.
   The perturbed input is the byte's arrival: it becomes valid [lag] after it is due. Two kinds of
   host side:
   - contract: the doorbell rings only once the byte is valid (doorbell => byte valid, which the
     benches and ps2_fw.ml's pin comment assume);
   - early doorbell: the doorbell rings when the byte is due and the byte follows [lag] later,
     which breaks that contract, so the IN waits.
   Every run is judged by the benches' own checks (ps2_bench.ml: the independent models' protocol
   violations, the bytes and parity each side saw, command outcomes, contention), interpreter and
   RTL in lockstep. *)
open Ps2_bench

let us = Sim.us
let hello = [ 0x33; 0xF0; 0x33; 0x24; 0xF0; 0x24; 0x4B; 0xF0; 0x4B ]

let () =
  let ok = ref true and early_fails = ref 0 in
  let lags = [ 0.; 20.; 100.; 500.; 2000. ] in
  let row role contract lag (res : result) =
    Printf.printf "  %-6s %-14s byte %6.0f us late: %s%s\n" role (if contract then "contract" else "early doorbell") lag
      (if res.ok then "PASS" else "FAIL") (if res.ok then "" else "\n      " ^ res.detail) in
  print_endline "device role (our device firmware, the model host: 3 commands, 3 inhibits)";
  List.iter (fun contract ->
      List.iter (fun lag ->
          let res, _ = device_vs_model_host ~lag:(us lag) ~early:(not contract) ~name:"" ~seed:0 ~codes:hello
              ~cmds:[ us 2500., 0xFF, false; us 9000., 0xED, false; us 13000., 0x02, false ]
              ~inhibits:[ us 1200., us 150.; us 5000., us 300.; us 10300., us 220. ] ~rise:(us 2.) () in
          row "device" contract lag res;
          if contract && not res.ok then ok := false;
          if (not contract) && not res.ok then incr early_fails) lags) [ true; false ];
  print_endline "host role (our host firmware, the model device at 13 kHz: 3 commands)";
  List.iter (fun contract ->
      List.iter (fun lag ->
          let res, _ = host_vs_model_device ~lag:(us lag) ~early:(not contract) ~name:"" ~codes:hello
              ~cmds:[ us 3000., 0xED; us 8000., 0x07; us 14000., 0xF2 ] ~dev_hz:13e3 ~rise:(us 2.) () in
          row "host" contract lag res;
          if contract && not res.ok then ok := false;
          if (not contract) && not res.ok then incr early_fails) lags) [ true; false ];
  (* non-vacuity: the same checks must see the early-doorbell failures *)
  Printf.printf "\nearly-doorbell runs failing the benches' checks: %d (must be at least one)\n" !early_fails;
  if !early_fails = 0 then ok := false;
  Printf.printf "\nPS/2 STALL %s (PASS = every run with the doorbell contract passes, and the checks see the early-doorbell failures)\n"
    (if !ok then "PASS" else "FAIL");
  exit (if !ok then 0 else 1)
