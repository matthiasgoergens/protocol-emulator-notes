(* Self-test: bit-bangs both reference models from scratch and checks the
   results against the values the test itself expects.  Prints one
   PASS/FAIL line per check and exits non-zero if anything failed. *)

let failures = ref 0

let check name cond =
  if cond then Printf.printf "PASS: %s\n%!" name
  else begin
    Printf.printf "FAIL: %s\n%!" name;
    incr failures
  end

let check_eq name got expect = check name (got = expect)

(* ------------------------------------------------------------------ *)
(* JTAG                                                                *)
(* ------------------------------------------------------------------ *)

module J = Jtag_tap

(* One "tick" = a rising edge followed by a falling edge; reading [J.tdo]
   right after a tick gives the value that same tick just settled onto
   TDO (see NOTES.txt for why rising-then-falling, sampled immediately
   after, is the right order for this model). *)
let jtick t ~tms ~tdi =
  J.step t ~tck:1 ~tms ~tdi;
  J.step t ~tck:0 ~tms ~tdi

let jtag_test () =
  Printf.printf "\n-- JTAG TAP self-test --\n%!";
  let idcode_a = 0x12345679 in
  let cfg_a = { J.ir_len = 4; idcode = Some idcode_a; bsr_len = 3 } in
  let cfg_b = { J.ir_len = 4; idcode = None; bsr_len = 3 } in
  let a = J.create cfg_a in
  let b = J.create cfg_b in
  (* Establish the initial clock level (first call is never an edge). *)
  J.step a ~tck:0 ~tms:1 ~tdi:0;
  J.step b ~tck:0 ~tms:1 ~tdi:0;

  (* Drive 5 TMS=1 ticks: must land (and stay) in Test-Logic-Reset. *)
  for _ = 1 to 5 do
    jtick a ~tms:1 ~tdi:0;
    jtick b ~tms:1 ~tdi:0
  done;
  check_eq "TLR reached via 5x TMS=1 (A)" (J.state a) "Test-Logic-Reset";
  check_eq "TLR reached via 5x TMS=1 (B)" (J.state b) "Test-Logic-Reset";
  let idcode_op = J.code_idcode cfg_a in
  check_eq "A selects IDCODE at power-up" (J.ir a)
    (match idcode_op with Some c -> c | None -> -1);
  check_eq "B (no IDCODE) selects BYPASS at power-up" (J.ir b)
    (J.code_bypass cfg_b);

  (* -- Two-TAP chain IDCODE read (B relays A's output, both in their
     power-up-selected instructions: IDCODE on A, BYPASS on B). -- *)
  jtick a ~tms:0 ~tdi:0; jtick b ~tms:0 ~tdi:0; (* TLR -> RTI *)
  jtick a ~tms:1 ~tdi:0; jtick b ~tms:1 ~tdi:0; (* RTI -> Select-DR-Scan *)
  jtick a ~tms:0 ~tdi:0; jtick b ~tms:0 ~tdi:0; (* -> Capture-DR *)
  (* Capture tick: old_state = Capture-DR for both, so this is the tick
     that loads idcode/0 into the shift registers. *)
  jtick a ~tms:0 ~tdi:0; jtick b ~tms:0 ~tdi:0; (* -> Shift-DR, and captures *)
  check_eq "A in Shift-DR" (J.state a) "Shift-DR";
  let b_samples = Array.make 33 0 in
  b_samples.(0) <- (match J.tdo b with Some x -> x | None -> -1);
  for i = 1 to 32 do
    let tms = if i = 32 then 1 else 0 in
    (* Chain: B's TDI this tick is A's TDO as it stood *before* this
       tick (one full period of propagation delay), matching a real
       TDO-changes-on-falling-edge chain. *)
    let tdi_b = match J.tdo a with Some x -> x | None -> 0 in
    jtick a ~tms ~tdi:0;
    jtick b ~tms ~tdi:tdi_b;
    b_samples.(i) <- (match J.tdo b with Some x -> x | None -> -1)
  done;
  jtick a ~tms:1 ~tdi:0; jtick b ~tms:1 ~tdi:0; (* Exit1-DR -> Update-DR *)
  jtick a ~tms:0 ~tdi:0; jtick b ~tms:0 ~tdi:0; (* Update-DR -> RTI *)
  let idcode_read = ref 0 in
  for i = 0 to 31 do
    idcode_read := !idcode_read lor (b_samples.(i + 1) lsl i)
  done;
  check_eq "two-TAP chain IDCODE read via BYPASS relay" !idcode_read idcode_a;

  (* -- SAMPLE/PRELOAD boundary-scan on A, standalone -- *)
  let a2 = J.create cfg_a in
  J.step a2 ~tck:0 ~tms:1 ~tdi:0;
  for _ = 1 to 5 do jtick a2 ~tms:1 ~tdi:0 done;
  (* Shift IR = SAMPLE/PRELOAD (ir_len = 4). *)
  jtick a2 ~tms:0 ~tdi:0; (* TLR -> RTI *)
  jtick a2 ~tms:1 ~tdi:0; (* RTI -> Select-DR-Scan *)
  jtick a2 ~tms:1 ~tdi:0; (* -> Select-IR-Scan *)
  jtick a2 ~tms:0 ~tdi:0; (* -> Capture-IR *)
  jtick a2 ~tms:0 ~tdi:0; (* -> Shift-IR, captures "01" pattern *)
  let sample_preload = J.code_sample_preload cfg_a in
  for i = 0 to 3 do
    let tms = if i = 3 then 1 else 0 in
    jtick a2 ~tms ~tdi:((sample_preload lsr i) land 1)
  done;
  jtick a2 ~tms:1 ~tdi:0; (* Exit1-IR -> Update-IR *)
  jtick a2 ~tms:0 ~tdi:0; (* Update-IR -> RTI *)
  check_eq "IR updated to SAMPLE/PRELOAD" (J.ir a2) sample_preload;

  let pins_in = [| 1; 0; 1 |] in
  let new_pins = [| 0; 1; 1 |] in
  J.set_pins_in a2 pins_in;
  check_eq "set_pins_in reports no errors for correct length" (J.errors a2) [];
  jtick a2 ~tms:1 ~tdi:0; (* RTI -> Select-DR-Scan *)
  jtick a2 ~tms:0 ~tdi:0; (* -> Capture-DR *)
  jtick a2 ~tms:0 ~tdi:0; (* -> Shift-DR, captures pins_in *)
  let bsr_samples = Array.make 3 (-1) in
  bsr_samples.(0) <- (match J.tdo a2 with Some x -> x | None -> -1);
  for i = 0 to 2 do
    let tms = if i = 2 then 1 else 0 in
    jtick a2 ~tms ~tdi:new_pins.(i);
    if i < 2 then
      bsr_samples.(i + 1) <- (match J.tdo a2 with Some x -> x | None -> -1)
  done;
  jtick a2 ~tms:1 ~tdi:0; (* Exit1-DR -> Update-DR *)
  jtick a2 ~tms:0 ~tdi:0; (* Update-DR -> RTI, latches pins_out *)
  check_eq "boundary-scan capture read back via TDO" bsr_samples pins_in;
  check_eq "boundary-scan Update-DR loads pins_out" (J.pins_out a2) new_pins

