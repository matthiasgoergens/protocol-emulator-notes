(* Protocol bridges on the mailbox variant, run cycle by cycle on the interpreter and the RTL in
   lockstep, against independent models of both sides.

   Bridge A, UART <-> I2C master (a UART command interface to an I2C sensor):
     T0 UART receiver (pin 0) -> inbox 1; RTS (pin 2) is raised when inbox 1 is full.
     T1 I2C master (SDA pin 3, SCL pin 4, open drain, clock stretching honoured everywhere),
        executing a byte code from the UART: START, STOP, WRITE b, READ, ACK, NACK.
        Every op but START/STOP answers one byte (the acknowledge bit, or the byte read) -> inbox 2.
     T2 UART transmitter (pin 1) from inbox 2.
     T3 unrelated: an SPI master loop on pins 5..7.
   Bridge B, UART <-> SPI master:
     T0 as above (no RTS: no pin left), T1 SPI master mode 0 (SCLK 2, MOSI 3, MISO 4, CS 5) with
        ops CS_LOW, CS_HIGH, XFER b (answers the MISO byte), T2 as above,
     T3 unrelated: an I2C master write loop on pins 6, 7 with its own slave.

   The host side is a UART model that honours CTS at each byte start (or, in a control, ignores
   it), with random gaps and a baud error; its receiver is Decoders.uart on our TX pin. The device
   side is a bit-level I2C slave with random clock stretching, or a bit-level SPI memory. The
   expected answers come from separate transaction-level reference models of the devices. *)

open Bridge_lib

