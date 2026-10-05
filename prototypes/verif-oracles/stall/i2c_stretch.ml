(* Environment perturbation on the deadline-sequencer demo (../../deadline-sequencer/demo.ml):
   UART TX, SPI master and I2C master write, compiled by its compiler, run on ISA v2.

   The demo's programmes take no host input: their bytes are compiled in. The only input from
   the environment that can legitimately be late is I2C's clock stretching: a slave may hold SCL
   low after the master releases it, and a master must wait for SCL to go high. So the stall
   pattern here is random clock stretching by the slave (in the style of Gergo Erdi's
   test-sim.hs random "ready" patterns), and the golden transcript is what the three decoders
   (Decoders.uart, .spi, .i2c) recover from the bus without stretching. The I2C ack bytes the
   firmware sends to the host (OUT) are part of the transcript.

   Two I2C programmes are run: the compiler's stretch-blind original (copied below as
   [i2c_write_v0], from before the fix) and the compiler's current [i2c_write], which waits for
   SCL to read high after each release. Expectation, stated before running: UART and SPI read
   no pins, so their transcripts are identical under any stretching; the original breaks under
   stretching (it never reads SCL) and the current one does not. *)

open Demo_lib

(* The compiler's I2C master as it was before the clock-stretching fix (63 words), kept here
   only as the "before" of this oracle. *)
let i2c_write_v0 (c : Compiler.i2c) =
  let open Compiler in
  let q = c.q in
  let mk p = 1 lsl p in
  let drive_low p = W (Isa.setp ~mask:(mk p) ~value:0 ~oe:1) in
  let release p = W (Isa.setp ~mask:(mk p) ~value:0 ~oe:0) in
  let wait n = [ W (Isa.ldd n); W Isa.waitd ] in
  let items = ref [] in
  let emit i = items := i :: !items in
  let emits l = List.iter emit l in
  emit (W (Isa.setp ~mask:(mk c.sda lor mk c.scl) ~value:0 ~oe:0));
  emit (drive_low c.sda); emits (wait (q - 3)); emit (drive_low c.scl);
  List.iteri (fun bi byte ->
    emit (W (Isa.lda byte)); emit (W (Isa.ldc 8));
    let l = Printf.sprintf "ibit%d" bi in
    emit (Label l);
    emit (W (Isa.sho ~od:1 ~pin:c.sda ~msb:1 ()));
    emits (wait (q - 3)); emit (release c.scl);
    emits (wait (2 * q - 3)); emit (drive_low c.scl);
    emits (wait (q - 4)); emit (Jnz l);
    emit (release c.sda); emits (wait (q - 3)); emit (release c.scl);
    emits (wait (q - 3)); emit (W (Isa.shi ~pin:c.sda ~msb:1));
    emits (wait (q - 3)); emit (drive_low c.scl);
    emits (wait (q - 3)); emit (W Isa.out)) c.ibytes;
  emit (drive_low c.sda); emits (wait (q - 3)); emit (release c.scl); emits (wait (q - 3)); emit (release c.sda);
  emit (W Isa.halt);
  assemble (List.rev !items)

type transcript = { uart : (int * bool) list; spi : int list; i2c : (int * bool) list; stop : bool; host : int list }

type run = { t : transcript; stretched : int; rtl_diff : int; scl_edges : (int * int) list;
             final_oe : int; final_pc : int; pc_moves_late : bool }

(* [stretch] decides, at each master release of SCL while the slave is addressed, how many
   clocks the slave holds SCL low (0 = none). *)