let () = jtag_test ()

(* ------------------------------------------------------------------ *)
(* SWD                                                                 *)
(* ------------------------------------------------------------------ *)

module S = Swd_target

let stick s ~swdio =
  S.step s ~swclk:1 ~swdio;
  S.step s ~swclk:0 ~swdio;
  S.drive s

let send_bits s bits = List.iter (fun b -> ignore (stick s ~swdio:b)) bits
let skip_cycle s = ignore (stick s ~swdio:0)

let recv_bits s n =
  Array.init n (fun _ ->
      match stick s ~swdio:0 with
      | Some b -> b
      | None -> -1)

let bits_of_int_lsb value n = List.init n (fun i -> (value lsr i) land 1)

let int_of_bits_lsb bits =
  let acc = ref 0 in
  Array.iteri (fun i b -> if b > 0 then acc := !acc lor (1 lsl i)) bits;
  !acc

let make_request ~apndp ~rnw ~a2 ~a3 =
  let parity = (apndp lxor rnw lxor a2 lxor a3) land 1 in
  [ 1; apndp; rnw; a2; a3; parity; 0; 1 ]

let make_data value =
  let bits = bits_of_int_lsb value 32 in
  let parity = List.fold_left ( lxor ) 0 bits land 1 in
  bits @ [ parity ]

(* Drives a full transaction assuming the DP is listening (i.e. not
   pre-DPIDR-gated) and the request itself is well formed.  Returns
   (ack_code, data option). *)
