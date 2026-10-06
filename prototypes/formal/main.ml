(* Bounded model checking of sequencer programmes on ISA v2: the four properties of README.md,
   each on a correct programme (no violation to the depth given, with non-vacuity covers) and on
   a planted bug (a counterexample, replayed on Isa2.Spec through the same monitors).

   Usage: formal.exe [scenario ...]   (no argument: all; names as in [scenarios] below) *)

open Machine

let addr = Programmes.addr
let pr = Printf.printf

let replay ?bank ?(prefix = "") ~store ~code model ~upto f =
  let c = Machine.concrete ~prefix ?bank ~store ~code () in
  for k = 0 to upto do
    let io = Machine.concrete_io model ~k in
    let t, a, instr, e = Machine.concrete_clock c model ~k io in
    f k io t a instr e c.cst
  done

let flag_or r x = r := Smt.or_ !r x

let check_replay ~expected ~fired =
  pr "  replay on Isa2.Spec: the monitor fires first at clock %s (solver: clock %d) -> %s\n"
    (match fired with Some k -> string_of_int k | None -> "never") expected
    (if fired = Some expected then "counterexample CONFIRMED" else "MISMATCH")

(* ---- (a) deadline waits ---- *)

(* [cut]: Machine.cut after every clock, and the monitors' counters with it (for programmes whose
   control flow follows their inputs, such as the I2C master since it honours clock stretching) *)
let deadline ?(cut = false) ~name ~store ~code ~(contracts : Props.contract list) ~depth () =
  let m = Machine.create ~store ~code () in
  let mons = List.map P.deadline contracts in
  let by_event = Array.make (List.length contracts) Smt.ff and by_deadline = Array.make (List.length contracts) Smt.ff in
  let executed = Array.make (List.length contracts) Smt.ff in
  let step k =
    let io = Machine.io ~k in
    let t, addr_before, _ = Machine.clock m ~k io in
    let addr_after = Sym.fetch_addr m.st t in
    let bad = ref Smt.ff in
    List.iteri (fun i (mon : P.deadline) ->
        if mon.contract.thread = t then begin
          let b, ev, dd = P.deadline_step mon ~addr_before ~addr_after ~io in
          bad := Smt.or_ !bad b;
          executed.(i) <- Smt.or_ executed.(i) (Smt.eq addr_before (Smt.k ~w:10 mon.contract.wait));
          by_event.(i) <- Smt.or_ by_event.(i) ev; by_deadline.(i) <- Smt.or_ by_deadline.(i) dd
        end) mons;
    let cuts =
      if not cut then []
      else begin
        let eqs = ref (Machine.cut m ~k) in
        List.iteri (fun i (mon : P.deadline) -> mon.since <- Machine.cut_value ~prefix:"" ~k (Printf.sprintf "since%d" i) mon.since eqs) mons;
        Array.iteri (fun i x -> by_event.(i) <- Machine.cut_value ~prefix:"" ~k (Printf.sprintf "ev%d" i) x eqs) by_event;
        Array.iteri (fun i x -> by_deadline.(i) <- Machine.cut_value ~prefix:"" ~k (Printf.sprintf "dd%d" i) x eqs) by_deadline;
        Array.iteri (fun i x -> executed.(i) <- Machine.cut_value ~prefix:"" ~k (Printf.sprintf "ex%d" i) x eqs) executed;
        !eqs
      end in
    !bad, cuts in
  let antecedent = "every contract's wait executes" in
  let covers () =
    (antecedent, Array.fold_left Smt.and_ Smt.tt executed) ::
    List.concat (List.mapi (fun i (c : Props.contract) ->
        let w = Printf.sprintf "wait at %d.%d" (c.wait lsr 8) (c.wait land 0xFF) in
        (match c.kind with Waitp _ -> [ w ^ " left on its event", by_event.(i) ] | Waitd -> [])
        @ [ w ^ " left at its deadline", by_deadline.(i) ]) contracts) in
  let r = Bmc.run ~antecedent ~name ~depth ~step ~covers () in
  Bmc.report r;
  (match r.violation with
   | None -> ()
   | Some (kbad, model) ->
     let mons = List.map PC.deadline contracts in
     let fired = ref None in
     let watched = List.sort_uniq compare (List.map (fun (c : Props.contract) -> c.thread) contracts) in
     pr "  counterexample, the watched thread's slots (clock: address instruction | dl after | pin_in | slots since anchor):\n";
     replay ~store ~code model ~upto:kbad (fun k io t a instr _e st ->
         if List.mem t watched then begin
           let since = List.fold_left (fun acc (mon : PC.deadline) -> if mon.contract.thread = t then mon.since else acc) 0 mons in
           let addr_after = Isa2.fetch_addr st t in
           List.iter (fun (mon : PC.deadline) ->
               if mon.contract.thread = t then begin
                 let b, _, _ = PC.deadline_step mon ~addr_before:a ~addr_after ~io in
                 if b && !fired = None then fired := Some k
               end) mons;
           pr "    %4d: %d.%-3d %-28s | dl %4d | pin_in %s | %s\n" k (a lsr 8) (a land 0xFF) (Isa2.disasm instr) st.dls.(t)
             (String.init 8 (fun i -> if (io.pin_in lsr (7 - i)) land 1 = 1 then '1' else '0'))
             (if since = 0xFFFF then "-" else string_of_int since)
         end);
     check_replay ~expected:kbad ~fired:!fired);
  r

let a_main ~ldd ~name =
  let store = Programmes.store_of [| Programmes.idle; Programmes.deadline_program ~ldd; Programmes.idle; Programmes.idle |] in
  (* the contract: a window of 21 slots (84 clocks) from the LDD, as main.ml's test exercises *)
  let contract = { Props.thread = 1; anchor = addr ~thread:1 1; wait = addr ~thread:1 2; fail = addr ~thread:1 5;
                   slots = 21; kind = Waitp (1, 1) } in
  deadline ~name ~store ~code:[| Havoc; Fixed; Havoc; Havoc |] ~contracts:[ contract ] ~depth:160 ()

(* a control for the report itself: the same programme with the contract placed on an address
   thread 1 never reaches, so no violation is possible and the verdict must be VACUOUS, not PROVED *)
let a_vacuous ~name =
  let store = Programmes.store_of [| Programmes.idle; Programmes.deadline_program ~ldd:20; Programmes.idle; Programmes.idle |] in
  let contract = { Props.thread = 1; anchor = addr ~thread:1 1; wait = addr ~thread:1 200; fail = addr ~thread:1 5;
                   slots = 21; kind = Waitp (1, 1) } in
  deadline ~name ~store ~code:[| Havoc; Fixed; Havoc; Havoc |] ~contracts:[ contract ] ~depth:160 ()

(* [watch]: the threads whose contracts are checked (all three by default); [i2c_limit]: the I2C
   master's stretch limit (the compiler's default, 4095, by default); [waitp]: also a contract for
   every WAITP of the watched threads (Programmes.waitp_contracts). Every thread runs its
   programme whichever threads are watched, and every input is free on every clock. *)
