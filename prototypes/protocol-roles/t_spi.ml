(* Task 2: SPI controller in modes 0-3, msb and lsb first, full duplex, at 60 MHz.

   Each configuration runs on the interpreter and the RTL in lockstep against the peer target of
   peers.ml in the same mode, which records what it receives and answers with its own bytes. The
   bus timing is measured on the trace, at clock resolution, against what the mode requires:
   SCLK's period and its two phases, MOSI stable around every sampling edge (set-up before it,
   hold after it), and where the controller samples MISO relative to the sampling edge. Then the
   peer's MISO is delayed (its output valid time after the shift edge) until the controller reads
   it wrongly: the largest delay it reads correctly is the controller's MISO margin. *)

let pr = Printf.printf
let sclk = 1 and mosi = 2 and miso = 3 and cs = 4
let op w = (w lsr 12) land 15

let modes = List.concat_map (fun (cpol, cpha) -> List.map (fun msb -> { Fw.cpol; cpha; msb }) [ true; false ])
    [ (0, 0); (0, 1); (1, 0); (1, 1) ]
let peer_mode (m : Fw.spi_mode) = { Peers.Spi.cpol = m.cpol; cpha = m.cpha; msb = m.msb }

type meas = {
  ok : bool; mism : int; words : int;
  sent : int list; peer_got : (int * bool) list; replies : int list; got : int list;
  periods : int list;            (* sampling edge to sampling edge within a byte, clocks *)
  act_min : int; act_max : int; idl_min : int;
  setup : int; hold : int;       (* MOSI around sampling edges: min clocks *)
  sample_after : int list;       (* clocks from the sampling edge on the bus to the SHI *)
  cs_setup : int; cs_hold : int;
  mosi_wrong_phase : int;        (* MOSI changes while SCLK is in the phase where the mode samples *)
  tr : Bench.result;
}