let do_txn s ~apndp ~rnw ~a2 ~a3 ~write_value =
  send_bits s (make_request ~apndp ~rnw ~a2 ~a3);
  (* The Trn_to_ack -> Ack transition happens on the very first of these
     three ticks and, because driving is immediate (no settle cycle
     needed), that same tick already exposes ACK bit 0 -- there is no
     separate "dead" turnaround tick to skip here. *)
  let ack_bits = recv_bits s 3 in
  let ack_code = ack_bits.(0) lor (ack_bits.(1) lsl 1) lor (ack_bits.(2) lsl 2) in
  if ack_code = 1 && rnw = 1 then begin
    (* OK + read: target keeps driving straight from ACK into DATA, no
       turnaround in between. *)
    let bits = recv_bits s 33 in
    let data = int_of_bits_lsb (Array.sub bits 0 32) in
    (* Two more ticks: one finishes Data_r and enters the trailing
       turnaround, the other leaves that turnaround for Idle. Sampling
       needs the target to already *be* in a phase before it can sample
       a bit, so entering a sampling phase costs a tick that a driving
       phase does not. *)
    skip_cycle s;
    skip_cycle s;
    (ack_code, Some data)
  end else if ack_code = 1 && rnw = 0 then begin
    (* OK + write: a real 1-cycle turnaround (driver changes host<-target),
       then the host must actually be driving for a full period before the
       target can sample it -- hence two dead ticks before the 33 real
       (32 data + 1 parity) bits. *)
    send_bits s (0 :: 0 :: make_data write_value);
    (ack_code, None)
  end else begin
    (* WAIT/FAULT: one dead tick leaves Ack for the trailing turnaround,
       a second leaves that turnaround for Idle. *)
    skip_cycle s;
    skip_cycle s;
    (ack_code, None)
  end

let expect_no_response s ~apndp ~rnw ~a2 ~a3 =
  send_bits s (make_request ~apndp ~rnw ~a2 ~a3);
  let all_none = ref true in
  for _ = 1 to 6 do
    if stick s ~swdio:0 <> None then all_none := false
  done;
  !all_none