let run_stretch ~mem ~cycles ~stretch =
  let s = Harness.make mem in
  let st = Isa.init () in
  let sl = new_slave () in
  let hold = ref 0 and prev_master_scl = ref 1 and stretched = ref 0 and rtl_diff = ref 0 and nrise = ref 0 in
  let resolve_with_slave ~pin_out ~pin_oe =
    let master_scl = if (pin_oe lsr scl) land 1 = 1 then (pin_out lsr scl) land 1 else 1 in
    if master_scl = 1 && !prev_master_scl = 0 && sl.started then (incr nrise; hold := stretch !nrise);
    prev_master_scl := master_scl;
    if !hold > 0 then begin
      decr hold; incr stretched;
      (* the slave pulls SCL low: on an open-drain line that is the same as a driver at 0 *)
      resolve sl ~pin_out:(pin_out land lnot (1 lsl scl)) ~pin_oe:(pin_oe lor (1 lsl scl))
    end else resolve sl ~pin_out ~pin_oe in
  let bus = ref (resolve_with_slave ~pin_out:0 ~pin_oe:0) in
  let trace = ref [] and host = ref [] in
  let pc_at = ref (-1) and pc_moves_late = ref false in
  for c = 0 to cycles - 1 do
    let pin_in = !bus in
    let eff = Isa.step st ~mem ~pin_in ~host_in:0 ~host_in_valid:false in
    let o = Harness.cycle s ~pin_in ~host_in:0 ~host_in_valid:false in
    if o.pin_out <> st.pin_out || o.pin_oe <> st.pin_oe || o.host_out <> eff.host_out then incr rtl_diff;
    (match eff.host_out with Some b -> host := b :: !host | None -> ());
    bus := resolve_with_slave ~pin_out:st.pin_out ~pin_oe:st.pin_oe;
    trace := { Decoders.c; bus = !bus } :: !trace;
    (* the I2C thread's pc over the last quarter of the run: it must have stopped moving *)
    let pc2 = List.nth o.pcs 2 in
    if c >= cycles * 3 / 4 then (if !pc_at >= 0 && pc2 <> !pc_at then pc_moves_late := true; pc_at := pc2)
  done;
  let trace = List.rev !trace in
  let ub = Decoders.uart trace ~pin:uart_pin ~bit_cycles:(bit_slots * slot) in
  let ib, stop = Decoders.i2c trace ~sda ~scl in
  { t = { uart = List.map (fun (_, b, ok) -> (b, ok)) ub; spi = Decoders.spi trace ~sclk ~mosi ~cs; i2c = ib; stop;
          host = List.rev !host };
    stretched = !stretched; rtl_diff = !rtl_diff; scl_edges = Decoders.edges trace scl;
    final_oe = st.pin_oe; final_pc = !pc_at; pc_moves_late = !pc_moves_late }

let show t =
  let hx = List.map (Printf.sprintf "%02x") in
  Printf.sprintf "uart [%s] spi [%s] i2c [%s] stop=%b host-acks [%s]"
    (String.concat " " (List.map (fun (b, ok) -> Printf.sprintf "%02x%s" b (if ok then "" else "!")) t.uart))
    (String.concat " " (hx t.spi))
    (String.concat " " (List.map (fun (b, a) -> Printf.sprintf "%02x%s" b (if a then "+" else "-")) t.i2c)) t.stop
    (String.concat " " (hx t.host))

let pr = Printf.printf

(* scl high and low widths, in clocks, in order *)
let widths edges =
  let rec go = function
    | (c1, v) :: ((c2, _) :: _ as r) -> (v, c2 - c1) :: go r
    | _ -> [] in
  go edges

let () =
  let mem_new, _ = build () in
  let ic0, l0 = i2c_write_v0 { sda; scl; q; ibytes = i2c_bytes } in
  let mem_old = Array.copy mem_new in
  mem_old.(2) <- ic0;
  let _, l1 = Compiler.i2c_write { sda; scl; q; ibytes = i2c_bytes } in
  pr "I2C programme before the fix: %d words; after: %d words (of %d)\n" l0 l1 Isa.prog_len;
  let cycles = 8000 in
  let none _ = 0 in
  let g_old = run_stretch ~mem:mem_old ~cycles ~stretch:none and g_new = run_stretch ~mem:mem_new ~cycles ~stretch:none in
  let ok = ref true in
  let expect_golden name g =
    let m = g.rtl_diff = 0 && g.t.uart = List.map (fun b -> (b, true)) uart_bytes && g.t.spi = spi_bytes
            && List.map fst g.t.i2c = i2c_bytes && List.for_all snd g.t.i2c && g.t.stop && g.t.host = [ 0; 0 ] in
    pr "%s, no stretching: %s; RTL vs interpreter: %d clocks differ; matches the demo's expected bytes: %b\n"
      name (show g.t) g.rtl_diff m;
    if not m then ok := false in
  expect_golden "before" g_old; expect_golden "after " g_new;
  (* unstretched timing, before against after: scl's edges *)
  let wo = widths g_old.scl_edges and wn = widths g_new.scl_edges in
  let highs w = List.filter_map (fun (v, d) -> if v = 1 then Some d else None) w in
  let lows w = List.filter_map (fun (v, d) -> if v = 0 then Some d else None) w in
  let ints l = String.concat "," (List.map string_of_int l) in
  pr "\nunstretched scl timing, in clocks (q = %d slots = %d clocks):\n" q (q * slot);
  pr "  high widths before: %s\n  high widths after:  %s\n  identical: %b\n" (ints (highs wo)) (ints (highs wn)) (highs wo = highs wn);
  pr "  low widths before:  %s\n  low widths after:   %s\n" (ints (lows wo)) (ints (lows wn));
  let diffs = if List.length (lows wo) <> List.length (lows wn) then [ "different numbers of low phases" ]
    else List.concat (List.mapi (fun i (a, b) -> if a <> b then [ Printf.sprintf "#%d %d->%d" (i + 1) a b ] else [])
                        (List.combine (lows wo) (lows wn))) in
  pr "  low widths that differ: %s (expected: #1, after START, %d -> %d; #10, between the bytes, %d -> %d)\n"
    (String.concat " " diffs) ((q + 3) * slot) ((2 * q + 1) * slot) ((2 * q + 3) * slot) ((2 * q + 2) * slot);
  if highs wo <> highs wn || List.length diffs <> 2 then ok := false;
  (* stretching *)
  let campaign name mem golden ~must_survive =
    let broke = ref 0 in
    List.iter (fun (p, maxk) ->
        let seeds = 30 in
        let du = ref 0 and ds = ref 0 and di = ref 0 and str = ref 0 and rd = ref 0 and example = ref "" in
        let min_high = ref max_int in
        for seed = 1 to seeds do
          let rnd = Random.State.make [| seed |] in
          let stretch _ = if Random.State.float rnd 1.0 < p then 1 + Random.State.int rnd maxk else 0 in
          let r = run_stretch ~mem ~cycles:(cycles + (20 * maxk)) ~stretch in  (* room for 19 rises held maxk *)
          str := !str + r.stretched; rd := !rd + r.rtl_diff;
          List.iter (fun (v, d) -> if v = 1 && d < !min_high then min_high := d) (widths r.scl_edges);
          if r.t.uart <> golden.uart then incr du;
          if r.t.spi <> golden.spi then incr ds;
          if r.t.i2c <> golden.i2c || r.t.stop <> golden.stop || r.t.host <> golden.host then
            (incr di; if !example = "" then example := Printf.sprintf "seed %d: %s" seed (show r.t))
        done;
        pr "%s: stretch p = %.2f per SCL release, 1..%4d clocks: %d runs, %d stretched clocks; transcripts differing from golden: uart %d, spi %d, i2c %d; RTL vs interpreter %d clocks differ; shortest scl high %d clocks\n"
          name p maxk seeds !str !du !ds !di !rd !min_high;
        if !example <> "" then pr "    first differing i2c transcript: %s\n" !example;
        if !du + !ds + !rd > 0 then ok := false;
        broke := !broke + !di) [ (0.1, 4); (0.3, 16); (0.5, 64); (1.0, 200); (1.0, 2000) ];
    if must_survive && !broke > 0 then ok := false;
    if (not must_survive) && !broke = 0 then (ok := false; pr "    ^ the stretch-blind original was expected to break and did not\n");
    !broke in
  pr "\n";
  let b_old = campaign "before" mem_old g_old.t ~must_survive:false in
  let b_new = campaign "after " mem_new g_new.t ~must_survive:true in
  pr "\nI2C runs differing from golden under stretching: before %d of 150, after %d of 150\n" b_old b_new;
  (* the deadline: one stretch just inside it must be absorbed; one beyond it must end the write
     cleanly (both lines released, thread halted, fewer acks to the host, no wrong byte) *)
  let limit_clocks = 4095 * slot in
  pr "\nstretch deadline (4095 slots = %d clocks):\n" limit_clocks;
  List.iter (fun (k, hold, expect_ok) ->
      let r = run_stretch ~mem:mem_new ~cycles:(cycles + hold + 2000) ~stretch:(fun n -> if n = k then hold else 0) in
      let golden = r.t = g_new.t in
      let released = (r.final_oe lsr sda) land 1 = 0 && (r.final_oe lsr scl) land 1 = 0 in
      let prefix_ok = List.length r.t.i2c <= 2
                      && List.for_all2 (fun a b -> a = b) r.t.i2c (List.filteri (fun i _ -> i < List.length r.t.i2c) g_new.t.i2c) in
      (* acks completed before the held rise: nine rises per byte, the STOP's is the 19th *)
      let acks_before = (k - 1) / 9 in
      let fine =
        if expect_ok then golden && r.rtl_diff = 0
        else (not golden) && released && (not r.pc_moves_late) && List.length r.t.host = acks_before && prefix_ok
             && (not r.t.stop) && r.rtl_diff = 0 in
      pr "  rise %d held low %d clocks: %s; lines released at the end %b, thread stopped %b, RTL differs %d clocks -> %s\n"
        k hold (show r.t) released (not r.pc_moves_late) r.rtl_diff
        (if fine then (if expect_ok then "absorbed, as expected" else "timed out cleanly, as expected") else "UNEXPECTED");
      if not fine then ok := false)
    [ (3, limit_clocks - 200, true); (12, limit_clocks - 200, true); (3, limit_clocks + 400, false); (12, limit_clocks + 400, false);
      (19, limit_clocks + 400, false) ];
  (* control: a transcript that should differ must be flagged by the comparison *)
  let mem_bad, _ = build ~stretch:(5, 9) () in
  let r = run_stretch ~mem:mem_bad ~cycles ~stretch:none in
  let flagged = r.t.uart <> g_new.t.uart in
  pr "\ncontrol: UART data bit 5 stretched by 9 slots (the demo's own fault), no I2C stretching: comparison %s\n"
    (if flagged then "flags it" else "MISSES it");
  if not flagged then ok := false;
  pr "\nI2C STRETCH %s (PASS = UART/SPI insensitive, RTL agrees, the original breaks and the fix survives every stretch, \
      scl high widths unchanged, the deadline absorbs or times out cleanly, control flagged)\n"
    (if !ok then "PASS" else "FAIL");
  exit (if !ok then 0 else 1)