let run ?bug ?(rtl = true) ?fault ?(delay = 0) ?peer ?image ~mode ~period ~seed () =
  let rng = Random.State.make [| seed; period |] in
  let sent = List.init 4 (fun _ -> Random.State.int rng 256) in
  let replies = List.init 4 (fun _ -> Random.State.int rng 256) in
  (* [image]: the firmware is generated for that mode while the checks assume [mode] (controls) *)
  let page, words = Fw.spi_ctl ?fault ~sclk ~mosi ~miso ~cs ~mode:(Option.value image ~default:mode) ~period sent in
  let t = Peers.Spi.target ~delay ~mode:(match peer with Some p -> p | None -> peer_mode mode) replies in
  let clocks = (period * 4 * 8 * 5) + (period * 40) + 400 in
  let world ~clock:_ ~pin_out ~pin_oe =
    let lv p = if (pin_oe lsr p) land 1 = 1 then (pin_out lsr p) land 1 else 1 in
    let m = Peers.Spi.step t ~sclk:(lv sclk) ~mosi:(lv mosi) ~cs:(lv cs) in
    let bus = Bench.driven ~idle:0xFF ~pin_out ~pin_oe () in
    (bus land lnot (1 lsl miso)) lor ((match m with Some v -> v | None -> 1) lsl miso) in
  let r = Bench.run ?bug ~rtl ~record_issues:true ~pages:[| Some page; None; None; None |] ~clocks ~world (Bench.host []) in
  let got = List.map (fun (_, _, b) -> b) r.outs in
  (* the bus, from the trace *)
  let lv c p = Bench.level r c p in
  let active = 1 - mode.cpol in
  let sampling_kind = if mode.cpha = 0 then active else mode.cpol in   (* the level SCLK moves to on a sampling edge *)
  let sclk_edges = Bench.edges r sclk and mosi_edges = List.map fst (Bench.edges r mosi) in
  let cs_edges = Bench.edges r cs in
  let in_cs c = lv c cs = 0 in
  let samp = List.filter_map (fun (c, v) -> if v = sampling_kind && in_cs c then Some c else None) sclk_edges in
  let periods = let rec go = function a :: (b :: _ as r) -> (b - a) :: go r | _ -> [] in go samp in
  let byte_periods = List.filteri (fun i _ -> i mod 8 <> 7) periods in
  let phases v = let rec go = function (a, x) :: ((b, _) :: _ as r) -> (if x = v && in_cs a then [ b - a ] else []) @ go r | _ -> [] in go sclk_edges in
  let acts = phases active and idls = phases mode.cpol in
  let mn l = List.fold_left min max_int l and mx l = List.fold_left max 0 l in
  let setup = mn (List.map (fun e -> e - mx (List.filter (fun c -> c <= e) mosi_edges @ [ 0 ])) samp) in
  let hold = mn (List.map (fun e -> mn (List.filter (fun c -> c > e) mosi_edges @ [ r.clocks ]) - e) samp) in
  let shis = List.filter_map (fun (c, th, w) -> if th = 0 && op w = 8 then Some c else None) r.issues in
  let rec zip a b = match a, b with x :: a, y :: b -> (x, y) :: zip a b | _ -> [] in
  let sample_after = List.sort_uniq compare (List.map (fun (s, e) -> s - e) (zip shis samp)) in
  let cs_fall = mn (List.filter_map (fun (c, v) -> if v = 0 then Some c else None) cs_edges) in
  let cs_rise = mx (List.filter_map (fun (c, v) -> if v = 1 then Some c else None) cs_edges) in
  let first_edge = mn (List.map fst (List.filter (fun (c, _) -> in_cs c) sclk_edges)) in
  let last_edge = mx (List.map fst (List.filter (fun (c, _) -> c < cs_rise) sclk_edges)) in
  (* CPHA 0 samples on the leading edge, so MOSI may change only while SCLK idles (after the
     trailing edge); CPHA 1 samples on the trailing edge, so only while SCLK is active *)
  let change_level = if mode.cpha = 0 then mode.cpol else active in
  let mosi_wrong_phase = List.length (List.filter (fun c -> in_cs c && lv c sclk <> change_level) mosi_edges) in
  let peer_got = List.rev t.got in
  let ok = r.mismatches = 0 && peer_got = List.map (fun b -> (b, true)) sent && got = replies in
  { ok; mism = r.mismatches; words; sent; peer_got; replies; got; periods = byte_periods;
    act_min = mn acts; act_max = mx acts; idl_min = mn idls; setup; hold; sample_after;
    cs_setup = first_edge - cs_fall; cs_hold = cs_rise - last_edge; mosi_wrong_phase; tr = r }

(* the largest MISO delay (clocks after the shift edge) read correctly, by bisection on the
   interpreter; the delay that fails first is one more *)
let margin ~mode ~period =
  let ok d = List.for_all (fun seed -> let m = run ~rtl:false ~delay:d ~mode ~period ~seed () in m.got = m.replies) [ 1; 2 ] in
  let rec go lo hi = if hi - lo <= 1 then lo else let m = (lo + hi) / 2 in if ok m then go m hi else go lo m in
  if not (ok 0) then -1 else go 0 (period * 4 + 8)

let periods_for (m : Fw.spi_mode) = (if m.cpha = 1 then [ 8 ] else []) @ [ 10; 15; 30; 150 ]

