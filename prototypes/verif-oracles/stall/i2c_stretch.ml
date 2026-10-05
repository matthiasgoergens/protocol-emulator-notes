(* Environment perturbation on the deadline-sequencer demo (../../deadline-sequencer/demo.ml):
   UART TX, SPI master and I2C master write, compiled by its compiler, run on ISA v2.

   The demo's programmes take no host input: their bytes are compiled in. The only input from
   the environment that can legitimately be late is I2C's clock stretching: a slave may hold SCL
   low after the master releases it, and a master must wait for SCL to go high. So the stall
   pattern here is random clock stretching by the slave (in the style of Gergo Erdi's
   test-sim.hs random "ready" patterns), and the golden transcript is what the three decoders
   (Decoders.uart, .spi, .i2c) recover from the bus without stretching. The I2C ack bytes the
   firmware sends to the host (OUT) are part of the transcript.

   Expectation, stated before running: UART and SPI read no pins, so their transcripts must be
   identical under any stretching; the compiled I2C master never reads SCL, so it does not
   honour stretching and its transcript should break. *)

open Demo_lib

type transcript = { uart : (int * bool) list; spi : int list; i2c : (int * bool) list; stop : bool; host : int list }

let run_stretch ~mem ~cycles ~p ~maxk ~seed =
  let rnd = Random.State.make [| seed |] in
  let s = Harness.make mem in
  let st = Isa.init () in
  let sl = new_slave () in
  let hold = ref 0 and prev_master_scl = ref 1 and stretched = ref 0 and rtl_diff = ref 0 in
  let resolve_with_slave ~pin_out ~pin_oe =
    let master_scl = if (pin_oe lsr scl) land 1 = 1 then (pin_out lsr scl) land 1 else 1 in
    if master_scl = 1 && !prev_master_scl = 0 && sl.started && Random.State.float rnd 1.0 < p then
      hold := 1 + Random.State.int rnd maxk;
    prev_master_scl := master_scl;
    if !hold > 0 then begin
      decr hold; incr stretched;
      (* the slave pulls SCL low: on an open-drain line that is the same as a driver at 0 *)
      resolve sl ~pin_out:(pin_out land lnot (1 lsl scl)) ~pin_oe:(pin_oe lor (1 lsl scl))
    end else resolve sl ~pin_out ~pin_oe in
  let bus = ref (resolve_with_slave ~pin_out:0 ~pin_oe:0) in
  let trace = ref [] and host = ref [] in
  for c = 0 to cycles - 1 do
    let pin_in = !bus in
    let eff = Isa.step st ~mem ~pin_in ~host_in:0 ~host_in_valid:false in
    let o = Harness.cycle s ~pin_in ~host_in:0 ~host_in_valid:false in
    if o.pin_out <> st.pin_out || o.pin_oe <> st.pin_oe || o.host_out <> eff.host_out then incr rtl_diff;
    (match eff.host_out with Some b -> host := b :: !host | None -> ());
    bus := resolve_with_slave ~pin_out:st.pin_out ~pin_oe:st.pin_oe;
    trace := { Decoders.c; bus = !bus } :: !trace
  done;
  let trace = List.rev !trace in
  let ub = Decoders.uart trace ~pin:uart_pin ~bit_cycles:(bit_slots * slot) in
  let ib, stop = Decoders.i2c trace ~sda ~scl in
  { uart = List.map (fun (_, b, ok) -> (b, ok)) ub; spi = Decoders.spi trace ~sclk ~mosi ~cs; i2c = ib; stop;
    host = List.rev !host }, !stretched, !rtl_diff

let show t =
  let hx = List.map (Printf.sprintf "%02x") in
  Printf.sprintf "uart [%s] spi [%s] i2c [%s] stop=%b host-acks [%s]"
    (String.concat " " (List.map (fun (b, ok) -> Printf.sprintf "%02x%s" b (if ok then "" else "!")) t.uart))
    (String.concat " " (hx t.spi))
    (String.concat " " (List.map (fun (b, a) -> Printf.sprintf "%02x%s" b (if a then "+" else "-")) t.i2c)) t.stop
    (String.concat " " (hx t.host))

let pr = Printf.printf

let () =
  let mem, _ = build () in
  let cycles = 8000 in
  let golden, _, rd0 = run_stretch ~mem ~cycles ~p:0.0 ~maxk:1 ~seed:1 in
  pr "golden (no stretching): %s; RTL vs interpreter: %d clocks differ\n" (show golden) rd0;
  let ok = ref (rd0 = 0 && golden.uart = List.map (fun b -> (b, true)) uart_bytes && golden.spi = spi_bytes
                && List.map fst golden.i2c = i2c_bytes && golden.stop) in
  pr "golden matches the demo's own expected bytes: %b\n\n" !ok;
  let tally = Hashtbl.create 4 in
  let bump k = Hashtbl.replace tally k (1 + Option.value ~default:0 (Hashtbl.find_opt tally k)) in
  List.iter (fun (p, maxk) ->
      let seeds = 30 in
      let du = ref 0 and ds = ref 0 and di = ref 0 and str = ref 0 and rd = ref 0 and example = ref "" in
      for seed = 1 to seeds do
        let t, n, r = run_stretch ~mem ~cycles ~p ~maxk ~seed in
        str := !str + n; rd := !rd + r;
        if t.uart <> golden.uart then incr du;
        if t.spi <> golden.spi then incr ds;
        if t.i2c <> golden.i2c || t.stop <> golden.stop || t.host <> golden.host then
          (incr di; if !example = "" then example := Printf.sprintf "seed %d: %s" seed (show t))
      done;
      pr "stretch p = %.2f per SCL release, 1..%3d clocks: %d runs, %d stretched clocks; transcripts differing from golden: uart %d, spi %d, i2c %d; RTL vs interpreter %d clocks differ\n"
        p maxk seeds !str !du !ds !di !rd;
      if !example <> "" then pr "    first differing i2c transcript: %s\n" !example;
      if !du + !ds + !rd > 0 then ok := false;
      if !di > 0 then bump "i2c breaks") [ (0.1, 4); (0.3, 16); (0.5, 64); (1.0, 200) ];
  pr "\nfinding: UART and SPI transcripts are identical under every stretch pattern (they read no pins);\n";
  pr "the compiled I2C master's transcript %s under stretching: it never samples SCL, so it does not honour clock stretching.\n"
    (if Hashtbl.mem tally "i2c breaks" then "BREAKS" else "survives");
  (* control: a transcript that should differ must be flagged by the comparison *)
  let mem_bad, _ = build ~stretch:(5, 9) () in
  let t, _, _ = run_stretch ~mem:mem_bad ~cycles ~p:0.0 ~maxk:1 ~seed:1 in
  let flagged = t.uart <> golden.uart in
  pr "control: UART data bit 5 stretched by 9 slots (the demo's own fault), no I2C stretching: comparison %s\n"
    (if flagged then "flags it" else "MISSES it");
  if not flagged then ok := false;
  pr "\nI2C STRETCH %s (PASS = UART/SPI insensitive, RTL agrees, control flagged; the I2C result is a finding, reported above)\n"
    (if !ok then "PASS" else "FAIL");
  exit (if !ok then 0 else 1)