let a_protocols ?(cut = false) ?(watch = [ 0; 1; 2 ]) ?i2c_limit ?(waitp = false) ?(depth = 720) ~spi_period ~name () =
  let u = Programmes.uart ~bit_slots:5 [ 0x4F ] and spi = Programmes.spi_with ~period:spi_period in
  let i2c = Programmes.i2c_with ?stretch_limit:i2c_limit () in
  let store = Programmes.store_of [| u; spi; i2c; Programmes.idle |] in
  let progs = [| u; spi; i2c |] in
  let contracts = List.concat_map (fun t ->
      Programmes.waitd_contracts ~thread:t progs.(t)
      @ (if waitp then Programmes.waitp_contracts ~thread:t progs.(t) else [])) watch in
  let nwaitp = List.length (List.filter (fun (c : Props.contract) -> c.kind <> Props.Waitd) contracts) in
  pr "(a) %d WAITD and %d WAITP contracts of threads %s (UART, SPI period %d slots, I2C stretch limit %d), all three running, %d clocks\n"
    (List.length contracts - nwaitp) nwaitp (String.concat "," (List.map string_of_int watch)) spi_period
    (Option.value i2c_limit ~default:4095) depth;
  deadline ~cut ~name ~store ~code:[| Fixed; Fixed; Fixed; Fixed |] ~contracts ~depth ()

(* ---- (b) pin ownership ---- *)

let ownership ~name ~timeout_mask ~depth =
  let progs = [| Programmes.uart ~bit_slots:5 [ 0x4F ]; Programmes.spi; Programmes.i2c; Programmes.watchdog ~timeout_mask |] in
  let store = Programmes.store_of progs in
  let code = [| Fixed; Fixed; Fixed; Fixed |] in
  let m = Machine.create ~store ~code () in
  let own = P.ownership () in
  let wrote = Array.make 4 Smt.ff in
  let step k =
    let io = Machine.io ~k in
    let t, _, e = Machine.clock m ~k io in
    wrote.(t) <- Smt.or_ wrote.(t) (Smt.not_ (Smt.eq e.pins_written (Smt.k ~w:8 0)));
    P.ownership_step own ~thread:t ~e, [] in
  (* the property can only fail once two threads have written pins *)
  let antecedent = "two threads write pins" in
  let two () = List.fold_left Smt.or_ Smt.ff
      (List.concat (List.init 4 (fun t -> List.init (3 - t) (fun j -> Smt.and_ wrote.(t) wrote.(t + j + 1))))) in
  let covers () = (antecedent, two ()) :: List.init 4 (fun t -> Printf.sprintf "thread %d writes pins" t, wrote.(t)) in
  let r = Bmc.run ~antecedent ~name ~depth ~step ~covers () in
  Bmc.report r;
  (match r.violation with
   | None -> ()
   | Some (kbad, model) ->
     let own = PC.ownership () in
     let fired = ref None in
     pr "  counterexample: pin writes and thread 3's slots (clock: thread address instruction -> pins written)\n";
     replay ~store ~code model ~upto:kbad (fun k io t a instr e _st ->
         if PC.ownership_step own ~thread:t ~e && !fired = None then fired := Some k;
         if t = 3 || (e.pins_written <> 0 && k > kbad - 40) then
           pr "    %4d: t%d %d.%-3d %-28s -> %02x%s\n" k t (a lsr 8) (a land 0xFF) (Isa2.disasm instr) e.pins_written
             (if t = 3 then Printf.sprintf "   (pin 6 in: %d)" ((io.pin_in lsr 6) land 1) else ""));
     pr "  pins written so far by thread: %s\n" (String.concat " " (Array.to_list (Array.mapi (fun t w -> Printf.sprintf "t%d=%02x" t w) own.written)));
     check_replay ~expected:kbad ~fired:!fired);
  r

(* ---- (c) isolation: a two-copy miter ---- *)

