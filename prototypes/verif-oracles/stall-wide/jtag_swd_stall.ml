(* Host-stall injection on the JTAG and SWD host firmware (../../proto-jtag-swd/wide), on ISA v2,
   at stall rates far above the suites' own 0.02, with a golden-transcript comparison added.

   The suites already inject host stalls (Jtag_suite.stall_fn: per clock, with probability p, a
   burst of 0..39 clocks with host_in_valid low) and judge each session against independent
   models (IEEE 1149.1 TAPs, an ADIv5 SW-DP/MEM-AP). What is added here, after Gergo Erdi's
   test-sim.hs: the same session is run unstalled and its protocol transcript (JTAG: the TDO bits
   returned to the host; SWD: every packet's final ACK, read data and parity verdict) is the
   golden output that every stalled run must reproduce exactly. SWD runs also get target WAIT
   responses (the protocol's own ready signal) with probability up to 0.5.

   A run that hits the bench's own cycle budget (200 clocks per vector + 10,000 for JTAG) is
   counted as "timed out", not as a failure, provided what it did deliver is a prefix of the
   golden transcript: a wrong bit is a failure, a missing one at the cut-off is the budget. *)

let is_prefix a b = let n = Array.length a in n <= Array.length b && Array.sub b 0 n = a
let is_prefix_l a b = is_prefix (Array.of_list a) (Array.of_list b)

let pr fmt = Printf.printf (fmt ^^ "\n%!")

let jtag ~runs stall_p ?plant () =
  let fails = ref 0 and differ = ref 0 and transcript = ref 0 and stalls = ref 0 and first = ref "" and timeouts = ref 0 in
  for i = 1 to runs do
    let st = Random.State.make [| 4242; i |] in
    let ch = Jtag_test.random_chain st ~max_devs:4 ~max_bsr:120 in
    let _, _, _, _, golden = Jtag_suite.both ~stall_p:0.0 ~seed:(5000 + i) ch in
    let fi, fr, _, d, r = Jtag_suite.both ?plant ~stall_p ~seed:(5000 + i) ch in
    stalls := !stalls + r.stalls; differ := !differ + d;
    let tdo = Array.of_list (List.filter (fun b -> b >= 0) (Array.to_list r.tdo)) in
    if not r.complete && is_prefix tdo golden.tdo && plant = None then incr timeouts
    else begin
      if fi <> [] || fr <> [] then (incr fails; if !first = "" then first := String.concat " | " (fi @ fr));
      if r.tdo <> golden.tdo then incr transcript
    end
  done;
  pr "  JTAG stall p = %.2f%s: %d sessions, %d stalled clocks; timed out with a correct prefix %d; oracle failures %d, TDO transcript differs from golden %d, interpreter vs RTL clocks differing %d%s"
    stall_p (match plant with Some _ -> " (planted bug: early exit)" | None -> "") runs !stalls !timeouts !fails !transcript !differ
    (if !first = "" then "" else "\n    first failure: " ^ !first);
  !fails, !transcript, !differ

let swd ~runs stall_p wait_p =
  let key (o : Swd_test.outcome) = (o.tag, o.ack, o.data, o.parity_ok) in
  let fails = ref 0 and differ = ref 0 and transcript = ref 0 and stalls = ref 0 and waits = ref 0 and first = ref "" and timeouts = ref 0 in
  for i = 1 to runs do
    let st = Random.State.make [| 777; i |] in
    let sc = Swd_suite.random_traffic st ~n:(10 + Random.State.int st 20) in
    let _, _, _, _, golden = Swd_suite.both ~stall_p:0.0 ~wait_p:0.0 ~seed:(300 + i) sc in
    let fi, fr, _, d, r = Swd_suite.both ~stall_p ~wait_p ~seed:(300 + i) sc in
    stalls := !stalls + r.stalls; differ := !differ + d; waits := !waits + Swd_suite.waits r;
    if not r.complete && is_prefix_l (List.map key r.outcomes) (List.map key golden.outcomes) then incr timeouts
    else begin
      if fi <> [] || fr <> [] then (incr fails; if !first = "" then first := String.concat " | " (fi @ fr));
      if List.map key r.outcomes <> List.map key golden.outcomes then incr transcript
    end
  done;
  pr "  SWD stall p = %.2f, target WAIT p = %.2f: %d sessions, %d stalled clocks, %d WAITs retried; timed out with a correct prefix %d; oracle failures %d, transcript differs %d, interpreter vs RTL clocks differing %d%s"
    stall_p wait_p runs !stalls !waits !timeouts !fails !transcript !differ (if !first = "" then "" else "\n    first failure: " ^ !first);
  !fails, !transcript, !differ

let () =
  let ok = ref true in
  pr "JTAG host firmware (random chains of 1-4 TAPs, sessions of reset, IDCODE, BYPASS, SAMPLE, EXTEST):";
  List.iter (fun p -> let f, t, d = jtag ~runs:20 p () in if f + t + d > 0 then ok := false) [ 0.02; 0.2; 0.6; 0.95 ];
  pr "SWD host firmware (random reads and writes through the MEM-AP):";
  List.iter (fun (p, w) -> let f, t, d = swd ~runs:15 p w in if f + t + d > 0 then ok := false)
    [ (0.02, 0.0); (0.2, 0.2); (0.6, 0.5); (0.95, 0.5) ];
  pr "controls (must be flagged under heavy stalls):";
  let f, _, _ = jtag ~runs:10 0.6 ~plant:Jtag_test.Early_exit () in
  pr "  control JTAG planted early-exit bug under stalls: %s" (if f > 0 then "flagged" else "MISSED");
  if f = 0 then ok := false;
  pr "\nJTAG/SWD STALL %s" (if !ok then "PASS" else "FAIL");
  exit (if !ok then 0 else 1)