let swd_test () =
  Printf.printf "\n-- SWD target self-test --\n%!";
  let dpidr = 0x2BA01477 in
  let ap_idr = 0x04770021 in
  let wait_flag = ref false in
  let cfg =
    {
      S.dpidr;
      ap_idr;
      mem_words = 16;
      wait_on_ap = (fun () -> !wait_flag);
      start_in_swd = false;
    }
  in
  let s = S.create cfg in
  S.step s ~swclk:0 ~swdio:1;
  (* establish baseline clock level *)
  check_eq "starts in jtag mode" (S.mode s) "jtag";

  (* JTAG-to-SWD switch sequence: >=50 high, 16-bit magic (LSB first of
     0xE79E), >=50 high (line reset). *)
  for _ = 1 to 50 do ignore (stick s ~swdio:1) done;
  for i = 0 to 15 do ignore (stick s ~swdio:((0xE79E lsr i) land 1)) done;
  for _ = 1 to 50 do ignore (stick s ~swdio:1) done;
  check_eq "switch sequence lands in swd-reset" (S.mode s) "swd-reset";

  (* Before the mandatory DPIDR read, other accesses must not be
     honoured: a CTRL/STAT write attempt should get no response. *)
  let ignored = expect_no_response s ~apndp:0 ~rnw:0 ~a2:1 ~a3:0 in
  check "pre-DPIDR access gets no response" ignored;

  let ack, data = do_txn s ~apndp:0 ~rnw:1 ~a2:0 ~a3:0 ~write_value:0 in
  check_eq "DPIDR read ACK=OK" ack 1;
  check_eq "DPIDR read value" data (Some dpidr);
  check_eq "DP now in swd mode after DPIDR read" (S.mode s) "swd";

  (* CTRL/STAT power-up request: CSYSPWRUPREQ (bit30) + CDBGPWRUPREQ
     (bit28); both ACK bits (31, 29) must mirror the request bits. *)
  let pwrup = (1 lsl 30) lor (1 lsl 28) in
  let ack, _ = do_txn s ~apndp:0 ~rnw:0 ~a2:1 ~a3:0 ~write_value:pwrup in
  check_eq "CTRL/STAT power-up write ACK=OK" ack 1;
  let ack, data = do_txn s ~apndp:0 ~rnw:1 ~a2:1 ~a3:0 ~write_value:0 in
  check_eq "CTRL/STAT read ACK=OK" ack 1;
  let expect_ctrl = pwrup lor (1 lsl 31) lor (1 lsl 29) in
  check_eq "CTRL/STAT power-up ACKs mirror REQs" data (Some expect_ctrl);

  (* SELECT: APSEL=0, APBANK=0, DPBANK=0 (explicit, though already the
     reset default). *)
  let ack, _ = do_txn s ~apndp:0 ~rnw:0 ~a2:0 ~a3:1 ~write_value:0 in
  check_eq "SELECT write ACK=OK" ack 1;

  (* MEM-AP: TAR := 0x10 (word index 4), then DRW := 0xDEADBEEF. *)
  let ack, _ = do_txn s ~apndp:1 ~rnw:0 ~a2:1 ~a3:0 ~write_value:0x10 in
  check_eq "AP TAR write ACK=OK" ack 1;
  let ack, _ = do_txn s ~apndp:1 ~rnw:0 ~a2:1 ~a3:1 ~write_value:0xDEADBEEF in
  check_eq "AP DRW write ACK=OK" ack 1;
  check_eq "DRW write landed in mem.(4)" (S.mem s).(4) 0xDEADBEEF;

  (* Posted AP read of DRW: first read returns the *previous* posted
     value (0, nothing read yet), and primes the buffer with 0xDEADBEEF
     for the next AP read / RDBUFF. *)
  let ack, data = do_txn s ~apndp:1 ~rnw:1 ~a2:1 ~a3:1 ~write_value:0 in
  check_eq "posted AP read ACK=OK" ack 1;
  check_eq "posted AP read returns stale (pre-access) buffer" data (Some 0);
  let ack, data = do_txn s ~apndp:0 ~rnw:1 ~a2:1 ~a3:1 ~write_value:0 in
  check_eq "RDBUFF read ACK=OK" ack 1;
  check_eq "RDBUFF returns the posted DRW value" data (Some 0xDEADBEEF);

  (* WAIT: host asserts wait_on_ap, next AP access must ACK=WAIT with no
     data phase. *)
  wait_flag := true;
  let ack, data = do_txn s ~apndp:1 ~rnw:1 ~a2:1 ~a3:1 ~write_value:0 in
  check_eq "AP access under wait_on_ap ACKs WAIT" ack 2;
  check_eq "WAIT carries no data" data None;
  wait_flag := false;

  (* FAULT: select an unimplemented AP (APSEL=1), attempt an access,
     expect FAULT and a set STICKYERR; then clear via ABORT.STKERRCLR
     and restore APSEL=0. *)
  let ack, _ = do_txn s ~apndp:0 ~rnw:0 ~a2:0 ~a3:1 ~write_value:(1 lsl 24) in
  check_eq "SELECT APSEL=1 write ACK=OK" ack 1;
  let ack, _ = do_txn s ~apndp:1 ~rnw:1 ~a2:1 ~a3:1 ~write_value:0 in
  check_eq "AP access to unimplemented APSEL ACKs FAULT" ack 4;
  check "FAULT sets STICKYERR" (S.ctrl_stat s land (1 lsl 5) <> 0);
  let ack, _ = do_txn s ~apndp:0 ~rnw:0 ~a2:0 ~a3:0 ~write_value:0x4 in
  check_eq "ABORT (STKERRCLR) write ACK=OK" ack 1;
  check "STICKYERR cleared after ABORT" (S.ctrl_stat s land (1 lsl 5) = 0);
  let ack, _ = do_txn s ~apndp:0 ~rnw:0 ~a2:0 ~a3:1 ~write_value:0 in
  check_eq "SELECT APSEL=0 restore write ACK=OK" ack 1;

  let stats = S.stats s in
  Printf.printf "stats: %s\n%!"
    (String.concat ", "
       (List.map (fun (k, v) -> Printf.sprintf "%s=%d" k v) stats));
  Printf.printf "log:\n%s\n%!"
    (String.concat "\n" (List.map (fun l -> "  " ^ l) (S.log s)))

let () = swd_test ()

let () =
  Printf.printf "\n%d check(s) failed.\n%!" !failures;
  if !failures > 0 then exit 1 else exit 0