let isolation ~name ~ldb ~depth () =
  let u = Programmes.uart ~bit_slots:5 [ 0x4F; 0x4B ] in
  let store = Programmes.store_of [| u; Programmes.idle; Programmes.idle; Programmes.idle |] in
  (* planted: the transmitter takes its bytes from the shared data bank (LDB, from bp = 0 after
     reset) instead of from immediates *)
  if ldb then for pc = 0 to Isa2.page_len - 1 do if Programmes.opcode store.(pc) = Isa2.op_lda then store.(pc) <- Isa2.ldb done;
  let bank = [ (0, 0x4F); (1, 0x4B) ] in
  let code = [| Fixed; Havoc; Havoc; Havoc |] in
  let a = Machine.create ~prefix:"a." ~bank ~store ~code () and b = Machine.create ~prefix:"b." ~bank ~store ~code () in
  let others_differ = ref Smt.ff and uart_low = ref Smt.ff in
  let step k =
    let io = Machine.io ~k in
    let t, _, ea = Machine.clock a ~k io in
    let _, _, eb = Machine.clock b ~k io in
    let assumptions = if code.(t) = Havoc then [ P.keeps_off ~pins:0x01 ea; P.keeps_off ~pins:0x01 eb ] else [] in
    flag_or others_differ (P.pins_differ ~pins:0xFE a.st b.st);
    flag_or uart_low (Smt.not_ (Smt.eq (Smt.extract a.st.pin_out ~hi:0 ~lo:0) (Smt.k ~w:1 1)));
    (* no Machine.cut here: the copies' identical terms are shared, which the cut would undo (at
       16 clocks the solver took 5.9 s with it and 0.3 s without) *)
    P.pins_differ ~pins:0x01 a.st b.st, assumptions in
  let c_differ = "the other threads make the copies' other pins differ" and c_low = "the transmitter drives its pin low" in
  let covers () = [ c_differ, !others_differ; c_low, !uart_low ] in
  (* Concrete witnesses for the two covers, which the solver could not answer in 22 minutes on
     its own: every input 0 and every unconstrained word a NOP, except, for the first, copy a's
     thread 1 setting pin 1 at its first slot (clock 1). Each witness is first replayed on
     Isa2.Spec through the same conditions; the solver then checks it as a satisfying assignment
     of the unrolled miter, assumptions included. *)
  let setp_pin1 = Isa2.setp ~mask:0x02 ~value:1 ~oe:1 () in
  let w_differ n = Some (if n = "a.instr1@1" then setp_pin1 else 0) and w_low _ = Some 0 in
  let replay_cover w =
    let m = Hashtbl.create 16 in
    List.iter (fun k -> let n = Printf.sprintf "a.instr1@%d" k in Hashtbl.replace m n (Option.get (w n))) (List.init depth Fun.id);
    let ca = Machine.concrete ~prefix:"a." ~bank ~store ~code () and cb = Machine.concrete ~prefix:"b." ~bank ~store ~code () in
    let first_differ = ref None and first_low = ref None in
    for k = 0 to depth - 1 do
      let io = Machine.concrete_io m ~k in
      let t, _, _, ea = Machine.concrete_clock ca m ~k io in
      let _, _, _, eb = Machine.concrete_clock cb m ~k io in
      if code.(t) = Havoc && not (PC.keeps_off ~pins:0x01 ea && PC.keeps_off ~pins:0x01 eb) then failwith "witness breaks the assumption";
      if !first_differ = None && PC.pins_differ ~pins:0xFE ca.cst cb.cst then first_differ := Some k;
      if !first_low = None && ca.cst.pin_out land 1 = 0 then first_low := Some k
    done;
    (!first_differ, !first_low) in
  let show = function Some k -> Printf.sprintf "clock %d" k | None -> "never" in
  let d1, _ = replay_cover w_differ and _, l2 = replay_cover w_low in
  pr "  witnesses replayed on Isa2.Spec: '%s' holds from %s; '%s' from %s\n" c_differ (show d1) c_low (show l2);
  let witnesses = (if d1 <> None then [ c_differ, w_differ ] else []) @ (if l2 <> None then [ c_low, w_low ] else []) in
  (* the property says something only once the other threads disturb their copies differently *)
  let r = Bmc.run ~progress:4 ~witnesses ~antecedent:c_differ ~name ~depth ~step ~covers () in
  Bmc.report r;
  (match r.violation with
   | None -> ()
   | Some (kbad, model) ->
     pr "  counterexample: the two copies side by side (clock: thread, copy a | copy b; pin 0 after the clock)\n";
     let ca = Machine.concrete ~prefix:"a." ~bank ~store ~code () and cb = Machine.concrete ~prefix:"b." ~bank ~store ~code () in
     let fired = ref None in
     for k = 0 to kbad do
       let io = Machine.concrete_io model ~k in
       let t, aa, ia, ea = Machine.concrete_clock ca model ~k io in
       let _, ab, ib, eb = Machine.concrete_clock cb model ~k io in
       let d = PC.pins_differ ~pins:0x01 ca.cst cb.cst in
       if d && !fired = None then fired := Some k;
       let wrote (v, _, _) = v in
       let bw (v, ad, x) = if v then Printf.sprintf " [bank %d <- %02x]" ad x else "" in
       let reads_bank = Programmes.opcode ia = Isa2.op_ext && (ia lsr 8) land 15 = Isa2.x_ldb in
       if wrote ea.bank_write || wrote eb.bank_write || (t = 0 && (reads_bank || k > kbad - 24)) then
         pr "    %4d: t%d %-24s%s | %-24s%s | pin0 %d %d\n" k t (Isa2.disasm ia) (bw ea.bank_write) (Isa2.disasm ib) (bw eb.bank_write)
           (ca.cst.pin_out land 1) (cb.cst.pin_out land 1);
       ignore (aa, ab)
     done;
     check_replay ~expected:kbad ~fired:!fired);
  r

(* The same miter without a depth bound: a relational induction step. R(a, b) says the copies
   agree on everything thread 0 owns or reads: its registers, pin 0's level, output enable and
   quarter-clock levels, and the round latch. Everything else (the other threads' registers, the
   other pins, inboxes, the data bank) is a separate free variable in each copy, and thread 0's pc
   is any address it can reach. If R before a round (thread 0's clock, then three clocks of
   arbitrary instructions that keep off pin 0) implies pin 0 equal after every clock and R after
   the round, then, since both copies start from the same reset state, pin 0 agrees at every
   clock of every run: isolation without a bound. *)
(* [owned]: the bank ownership of ownership.ml as well (README, "isolation with the bank"):
   thread 0 may read bank addresses 0 and 1 (its two bytes, with ~ldb), the other threads may
   write anything but those ([others_write], 2..1023); every thread is assumed to keep to its declaration (each such
   assumption is a property checked on its own, statically and by scenario e-bank), and R also
   says the copies agree on bank addresses 0 and 1. *)
