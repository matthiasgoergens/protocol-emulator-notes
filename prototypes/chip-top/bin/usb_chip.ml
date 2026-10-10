(* Low-speed USB on the combined chip, with the bit layer in the bit-path assists (src/usb_dev.ml),
   against ../usb-ls's independent host model, reference device, bench and scenarios, unchanged.

     usb_chip.exe [SEEDS]      the directed session at three host clock errors, SEEDS random
                               sessions (default 8), thread time, the controls

   The chip's specification and its RTL run in lockstep on the same board (Board): the bench's
   line drives both, the specification's pads drive the line, and every pad and output enable
   is compared every clock (the "lockstep mismatches" count). The host on the host link runs
   the controller: it loads the chip, then polls HOSTOUT and feeds HOSTIN. *)

open Regs
module S = Chip_spec
module U = Usb_dev

let pr = Printf.printf

type dut = {
  bench : Bench.dut;
  spec : S.t;
  ctl : U.ctl;
  board : Board.t;
  (* per thread: slots in which the thread's pc moved, and slots in which it stayed (a wait) *)
  moved : int array;
  stayed : int array;
}

let make ?(name = "chip-top") ?(cfg = U.default_cfg) ?(jk_swap = false) () =
  let ccfg = { S.default_config with prog_words = 512 } in
  let spec = S.create ~cfg:ccfg () and rtl = Chip_sim.create ~cfg:ccfg () in
  let cores = [ Board.spec_core spec; Board.rtl_core rtl ] in
  let b = Board.create () in
  let ctl = U.create_ctl () in
  U.configure ~jk_swap b.host cfg;
  let mism = ref 0 and line = ref (0, 1) and loaded = ref false in
  let moved = Array.make 4 0 and stayed = Array.make 4 0 in
  let clock ~reset =
    U.now := b.clock;
    if !loaded then U.pump ctl b.host;
    let dp, dm = !line in
    let ext = Array.make n_pads 0 in
    ext.(U.pad_dp) <- Board.rep4 dp; ext.(U.pad_dm) <- Board.rep4 dm;
    let smp = Board.samples b ~ext in
    let th = spec.seq.thread and running = S.run spec in
    let pc0 = spec.seq.pcs.(th) in
    (match Board.advance b cores ~smp ~reset with
     | [ a; o ] -> if a.pad_nib <> o.pad_nib || a.uio_oe <> o.uio_oe then incr mism
     | _ -> assert false);
    (match Sys.getenv_opt "USB_TRACE" with
     | Some w ->
       let lo, hi = Scanf.sscanf w "%d-%d" (fun a b -> (a, b)) in
       if b.clock >= lo && b.clock <= hi && (spec.es_out.valid || spec.rx.cv) then
         pr "        %6d line %d%d es %s chain %s hist %02x hc %d frame %b n %d fifo %d tx %b pc0 %02x\n" b.clock dp dm
           (if spec.es_out.valid then string_of_int spec.es_out.bit else "-") (if spec.rx.cv then string_of_int spec.rx.cb else "-")
           spec.rx.hist spec.rx.hcount spec.rx.in_frame spec.rx.nbits (Queue.length spec.rx.fifo) (Txpath.active spec.tx) spec.seq.pcs.(0);
       if b.clock = hi then exit 0
     | None -> ());
    if running && !loaded then (if spec.seq.pcs.(th) = pc0 then stayed.(th) <- stayed.(th) + 1 else moved.(th) <- moved.(th) + 1)
  in
  (* reset, load and start while the line idles at J *)
  let c = ref 0 in
  while !c < 2 || not (Host.idle b.host) do clock ~reset:(!c < 2); incr c done;
  for _ = 1 to 200 do clock ~reset:false done;
  loaded := true;
  let step ~dp ~dm = line := (dp, dm); clock ~reset:false in
  let out () =
    let o = b.out in
    let lv p = (o.pad_nib.(p) lsr 3) land 1 and oe p = (o.uio_oe lsr (p - 8)) land 1 in
    (lv U.pad_dp, lv U.pad_dm, oe U.pad_dp lor oe U.pad_dm) in
  let bench = { Bench.name; step; out; offer_report = U.offer_report ctl; nak_ok = true; mismatches = (fun () -> !mism) } in
  { bench; spec; ctl; board = b; moved; stayed }

let report b =
  pr "  %s\n" (Bench.summary b);
  List.iter (fun e -> pr "    %s\n" e) (List.rev b.Bench.errors);
  b.Bench.errors = [] && b.dut.mismatches () = 0

let directed ?(verbose = false) ?cfg ?jk_swap ~ppm name =
  let d = make ~name ?cfg ?jk_swap () in
  let b = Bench.create ~verbose ~ppm d.bench in
  Scenario.directed b ~addr:42;
  (b, d)

let thread_time (d : dut) =
  Array.iteri (fun t m ->
      let s = d.stayed.(t) in
      pr "    T%d: %d of %d slots moved on (%.1f %%), the rest waited in place\n" t m (m + s) (100.0 *. float m /. float (max 1 (m + s))))
    d.moved

(* ---- headroom: the bit path as a USB-style link, the chip talking to itself ----

   The serialiser drives uio[6] and uio[7] (NRZI, stuffing after six 1s, sync, EOP) and the edge
   sampler, the decoder, the destuffer and the framer receive the same pads (they read back what
   the chip drives): T2 sends a packet (sync, then n bytes from bank page 1: a PID, a payload and
   its CRC-16), T0 stores every byte it receives in bank page 2 and, at the frame's end, 0xC0 if
   the CRC unit's residue check holds (0xBA if not). The host loads, runs, stops and reads page 2
   back. Swept over the symbol period: the fastest the bit layer and one thread per direction,
   moving bytes only, keep up with. ../usb-ls's firmware bit layer needs 10 slots (40 clocks) per
   bit, a whole thread. *)
let loopback ~per ~payload =
  let open U in
  let pkt = Fw_codec.data_bytes 0xC3 payload in
  let tx = [ L "t2"; w (Isa2.lda 0); w (Isa2.bank 1); w Isa2.ldb; w Isa2.cnta; w (Isa2.ldd 0) ] @ send_byte 0x80
           @ [ L "tx"; w Isa2.ldb ] @ send () @ [ dec_cnt; jnz "tx"; L "h2"; jmp "h2" ] in
  let rx = [ L "t0"; w (Isa2.lda 0); w (Isa2.bank 2);
             L "w"; w (Isa2.ldd 0); recv "w"; w Isa2.stb;
             L "fwd"; w (Isa2.ldd 0); recv "chk"; w Isa2.stb; jmp "fwd";
             L "chk"; waitc f_done "fwd"; waitc f_crc "bad"; w (Isa2.lda 0xC0); w Isa2.stb; L "h0"; jmp "h0";
             L "bad"; w (Isa2.lda 0xBA); w Isa2.stb; L "h1"; jmp "h1" ] in
  let ccfg = { S.default_config with prog_words = 512 } in
  let spec = S.create ~cfg:ccfg () and rtl = Chip_sim.create ~cfg:ccfg () in
  let cores = [ Board.spec_core spec; Board.rtl_core rtl ] in
  let b = Board.create () in
  let h = b.host in
  let wr tgt addr data = Host.submit h (Host.Write { tgt; addr; data }) in
  Host.wreg h r_ctrl 2;
  List.iter (fun (page, base, items) ->
      let words = U.assemble ~base items in
      wr t_prog (2 * ((page lsl 8) lor base)) (List.concat_map (fun x -> [ x land 0xFF; x lsr 8 ]) (Array.to_list words)))
    [ (0, 0, rx); (1, 0x80, tx); (1, 0xF0, [ L "t1"; jmp "t1" ]); (1, 0xF8, [ L "t3"; jmp "t3" ]) ];
  wr t_reg (r_boot_pc 0) [ 0; 0xF0; 0x80; 0xF8; (1 lsl 2) lor (1 lsl 4) lor (1 lsl 6) ];
  wr t_reg (r_padsel pad_dm) [ src_tx_a; src_tx_b ];
  wr t_reg (r_flagsel 0) [ fl_rx_done; fl_rx_err; fl_crc_check; fl_line_active ];
  let off = min 255 (2 * per) and pd = min 255 (4 * per) in
  wr t_reg r_es_mode [ 2 lor 8 lor 16; (pad_dm lsl 4) lor pad_dp; min 8 (2 * per); 0; 0xFF; 3; off; pd ];
  let le32 v = List.init 4 (fun k -> (v lsr (8 * k)) land 0xFF) in
  wr t_reg r_crc_ctrl [ 1 ];
  wr t_reg r_crc_poly (le32 0xA001 @ le32 0xFFFF @ le32 0xFFFF @ le32 0xFFFF @ le32 0xB001);
  (* as the device, but without half duplex: it receives itself *)
  wr t_reg r_bp_ctrl [ 1 lor 8 lor 32 lor 128; 0x01; 0x26; 0x80; 0xFF; 8; 0x05; 0x26; per land 0xFF; per lsr 8; 0x02; 0x11; 0x76 ];
  wr t_bank 0x100 (List.length pkt :: pkt);
  Host.wreg h r_ctrl 1;
  let frame_clocks = (List.length pkt + 2) * 8 * per * 8 / 6 + 2000 in
  Host.submit h (Host.Idle frame_clocks);
  Host.wreg h r_ctrl 0;
  let got = ref [] in
  Host.submit h (Host.Read { tgt = t_bank; addr = 0x200; n = List.length pkt + 1; k = (fun l -> got := l) });
  let mism = ref 0 and c = ref 0 in
  while !c < 2 || not (Host.idle h) do
    let ext = Array.make n_pads 0 in
    let o = b.out in
    List.iter (fun p -> ext.(p) <- Board.resolve_uio o p ~ext:(if p = pad_dm then 15 else 0)) [ pad_dm; pad_dp ];
    (match Board.advance b cores ~smp:(Board.samples b ~ext) ~reset:(!c < 2) with
     | [ a; o ] -> if a.pad_nib <> o.pad_nib || a.uio_oe <> o.uio_oe then incr mism
     | _ -> ());
    incr c
  done;
  let want = pkt @ [ 0xC0 ] in
  (!got = want, !mism, !got, want)

let rates () =
  pr "== headroom: the chip's bit path as a USB-style link to itself (one thread sends, one receives)\n";
  pr "   clocks per bit, Mbit/s: packets received whole with a good CRC, of 4 (64-byte payloads, a third 0xFF)\n";
  List.iter (fun per ->
      let good = ref 0 and mism = ref 0 in
      for seed = 1 to 4 do
        let r = Random.State.make [| seed; per |] in
        let payload = List.init 64 (fun _ -> if Random.State.int r 3 = 0 then 0xFF else Random.State.int r 256) in
        let ok, m, got, want = loopback ~per ~payload in
        if (not ok) && seed = 1 && Sys.getenv_opt "RATES_DEBUG" <> None then
          pr "     got  %s\n     want %s\n" (String.concat " " (List.map (Printf.sprintf "%02x") got)) (String.concat " " (List.map (Printf.sprintf "%02x") want));
        if ok then incr good; mism := !mism + m
      done;
      pr "   %3d clocks (%5.2f Mbit/s): %d of 4; specification and RTL: %d mismatching clocks\n%!" per (60.0 /. float per) !good !mism)
    [ 40; 20; 10; 5; 4; 3; 2; 1 ]

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "rates" then (rates (); exit 0);
  let ok = ref true in
  let sizes = Array.map (fun (_, _, w) -> Array.length w) (U.images U.default_cfg) in
  pr "== programme sizes: T0 %d, T1 %d, T2 %d, T3 %d words (../usb-ls's firmware: T0 63, T1 180, T2 186)\n"
    sizes.(0) sizes.(1) sizes.(2) sizes.(3);
  pr "== the device on the chip, specification and RTL in lockstep: directed\n%!";
  let t0 = Unix.gettimeofday () in
  let b, d = directed ~verbose:true ~ppm:0 "chip-top" in
  ok := report b && !ok;
  pr "  controller: %d messages (%d events)\n" d.ctl.messages d.ctl.events;
  pr "  thread time (the interpreter's pc, every slot of the session):\n";
  thread_time d;
  List.iter (fun ppm -> let b, _ = directed ~ppm "chip-top" in ok := report b && !ok) [ -15000; 15000 ];
  pr "  (%.0f s)\n%!" (Unix.gettimeofday () -. t0);
  pr "== constrained random sessions\n%!";
  let nseeds = try int_of_string Sys.argv.(1) with _ -> 8 in
  for seed = 1 to nseeds do
    let rng = Random.State.make [| seed; 77 |] in
    let ppm = match seed with 1 -> -15000 | 2 -> 15000 | _ -> Random.State.int rng 30001 - 15000 in
    let d = make ~name:"chip-top" () in
    let b = Bench.create ~seed ~ppm d.bench in
    Scenario.random_session b ~n:120;
    ok := report b && !ok;
    pr "%!"
  done;
  let beyond = List.map (fun ppm ->
      let b, _ = directed ~ppm "chip-top" in
      Printf.sprintf "%+d%%:%s" (ppm / 10000) (if b.Bench.errors = [] then "ok" else "FAIL"))
      [ -40000; -30000; -20000; 20000; 30000; 40000 ] in
  pr "  device beyond +-1.5 %% (directed): %s\n%!" (String.concat " " beyond);
  pr "== controls: each must FAIL\n";
  let control name ?cfg ?jk_swap () =
    let b, _ = directed ~ppm:0 ?cfg ?jk_swap name in
    let failed = b.Bench.errors <> [] in
    pr "  %-44s %s (%d errors; first: %s)\n%!" name (if failed then "caught" else "NOT CAUGHT")
      (List.length b.errors) (match List.rev b.errors with e :: _ -> e | [] -> "-");
    if not failed then ok := false in
  let c = U.default_cfg in
  control "J and K swapped" ~jk_swap:true ();
  control "reply 4 bit times late" ~cfg:{ c with turn = c.turn + 40 } ();
  control "reply 1.5 bit times early" ~cfg:{ c with turn = c.turn - 15 } ();
  control "CRC not checked" ~cfg:{ c with check_crc = false } ();
  pr "%s\n" (if !ok then "CHIP-TOP LS DEVICE PASS" else "CHIP-TOP LS DEVICE FAIL");
  exit (if !ok then 0 else 1)