let run_all () =
  pr "== Task 2: SPI controller, modes 0-3, msb and lsb first, full duplex, 60 MHz core clock\n";
  pr "Peer: an SPI target in the same mode (peers.ml) answering 4 random bytes to the 4 sent.\n";
  pr "All times in clocks (16.67 ns); the period P is in slots (4 clocks).\n\n";
  pr "%-12s %4s %9s | %-6s %-9s %-7s | %-11s | %-12s | %-9s | %s\n" "mode" "P" "SCLK" "period" "act/idle" "MOSI" "MISO sample" "MISO margin" "CS" "lockstep, data";
  pr "%-12s %4s %9s | %-6s %-9s %-7s | %-11s | %-12s | %-9s | %s\n" "" "" "" "" "" "su/hold" "after edge" "(valid after" "su/hold" "";
  pr "%-12s %4s %9s | %-6s %-9s %-7s | %-11s | %-12s | %-9s | %s\n" "" "" "" "" "" "" "" "shift edge)" "" "";
  let all = ref true in
  List.iter (fun mode ->
      List.iter (fun period ->
          let m = run ~mode ~period ~seed:1 () in
          let m2 = run ~mode ~period ~seed:2 () in
          let per_ok = List.for_all (fun p -> p = 4 * period) (m.periods @ m2.periods) in
          let marg = margin ~mode ~period in
          let ok = m.ok && m2.ok && per_ok && m.act_min = m.act_max && m.act_min = 4 * (period / 2) && m.idl_min >= 4 * (period - (period / 2))
                   && m.setup > 0 && m.hold > 0 && marg >= 0 && m.mosi_wrong_phase = 0 && m.sample_after = [ 3 ] in
          if not ok then all := false;
          pr "%-12s %4d %6.0f kHz | %-6s %3d/%-5d %3d/%-3d | %-11s | %4d (%3.0f%%) | %3d/%-5d | %d, %s%s\n" (Fw.spi_mode_name mode) period
            (Fw.clock_hz /. float (4 * period) /. 1000.)
            (if per_ok then string_of_int (4 * period) else "VARIES") m.act_min m.idl_min m.setup m.hold
            (String.concat "," (List.map string_of_int m.sample_after)) marg
            (100. *. float marg /. float (4 * period))
            m.cs_setup m.cs_hold (m.mism + m2.mism) (if m.ok && m2.ok then "ok" else "WRONG") (if ok then "" else "  FAIL")) (periods_for mode)) modes;
  pr "\nColumns: SCLK = the clock rate (60 MHz / 4P); period = sampling edge to sampling edge within\n";
  pr "a byte (between bytes SCLK idles 3 slots longer); act/idle = the shortest active and idle phase;\n";
  pr "MOSI su/hold = the least time MOSI is stable before and after a sampling edge, on the trace;\n";
  pr "MISO sample after edge = clocks from the sampling edge appearing on the bus to the SHI that\n";
  pr "samples MISO; MISO margin = the longest delay of the peer's MISO after its shift edge that the\n";
  pr "controller still reads correctly, clocks and %% of the period; CS su/hold = CS fall to the first\n";
  pr "edge, last edge to CS rise; lockstep = clocks where interpreter and RTL differ (2 runs, 4 bytes\n";
  pr "each way); data ok = the peer received the bytes sent and the controller reported the peer's.\n";
  pr "Bench timing: the core reads the bus one clock after it drives it. Every row also checks\n";
  pr "that MOSI changes only in the phase where the mode does not sample (CPHA 0: SCLK idle,\n";
  pr "CPHA 1: SCLK active) and that MISO is sampled 3 clocks after the sampling edge.\n";
  pr "\nPage sizes (4 bytes, constant): %s\n"
    (String.concat ", " (List.map (fun m -> Printf.sprintf "%s %d" (Fw.spi_mode_name m)
                                     (snd (Fw.spi_ctl ~sclk ~mosi ~miso ~cs ~mode:m ~period:10 [ 1; 2; 3; 4 ]))) modes));
  (* controls *)
  pr "\nControls (each must fail the check named):\n";
  let ctl name ok = pr "  %-78s %s\n" name (if ok then "CAUGHT" else "MISSED"); if not ok then all := false in
  (* Sampling one slot after the shift edge instead of the sampling edge is a race with the
     target's output: against a target whose MISO follows its shift at once it reads the next bit
     in CPHA 0, and against one 8 clocks late it reads the previous bit in CPHA 1 (with no delay
     the CPHA 1 target holds the bit from the leading edge to the next, so the wrong edge reads
     the right bit). The correct firmware reads right at both delays (the margin column). *)
  List.iter (fun mode ->
      let delay = if mode.Fw.cpha = 0 then 0 else 8 in
      let c = run ~fault:Fw.Sample_on_shift_edge ~delay ~mode ~period:15 ~seed:3 () in
      let good = run ~delay ~mode ~period:15 ~seed:3 () in
      ctl (Printf.sprintf "%s: MISO sampled after the shift edge, peer %d clocks (wrong bytes; %d clocks after edge)"
             (Fw.spi_mode_name mode) delay (match c.sample_after with x :: _ -> x | [] -> -1))
        (c.got <> c.replies && good.got = good.replies && c.sample_after <> [ 3 ])) modes;
  let mode0 = List.hd modes in
  let c = run ~fault:Fw.No_branch_balance ~mode:mode0 ~period:15 ~seed:4 () in
  ctl (Printf.sprintf "mode 0: the MOSI = 0 path one slot short (sampling period varies: %s)"
         (String.concat "," (List.map string_of_int (List.sort_uniq compare c.periods))))
    (List.exists (fun p -> p <> 60) c.periods);
  (* A mode 0 controller and a mode 1 target exchange the right bytes when the target has no
     output delay (MOSI is held past the trailing edge, MISO sampled just after the leading one),
     so the mode is checked by timing: firmware built for one CPHA, judged as the other. *)
  let c = run ~image:(List.nth modes 2) ~mode:mode0 ~period:15 ~seed:5 () in
  ctl (Printf.sprintf "mode 1 firmware judged as mode 0 (%d MOSI changes in the sampling phase)" c.mosi_wrong_phase) (c.mosi_wrong_phase > 0);
  let c = run ~image:mode0 ~mode:(List.nth modes 2) ~period:15 ~seed:5 () in
  ctl (Printf.sprintf "mode 0 firmware judged as mode 1 (%d MOSI changes in the sampling phase)" c.mosi_wrong_phase) (c.mosi_wrong_phase > 0);
  let c = run ~image:(List.nth modes 4) ~mode:mode0 ~period:15 ~seed:5 () in
  ctl "mode 2 firmware against a mode 0 peer (data wrong)" (not c.ok);
  let c = run ~peer:{ Peers.Spi.cpol = 0; cpha = 0; msb = false } ~mode:mode0 ~period:15 ~seed:6 () in
  ctl "msb-first controller against an lsb-first peer (data wrong)" (not c.ok);
  let marg = margin ~mode:mode0 ~period:15 in
  let c = run ~delay:(marg + 1) ~mode:mode0 ~period:15 ~seed:1 () in
  ctl (Printf.sprintf "mode 0, P 15: the peer's MISO %d clocks late, one past the margin (read wrongly)" (marg + 1)) (c.got <> c.replies);
  let c = run ~bug:Sequencer2.Waitd_early ~mode:mode0 ~period:15 ~seed:1 () in
  ctl (Printf.sprintf "lockstep: RTL mutant \"WAITD leaves at dl = 1\" (%d clocks differ)" c.mism) (c.mism > 0);
  pr "\nSPI controller: %s\n" (if !all then "PASS" else "FAIL");
  !all