let isolation_induction ?(assume = true) ?(owned = false) ?(others_write = (2, 1023)) ~name ~ldb () =
  let u = Programmes.uart ~bit_slots:5 [ 0x4F; 0x4B ] in
  let store = Programmes.store_of [| u; Programmes.idle; Programmes.idle; Programmes.idle |] in
  if ldb then for pc = 0 to Isa2.page_len - 1 do if Programmes.opcode store.(pc) = Isa2.op_lda then store.(pc) <- Isa2.ldb done;
  let reach = Lustre.cfg_closure store ~start:(addr ~thread:0 0) in
  let code = [| Fixed; Havoc; Havoc; Havoc |] in
  let v name w = Smt.var name (Smt.Bv w) in
  let shared name w = v ("r." ^ name) w in
  (* thread 0's registers: one variable for both copies; the rest: one per copy *)
  let regs pfx name w = Array.init Isa2.n_threads (fun t -> if t = 0 then shared (name ^ "0") w else v (Printf.sprintf "%s%s%d" pfx name t) w) in
  let pins pfx name w keep = Smt.logor (Smt.logand (v (pfx ^ name) w) (Smt.k ~w (lnot keep))) (Smt.logand (shared name w) (Smt.k ~w keep)) in
  let state pfx : Sym.state =
    { pcs = regs pfx "pc" 8; pages = Array.init 4 (fun t -> Smt.k ~w:2 t); accs = regs pfx "acc" 8; cnts = regs pfx "cnt" 12;
      dls = regs pfx "dl" 12; bps = regs pfx "bp" 10; fines = regs pfx "fine" 8; armed = regs pfx "armed" 1;
      cfgs = regs pfx "cfg" 8; lsend = regs pfx "lsend" 3;
      inbox = Array.init 4 (fun i -> v (Printf.sprintf "%sinbox%d" pfx i) 8); full = Array.init 4 (fun i -> v (Printf.sprintf "%sfull%d" pfx i) 1);
      pin_out = pins pfx "pin_out" 8 0x01; pin_oe = pins pfx "pin_oe" 8 0x01; pin_sub = pins pfx "pin_sub" 32 0xF;
      thread = 0; latch = shared "latch" 8; bankmem = Smt.mem_var (pfx ^ "bank") } in
  let mk pfx = { Machine.prefix = pfx; st = state pfx; store; code; reach = [| Some reach; None; None; None |] } in
  let a = mk "a." and b = mk "b." in
  let s0 = a.st in
  let in_reach = List.fold_left (fun acc x -> Smt.or_ acc (Smt.eq s0.pcs.(0) (Smt.k ~w:8 (x land 0xFF)))) Smt.ff reach in
  let own : Ownership.t =
    let n = Ownership.nothing and all = [ 0; 1; 2; 3 ] in
    let other = { Ownership.bank_read = [ (0, 1023) ]; bank_write = [ others_write ]; inbox_send = all; inbox_recv = all; port_out = all; port_in = all } in
    [| { n with bank_read = [ (0, 1) ] }; other; other; other |] in
  let cells_equal () =
    List.fold_left Smt.and_ Smt.tt
      (List.map (fun i -> Smt.eq (Smt.select a.st.bankmem (Smt.k ~w:10 i)) (Smt.select b.st.bankmem (Smt.k ~w:10 i))) [ 0; 1 ]) in
  let assumptions = ref ([ in_reach ] @ if owned then [ cells_equal () ] else []) and differ = ref Smt.ff in
  for k = 0 to 3 do
    let io = Machine.io ~k in
    let t, _, ea = Machine.clock a ~k io in
    let _, _, eb = Machine.clock b ~k io in
    if assume && code.(t) = Havoc then assumptions := P.keeps_off ~pins:0x01 ea :: P.keeps_off ~pins:0x01 eb :: !assumptions;
    if owned then assumptions := P.obeys own.(t) ea :: P.obeys own.(t) eb :: !assumptions;
    differ := Smt.or_ !differ (P.pins_differ ~pins:0x01 a.st b.st)
  done;
  let eq0 f = Smt.eq (f a.st).(0) (f b.st).(0) in
  let r_after = List.fold_left Smt.and_ (if owned then Smt.and_ (cells_equal ()) (Smt.eq a.st.latch b.st.latch) else Smt.eq a.st.latch b.st.latch)
      [ eq0 (fun s -> s.Isa2.pcs); eq0 (fun s -> s.Isa2.accs); eq0 (fun s -> s.Isa2.cnts); eq0 (fun s -> s.Isa2.dls);
        eq0 (fun s -> s.Isa2.bps); eq0 (fun s -> s.Isa2.fines); eq0 (fun s -> s.Isa2.armed); eq0 (fun s -> s.Isa2.cfgs);
        eq0 (fun s -> s.Isa2.lsend) ] in
  let goal = Smt.or_ !differ (Smt.not_ r_after) in
  let t0 = Unix.gettimeofday () in
  let sv = Smt.Solver.start ?log:(Option.map (fun d -> Filename.concat d (name ^ ".smt2")) (Bmc.log_dir ())) () in
  List.iter (Smt.Solver.assert_ sv) !assumptions;
  (* non-vacuity: the assumptions alone must be satisfiable, or "inductive" would mean nothing *)
  let consistent = Smt.Solver.check sv = `Sat in
  Smt.Solver.assert_ sv goal;
  let r = Smt.Solver.check sv in
  let defs = sv.Smt.Solver.defs in
  let cti = match r with
    | `Sat ->
      let vals = Smt.Solver.get_values sv (List.filter (fun (x : Smt.term) -> x.sort <> Smt.Mem) sv.Smt.Solver.vars) in
      let g n = List.assoc_opt n (List.map (fun ((x : Smt.term), v) -> ((match x.node with Var n -> n | _ -> ""), v)) vals) in
      Some (Option.value (g "r.pc0") ~default:(-1))
    | _ -> None in
  Smt.Solver.close sv;
  pr "%s: %s; assumptions %s; thread 0 can be at %d addresses; %d definitions, %.2f s\n" name
    (match r with
     | `Unsat -> "the relation is inductive: pin 0 cannot depend on the other threads, at any depth"
     | `Sat -> Printf.sprintf "NOT inductive (a counterexample to induction with thread 0 at pc %d)"
                 (Option.value cti ~default:(-1))
     | `Unknown e -> "unknown: " ^ e)
    (if consistent then "satisfiable" else "CONTRADICTORY (vacuous)") (List.length reach) defs (Unix.gettimeofday () -. t0);
  (* the antecedent of an induction step is its hypotheses: unsatisfiable hypotheses prove
     anything, so they make the verdict VACUOUS *)
  pr "PROPERTY %s: %s\n" name
    (match r, consistent with
     | _, false -> "VACUOUS (the induction hypotheses are contradictory)"
     | `Unsat, true -> "PROVED (unbounded, by induction); hypotheses satisfiable"
     | `Sat, true -> "FAILED (not inductive)"
     | `Unknown e, true -> "UNDECIDED (" ^ e ^ ")")

(* ---- (d) UART transmitter, every byte ---- *)

(* [anytime]: the host's byte may arrive at any clock (host_in_valid free); otherwise it is always
   ready, which fixes the timing and leaves only the data free *)
let uart_functional ~name ?stretch ?(anytime = false) ~bytes ~depth () =
  let bit_slots = 5 in
  let u = Programmes.uart_from_host ?stretch ~bit_slots bytes in
  let store = Programmes.store_of [| u; Programmes.idle; Programmes.idle; Programmes.idle |] in
  let code = [| Fixed; Fixed; Fixed; Fixed |] in
  let m = Machine.create ~store ~code () in
  let rx = P.uart_rx ~pin:0 ~bit_clocks:(4 * bit_slots) ~tx_thread:0 in
  let step k =
    let io = Machine.io ~k in
    let io = if anytime then io else { io with host_in_valid = Smt.tt } in
    let t, _, e = Machine.clock m ~k io in
    P.uart_rx_step rx ~thread:t ~io ~e ~st:m.st, [] in
  (* the receiver checks samples only inside a frame: a whole frame sampled is the antecedent *)
  let antecedent = "a frame is sampled" in
  let covers () = [ antecedent, Smt.not_ (Smt.eq rx.frames (Smt.k ~w:8 0));
                    Printf.sprintf "%d frames received" bytes, Smt.eq rx.frames (Smt.k ~w:8 bytes) ] in
  let r = Bmc.run ~progress:(if anytime then 4 else 100) ~antecedent ~name ~depth ~step ~covers () in
  Bmc.report r;
  (match r.violation with
   | None -> ()
   | Some (kbad, model) ->
     if not anytime then for k = 0 to kbad do Hashtbl.replace model (Printf.sprintf "host_in_valid@%d" k) 1 done;
     let rx = PC.uart_rx ~pin:0 ~bit_clocks:(4 * bit_slots) ~tx_thread:0 in
     let fired = ref None and line = Buffer.create 1024 in
     let bytes = ref [] in
     replay ~store ~code model ~upto:kbad (fun k io t _a _instr e st ->
         if t = 0 && e.host_in_ready then bytes := (k, io.host_in) :: !bytes;
         if PC.uart_rx_step rx ~thread:t ~io ~e ~st && !fired = None then fired := Some k;
         Buffer.add_char line (if (st.pin_oe land 1) = 0 || (st.pin_out land 1) = 1 then '1' else '0'));
     List.iter (fun (k, b) -> pr "  the host's byte, taken at clock %d: 0x%02x = %s (lsb first on the line: %s)\n" k b
                   (String.init 8 (fun i -> if (b lsr (7 - i)) land 1 = 1 then '1' else '0'))
                   (String.init 8 (fun i -> if (b lsr i) land 1 = 1 then '1' else '0'))) (List.rev !bytes);
     let s = Buffer.contents line in
     let start = try String.index s '0' with Not_found -> 0 in
     pr "  the line from the start edge (clock %d), one character per clock, '|' every bit period (%d clocks):\n    " start (4 * bit_slots);
     String.iteri (fun i ch -> if i >= start then begin
         if (i - start) mod (4 * bit_slots) = 0 then print_char '|';
         print_char ch end) s;
     print_newline ();
     pr "  the receiver samples %d clocks after each '|'\n" (2 * bit_slots);
     check_replay ~expected:kbad ~fired:!fired);
  r

(* ---- export for Kind 2 (task 3): the (a) programme and contract, one round per Lustre step ---- *)

let export_kind2 ~ldd ~file =
  let store = Programmes.store_of [| Programmes.idle; Programmes.deadline_program ~ldd; Programmes.idle; Programmes.idle |] in
  let st, slots = Lustre.state_slots () in
  let reach = Lustre.cfg_closure store ~start:(addr ~thread:1 0) in
  let m = { Machine.prefix = ""; st; store; code = [| Havoc; Fixed; Havoc; Havoc |];
            reach = [| None; Some reach; None; None |] } in
  let contract = { Props.thread = 1; anchor = addr ~thread:1 1; wait = addr ~thread:1 2; fail = addr ~thread:1 5;
                   slots = 21; kind = Waitp (1, 1) } in
  let mon = P.deadline contract in
  let since = Smt.var "since" (Smt.Bv 16) in
  mon.since <- since;
  let in_reach = List.fold_left (fun acc a ->
      Smt.or_ acc (Smt.and_ (Smt.eq st.pcs.(1) (Smt.k ~w:8 (a land 0xFF))) (Smt.eq st.pages.(1) (Smt.k ~w:2 (a lsr 8)))))
      Smt.ff reach in
  let bad = ref Smt.ff in
  for k = 0 to 3 do
    let io = Machine.io ~k in
    let t, addr_before, _ = Machine.clock m ~k io in
    if t = 1 then begin
      let b, _, _ = P.deadline_step mon ~addr_before ~addr_after:(Sym.fetch_addr m.st t) ~io in
      bad := Smt.or_ !bad b
    end
  done;
  let since_slot = { Lustre.sname = "since"; var = since; init = 0xFFFF; next = (let n = mon.since in fun _ -> n) } in
  let oc = open_out file in
  let ns, ni, ne = Lustre.write oc ~node:"deadline" ~ok:(Smt.and_ in_reach (Smt.not_ !bad)) ~slots:(since_slot :: slots) ~final:m.st in
  close_out oc;
  pr "%s: thread 1 can be at %d addresses; %d state variables, %d inputs, %d equations in the cone of the property\n"
    file (List.length reach) ns ni ne

(* (d) for Kind 2: thread 0 transmits [bytes] bytes taken from the host, the receiver monitor's
   registers become state variables; [anytime]: the host's byte may arrive at any clock *)
let export_kind2_uart ?stretch ~anytime ~bytes ~file () =
  let bit_slots = 5 in
  let u = Programmes.uart_from_host ?stretch ~bit_slots bytes in
  let store = Programmes.store_of [| u; Programmes.idle; Programmes.idle; Programmes.idle |] in
  let st, slots = Lustre.state_slots () in
  let reach = Lustre.cfg_closure store ~start:(addr ~thread:0 0) in
  let idle t = Lustre.cfg_closure store ~start:(addr ~thread:t 0) in
  let m = { Machine.prefix = ""; st; store; code = [| Fixed; Fixed; Fixed; Fixed |];
            reach = [| Some reach; Some (idle 1); Some (idle 2); Some (idle 3) |] } in
  let rx = P.uart_rx ~pin:0 ~bit_clocks:(4 * bit_slots) ~tx_thread:0 in
  let mon name w get set init =
    let v = Smt.var name (Smt.Bv w) in set v; (v, name, w, get, init) in
  let mons = [ mon "rx_busy" 1 (fun () -> rx.busy) (fun v -> rx.busy <- v) 0;
               mon "rx_count" 16 (fun () -> rx.count) (fun v -> rx.count <- v) 0;
               mon "rx_byte" 8 (fun () -> rx.byte) (fun v -> rx.byte <- v) 0;
               mon "rx_frames" 8 (fun () -> rx.frames) (fun v -> rx.frames <- v) 0 ] in
  let in_reach = List.fold_left (fun acc a -> Smt.or_ acc (Smt.eq st.pcs.(0) (Smt.k ~w:8 (a land 0xFF)))) Smt.ff reach in
  let bad = ref Smt.ff in
  for k = 0 to 3 do
    let io = Machine.io ~k in
    let io = if anytime then io else { io with host_in_valid = Smt.tt } in
    let t, _, e = Machine.clock m ~k io in
    bad := Smt.or_ !bad (P.uart_rx_step rx ~thread:t ~io ~e ~st:m.st)
  done;
  let mon_slots = List.map (fun (v, name, _, get, init) -> let n = get () in { Lustre.sname = name; var = v; init; next = (fun _ -> n) }) mons in
  let oc = open_out file in
  let ns, ni, ne = Lustre.write oc ~node:"uart" ~ok:(Smt.and_ in_reach (Smt.not_ !bad)) ~slots:(mon_slots @ slots) ~final:m.st in
  close_out oc;
  pr "%s: %d state variables, %d inputs, %d equations in the cone of the property\n" file ns ni ne

(* ---- (e) ownership of the bank, the inboxes and the ports (ownership.ml) ---- *)

(* v2 words, thread t's at page t *)
let store_v2 (progs : int array array) =
  let s = Array.make Isa2.store_len 0 in
  Array.iteri (fun t p -> Array.iteri (fun pc w -> s.(Programmes.addr ~thread:t pc) <- w) p) progs;
  s

(* Bridge A's declaration, as in ../verif-oracles/hazard-mp/hazard_bridge.ml *)
let bridge_owns () : Ownership.t =
  let n = Ownership.nothing in
  [| { n with inbox_send = [ 1 ] }; { n with inbox_recv = [ 1 ]; inbox_send = [ 2 ] }; { n with inbox_recv = [ 2 ] }; n |]

(* A concrete input sequence for bridge A: the host sends [byte] on the UART line (pin 0) from
   clock [start], 8N1 at the bridge's bit period; every other pin input reads 1 (the I2C lines
   released and never stretched); no host or port traffic. As a function from variable name to
   value, for Machine's models and Bmc's witnesses. *)
let uart_stimulus ~start ~byte =
  let bit_clocks = Bridge_fw.Bridge_a_words.uart_bit_clocks in
  let line k =
    if k < start then 1
    else let i = (k - start) / bit_clocks in
      if i = 0 then 0 else if i <= 8 then (byte lsr (i - 1)) land 1 else 1 in
  fun name ->
    match String.index_opt name '@' with
    | None -> None
    | Some j ->
      let k = int_of_string (String.sub name (j + 1) (String.length name - j - 1)) and base = String.sub name 0 j in
      let pins = 0xFE lor line k in
      if base = "pin_in" then Some pins else if base = "pin_in4" then Some (Isa2.replicate4 pins)
      else if String.length base >= 4 && String.sub base 0 4 = "cut." then None else Some 0

let resources ~name ?(plant = fun (_ : int array array) -> ()) ~owns ~depth () =
  (* the declaration must keep the rules on declarations before a run means anything *)
  (match Ownership.conflicts owns with
   | [] -> ()
   | l -> failwith (name ^ ": the ownership declaration breaks its rules: " ^ String.concat "; " l));
  let progs = Bridge_fw.Bridge_a_words.threads () in
  plant progs;
  let store = store_v2 progs in
  let code = [| Fixed; Fixed; Fixed; Fixed |] in
  let m = Machine.create ~store ~code () in
  (* non-vacuity: every inbox a thread is declared to use is touched by it *)
  let touched = Hashtbl.create 8 in
  let touch key x = Hashtbl.replace touched key (Smt.or_ (Option.value (Hashtbl.find_opt touched key) ~default:Smt.ff) x) in
  let step k =
    let io = Machine.io ~k in
    let t, _, e = Machine.clock m ~k io in
    List.iter (fun i -> touch (Printf.sprintf "T%d sends to inbox %d" t i) (Smt.not_ (Smt.eq (Smt.extract e.inbox_send ~hi:i ~lo:i) (Smt.k ~w:1 0))))
      owns.(t).Ownership.inbox_send;
    List.iter (fun i -> touch (Printf.sprintf "T%d receives from inbox %d" t i) (Smt.not_ (Smt.eq (Smt.extract e.inbox_recv ~hi:i ~lo:i) (Smt.k ~w:1 0))))
      owns.(t).Ownership.inbox_recv;
    let bad = P.resources_step owns ~thread:t ~e in
    bad, Machine.cut m ~k in
  (* the antecedent: some thread touches an inbox at all *)
  let antecedent = "some thread sends to or receives from an inbox" in
  let covers () =
    (antecedent, Hashtbl.fold (fun _ v acc -> Smt.or_ acc v) touched Smt.ff)
    :: List.sort compare (Hashtbl.fold (fun k v acc -> (k, v) :: acc) touched []) in
  (* one witness for every cover: the host sends ACK (0x10), which T0 receives and passes to T1,
     whose I2C master acknowledges and answers into inbox 2; replayed on Isa2.Spec first *)
  let w = uart_stimulus ~start:8 ~byte:Bridge_fw.Bridge_a_words.op_ack in
  (* the replay runs past the bound, to show where the covers the bound cannot reach are reached *)
  let horizon = max depth 1200 in
  let model = Hashtbl.create 4096 in
  List.iter (fun k -> List.iter (fun b -> let n = Printf.sprintf "%s@%d" b k in Hashtbl.replace model n (Option.get (w n))) [ "pin_in"; "pin_in4" ])
    (List.init horizon Fun.id);
  let seen = Hashtbl.create 8 in
  replay ~store ~code model ~upto:(horizon - 1) (fun k _ t _ _ e _ ->
      List.iter (fun i -> if (e.inbox_send lsr i) land 1 = 1 && not (Hashtbl.mem seen (Printf.sprintf "T%d sends to inbox %d" t i)) then
                    Hashtbl.replace seen (Printf.sprintf "T%d sends to inbox %d" t i) k) [ 0; 1; 2; 3 ];
      List.iter (fun i -> if (e.inbox_recv lsr i) land 1 = 1 && not (Hashtbl.mem seen (Printf.sprintf "T%d receives from inbox %d" t i)) then
                    Hashtbl.replace seen (Printf.sprintf "T%d receives from inbox %d" t i) k) [ 0; 1; 2; 3 ]);
  pr "  witness (the host sends 0x%02x from clock 8), replayed on Isa2.Spec: %s\n" Bridge_fw.Bridge_a_words.op_ack
    (String.concat "; " (List.sort compare (Hashtbl.fold (fun n k acc -> Printf.sprintf "%s at clock %d" n k :: acc) seen [])));
  let witnesses = Hashtbl.fold (fun n k acc -> if k < depth then (n, w) :: acc else acc) seen [] in
  let witnesses = if witnesses <> [] then (antecedent, w) :: witnesses else witnesses in
  Hashtbl.iter (fun n k -> if k >= depth then pr "  (cover '%s' is reached at clock %d, beyond the bound of %d)\n" n k depth) seen;
  let r = Bmc.run ~progress:50 ~witnesses ~antecedent ~name ~depth ~step ~covers () in
  Bmc.report r;
  (match r.violation with
   | None -> ()
   | Some (kbad, model) ->
     let fired = ref None in
     pr "  counterexample: the offending clock and the UART line before it\n";
     replay ~store ~code model ~upto:kbad (fun k io t a instr e _ ->
         if PC.resources_step owns ~thread:t ~e && !fired = None then begin
           fired := Some k;
           pr "    %4d: t%d %d.%-3d %-28s inbox send %x recv %x, port out %x in %x, bank read %s write %s\n" k t (a lsr 8) (a land 0xFF)
             (Isa2.disasm instr) e.inbox_send e.inbox_recv e.port_out e.port_in
             (let v, x = e.bank_read in if v then string_of_int x else "-") (let v, x, _ = e.bank_write in if v then string_of_int x else "-")
         end;
         ignore io);
     let falls = ref [] in
     replay ~store ~code model ~upto:kbad (fun k io _ _ _ _ _ ->
         if k > 0 && io.pin_in land 1 = 0 && List.length !falls < 12 then falls := k :: !falls);
     pr "    the UART line (pin 0) is low at clocks %s ...\n" (String.concat "," (List.rev_map string_of_int !falls));
     check_replay ~expected:kbad ~fired:!fired);
  r

(* The bank under ownership: the UART of (c) taking its two bytes from bank addresses 0 and 1
   (LDB, the planted variant of the isolation check), thread 0 declared to read addresses
   [reads]; the other threads idle and own nothing. Every LDB's address is in the range at every
   clock, or the counterexample shows the first that is not. *)
let bank_ownership ~name ~reads ~depth =
  let u = Programmes.uart ~bit_slots:5 [ 0x4F; 0x4B ] in
  let store = Programmes.store_of [| u; Programmes.idle; Programmes.idle; Programmes.idle |] in
  for pc = 0 to Isa2.page_len - 1 do if Programmes.opcode store.(pc) = Isa2.op_lda then store.(pc) <- Isa2.ldb done;
  let bank = [ (0, 0x4F); (1, 0x4B) ] in
  let owns = Ownership.none () in
  owns.(0) <- { Ownership.nothing with bank_read = reads };
  let code = [| Fixed; Fixed; Fixed; Fixed |] in
  let m = Machine.create ~bank ~store ~code () in
  let read = Array.make 2 Smt.ff and any_read = ref Smt.ff in
  let step k =
    let io = Machine.io ~k in
    let t, _, e = Machine.clock m ~k io in
    let rd, ra = e.bank_read in
    any_read := Smt.or_ !any_read rd;
    Array.iteri (fun i r -> read.(i) <- Smt.or_ r (Smt.and_ rd (Smt.eq ra (Smt.k ~w:10 i)))) read;
    P.resources_step owns ~thread:t ~e, [] in
  let antecedent = "thread 0 reads the bank" in
  let covers () = (antecedent, !any_read)
                  :: List.init 2 (fun i -> Printf.sprintf "thread 0 reads bank address %d" i, read.(i)) in
  let r = Bmc.run ~antecedent ~name ~depth ~step ~covers () in
  Bmc.report r;
  (match r.violation with
   | None -> ()
   | Some (kbad, model) ->
     let fired = ref None in
     replay ~bank ~store ~code model ~upto:kbad (fun k _ t a instr e _ ->
         let rd, ra = e.bank_read in
         if rd then pr "    %4d: t%d %d.%-3d %-28s reads bank address %d\n" k t (a lsr 8) (a land 0xFF) (Isa2.disasm instr) ra;
         if PC.resources_step owns ~thread:t ~e && !fired = None then fired := Some k);
     check_replay ~expected:kbad ~fired:!fired);
  r

(* The rules on declarations themselves (Ownership.conflicts), on bridge A's declaration and on
   planted variants of it; the hazard checker applies the same function (its OWNERSHIP rule). *)
let declarations () =
  let show name (o : Ownership.t) =
    match Ownership.conflicts o with
    | [] -> pr "DECLARATION %s: keeps the rules\n" name
    | l -> pr "DECLARATION %s: REJECTED: %s\n" name (String.concat "; " l) in
  let a = bridge_owns () in
  show "bridge A" a;
  let with_ t f = let o = Array.copy a in o.(t) <- f o.(t); o in
  show "bridge A, planted: T3 also declared to receive from inbox 2"
    (with_ 3 (fun th -> { th with Ownership.inbox_recv = [ 2 ] }));
  show "bridge A, planted: T3 also declared to send to inbox 1"
    (with_ 3 (fun th -> { th with Ownership.inbox_send = [ 1 ] }));
  show "bridge A, planted: T2 no longer declared to receive from inbox 2"
    (with_ 2 (fun th -> { th with Ownership.inbox_recv = [] }));
  show "bridge A, planted: T0 and T3 both declared to write bank 0..15"
    (let o = with_ 0 (fun th -> { th with Ownership.bank_write = [ (0, 15) ] }) in
     o.(3) <- { (o.(3)) with Ownership.bank_write = [ (8, 23) ] }; o)

let scenarios = [
  "e-declarations", declarations;
  "a", (fun () -> ignore (a_main ~ldd:20 ~name:"a-deadline-main.ml-programme"));
  "a-planted", (fun () -> ignore (a_main ~ldd:21 ~name:"a-deadline-planted-ldd21"));
  "a-vacuous-planted", (fun () -> ignore (a_vacuous ~name:"a-deadline-planted-unreachable-wait"));
  "a-protocols", (fun () -> ignore (a_protocols ~spi_period:10 ~name:"a-waitd-uart-spi-i2c" ()));
  "a-protocols-cut", (fun () -> ignore (a_protocols ~cut:true ~spi_period:10 ~name:"a-waitd-uart-spi-i2c-cut" ()));
  "a-spi8", (fun () -> ignore (a_protocols ~spi_period:8 ~name:"a-waitd-uart-spi8-i2c" ()));
  (* a-protocols split (README.md, Findings 4): the UART's and SPI's contracts beside the real I2C
     master (stretch limit 4095), and the I2C master's own WAITD and WAITP contracts with a short
     stretch limit *)
  "a-protocols-uart-spi", (fun () ->
      ignore (a_protocols ~watch:[ 0; 1 ] ~spi_period:10 ~name:"a-waitd-uart-spi-beside-i2c-l4095" ()));
  "a-protocols-i2c-l1", (fun () ->
      ignore (a_protocols ~watch:[ 2 ] ~i2c_limit:1 ~waitp:true ~spi_period:10 ~name:"a-waitd-waitp-i2c-l1" ()));
  "a-protocols-i2c-l2", (fun () ->
      ignore (a_protocols ~watch:[ 2 ] ~i2c_limit:2 ~waitp:true ~spi_period:10 ~name:"a-waitd-waitp-i2c-l2" ()));
  "a-protocols-i2c-l2-cut", (fun () ->
      ignore (a_protocols ~cut:true ~watch:[ 2 ] ~i2c_limit:2 ~waitp:true ~spi_period:10 ~name:"a-waitd-waitp-i2c-l2-cut" ()));
  "b", (fun () -> ignore (ownership ~name:"b-ownership" ~timeout_mask:0x80 ~depth:720));
  "b-planted", (fun () -> ignore (ownership ~name:"b-ownership-planted-mask01" ~timeout_mask:0x01 ~depth:720));
  "c", (fun () -> ignore (isolation ~name:"c-isolation-uart" ~ldb:false ~depth:36 ()));
  (* 300 clocks: with the cut the unrolling grows linearly (about 525 definitions a clock), but
     the solver's time per goal does not: 126 s in all at 300 clocks, and it had not reached 400
     after a further 10 minutes *)
  "e", (fun () -> ignore (resources ~name:"e-ownership-bridge-a" ~owns:(bridge_owns ()) ~depth:300 ()));
  "e-bank", (fun () -> ignore (bank_ownership ~name:"e-bank-uart-reads-0..1" ~reads:[ (0, 1) ] ~depth:440));
  "e-bank-planted", (fun () -> ignore (bank_ownership ~name:"e-bank-uart-declared-0-only" ~reads:[ (0, 0) ] ~depth:440));
  "e-planted-steal", (fun () ->
      ignore (resources ~name:"e-ownership-planted-t3-receives-inbox-2" ~owns:(bridge_owns ())
                ~plant:(fun p -> p.(3).(0) <- Isa2.recv ~ch:2 ~fail:0) ~depth:40 ()));
  "c-short", (fun () -> ignore (isolation ~name:"c-isolation-uart-16" ~ldb:false ~depth:16 ()));
  "c-induction", (fun () -> isolation_induction ~name:"c-isolation-uart-induction" ~ldb:false ());
  "c-induction-planted", (fun () -> isolation_induction ~name:"c-isolation-planted-ldb-induction" ~ldb:true ());
  "c-induction-ldb-owned", (fun () ->
      isolation_induction ~owned:true ~name:"c-isolation-ldb-with-bank-ownership-induction" ~ldb:true ());
  "c-induction-ldb-owned-overlap", (fun () ->
      isolation_induction ~owned:true ~others_write:(1, 1023)
        ~name:"c-isolation-ldb-others-may-write-address-1-induction" ~ldb:true ());
  "c-induction-no-ownership", (fun () ->
      isolation_induction ~assume:false ~name:"c-isolation-uart-induction-without-ownership-assumption" ~ldb:false ());
  "c-planted", (fun () -> ignore (isolation ~name:"c-isolation-planted-ldb" ~ldb:true ~depth:440 ()));
  "kind2-export", (fun () ->
      export_kind2 ~ldd:20 ~file:"kind2/deadline-ldd20.lus"; export_kind2 ~ldd:21 ~file:"kind2/deadline-ldd21.lus";
      export_kind2_uart ~anytime:false ~bytes:1 ~file:"kind2/uart-every-byte.lus" ();
      export_kind2_uart ~anytime:true ~bytes:1 ~file:"kind2/uart-every-byte-any-arrival.lus" ();
      export_kind2_uart ~stretch:(3, 3) ~anytime:false ~bytes:1 ~file:"kind2/uart-planted-stretch.lus" ());
  "d", (fun () -> ignore (uart_functional ~name:"d-uart-every-byte" ~bytes:2 ~depth:440 ()));
  "d-planted", (fun () -> ignore (uart_functional ~name:"d-uart-planted-stretch" ~stretch:(3, 3) ~bytes:2 ~depth:440 ()));
  "d-anytime", (fun () -> ignore (uart_functional ~name:"d-uart-every-byte-any-arrival" ~anytime:true ~bytes:1 ~depth:208 ()));
]

let () =
  let names = match Array.to_list Sys.argv with _ :: (_ :: _ as l) -> l | _ -> List.map fst scenarios in
  List.iter (fun n ->
      match List.assoc_opt n scenarios with
      | Some f -> f (); print_newline ()
      | None -> failwith ("unknown scenario " ^ n)) names