(* ---------------- the host's UART ---------------- *)
type host = {
  bytes : int array; mutable next : int; mutable t_next : float; mutable cur : int; mutable bitn : int;
  period : float; gap_bits : int; respect_cts : bool; rnd : Random.State.t; mutable cts_waits : int;
}

let new_host ~seed ~bytes ~err ~gap_bits ~respect_cts =
  { bytes = Array.of_list bytes; next = 0; t_next = 200.0; cur = 0; bitn = -1; period = float (4 * bit_slots) *. (1.0 +. err);
    gap_bits; respect_cts; rnd = Random.State.make [| seed |]; cts_waits = 0 }

(* level on the host's TX at clock n; [cts] = our RTS pin level (0 = send) *)
let host_level hs ~now ~cts =
  let t = float now in
  if hs.bitn < 0 then begin
    if hs.next < Array.length hs.bytes && t >= hs.t_next then begin
      if hs.respect_cts && cts = 1 then (hs.cts_waits <- hs.cts_waits + 1; 1)
      else begin hs.cur <- hs.bytes.(hs.next); hs.next <- hs.next + 1; hs.bitn <- 0; hs.t_next <- t; 0 end
    end else 1
  end else begin
    let k = int_of_float ((t -. hs.t_next) /. hs.period) in
    if k >= 10 then begin
      hs.bitn <- -1;
      hs.t_next <- hs.t_next +. (10.0 +. float (Random.State.int hs.rnd (hs.gap_bits + 1))) *. hs.period;
      1
    end else if k = 0 then 0 else if k <= 8 then (hs.cur lsr (k - 1)) land 1 else 1
  end

(* ---------------- running a bridge ---------------- *)
type which = A | B
type neigh = Compiled | Rand of int | Off

type cfg = {
  which : which; seed : int; ntx : int; rtl : bool; neigh : neigh; fault : Isa_mb.fault; late : int;
  respect_cts : bool; err : float; gap_bits : int; max_stretch : int; bridge : bool; depth : int;
}

let base = { which = A; seed = 1; ntx = 12; rtl = true; neigh = Compiled; fault = Isa_mb.No_fault; late = 0;
             respect_cts = true; err = 0.01; gap_bits = 2; max_stretch = 400; bridge = true; depth = 2 }

type outcome = {
  answers : int list; expected : int list; regs_ok : bool; bus_ok : bool; mism : int; reports : (int * int) list;
  bridge_hash : int; neigh_hash : int; cycles : int; rts_cycles : int; max_fill : int; stretched : int;
  min_slack : int; neigh_ok : bool; n_ops : int; cts_waits : int; ntr : int array; swapped : (int * int) option;
}

(* two neighbour traces agree on their common prefix (runs end at different times) *)
let same_prefix a b = let n = min (Array.length a) (Array.length b) in n > 50_000 && Array.sub a 0 n = Array.sub b 0 n

let random_i2c rnd n ~addr =
  List.init n (fun _ ->
    let a = if Random.State.int rnd 10 = 0 then 0x21 else addr in
    if Random.State.bool rnd then Wr (a, Random.State.int rnd 256, List.init (1 + Random.State.int rnd 4) (fun _ -> Random.State.int rnd 256))
    else Rd (a, Random.State.int rnd 256, 1 + Random.State.int rnd 3))

let random_spi rnd n =
  List.init n (fun _ -> match Random.State.int rnd 5 with
    | 0 | 1 -> Sw (Random.State.int rnd 256, List.init (1 + Random.State.int rnd 4) (fun _ -> Random.State.int rnd 256))
    | 2 | 3 -> Sr (Random.State.int rnd 256, 1 + Random.State.int rnd 4)
    | _ -> Ss)

let run (c : cfg) =
  let ic = Isa_mb.cfg ~pc_bits:7 ~depth:c.depth ~fault:c.fault () in
  let halt = Array.make 128 Isa.halt in
  let rnd = Random.State.make [| c.seed |] in
  let dev_addr = 0x48 in
  let rx = 0 and tx = 1 in
  let (t0, _, l0), (t1, _, _), (t2, _, _) =
    match c.which with
    | A -> uart_rx ~late:c.late ~rx ~rts:(Some 2) ~dst:1 (), i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 (), uart_tx ~tx ~own:2 ()
    | B -> uart_rx ~late:c.late ~rx ~rts:None ~dst:1 (), spi_master ~sclk:2 ~mosi:3 ~miso:4 ~cs:5 ~own:1 ~reply:2 (), uart_tx ~tx ~own:2 () in
  let rearm_pc = Hashtbl.find l0 "rearm" and stopchk_pc = Hashtbl.find l0 "stopchk" in
  let t0, t1, t2 = if c.bridge then t0, t1, t2 else halt, halt, halt in
  let neigh_pins = match c.which with A -> 0xE0 | B -> 0xC0 in
  let t3 = match c.neigh with
    | Off -> halt
    | Rand s -> Random.init s; Dual.random_neighbour ~plen:128 ~pins:neigh_pins ~own:[ 3 ]
    | Compiled -> (match c.which with
        | A -> Asm.of_base ~loop:true (Compiler.spi_master { sclk = 5; mosi = 6; cs = 7; period = 12; sbytes = [ 0x96 ] }) ~plen:128
        | B -> Asm.of_base ~loop:true (Compiler.i2c_write { sda = 6; scl = 7; q = 4; ibytes = [ 0xA0; 0x3C ] }) ~plen:128) in
  let mem = [| t0; t1; t2; t3 |] in
  let d = Dual.make ~rtl:c.rtl ic mem in
  let i2c_txs = random_i2c rnd c.ntx ~addr:dev_addr and spi_txs = random_spi rnd c.ntx in
  let ops = if c.bridge then (match c.which with A -> i2c_ops i2c_txs | B -> spi_ops spi_txs) else [] in
  let expected, expect_bus, ref_mem = match c.which with
    | A -> i2c_reference ~addr:dev_addr i2c_txs
    | B -> let a, m = spi_reference spi_txs in a, [], m in
  let expected = if c.bridge then expected else [] in
  let hs = new_host ~seed:(c.seed + 1000) ~bytes:ops ~err:c.err ~gap_bits:c.gap_bits ~respect_cts:c.respect_cts in
  let slave = new_i2c_slave ~max_stretch:c.max_stretch ~bit_stretch:0.02 ~seed:(c.seed + 7) dev_addr in
  let nslave = new_i2c_slave ~seed:5 0x50 in               (* bridge B's neighbour bus: 0xA0 >> 1 *)
  let sdev = new_spi_dev () in
  let tr = ref (Array.make 1_000_000 0) in
  let reports = ref [] in
  let rts_cycles = ref 0 and max_fill = ref 0 and min_slack = ref max_int in
  let bridge_hash = ref 0 and neigh_hash = ref 0 in
  let t_stop = ref (-1) in
  (* an online count of the bytes on our TX, only to know when to stop *)
  let txs_state = ref (-1) and txs_count = ref 0 and last_tx = ref 0 in
  let n = ref 0 and fin = ref false in
  while not !fin do
    let now = !n in
    let po = Dual.pin_out d and oe = Dual.pin_oe d in
    let drv p = (oe lsr p) land 1 = 1 in
    let pushpull p = if drv p then (po lsr p) land 1 else 1 in
    let od_low p = drv p && (po lsr p) land 1 = 0 in
    let bus = ref 0 in
    let setb p v = if v = 1 then bus := !bus lor (1 lsl p) in
    let cts = pushpull 2 in
    let hl = host_level hs ~now ~cts:(match c.which with A -> cts | B -> 0) in
    setb rx hl; setb tx (pushpull tx);
    (match c.which with
     | A ->
       setb 2 cts;
       let sda, scl = i2c_slave_step slave ~now ~m_sda_low:(od_low 3) ~m_scl_low:(od_low 4) in
       setb 3 sda; setb 4 scl;
       List.iter (fun p -> setb p (pushpull p)) [ 5; 6; 7 ];
       if cts = 1 then incr rts_cycles
     | B ->
       let sclk = pushpull 2 and mosi = pushpull 3 and cs = pushpull 5 in
       let miso = spi_dev_step sdev ~sclk ~mosi ~cs in
       setb 2 sclk; setb 3 mosi; setb 4 miso; setb 5 cs;
       let sda, scl = i2c_slave_step nslave ~now ~m_sda_low:(od_low 6) ~m_scl_low:(od_low 7) in
       setb 6 sda; setb 7 scl);
    let pin_in = !bus in
    if now >= Array.length !tr then (let a = Array.make (2 * now) 0 in Array.blit !tr 0 a 0 now; tr := a);
    (!tr).(now) <- pin_in;
    let nb = lnot neigh_pins land 0xFF in
    bridge_hash := Hashtbl.hash (!bridge_hash, pin_in land nb, po land nb, oe land nb);
    neigh_hash := Hashtbl.hash (!neigh_hash, pin_in land neigh_pins, po land neigh_pins, oe land neigh_pins);
    let pc0 = d.st.pcs.(0) and th = d.st.thread in
    let e = Dual.step d { Isa_mb.idle_io with pin_in } in
    (* receive budget: from the stop-bit check to the poll at idle, in slots *)
    if th = 0 && c.bridge then begin
      if pc0 = stopchk_pc then t_stop := now;
      if pc0 = rearm_pc && !t_stop >= 0 then begin
        let used = (now - !t_stop) / 4 + 1 in
        (* at exact baud the next start edge has the same phase against the poll, so the poll must
           run no later than B/2 slots after the stop check; a drifting host takes one more slot *)
        let slack = (bit_slots / 2) - used in
        if slack < !min_slack then min_slack := slack;
        t_stop := -1
      end
    end;
    (match e.host_out with Some v when th = 0 -> reports := (th, v) :: !reports | _ -> ());
    let fill = List.length d.st.inbox.(1) in if fill > !max_fill then max_fill := fill;
    let txl = pushpull tx in
    (if !txs_state < 0 then (if txl = 0 then txs_state := now)
     else if now - !txs_state >= 10 * 4 * bit_slots then (txs_state := -1; incr txs_count; last_tx := now));
    incr n;
    let sent_all = hs.next >= Array.length hs.bytes && hs.bitn < 0 in
    if (c.bridge && sent_all && ((!txs_count >= List.length expected && now - !last_tx > 20000) || now - max !last_tx 0 > 400000))
       || now >= 6_000_000 || ((not c.bridge) && now >= 400_000) then fin := true
  done;
  if Sys.getenv_opt "DEBUG" <> None then
    Printf.printf "end state: pcs %s, inbox fills %s, inbox1 %s, pin_out %02x oe %02x, t1 acc %02x dl %d\n"
      (String.concat "," (Array.to_list (Array.map string_of_int d.st.pcs)))
      (String.concat "," (Array.to_list (Array.map (fun l -> string_of_int (List.length l)) d.st.inbox)))
      (String.concat " " (List.map (Printf.sprintf "%02x") d.st.inbox.(1))) d.st.pin_out d.st.pin_oe d.st.accs.(1) d.st.dls.(1);
  let trace = List.init !n (fun i -> { Decoders.c = i; bus = (!tr).(i) }) in
  let answers = List.map (fun (_, b, ok) -> if ok then b else -1) (Decoders.uart trace ~pin:tx ~bit_cycles:(4 * bit_slots)) in
  let answers = if c.bridge then answers else [] in
  let regs_ok, bus_ok = match c.which with
    | A -> let got, _ = Decoders.i2c trace ~sda:3 ~scl:4 in (slave.regs = ref_mem, (not c.bridge) || got = expect_bus)
    | B -> (sdev.mem = ref_mem, true) in
  let neigh_ok = match c.neigh, c.which with
    | Compiled, A -> let got = Decoders.spi trace ~sclk:5 ~mosi:6 ~cs:7 in got <> [] && List.for_all (fun x -> x = 0x96) got
    | Compiled, B -> let got, _ = Decoders.i2c trace ~sda:6 ~scl:7 in got <> [] && List.for_all (fun (x, a) -> (x = 0xA0 || x = 0x3C) && a) got
    | _ -> true in
  { answers; expected; regs_ok; bus_ok; mism = d.mismatches; reports = List.rev !reports; bridge_hash = !bridge_hash;
    neigh_hash = !neigh_hash; cycles = !n; rts_cycles = !rts_cycles; max_fill = !max_fill; stretched = slave.stretched;
    min_slack = (if !min_slack = max_int then 0 else !min_slack); neigh_ok; n_ops = List.length ops; cts_waits = hs.cts_waits;
    ntr = Array.init !n (fun i -> (!tr).(i) land neigh_pins); swapped = d.st.swapped }

let pass o = o.answers = o.expected && o.regs_ok && o.bus_ok && o.mism = 0 && o.reports = [] && o.neigh_ok

let describe name o =
  let first_diff =
    let rec go i a b = match a, b with
      | [], [] -> "none" | x :: r1, y :: r2 -> if x = y then go (i + 1) r1 r2 else Printf.sprintf "answer %d: got %d expected %d" i x y
      | [], _ -> Printf.sprintf "%d answers missing" (List.length b) | _, [] -> Printf.sprintf "%d extra answers" (List.length a) in
    go 0 o.answers o.expected in
  let rec agree a b = match a, b with x :: r1, y :: r2 when x = y -> 1 + agree r1 r2 | _ -> 0 in
  Printf.printf "%-50s %s: %d bytes in, answers %d/%d in agreement before the first difference (%s); device %s, bus %s; \
                 RTL mismatches %d; T0 reports %d; %d cycles; RTS high %d cycles; host waited on CTS %d cycles; \
                 max inbox fill %d; slave stretched %d cycles; receive slack %d slots\n%!"
    name (if pass o then "PASS" else "FAIL") o.n_ops (agree o.answers o.expected) (List.length o.expected) first_diff
    (if o.regs_ok then "ok" else "WRONG") (if o.bus_ok then "ok" else "WRONG")
    o.mism (List.length o.reports) o.cycles o.rts_cycles o.cts_waits o.max_fill o.stretched o.min_slack

let () =
  let t0 = Unix.gettimeofday () in
  let mode = try Sys.argv.(1) with _ -> "all" in
  List.iter (fun (name, (_, len, _)) -> Printf.printf "programme %-22s %3d words of 128\n" name len)
    [ ("T0 UART receive (RTS)", uart_rx ~rx:0 ~rts:(Some 2) ~dst:1 ()); ("T1 I2C master", i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 ());
      ("T1 SPI master", spi_master ~sclk:2 ~mosi:3 ~miso:4 ~cs:5 ~own:1 ~reply:2 ()); ("T2 UART transmit", uart_tx ~tx:1 ~own:2 ()) ];
  if mode = "iso" then begin
    let full = run { base with rtl = false } and nalone = run { base with rtl = false; bridge = false } in
    let n = min (Array.length full.ntr) (Array.length nalone.ntr) in
    let first = ref (-1) in
    for i = n - 1 downto 0 do if full.ntr.(i) <> nalone.ntr.(i) then first := i done;
    Printf.printf "lengths %d %d (prefix compared: %b), first difference at %d: full %02x idle %02x\n" (Array.length full.ntr) (Array.length nalone.ntr) (same_prefix full.ntr nalone.ntr) !first
      (if !first >= 0 then full.ntr.(!first) else 0) (if !first >= 0 then nalone.ntr.(!first) else 0)
  end;
  if mode = "late" then describe "late" (run { base with rtl = false; late = 6; gap_bits = 0 });
  if mode = "smoke" then begin
    describe "A smoke" (run { base with ntx = 3 });
    describe "B smoke" (run { base with which = B; ntx = 3 })
  end;
  if mode = "all" then begin
    let all_ok = ref true in
    let expect_pass name o = describe name o; if not (pass o) then all_ok := false in
    let expect_fail name o = describe name o; if pass o then (all_ok := false; print_endline "  ^ CONTROL DID NOT FAIL") in
    (* main runs, RTL in lockstep *)
    let a = run base in expect_pass "A: UART<->I2C, SPI neighbour, RTL+interp" a;
    let b = run { base with which = B } in expect_pass "B: UART<->SPI, I2C neighbour, RTL+interp" b;
    (* constrained random: seeds, both bridges, fast host (no gaps), baud error, slow slave *)
    let ok = ref 0 and tot = ref 0 in
    for seed = 2 to 13 do
      List.iter (fun which ->
        let c = { base with which; seed; rtl = seed <= 4; gap_bits = seed mod 3; err = (float (seed mod 5) -. 2.0) *. 0.008;
                  max_stretch = (seed mod 4) * 300 } in
        let o = run c in incr tot; if pass o then incr ok else describe (Printf.sprintf "  random seed %d %s" seed (if which = A then "A" else "B")) o) [ A; B ]
    done;
    Printf.printf "constrained random: %d of %d runs pass (12 seeds x 2 bridges; RTL in lockstep for seeds 2..4)\n%!" !ok !tot;
    if !ok <> !tot then all_ok := false;
    (* isolation *)
    List.iter (fun which ->
      let nm = if which = A then "A" else "B" in
      let full = run { base with which; rtl = false } in
      let alone = run { base with which; rtl = false; neigh = Off } in
      let nalone = run { base with which; rtl = false; bridge = false } in
      let same = ref 0 in
      for s = 1 to 6 do if (run { base with which; rtl = false; neigh = Rand s }).bridge_hash = full.bridge_hash then incr same done;
      let traffic = run { base with which; rtl = false; seed = 77 } in
      Printf.printf "isolation %s: bridge pins identical without the neighbour %b, under 6 random neighbours %d/6; \
                     neighbour pins identical with the bridge idle %b and under other traffic %b\n%!"
        nm (alone.bridge_hash = full.bridge_hash) !same (same_prefix nalone.ntr full.ntr) (same_prefix traffic.ntr full.ntr);
      if not (alone.bridge_hash = full.bridge_hash && !same = 6 && same_prefix nalone.ntr full.ntr && same_prefix traffic.ntr full.ntr)
      then all_ok := false) [ A; B ];
    (* controls, each must fail *)
    expect_fail "control A: mailbox drops push 40 (interp)" (run { base with rtl = false; fault = Isa_mb.Drop_push 40 });
    expect_fail "control A: mailbox pops newest first (interp)" (run { base with rtl = false; fault = Isa_mb.Lifo });
    expect_fail "control B: mailbox drops push 40 (interp)" (run { base with which = B; rtl = false; fault = Isa_mb.Drop_push 40 });
    describe "control B: mailbox pops newest first (interp; vacuous)" (run { base with which = B; rtl = false; fault = Isa_mb.Lifo });
    print_endline "  (B's inbox never holds two bytes, so newest-first equals oldest-first: an ordering fault needs occupancy >= 2 to show)";
    List.iter (fun which ->
      let obs = ref 0 and caught = ref 0 and same = ref 0 in
      for k = 20 to 69 do
        let o = run { base with which; rtl = false; fault = Isa_mb.Swap_pair k } in
        match o.swapped with
        | Some (x, y) when x <> y -> incr obs; if not (pass o) then incr caught
        | Some _ -> incr same
        | None -> ()
      done;
      Printf.printf "control %s: two pushes delivered swapped, at pushes 20..69: %d swaps of different bytes, caught %d; %d swaps of equal bytes (unobservable by any checker)\n%!"
        (if which = A then "A" else "B") !obs !caught !same;
      if !caught <> !obs || !obs = 0 then all_ok := false) [ A; B ];
 expect_pass "budget edge A: +3 slots in the receiver (slack 0), exact baud" (run { base with rtl = false; late = 3; gap_bits = 0; ntx = 16; err = 0.0 });
    expect_fail "budget edge A: +4 slots (slack -1), exact baud" (run { base with rtl = false; late = 4; gap_bits = 0; ntx = 16; err = 0.0 });
    expect_pass "budget edge B: +5 slots (slack 0), exact baud" (run { base with which = B; rtl = false; late = 5; gap_bits = 0; ntx = 16; err = 0.0 });
    expect_fail "budget edge B: +6 slots (slack -1), exact baud" (run { base with which = B; rtl = false; late = 6; gap_bits = 0; ntx = 16; err = 0.0 });
    expect_fail "control A: receiver over budget by 6 slots" (run { base with rtl = false; late = 6; gap_bits = 0 });
    let ig = run { base with rtl = false; respect_cts = false; gap_bits = 0; max_stretch = 1500; ntx = 16 } in
    expect_fail "control A: host ignores CTS, slow slave" ig;
    Printf.printf "  (overflow reported by T0 on the host channel: %d bytes)\n" (List.length ig.reports);
    (* backpressure: the fast host against a slow device, with and without flow control *)
    let slow = run { base with rtl = true; gap_bits = 0; max_stretch = 1500; ntx = 16 } in
    expect_pass "backpressure A: no host gaps, slave stretches <=1500 cycles" slow;
    let d1 = run { base with rtl = false; gap_bits = 0; max_stretch = 1500; ntx = 16; depth = 1 } in
    expect_pass "backpressure A: same, inbox depth 1" d1;
    let d4 = run { base with rtl = false; gap_bits = 0; max_stretch = 1500; ntx = 16; depth = 4 } in
    expect_pass "backpressure A: same, inbox depth 4" d4;
    print_endline (if !all_ok then "BRIDGES PASS" else "BRIDGES FAIL")
  end;
  Printf.printf "elapsed %.0f s\n" (Unix.gettimeofday () -. t0)
