(* Stall injection on the low-speed USB device firmware (after ../verif-oracles/stall/eth_stall.ml).

   The input that may legitimately be late is the reply FIFO: the controller (software beside the
   sequencer) moves the reply's bytes into it, and T1's data loop (firmware.ml, "dloop") takes one
   byte per four bit times (160 clocks) with IN. Here the controller is made slow (a refill period
   above 160 clocks) or bursty (random extra delay before a refill), and every packet on the line
   is judged by the bench's independent host (bench.ml: turnaround, contention, bit stuffing, CRC,
   the reference device's answers). Interpreter and RTL run in lockstep throughout.

   Before: RDY means "FIFO not empty", the controller's default until 2026-10-05.
   After: RDY rises only when the whole reply is in the FIFO (Controller.create ~whole:true, the
   new default), so a slow controller costs NAKs, never a broken packet. *)

let pr = Printf.printf

type cfg = { name : string; refill : int; burst : (float * int) option }

let run ~whole ~depth (c : cfg) ~seed =
  let stall = match c.burst with
    | None -> (fun _ -> 0)
    | Some (p, maxd) ->
      (fun k -> let rng = Random.State.make [| seed; 99; k |] in
        if Random.State.float rng 1.0 < p then 1 + Random.State.int rng maxd else 0) in
  let dut, a, _ = Dut_fw.make ~name:c.name ~verbose_mismatch:false ~refill:c.refill ~depth ~whole ~stall () in
  let b = Bench.create ~seed ~ppm:0 dut in
  Scenario.directed b ~addr:42;
  Scenario.random_session b ~n:40;
  b, a

let () =
  let longest =
    List.fold_left (fun m pid -> max m (List.length (Fw_codec.reply (Fw_codec.data_bytes pid (List.init 8 (fun _ -> 0xFF)))) + 1)) 0
      [ 0xC3; 0x4B ] in
  pr "longest reply (8 bytes of 0xFF, most stuffing): %d FIFO bytes with the terminator; the FIFO takes one byte per 160 clocks\n\n" longest;
  let cfgs = [
    { name = "refill 40 (the default)"; refill = 40; burst = None };
    { name = "refill 160 (the stated bound)"; refill = 160; burst = None };
    { name = "refill 200"; refill = 200; burst = None };
    { name = "refill 400"; refill = 400; burst = None };
    { name = "refill 40, bursts p 0.2 x 1..800"; refill = 40; burst = Some (0.2, 800) };
    { name = "refill 40, bursts p 0.05 x 1..3000"; refill = 40; burst = Some (0.05, 3000) } ] in
  let ok = ref true in
  let one ~label ~whole ~depth ~must_pass =
    pr "== %s\n" label;
    List.iter (fun c ->
        let seeds = 3 in
        let bad = ref 0 and errs = ref 0 and naks = ref 0 and mism = ref 0 and replies = ref 0 and first = ref "" and peak = ref 0 in
        for seed = 1 to seeds do
          let b, a = run ~whole ~depth c ~seed in
          let e = List.rev b.Bench.errors in
          if e <> [] then (incr bad; errs := !errs + List.length e; if !first = "" then first := List.hd e);
          naks := !naks + b.naks_tolerated; mism := !mism + b.dut.mismatches (); replies := !replies + b.replies;
          peak := max !peak a.Dut_fw.ctl.Controller.max_fifo
        done;
        pr "  %-38s %d sessions: %d with errors (%d errors), %d replies, %d NAKs while preparing, FIFO peak %d, lockstep mismatches %d%s\n"
          c.name seeds !bad !errs !replies !naks !peak !mism (if !first = "" then "" else "\n      first error: " ^ !first);
        if !mism > 0 then ok := false;
        let slow = c.refill > 160 || c.burst <> None in
        if must_pass && !bad > 0 then ok := false;
        if (not must_pass) && (not slow) && !bad > 0 then ok := false;
        if (not must_pass) && slow && !bad = 0 then
          pr "      (no error: this stall pattern did not starve the FIFO mid-packet)\n") cfgs in
  one ~label:"before: RDY = FIFO not empty, depth 4 (the earlier defaults)" ~whole:false ~depth:4 ~must_pass:false;
  one ~label:"after: RDY = whole reply in the FIFO, depth 32" ~whole:true ~depth:32 ~must_pass:true;
  pr "\nUSB STALL %s (PASS = after: no errors under any pattern; before: no errors at or under the 160-clock bound; lockstep agrees)\n"
    (if !ok then "PASS" else "FAIL");
  exit (if !ok then 0 else 1)
