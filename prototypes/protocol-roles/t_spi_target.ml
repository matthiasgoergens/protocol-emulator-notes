(* Task 5: SPI target in modes 0-3, msb and lsb first, and the fastest SCLK it follows at 60 MHz.

   The controller is the peer of peers.ml: SCLK with given active and idle times in clocks, MOSI
   changed on the shift edge, MISO read exactly at the sampling edge (in the clock the controller
   drives it, so no time is allowed after the edge). The target runs on the interpreter and the
   RTL in lockstep. Checked: the controller reads the bytes the host gave the target (0xFF when the
   host had none ready), the host gets the bytes the controller sent and the end of each
   transaction. The fastest SCLK is searched with the controller's edges at 12 phases against the
   core clock: a speed counts only if every phase is right, and every slower speed too. *)

let pr = Printf.printf
let sclk = 0 and mosi = 1 and miso = 2 and cs = 3

let modes = T_spi.modes
let pm (m : Fw.spi_mode) = { Peers.Spi.cpol = m.cpol; cpha = m.cpha; msb = m.msb }

type run = { r : Bench.result; c : Peers.Spi.controller; outs : (int * int) list; ok : bool; got : int list; sent : int list;
             replies : int list; words : int; miso_setup : int;
             miso_wrong_phase : int }   (* MISO changes, CS low, while SCLK is in the phase where the mode samples *)

let run ?bug ?(rtl = true) ?(phase = 0) ?(gap = 0) ?(css = 200) ?(csh = 40) ?(host_at = 0) ?(nbytes = 4) ?image ~mode ~act ~idl ~seed () =
  let rng = Random.State.make [| seed; act; idl |] in
  let sent = List.init nbytes (fun _ -> Random.State.int rng 256) in
  let replies = List.init nbytes (fun _ -> Random.State.int rng 256) in
  (* [image]: the firmware built for that mode while the controller and the checks use [mode] *)
  let page, words = Fw.spi_target ~sclk ~mosi ~miso ~cs ~mode:(Option.value image ~default:mode) () in
  let c = Peers.Spi.controller ~start:(300 + phase) ~gap ~mode:(pm mode) ~act ~idl ~css ~csh sent in
  let n = 300 + phase + css + (nbytes * (8 * (act + idl) + gap)) + csh + 2000 in
  let lv = Array.make (n + 2) 0 in   (* bit 0 sclk, 1 mosi, 2 miso, 3 cs per clock, for the set-up *)
  let world ~clock ~pin_out ~pin_oe =
    let m = if (pin_oe lsr miso) land 1 = 1 then (pin_out lsr miso) land 1 else 1 in
    let s, o, q = Peers.Spi.controller_step c ~miso:m in
    if clock + 1 < Array.length lv then lv.(clock + 1) <- s lor (o lsl 1) lor (m lsl 2) lor (q lsl 3);
    (* MISO as the line is (the target does not read it; the trace for sigrok does) *)
    0xF0 lor (s lsl sclk) lor (o lsl mosi) lor (m lsl miso) lor (q lsl cs) in
  let h = Bench.host [] in
  List.iter (fun b -> Bench.push_host h ~at:host_at b) replies;
  let r = Bench.run ?bug ~rtl ~pages:[| Some page; None; None; None |] ~clocks:n ~world h in
  let got = List.rev c.rx in
  let outs = List.map (fun (_, t, b) -> (t, b)) r.outs in
  let expect_replies = if host_at = 0 then replies else got in
  let ok = r.mismatches = 0 && got = expect_replies && outs = List.map (fun b -> (0, b)) sent @ [ (1, 0) ] in
  (* MISO set-up: from MISO's last change to each sampling edge the controller makes, in the
     clocks the controller sees (lv is the line one clock late) *)
  let sampling = if mode.cpha = 0 then 1 - mode.cpol else mode.cpol in
  let edges = List.filter (fun i -> i > 0 && lv.(i) land 1 = sampling && lv.(i - 1) land 1 <> sampling && (lv.(i) lsr 3) land 1 = 0)
      (List.init (n + 1) Fun.id) in
  let changes = List.filter (fun i -> i > 0 && (lv.(i) lsr 2) land 1 <> (lv.(i - 1) lsr 2) land 1) (List.init (n + 1) Fun.id) in
  let su = List.map (fun e -> e - List.fold_left (fun a x -> if x <= e then x else a) 0 changes) edges in
  (* CPHA 0 samples on the leading edge, so MISO may change only while SCLK idles; CPHA 1 only
     while it is active (the first change, at CS fall, excepted) *)
  let change_level = if mode.cpha = 0 then mode.cpol else 1 - mode.cpol in
  let wrong = List.filter (fun i -> (lv.(i) lsr 3) land 1 = 0 && (lv.(i - 1) lsr 3) land 1 = 0 && lv.(i) land 1 <> change_level) changes in
  { r; c; outs; ok; got; sent; replies; words; miso_setup = List.fold_left min max_int su; miso_wrong_phase = List.length wrong }