(* traces for tools/sigrok-judge: every mode and order at 1 MHz (P = 15), and mode 0 and 3 at the
   fastest period *)
let dump dir =
  let ints l = String.concat "," (List.map string_of_int l) in
  List.iter (fun (mode, period) ->
      let m = run ~mode ~period ~seed:7 () in
      Bench.dump_trace ~dir ~stem:(Printf.sprintf "spi-ctl-m%d%s-p%d" (2 * mode.Fw.cpol + mode.cpha) (if mode.msb then "msb" else "lsb") period) m.tr
        [ ("judge", "spi"); ("spi_sclk", string_of_int sclk); ("spi_mosi", string_of_int mosi); ("spi_miso", string_of_int miso);
          ("spi_cs", string_of_int cs); ("spi_cpol", string_of_int mode.cpol); ("spi_cpha", string_of_int mode.cpha);
          ("spi_bitorder", if mode.msb then "msb-first" else "lsb-first"); ("spi_period_cycles", string_of_int (4 * period));
          ("spi_bytes", ints m.sent); ("spi_miso_bytes", ints m.got);
          ("# MOSI: the bytes the controller sent; MISO: the bytes it reported to the host", "") ])
    (List.map (fun m -> (m, 15)) modes @ [ (List.hd modes, 10); (List.nth modes 6, 10) ]);
  true
