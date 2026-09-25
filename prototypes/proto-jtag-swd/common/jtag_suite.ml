(* The JTAG checks, run on whichever ISA build links this file. *)

open Jtag_test

let pr fmt = Printf.printf (fmt ^^ "\n%!")

(* Compare two runs' per-clock traces over their common length. *)
let trace_diff (a : run) (b : run) =
  let n = min (Array.length a.trace) (Array.length b.trace) in
  let d = ref (abs (Array.length a.trace - Array.length b.trace)) in
  for i = 0 to n - 1 do if a.trace.(i) <> b.trace.(i) then incr d done;
  n, !d

let stall_fn st p =
  (* bursts: with probability p per clock start a stall of 1..40 clocks *)
  let left = ref 0 in
  fun () -> if !left > 0 then (decr left; true)
    else if Random.State.float st 1.0 < p then (left := Random.State.int st 40; true) else false

let fixed_chain = {
  cfgs = [| { Jtag_tap.ir_len = 4; idcode = Some 0x4BA00477; bsr_len = 20 };
            { Jtag_tap.ir_len = 5; idcode = None; bsr_len = 7 };
            { Jtag_tap.ir_len = 5; idcode = Some 0x06413041; bsr_len = 100 } |];
  pins = [||] }

let with_pins st ch =
  { ch with pins = Array.map (fun (c : Jtag_tap.config) -> Array.init c.bsr_len (fun _ -> Random.State.int st 2)) ch.cfgs }

(* One session, on both cores; returns (fails interp, fails rtl, cycles compared, differing). *)
let both ?(timing = Jtag_host.fastest) ?swap_tms_tdi ?plant ?(sync = 2) ?(tco = 0) ?(stall_p = 0.0) ~seed ch =
  let mem, _ = Jtag_host.programmes ?swap_tms_tdi timing in
  let go mk =
    let st = Random.State.make [| seed |] in
    let ops = session ?plant st ch in
    let vecs, placed = layout ops in
    let sst = Random.State.make [| seed; 7 |] in
    let r = run ~sync ~tco ~stall:(stall_fn sst stall_p) ~mk ~mem ~cfgs:ch.cfgs
        ~pins_in:(Array.map Option.some ch.pins) vecs in
    judge placed r, r in
  let fi, ri = go Asm.interp and fr, rr = go Asm.rtl in
  let n, d = trace_diff ri rr in
  fi, fr, n, d, ri

let main () =
  let mem, (dl, sl) = Jtag_host.programmes Jtag_host.fastest in
  ignore mem;
  pr "JTAG firmware: driver %d words, sampler %d words (store: %d per thread)" dl sl Isa.prog_len;
  let st = Random.State.make [| 1 |] in
  let ok = ref true in
  (* 1. directed: a fixed three-device chain *)
  let ch = with_pins st fixed_chain in
  let fi, fr, n, d, ri = both ~seed:11 ch in
  pr "directed chain (IDCODE 0x4BA00477, a device without IDCODE, IDCODE 0x06413041; BSR 20/7/100):";
  pr "  interpreter: %s; RTL: %s; %d clocks compared, %d differ; %d TCKs"
    (if fi = [] then "PASS" else String.concat " | " fi) (if fr = [] then "PASS" else String.concat " | " fr) n d
    (Wire.clock_stats ri.tck).rising;
  if fi <> [] || fr <> [] || d <> 0 then ok := false;
  (* 2. constrained random: chains, lengths, data, host stalls, synchroniser depth, target delay *)
  let runs = 60 in
  let pass = ref 0 and clocks = ref 0 and differ = ref 0 and tcks = ref 0 and stalls = ref 0 in
  let first_fail = ref None in
  for i = 1 to runs do
    let ch = random_chain st ~max_devs:4 ~max_bsr:300 in
    let sync = Random.State.int st 4 and tco = Random.State.int st 4 in
    let fi, fr, n, d, ri = both ~sync ~tco ~stall_p:0.02 ~seed:(1000 + i) ch in
    clocks := !clocks + n; differ := !differ + d; tcks := !tcks + (Wire.clock_stats ri.tck).rising;
    stalls := !stalls + ri.stalls;
    if fi = [] && fr = [] && d = 0 then incr pass
    else if !first_fail = None then first_fail := Some (i, sync, tco, fi @ fr)
  done;
  pr "constrained random: %d/%d sessions pass on both cores (chains of 1-4 TAPs, IR 2-8, BSR 1-300,"
    !pass runs;
  pr "  random data, sync 0-3, target delay 0-3, host stalls); %d clocks compared, %d differ; %d TCKs; %d stalled clocks"
    !clocks !differ !tcks !stalls;
  (match !first_fail with Some (i, s, t, f) -> pr "  first failure: run %d sync %d tco %d: %s" i s t (String.concat " | " f) | None -> ());
  if !pass <> runs then ok := false;
  (* 3. controls: planted bugs must be caught *)
  let control name f =
    let caught = ref 0 and total = 20 in
    for i = 1 to total do
      let ch = random_chain st ~max_devs:4 ~max_bsr:120 in
      let fi, fr, _, _, _ = f ~seed:(5000 + i) ch in
      if fi <> [] && fr <> [] then incr caught
    done;
    pr "  control %-44s caught %d/%d" name !caught total;
    if !caught <> total then ok := false in
  pr "controls (each must fail on both cores):";
  control "TMS raised one bit early (scan exit)" (fun ~seed ch -> let a, b, _, _, _ = both ~plant:Early_exit ~seed ch in a, b, 0, 0, ());
  control "one TMS=1 missing on the way to Shift-IR" (fun ~seed ch -> let a, b, _, _, _ = both ~plant:Drop_select ~seed ch in a, b, 0, 0, ());
  control "TMS and TDI pins swapped in the driver" (fun ~seed ch -> let a, b, _, _, _ = both ~swap_tms_tdi:true ~seed ch in a, b, 0, 0, ());
  control "TDO sampled two slots late (after falling)"
    (fun ~seed ch -> let a, b, _, _, _ = both ~timing:{ Jtag_host.fastest with sample_delay = 2 } ~seed ch in a, b, 0, 0, ());
  (* 4. clock rate *)
  let rate (t : Jtag_host.timing) ~sync ~tco =
    let st = Random.State.make [| 77 |] in
    let fails = ref 0 and s = ref None in
    for i = 1 to 8 do
      let ch = random_chain st ~max_devs:3 ~max_bsr:100 in
      let fi, _, _, _, ri = both ~timing:t ~sync ~tco ~seed:(9000 + i) ch in
      if fi <> [] then incr fails;
      if !s = None then s := Some (Wire.clock_stats ri.tck)
    done;
    !fails, Option.get !s in
  pr "TCK at a 60 MHz core clock (min high/low and period in core clocks, 8 random sessions each):";
  List.iter (fun (t, sync, tco) ->
    let fails, s = rate t ~sync ~tco in
    (* a 4-TCK group is 4 * (4 + lo + hi) + 1 slots of 4 clocks, so that many clocks per TCK *)
    let avg = 60.0 /. float_of_int (4 * (4 + t.Jtag_host.lo + t.hi) + 1) in
    pr "  lo %d hi %d sample+%d, sync %d, tco %d: high %d low %d period %d-%d -> max %.2f MHz, mean %.2f MHz: %s"
      t.lo t.hi t.sample_delay sync tco s.min_high s.min_low s.min_period s.max_period
      (60.0 /. float_of_int s.min_period) avg (if fails = 0 then "pass" else Printf.sprintf "FAIL %d/8" fails))
    [ Jtag_host.fastest, 2, 0; Jtag_host.fastest, 2, 3; Jtag_host.fastest, 3, 4; Jtag_host.fastest, 2, 6;
      { Jtag_host.fastest with lo = 1 }, 2, 6; { Jtag_host.fastest with lo = 1 }, 2, 9;
      { Jtag_host.fastest with lo = 2 }, 2, 10 ];
  !ok