(* Every alignment: the controller's phase against the core clock (12 values), and, with gaps
   between bytes, the gap itself over 12 consecutive values: the next byte's first leading edge
   then falls at every point of the target's 3-slot poll between bytes, which a fixed gap does
   not do (with a fixed gap only 4 of the 12 alignments occur). *)
let all_phases ?gap ~mode ~act ~idl () =
  match gap with
  | None -> List.for_all (fun ph -> (run ~rtl:false ~phase:ph ~mode ~act ~idl ~seed:ph ()).ok) (List.init 12 Fun.id)
  | Some g ->
    List.for_all (fun dg -> List.for_all (fun ph -> (run ~rtl:false ~phase:ph ~gap:(g + dg) ~mode ~act ~idl ~seed:(ph + dg) ()).ok)
                      [ 0; 1; 2; 3 ]) (List.init 12 Fun.id)

(* the least half period (act = idl, clocks) at which every phase is right, and every longer one
   up to 60 *)
let fastest ?gap ~mode () =
  let rec go h = if h < 4 then h + 1 else if all_phases ?gap ~mode ~act:h ~idl:h () then go (h - 1) else h + 1 in
  go 60

let run_all () =
  pr "== Task 5: SPI target, modes 0-3, msb and lsb first, 60 MHz core clock\n";
  pr "The peer controller (peers.ml) sends 4 random bytes; the target answers with the host's 4 bytes.\n\n";
  let all = ref true in
  pr "Standard rates, interpreter and RTL in lockstep, 2 runs each:\n";
  List.iter (fun mode ->
      let row = List.map (fun (khz, h) ->
          let a = run ~mode ~act:h ~idl:h ~seed:1 () and b = run ~mode ~act:h ~idl:(h + 1) ~seed:2 ~phase:3 () in
          let ok = a.ok && b.ok && a.miso_wrong_phase = 0 && b.miso_wrong_phase = 0 in
          if not ok then all := false;
          Printf.sprintf "%d kHz %s (lockstep %d)" khz (if ok then "ok" else "WRONG") (a.r.mismatches + b.r.mismatches))
          [ (100, 300); (500, 60); (1000, 30) ] in
      pr "  %-12s %s; page %d words\n" (Fw.spi_mode_name mode) (String.concat ", " row)
        (snd (Fw.spi_target ~sclk ~mosi ~miso ~cs ~mode ()))) modes;
  pr "\nThe fastest SCLK it follows (half periods act = idle, in clocks; 4 bytes; back to back: 12 phases;\n";
  pr "with gaps: 40 to 51 clocks between bytes, 4 phases each):\n";
  pr "  %-12s %-34s %-34s\n" "" "bytes back to back" "40 to 51 clocks between bytes";
  List.iter (fun mode ->
      let h0 = fastest ~mode () and h1 = fastest ~gap:40 ~mode () in
      let f h = Fw.clock_hz /. float (2 * h) /. 1e6 in
      let s0 = (run ~rtl:true ~mode ~act:h0 ~idl:h0 ~seed:5 ()).miso_setup and s1 = (run ~rtl:true ~gap:40 ~mode ~act:h1 ~idl:h1 ~seed:5 ()).miso_setup in
      pr "  %-12s half %2d clocks, %.2f MHz (MISO set-up %d) half %2d clocks, %.2f MHz (MISO set-up %d)\n" (Fw.spi_mode_name mode)
        h0 (f h0) s0 h1 (f h1) s1) modes;
  pr "  (MISO set-up: the least number of clocks between MISO's last change and a sampling edge, at that speed)\n";
  (* why: one clock below the limit *)
  pr "\nWhy, one clock faster (mode 0 msb, bytes back to back): ";
  let m0 = List.hd modes in
  let h0 = fastest ~mode:m0 () in
  let bad = List.filter (fun ph -> not (run ~rtl:false ~phase:ph ~mode:m0 ~act:(h0 - 1) ~idl:(h0 - 1) ~seed:ph ()).ok) (List.init 12 Fun.id) in
  pr "%d of 12 phases wrong at half %d clocks\n" (List.length bad) (h0 - 1);
  let hex l = String.concat " " (List.map (Printf.sprintf "%02x") l) in
  let explain ?gap h ph =
    let x = run ~rtl:false ?gap ~phase:ph ~mode:m0 ~act:h ~idl:h ~seed:ph () in
    pr "    phase %d: the controller read %s (the target sent %s): MISO %s; the host got %s (sent %s): MOSI %s\n" ph
      (hex x.got) (hex x.replies) (if x.got = x.replies then "right" else "WRONG")
      (hex (List.filter_map (fun (t, b) -> if t = 0 then Some b else None) x.outs)) (hex x.sent)
      (if List.filter_map (fun (t, b) -> if t = 0 then Some b else None) x.outs = x.sent then "right" else "WRONG") in
  List.iter (explain (h0 - 1)) (List.filteri (fun i _ -> i < 2) bad);
  List.iter (fun mode ->
      let h1 = fastest ~gap:40 ~mode () in
      let runs = List.concat_map (fun dg -> List.map (fun ph -> (dg, ph)) [ 0; 1; 2; 3 ]) (List.init 12 Fun.id) in
      let bad1 = List.filter (fun (dg, ph) -> not (run ~rtl:false ~gap:(40 + dg) ~phase:ph ~mode ~act:(h1 - 1) ~idl:(h1 - 1) ~seed:(ph + dg) ()).ok) runs in
      pr "  %s with gaps, at half %d clocks: %d of 48 runs wrong; the bits wrong:" (Fw.spi_mode_name mode) (h1 - 1) (List.length bad1);
      let first_bit = if mode.Fw.msb then 0x80 else 0x01 in
      let masks = List.sort_uniq compare (List.concat_map (fun (dg, ph) ->
          let x = run ~rtl:false ~gap:(40 + dg) ~phase:ph ~mode ~act:(h1 - 1) ~idl:(h1 - 1) ~seed:(ph + dg) () in
          List.filter (fun m -> m <> 0) (List.map2 ( lxor ) x.got x.replies)) bad1) in
      pr " %s (%s)\n" (String.concat " " (List.map (Printf.sprintf "%02x") masks))
        (if List.for_all (fun m -> m = first_bit) masks then "only the first bit of a byte" else "not only the first bit"))
    [ m0; List.nth modes 2 ];
  (* controls *)
  pr "\nControls (each must fail the check named):\n";
  let ctl name ok = pr "  %-84s %s\n" name (if ok then "CAUGHT" else "MISSED"); if not ok then all := false in
  let x = run ~mode:m0 ~act:30 ~idl:30 ~seed:7 ~host_at:1_000_000 () in
  ctl (Printf.sprintf "host has no data ready: the controller reads 0xFF (read %s)" (String.concat " " (List.map (Printf.sprintf "%02x") x.got)))
    (x.got = List.init 4 (fun _ -> 0xFF));
  (* a mode 0 target against a mode 1 controller, and an msb target against an lsb controller *)
  let mismatch name target_mode ctl_mode =
    let rng_seed = 9 in
    let rng = Random.State.make [| rng_seed; 30; 30 |] in
    let sent = List.init 4 (fun _ -> Random.State.int rng 256) in
    let page, _ = Fw.spi_target ~sclk ~mosi ~miso ~cs ~mode:target_mode () in
    let c = Peers.Spi.controller ~start:300 ~mode:(pm ctl_mode) ~act:30 ~idl:30 ~css:200 ~csh:40 sent in
    let world ~clock:_ ~pin_out ~pin_oe =
      let m = if (pin_oe lsr miso) land 1 = 1 then (pin_out lsr miso) land 1 else 1 in
      let s, o, q = Peers.Spi.controller_step c ~miso:m in
      0xF0 lor (s lsl sclk) lor (o lsl mosi) lor (1 lsl miso) lor (q lsl cs) in
    let h = Bench.host [ 1; 2; 3; 4 ] in
    let r = Bench.run ~rtl:false ~pages:[| Some page; None; None; None |] ~clocks:3000 ~world h in
    let outs = List.map (fun (_, _, b) -> b) (List.filter (fun (_, t, _) -> t = 0) r.outs) in
    ctl name (outs <> sent || List.rev c.rx <> [ 1; 2; 3; 4 ]) in
  (* as for the controller, the data alone does not tell CPHA apart at these speeds, so the
     phase in which MISO changes does *)
  let x = run ~image:(List.nth modes 2) ~mode:m0 ~act:30 ~idl:30 ~seed:10 () in
  ctl (Printf.sprintf "mode 1 firmware judged as mode 0: %d MISO changes in the sampling phase" x.miso_wrong_phase) (x.miso_wrong_phase > 0);
  let x = run ~image:m0 ~mode:(List.nth modes 2) ~act:30 ~idl:30 ~seed:10 () in
  ctl (Printf.sprintf "mode 0 firmware judged as mode 1: %d MISO changes in the sampling phase" x.miso_wrong_phase) (x.miso_wrong_phase > 0);
  mismatch "mode 3 target, mode 2 controller (data wrong)" (List.nth modes 6) (List.nth modes 4);
  mismatch "msb-first target, lsb-first controller (data wrong)" m0 (List.nth modes 1);
  let x = run ~mode:m0 ~act:(h0 - 1) ~idl:(h0 - 1) ~seed:(List.hd bad) ~phase:(List.hd bad) () in
  ctl (Printf.sprintf "one clock past the limit, phase %d: wrong" (List.hd bad)) (not x.ok);
  let x = run ~bug:Sequencer2.Waitc_host_inverted ~mode:m0 ~act:30 ~idl:30 ~seed:1 () in
  ctl (Printf.sprintf "lockstep: RTL bug \"WAITC 9 inverted\" (%d clocks differ)" x.r.mismatches) (x.r.mismatches > 0);
  pr "\nSPI target: %s\n" (if !all then "PASS" else "FAIL");
  !all

(* traces for tools/sigrok-judge: every mode and order at 1 MHz *)
let dump dir =
  let ints l = String.concat "," (List.map string_of_int l) in
  List.iter (fun mode ->
      let x = run ~mode ~act:30 ~idl:30 ~seed:11 () in
      Bench.dump_trace ~dir ~stem:(Printf.sprintf "spi-target-m%d%s" (2 * mode.Fw.cpol + mode.cpha) (if mode.msb then "msb" else "lsb")) x.r
        [ ("judge", "spi"); ("spi_sclk", string_of_int sclk); ("spi_mosi", string_of_int mosi); ("spi_miso", string_of_int miso);
          ("spi_cs", string_of_int cs); ("spi_cpol", string_of_int mode.cpol); ("spi_cpha", string_of_int mode.cpha);
          ("spi_bitorder", if mode.msb then "msb-first" else "lsb-first"); ("spi_period_cycles", "60");
          ("spi_bytes", ints x.sent); ("spi_miso_bytes", ints x.got);
          ("# MOSI: the bytes the controller sent; MISO: the bytes the target sent (the host's)", "") ]) modes;
  true
