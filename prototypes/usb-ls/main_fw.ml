(* Low-speed USB as firmware on the deadline sequencer.
   1. The ISA variant: interpreter against RTL on random programmes.
   2. The CRC assist: model against RTL on random stimulus and three configurations.
   3. The bit layer (T0) on the ORIGINAL sequencer, interpreter and RTL, decoding random packets
      from the host model with the host clock off by up to 1.5 %.
   4. The whole device (T0-T2, CRC assist, controller) on the variant, interpreter and RTL in
      lockstep: directed enumeration and reports, constrained random sessions, and controls that
      must fail.
   5. The reply path's timing budget, clock by clock. *)
open Hardcaml

let ok = ref true
let check name c = Printf.printf "  %-60s %s\n" name (if c then "ok" else "FAIL"); if not c then ok := false

(* ---------- 1. ISA variant lockstep ---------- *)
let isa_lockstep ~seed ~cycles =
  Random.init seed;
  let mem = Array.init Isa_ls.n_threads (fun _ -> Array.init Isa_ls.prog_len (fun _ ->
      (* bias towards the new and the branching instructions, and short deadlines *)
      let w = Random.int 0x10000 in
      match Random.int 6 with
      | 0 -> (0xE lsl 12) lor (w land 0x1FF)
      | 1 -> (0x7 lsl 12) lor (w land 0xFFF)
      | 2 -> (0xB lsl 12) lor (w land 0x1FF)
      | 3 -> (0x3 lsl 12) lor (w land 0x1F)
      | _ -> w)) in
  let sim = Cyclesim.create (Sequencer_ls.circuit ()) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  let clear = i "clear" in
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  let cur = ref 0 and pend = ref (Bits.to_int !(o "imem_addr")) in
  let st = Isa_ls.init () in
  let mism = ref 0 in
  for _ = 1 to cycles do
    let pin_in = Random.int 256 and host_in = Random.int 256 and host_in_valid = Random.bool () in
    let eff = Isa_ls.step st ~mem ~pin_in ~host_in ~host_in_valid in
    (i "imem_data") := Bits.of_int ~width:16 mem.(!cur lsr Isa_ls.pc_bits).(!cur land 255);
    (i "pin_in") := Bits.of_int ~width:8 pin_in; (i "host_in") := Bits.of_int ~width:8 host_in;
    (i "host_in_valid") := Bits.of_int ~width:1 (if host_in_valid then 1 else 0);
    Cyclesim.cycle sim;
    cur := !pend; pend := Bits.to_int !(o "imem_addr");
    let ho = if Bits.to_int !(o "host_out_valid") = 1 then Some (Bits.to_int !(o "host_out"), Bits.to_int !(o "host_out_tag") = 1) else None in
    let pcs = let v = Bits.to_int !(o "pcs") in List.init 4 (fun t -> (v lsr (8 * t)) land 255) in
    if not (Bits.to_int !(o "pin_out") = st.pin_out && Bits.to_int !(o "pin_oe") = st.pin_oe && ho = eff.host_out
            && (Bits.to_int !(o "host_in_ready") = 1) = eff.host_in_ready && pcs = Array.to_list st.pcs) then incr mism
  done;
  !mism

(* ---------- 2. CRC assist lockstep ---------- *)
let crc_lockstep ?(prog = false) cfg ~seed ~cycles =
  Random.init seed;
  let circ =
    let open Signal in
    let clock = input "clock" 1 and clear = input "clear" 1 in
    let en = input "en" 1 and frame = input "frame" 1 and stb = input "stb" 1 and value = input "value" 1 in
    let c w x = of_int ~width:w x in
    let ok =
      if prog then
        (* the programmable unit, its configuration inputs driven with this configuration *)
        Crc_unit.create_prog ~clock ~clear ~poly:(c 16 cfg.Crc_unit.poly) ~init:(c 16 cfg.init) ~check:(c 16 cfg.check)
          ~mask:(c 16 ((1 lsl cfg.width) - 1)) ~top:(c 4 (cfg.width - 1)) ~skip_n:(c 5 cfg.skip)
          ~msb_first:(if cfg.msb_first then vdd else gnd) ~en ~frame ~stb ~value
      else Crc_unit.create ~cfg ~clock ~clear ~en ~frame ~stb ~value in
    Circuit.create_exn ~name:"crc" [ output "ok" ok ] in
  let sim = Cyclesim.create circ in
  let i n = Cyclesim.in_port sim n in
  let m = Crc_unit.Model.create cfg in
  let mism = ref 0 and oks = ref 0 in
  (i "clear") := Bits.vdd; Cyclesim.cycle sim; (i "clear") := Bits.gnd;
  let en = ref 0 in
  for _ = 1 to cycles do
    if Random.int 200 = 0 then en := 1 - !en;
    let frame = if Random.int 50 = 0 then 0 else 1 and stb = Random.int 2 and value = Random.int 2 in
    List.iter2 (fun n v -> (i n) := Bits.of_int ~width:1 v) [ "en"; "frame"; "stb"; "value" ] [ !en; frame; stb; value ];
    let before = Crc_unit.Model.ok m in
    Cyclesim.cycle sim;
    Crc_unit.Model.step m ~en:!en ~frame ~stb ~value;
    ignore before;
    let rtl_ok = Bits.to_int !(Cyclesim.out_port sim "ok") = 1 in
    if rtl_ok <> Crc_unit.Model.ok m then incr mism;
    if rtl_ok then incr oks
  done;
  !mism, !oks

(* the model on real USB data packets: a good packet leaves the residue, a corrupted one not *)
let crc_on_packets () =
  let feed bytes_after_pid =
    let m = Crc_unit.Model.create { Crc_unit.usb_crc16 with skip = 0 } in
    Crc_unit.Model.step m ~en:0 ~frame:1 ~stb:0 ~value:0;
    List.iter (fun byte -> for k = 0 to 7 do
        Crc_unit.Model.step m ~en:1 ~frame:1 ~stb:0 ~value:0;
        Crc_unit.Model.step m ~en:1 ~frame:1 ~stb:1 ~value:((byte lsr k) land 1) done) bytes_after_pid;
    Crc_unit.Model.ok m in
  let good = List.tl (Ls_host.data_packet Ls_host.pid_data0 [ 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00 ]) in
  let bad = List.tl (Ls_host.data_packet ~corrupt_crc:true Ls_host.pid_data0 [ 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00 ]) in
  feed good && not (feed bad) && feed (List.tl (Ls_host.data_packet Ls_host.pid_data1 []))

(* ---------- 3. T0 on the original sequencer ---------- *)
let t0_stock ?ppm ~seed ~packets () =
  let rng = Random.State.make [| seed |] in
  let ppm = match ppm with Some p -> p | None -> Random.State.int rng 30001 - 15000 in
  let cfg = { Firmware.t0_default with stock_events = true } in
  let p0 = Asm.assemble ~size:Isa.prog_len ~fill:Isa.halt (Firmware.t0 ~cfg ()) in
  let mem = Array.init Isa.n_threads (fun t -> if t = 0 then Array.copy p0.words else Array.make Isa.prog_len Isa.halt) in
  let rtl = Harness.make mem in
  let st = Isa.init () in
  (* the pad and synchroniser model around each: pin_in = two flops of (oe ? out : external) *)
  let sync_m = [| 0; 0 |] and sync_r = [| 0; 0 |] in
  let rtl_pins = ref (0, 0) in
  let mism = ref 0 and now = ref 0 in
  let decoded = ref [] and cur = ref [] and prev_stb = ref 0 and events = ref [] in
  let clock line =
    let dp, dm = Ls_host.phy line in
    let ext = dp lor (dm lsl 1) in
    let raw po poe = (poe land po) lor (lnot poe land ext) land 0xFF in
    let pin_m = sync_m.(1) and pin_r = sync_r.(1) in
    let raw_m = raw st.pin_out st.pin_oe and raw_r = raw (fst !rtl_pins) (snd !rtl_pins) in
    let eff = Isa.step st ~mem ~pin_in:pin_m ~host_in:0 ~host_in_valid:false in
    let o = Harness.cycle rtl ~pin_in:pin_r ~host_in:0 ~host_in_valid:false in
    rtl_pins := (o.pin_out, o.pin_oe);
    sync_m.(1) <- sync_m.(0); sync_m.(0) <- raw_m; sync_r.(1) <- sync_r.(0); sync_r.(0) <- raw_r;
    if o.pin_out <> st.pin_out || o.pin_oe <> st.pin_oe || o.host_out <> eff.host_out || o.pcs <> Array.to_list st.pcs then incr mism;
    (match eff.host_out with Some e -> events := e :: !events | None -> ());
    (* the published bits: VALUE at each rising STB; BUSY low with the strobe ends a packet *)
    let stb = (st.pin_out lsr Fw_sys.p_stb) land 1 in
    if stb = 1 && !prev_stb = 0 then begin
      if (st.pin_out lsr Fw_sys.p_idle) land 1 = 0 then cur := ((st.pin_out lsr Fw_sys.p_value) land 1) :: !cur
      else begin
        (* an end of packet with no bits is a keep-alive or a reset *)
        if !cur <> [] then decoded := (List.rev !cur, (st.pin_out lsr Fw_sys.p_value) land 1) :: !decoded;
        cur := []
      end
    end;
    prev_stb := stb;
    incr now in
  let send states =
    let sched, fin = Ls_host.schedule ~ppm ~start:!now states in
    let n = Array.length sched in
    Array.iteri (fun k (c0, s) -> let c1 = if k + 1 < n then fst sched.(k + 1) else fin in for _ = c0 to c1 - 1 do clock s done) sched in
  let idle n = for _ = 1 to n do clock Ls_host.J done in
  idle 200;
  let sent = ref [] in
  for _ = 1 to packets do
    let len = 1 + Random.State.int rng 11 in
    let bytes = List.init len (fun _ -> match Random.State.int rng 8 with
        | 0 | 1 -> 0xFF | 2 -> 0x00 | 3 -> 0x55 | 4 -> 0xAA | 5 -> [| 0x7F; 0xFE; 0x3F; 0xFC |].(Random.State.int rng 4)
        | _ -> Random.State.int rng 256) in
    sent := bytes :: !sent;
    send (Ls_host.encode bytes);
    idle (80 + Random.State.int rng 400 + Random.State.int rng 40);
    if Random.State.int rng 4 = 0 then (send Ls_host.keep_alive; idle (80 + Random.State.int rng 200))
  done;
  (* one bus reset: SE0 for 20 us *)
  for _ = 1 to 1200 do clock Ls_host.SE0 done;
  idle 400;
  let to_bytes bits =
    let n = List.length bits / 8 in
    (List.length bits mod 8 = 0, List.init n (fun k -> List.fold_left (fun acc i -> acc lor (List.nth bits (8 * k + i) lsl i)) 0 (List.init 8 Fun.id))) in
  (* the sync is published too: zeros up to its final one *)
  let rec strip = function 0 :: r -> strip r | 1 :: r -> r | [] -> [] | _ -> [] in
  let got = List.rev_map (fun (bits, abort) -> (abort, to_bytes (strip bits))) !decoded in
  let want = List.rev !sent in
  if Sys.getenv_opt "T0DEBUG" <> None then begin
    let hex l = String.concat " " (List.map (Printf.sprintf "%02x") l) in
    List.iteri (fun k w -> Printf.printf "    sent %s\n" (hex w);
      match List.nth_opt got k with Some (ab, (wh, bs)) -> Printf.printf "    got  %s%s%s\n" (hex bs) (if wh then "" else " (partial)") (if ab = 1 then " ABORT" else "") | None -> ()) want
  end;
  let good = List.length got = List.length want
             && List.for_all2 (fun (abort, (whole, bs)) w -> abort = 0 && whole && bs = w) got want in
  let resets = List.length (List.filter (fun e -> e = Firmware.ev_reset) !events) in
  ppm, p0.used, good, List.length got, !mism, !now, resets

(* ---------- 4. the device ---------- *)
let fw_directed ?(verbose = false) ~ppm ?t0cfg ?t12cfg ?jk_swap ?latency name =
  let dut, a, _ = Dut_fw.make ~name ?t0cfg ?t12cfg ?jk_swap ?latency () in
  let b = Bench.create ~verbose ~ppm dut in
  Scenario.directed b ~addr:42;
  b, a

(* ---------- 5. the reply path, clock by clock ---------- *)
(* One IN (data queued) and one SETUP at the exact host clock: the clocks, from the start of the
   host's EOP (its first SE0 clock), at which each stage of the reply happens. *)
let budget () =
  let events = ref [] in
  let mark name c = if not (List.mem_assoc name !events) then events := (name, c) :: !events in
  let armed = ref false and se0_at = ref 0 and prev_line = ref (0, 1) and prev_out = ref 0 and prev_oe = ref 0 in
  let t1_decided = ref false in
  let trace cyc ~dp ~dm (m : Fw_sys.Model.t) (sys : Dut_fw.sys) =
    let po = m.st.pin_out and poe = m.st.pin_oe in
    if !armed then begin
      if (dp, dm) = (0, 0) && !prev_line <> (0, 0) && !se0_at = 0 then se0_at := cyc;
      let rel = cyc - !se0_at in
      if !se0_at > 0 then begin
        if (dp, dm) = (0, 1) && !prev_line = (0, 0) then mark "host EOP: SE0 to J (turnaround reference)" rel;
        if (po lsr Fw_sys.p_idle) land 1 = 1 && (!prev_out lsr Fw_sys.p_idle) land 1 = 0 then mark "T0 raises IDLE (end of packet seen)" rel;
        if (po lsr Fw_sys.p_stb) land 1 = 1 && (!prev_out lsr Fw_sys.p_stb) land 1 = 0 && (po lsr Fw_sys.p_idle) land 1 = 1 then mark "T0 end-of-packet strobe" rel;
        let pc1 = m.st.pcs.(1) and pc2 = m.st.pcs.(2) in
        let at1 l = pc1 = Asm.addr sys.img.p1 l and at2 l = pc2 = Asm.addr sys.img.p2 l in
        if not !t1_decided && (at1 "p_ep0_rdy" || at1 "p_ep1_rdy" || at1 "nr0" || at1 "nr1") then (t1_decided := true; mark "T1 reply chosen (token and RDY checked)" rel);
        if at2 "p_hs" then mark "T2 reply chosen (CRC checked)" rel;
        if poe land 3 <> 0 && !prev_oe land 3 = 0 then mark "device drives J" rel;
        if poe land 3 <> 0 && po land 3 = 1 then mark "device's first K (SOP)" rel
      end
    end;
    prev_line := (dp, dm); prev_out := po; prev_oe := poe in
  let dut, _, _ = Dut_fw.make ~name:"budget" ~trace () in
  let b = Bench.create ~ppm:0 dut in
  let run name f =
    events := []; se0_at := 0; t1_decided := false;
    f b;
    let evs = List.sort (fun (_, a) (_, c) -> compare a c) !events in
    Printf.printf "  %s (clocks from the first SE0 clock of the host's EOP; 40 clocks = 1 bit):\n" name;
    List.iter (fun (n, c) -> Printf.printf "    %4d  %s\n" c n) evs in
  Bench.idle b 200;
  (* SETUP: arm at the data packet *)
  Bench.send b (Ls_host.token Ls_host.pid_setup ~addr:0 ~ep:0); Bench.idle_bits b 3.0;
  armed := true;
  run "SETUP data, answered ACK by T2" (fun b ->
      Bench.send b (Ls_host.data_packet Ls_host.pid_data0 (Bench.get_descriptor ~typ:1 ~len:18 ())); ignore (Bench.receive b));
  armed := false; Bench.idle_bits b 400.0;
  armed := true;
  run "IN token, answered with data from the FIFO by T1" (fun b ->
      Bench.send b (Ls_host.token Ls_host.pid_in ~addr:0 ~ep:0); ignore (Bench.receive b));
  armed := false

let report b =
  print_endline ("  " ^ Bench.summary b);
  List.iter (fun e -> print_endline ("    " ^ e)) (List.rev b.Bench.errors);
  b.Bench.errors = [] && b.dut.mismatches () = 0

let () =
  if Sys.getenv_opt "BUDGET" <> None then (budget (); exit 0);
  (match Sys.getenv_opt "T0DEBUG" with
   | Some sd -> let ppm, _, good, _, _, _, resets = t0_stock ~seed:(int_of_string sd) ~packets:40 () in
     Printf.printf "ppm %d good %b resets %d\n" ppm good resets; exit 0
   | None -> ());
  print_endline "== 1. ISA variant: interpreter against RTL, random programmes";
  let m = List.fold_left (fun acc seed -> acc + isa_lockstep ~seed ~cycles:4000) 0 (List.init 200 Fun.id) in
  check (Printf.sprintf "200 programmes x 4000 clocks: %d mismatching clocks" m) (m = 0);
  print_endline "== 2. CRC assist: model against RTL";
  List.iter (fun (name, cfg) ->
    let mm, oks = crc_lockstep cfg ~seed:3 ~cycles:200_000 in
    check (Printf.sprintf "%s: 200,000 clocks, %d mismatches (ok seen %d times)" name mm oks) (mm = 0);
    let mm, oks = crc_lockstep ~prog:true cfg ~seed:4 ~cycles:200_000 in
    check (Printf.sprintf "  same, programmable unit: %d mismatches (ok seen %d times)" mm oks) (mm = 0))
    [ "USB CRC16 (reflected)", Crc_unit.usb_crc16;
      "USB CRC5 (reflected)", { Crc_unit.width = 5; poly = 0x14; init = 0x1F; check = 0x06; skip = 0; msb_first = false };
      "CAN CRC15 (MSB first)", { Crc_unit.width = 15; poly = 0x4599; init = 0; check = 0; skip = 0; msb_first = true } ];
  check "USB CRC16 residue on a good packet, not on a corrupted one, and on a zero-length one" (crc_on_packets ());
  print_endline "== 3. bit layer (T0) on the ORIGINAL sequencer, interpreter and RTL";
  List.iteri (fun k ppm ->
    let seed = 100 + k in
    let ppm, used, good, n, mism, clocks, resets = t0_stock ~ppm ~seed ~packets:60 () in
    check (Printf.sprintf "host %+6d ppm: %d words, %d/60 packets bit-exact, %d reset, %d clocks, %d lockstep mismatches"
             ppm used (if good then n else 0) resets clocks mism) (good && mism = 0 && used <= 64 && resets = 1))
    [ -15000; -12500; -10000; -7500; -5000; -2500; 0; 2500; 5000; 7500; 10000; 12500; 15000 ];
  (* beyond the specification: where does the software DPLL stop working? *)
  let margin = List.map (fun ppm ->
      let ok = List.for_all (fun seed -> let _, _, good, _, _, _, _ = t0_stock ~ppm ~seed ~packets:60 () in good) [ 1; 2; 3 ] in
      Printf.sprintf "%+d%%:%s" (ppm / 10000) (if ok then "ok" else "FAIL"), ok)
      [ -60000; -50000; -40000; -30000; -20000; 20000; 30000; 40000; 50000; 60000 ] in
  Printf.printf "  beyond +-1.5 %% (3 x 60 packets each): %s\n" (String.concat " " (List.map fst margin));
  let img = Firmware.build () in
  Printf.printf "== programme sizes: T0 %d, T1 %d, T2 %d words (of 256 per thread; T0 fits the original 64)\n" img.p0.used img.p1.used img.p2.used;
  print_endline "== 4. the device, interpreter and RTL in lockstep: directed";
  let b, a = fw_directed ~verbose:true ~ppm:0 "firmware" in
  ok := report b && !ok;
  Printf.printf "  controller: %d programme patches, FIFO peak %d bytes\n" a.ctl.patches a.ctl.max_fifo;
  List.iter (fun ppm -> let b, _ = fw_directed ~ppm "firmware" in ok := report b && !ok) [ -15000; 15000 ];
  print_endline "== 4. constrained random sessions";
  let nseeds = try int_of_string Sys.argv.(1) with _ -> 8 in
  for seed = 1 to nseeds do
    let rng = Random.State.make [| seed; 77 |] in
    (* the first two seeds at the extremes of the tolerance, the rest anywhere in it *)
    let ppm = match seed with 1 -> -15000 | 2 -> 15000 | _ -> Random.State.int rng 30001 - 15000 in
    (* controller latency: seed 3 near the bound the design assumes (a token's event must
       reach the controller before the data packet ends, 1,280 clocks), so that the firmware
       has to NAK while the controller prepares *)
    let latency = if seed = 3 then 1100 else 20 + Random.State.int rng 600 in
    (* seed 4: a controller that takes 5,000 clocks to prepare each reply; the firmware NAKs *)
    let prepare = if seed = 4 then 5000 else 0 in
    let dut, _, _ = Dut_fw.make ~name:(Printf.sprintf "firmware(latency %d, prepare %d)" latency prepare) ~latency ~prepare () in
    let b = Bench.create ~seed ~ppm dut in
    Scenario.random_session b ~n:120;
    ok := report b && !ok
  done;
  (* beyond the specification, directed enumeration only *)
  let beyond = List.map (fun ppm ->
      let b, _ = fw_directed ~ppm "firmware" in
      Printf.sprintf "%+d%%:%s" (ppm / 10000) (if b.Bench.errors = [] then "ok" else "FAIL"))
      [ -40000; -30000; -20000; 20000; 30000 ] in
  Printf.printf "  device beyond +-1.5 %% (directed): %s\n" (String.concat " " beyond);
  print_endline "== 5. the reply path, clock by clock";
  budget ();
  print_endline "== controls: each must FAIL";
  let control name ?t0cfg ?t12cfg ?jk_swap () =
    let b, _ = fw_directed ~ppm:0 ?t0cfg ?t12cfg ?jk_swap name in
    let failed = b.Bench.errors <> [] in
    Printf.printf "  %-44s %s (%d errors; first: %s)\n" name (if failed then "caught" else "NOT CAUGHT")
      (List.length b.errors) (match List.rev b.errors with e :: _ -> e | [] -> "-");
    if not failed then ok := false in
  let t12 = Firmware.t12_default and t0d = Firmware.t0_default in
  control "J and K swapped" ~t0cfg:{ t0d with jk_swap = true } ~t12cfg:{ t12 with jk_swap12 = true } ~jk_swap:true ();
  control "reply 4 bit times late" ~t12cfg:{ t12 with drive = t12.drive + 40 } ();
  control "reply 1 bit time early (drives into the host's EOP)" ~t12cfg:{ t12 with drive = t12.drive - 10 } ();
  control "CRC_OK not checked" ~t12cfg:{ t12 with skip_crc = true } ();
  print_endline (if !ok then "FIRMWARE LS DEVICE PASS" else "FIRMWARE LS DEVICE FAIL");
  exit (if !ok then 0 else 1)
