(* Task 3: I2C controller at Standard-mode (100 kHz) and Fast-mode (400 kHz), with reads,
   repeated start and clock stretching, against the timing limits of the I2C specification.

   The bus is the open-drain model of peers.ml with edge times: a falling line reads low tf
   clocks after it starts to fall, a released one high tr clocks after release. Each mode runs at
   the four corners of tr, tf in {0, the specification's maximum}. On the trace each parameter
   is measured conservatively: an interval that ends at an edge is taken to the edge's start (the
   moment a device starts or stops pulling), one that starts at an edge from the edge's end (the
   level reached), so the measured value is at most the true one, whatever the thresholds; the
   minimum over the four corners is then a lower bound for every rise and fall time up to the
   maximum. Maximum limits (fSCL, tVD) are measured the other way round.

   The controller is driven by the host's commands (Fw.i2c_commands), all queued at the start
   unless a run says otherwise. The peer is the register-file target of peers.ml at address
   0x50, which acknowledges,
   answers reads, holds its data until [t_vd] clocks after SCL falls, and stretches the clock at
   random. *)

let pr = Printf.printf
let sda = 4 and scl = 5
let addr = 0x50

type wave = {
  n : int;
  sda : int array; scl : int array;          (* bus levels *)
  sda_pull : bool array; scl_pull : bool array;   (* anyone pulling *)
  c_sda_pull : bool array;                   (* the controller pulling SDA *)
  c_sda : int array;                         (* SDA as the controller alone would make it, with edge times *)
}

type run = { r : Bench.result; tgt : Peers.I2c.target; w : wave; outs : (int * int) list; words : int;
             out_clocks : (int * int * int) list }

let run ?bug ?fault ?(rtl = true) ?(stretch = fun () -> 0) ?(t_vd = 4) ?nack_after ?(stretch_limit = 4095) ?(clocks = 400_000)
    ?(host_at = fun _ -> 0) ~(timing : Fw.i2c_timing) ~tr ~tf ops =
  let page, words = Fw.i2c_ctl ?fault ~stretch_limit ~sda ~scl ~timing () in
  let tgt = Peers.I2c.target ~t_vd ~stretch ?nack_after ~addr () in
  let sl = Peers.I2c.line ~tr ~tf and cl = Peers.I2c.line ~tr ~tf and vl = Peers.I2c.line ~tr ~tf in
  let w = { n = 0; sda = Array.make clocks 1; scl = Array.make clocks 1; sda_pull = Array.make clocks false;
            scl_pull = Array.make clocks false; c_sda_pull = Array.make clocks false; c_sda = Array.make clocks 1 } in
  let t_pull = ref (false, false) in
  let cur = ref 0 in
  let world ~clock ~pin_out ~pin_oe =
    cur := clock;
    let pulls p = (pin_oe lsr p) land 1 = 1 && (pin_out lsr p) land 1 = 0 in
    let csda = pulls sda and cscl = pulls scl in
    let ps = csda || fst !t_pull and pc = cscl || snd !t_pull in
    let s = Peers.I2c.line_step sl ~pulled:ps and c = Peers.I2c.line_step cl ~pulled:pc in
    let v = Peers.I2c.line_step vl ~pulled:csda in
    let i = clock + 1 in
    if i >= 0 && i < clocks then begin
      w.sda.(i) <- s; w.scl.(i) <- c; w.sda_pull.(i) <- ps; w.scl_pull.(i) <- pc; w.c_sda_pull.(i) <- csda; w.c_sda.(i) <- v
    end;
    t_pull := Peers.I2c.step tgt ~sda:s ~scl:c;
    0xFF land lnot ((1 - s) lsl sda) land lnot ((1 - c) lsl scl) in
  (* the host's commands, the i-th available from clock [host_at i] *)
  let h = Bench.host [] in
  List.iteri (fun i b -> Bench.push_host h ~at:(host_at i) b) (Fw.i2c_commands ops);
  (* stop 3,000 clocks after the controller reports the last STOP (tag 3) or a timeout (tag 2) *)
  let stops = List.length (List.filter (fun o -> o = Fw.Stop) ops) in
  let fin = ref max_int in
  let stop () =
    (if !fin = max_int then
       let ends = List.filter (fun (_, t, _) -> t = 3) h.outs and tos = List.filter (fun (_, t, _) -> t = 2) h.outs in
       match ends, tos with
       | (c, _, _) :: _, _ when List.length ends = stops -> fin := c + 3000
       | _, (c, _, _) :: _ -> fin := c + 3000
       | _ -> ());
    !cur > !fin in
  let r = Bench.run ?bug ~rtl ~stop ~pages:[| Some page; None; None; None |] ~clocks ~world h in
  { r; tgt; w = { w with n = r.clocks }; outs = List.map (fun (_, t, b) -> (t, b)) r.outs; words; out_clocks = r.outs }

(* ---- measurement ---- *)

let rises a n = List.filter (fun c -> a.(c - 1) = 0 && a.(c) = 1) (List.init (n - 1) (fun i -> i + 1))
let falls a n = List.filter (fun c -> a.(c - 1) = 1 && a.(c) = 0) (List.init (n - 1) (fun i -> i + 1))
let pull_starts a n = List.filter (fun c -> (not a.(c - 1)) && a.(c)) (List.init (n - 1) (fun i -> i + 1))
let pull_ends a n = List.filter (fun c -> a.(c - 1) && not a.(c)) (List.init (n - 1) (fun i -> i + 1))
let next_after l c = List.find_opt (fun x -> x > c) l
let last_before l c = List.fold_left (fun acc x -> if x < c then Some x else acc) None l

type params = {
  f_scl : float;                                 (* the highest, Hz *)
  t_low : float; t_high : float; hd_sta : float; su_sta : float; su_dat : float; hd_dat : float;
  su_sto : float; buf : float; vd_dat : float;   (* ns; vd_dat the largest, the others the least *)
  starts : int; restarts : int; stops : int;
}

let ns c = float c *. 1e9 /. Fw.clock_hz
let mn = List.fold_left min max_int
let mx = List.fold_left max min_int

let measure (w : wave) =
  let n = w.n in
  let r_scl = rises w.scl n and f_scl = falls w.scl n in
  let rs_scl = pull_ends w.scl_pull n and fs_scl = pull_starts w.scl_pull n in
  let r_sda = rises w.sda n and f_sda = falls w.sda n in
  let fs_sda = pull_starts w.sda_pull n and rs_sda = pull_ends w.sda_pull n in
  (* START / STOP: SDA changing while SCL is high *)
  let starts = List.filter (fun c -> w.scl.(c) = 1 && w.scl.(c - 1) = 1) f_sda in
  let stops = List.filter (fun c -> w.scl.(c) = 1 && w.scl.(c - 1) = 1) r_sda in
  let restarts = List.filter (fun c -> match last_before stops c, last_before starts c with
      | _, None -> false | None, Some _ -> true | Some p, Some s -> s > p) starts in
  let between a b l = List.exists (fun x -> x > a && x < b) l in
  (* tLOW: each SCL fall (end) to the next release (start of the rise) *)
  let lows = List.filter_map (fun f -> Option.map (fun r -> r - f) (next_after rs_scl f)) f_scl in
  (* tHIGH: each rise (end) to the next start of a fall, unless a STOP lies between *)
  let highs = List.filter_map (fun r -> match next_after fs_scl r with
      | Some f when not (between r f stops) -> Some (f - r) | _ -> None) r_scl in
  let periods = List.filter_map (fun r -> match next_after r_scl r with
      | Some r2 when not (between r r2 stops) -> Some (r2 - r) | _ -> None) r_scl in
  (* START and repeated START: the end of SDA's fall to the start of SCL's next fall *)
  let hd_sta = List.filter_map (fun s -> Option.map (fun f -> f - s) (next_after fs_scl s)) starts in
  (* repeated START: the end of SCL's rise before it to the start of SDA's fall *)
  let su_sta = List.filter_map (fun s -> match last_before r_scl s, last_before fs_sda (s + 1) with
      | Some r, Some f -> Some (f - r) | _ -> None) restarts in
  let su_sto = List.filter_map (fun s -> match last_before r_scl s, last_before rs_sda (s + 1) with
      | Some r, Some e -> Some (e - r) | _ -> None) stops in
  let buf = List.filter_map (fun s -> match next_after starts s with
      | Some st -> (match last_before fs_sda (st + 1) with Some f -> Some (f - s) | None -> None) | None -> None) stops in
  (* the controller's own SDA changes while SCL is low: hold from the end of SCL's fall to the
     start of the change; set-up from the end of the change to the start of SCL's next rise;
     valid time from the start of SCL's fall to the end of the change *)
  let changes = List.filter (fun c -> w.c_sda_pull.(c) <> w.c_sda_pull.(c - 1) && w.scl.(c) = 0) (List.init (n - 1) (fun i -> i + 1)) in
  let ends = List.filter (fun c -> w.c_sda.(c) <> w.c_sda.(c - 1)) (List.init (n - 1) (fun i -> i + 1)) in
  let in_data c = not (List.mem c starts) && not (List.mem c stops) in
  let hd_dat = List.filter_map (fun c -> Option.map (fun f -> c - f) (last_before f_scl c)) changes in
  let su_dat = List.filter_map (fun c ->
      match next_after ends (c - 1) with
      | Some e when w.scl.(e) = 0 && in_data e -> Option.map (fun r -> r - e) (next_after rs_scl e)
      | _ -> None) changes in
  let vd = List.filter_map (fun c ->
      match next_after ends (c - 1), last_before fs_scl c with
      | Some e, Some f -> Some (e - f) | _ -> None) changes in
  ignore r_sda; ignore fs_sda;
  { f_scl = (if periods = [] then 0. else Fw.clock_hz /. float (mn periods));
    t_low = ns (mn lows); t_high = ns (mn highs); hd_sta = ns (mn hd_sta); su_sta = (if su_sta = [] then nan else ns (mn su_sta));
    su_dat = ns (mn su_dat); hd_dat = ns (mn hd_dat); su_sto = ns (mn su_sto); buf = (if buf = [] then nan else ns (mn buf));
    vd_dat = ns (mx vd); starts = List.length starts; restarts = List.length restarts; stops = List.length stops }

(* ---- the transactions ---- *)

(* write 0x55 0xAA to registers 0x10, 0x11; then, in a second transaction, set the pointer to
   0x10 and read 3 bytes after a repeated START *)
let ops = Fw.[ Start; Write [ 0xA0; 0x10; 0x55; 0xAA ]; Stop; Start; Write [ 0xA0; 0x10 ]; Start; Write [ 0xA1 ]; Read 3; Stop ]
let expect_events reg12 = Peers.I2c.[ Ev_start; Ev_addr (0x50, 0, true); Ev_write (0x10, true); Ev_write (0x55, true); Ev_write (0xAA, true); Ev_stop;
                                       Ev_start; Ev_addr (0x50, 0, true); Ev_write (0x10, true); Ev_restart; Ev_addr (0x50, 1, true);
                                       Ev_read (0x55, true); Ev_read (0xAA, true); Ev_read (reg12, false); Ev_stop ]

let expect_outs reg12 = [ (1, 0); (1, 0); (1, 0); (1, 0); (3, 0); (1, 0); (1, 0); (1, 0); (0, 0x55); (0, 0xAA); (0, reg12); (3, 0) ]

let check_run (x : run) =
  let reg12 = x.tgt.regs.(0x12) in
  let evs = List.rev x.tgt.events in
  let ok = evs = expect_events reg12 && x.outs = expect_outs reg12 && x.r.mismatches = 0 in
  ok, evs

let modes = [ (Fw.standard_mode, Fw.standard_timing); (Fw.fast_mode, Fw.fast_timing) ]

let clocks_of ns = int_of_float (Float.ceil (ns *. Fw.clock_hz /. 1e9))

let run_all () =
  pr "== Task 3: I2C controller, Standard-mode and Fast-mode, 60 MHz core clock\n";
  pr "Transactions: write 0x55 0xAA to registers 0x10..0x11 of the target at 0x50; STOP; then set the\n";
  pr "pointer, repeated START, read 3 bytes (ACK, ACK, NACK), STOP. The target acknowledges, answers,\n";
  pr "holds SDA until 4 clocks after SCL falls; one run in each corner without clock stretching, one\n";
  pr "with it (each fall held 0..400 clocks at random).\n";
  let all = ref true in
  List.iter (fun ((lim : Fw.i2c_limits), (tm : Fw.i2c_timing)) ->
      pr "\n-- %s (limits from NXP UM10204 rev. 7.0, table 10); slots: low %d, high %d, hd_dat %d, hd_sta %d, su_sta %d, su_sto %d, buf %d, sample at %d\n"
        lim.name tm.low tm.high tm.hd_dat tm.hd_sta tm.su_sta tm.su_sto tm.buf tm.smp;
      let tr = clocks_of lim.t_r and tf = clocks_of lim.t_f in
      let corners = [ (0, 0); (tr, 0); (0, tf); (tr, tf) ] in
      let results = List.map (fun (tr, tf) ->
          let x = run ~timing:tm ~tr ~tf ops in
          let ok, evs = check_run x in
          let rng = Random.State.make [| tr; tf |] in
          let y = run ~timing:tm ~tr ~tf ~stretch:(fun () -> if Random.State.int rng 3 = 0 then Random.State.int rng 400 else 0) ops in
          let ok2, _ = check_run y in
          if not (ok && ok2) then begin
            all := false;
            pr "  corner tr=%d tf=%d: WRONG: %s; host %s; lockstep %d %d\n" tr tf
              (String.concat " " (List.map Peers.I2c.event_to_string evs))
              (String.concat " " (List.map (fun (t, b) -> Printf.sprintf "%d:%02x" t b) x.outs)) x.r.mismatches y.r.mismatches
          end;
          ((tr, tf), measure x.w, x, ok && ok2, measure y.w, y)) corners in
      pr "  %-26s %-12s" "parameter" "limit";
      List.iter (fun ((tr, tf), _, _, _, _, _) -> pr " tr%-3d tf%-3d" tr tf) results;
      pr "   worst   ok\n";
      let row name limit is_max get =
        let vs = List.map (fun (_, p, _, _, _, _) -> get p) results in
        let worst = if is_max then List.fold_left Float.max neg_infinity vs else List.fold_left Float.min infinity vs in
        let ok = if is_max then worst <= limit else worst >= limit in
        if not ok then all := false;
        pr "  %-26s %s %8.0f" name (if is_max then "<=" else ">=") limit;
        List.iter (fun v -> pr "   %8.0f" v) vs;
        pr "   %8.0f %s\n" worst (if ok then "ok" else "VIOLATED") in
      row "fSCL (Hz)" lim.f_max_hz true (fun p -> p.f_scl);
      row "tLOW (ns)" lim.t_low false (fun p -> p.t_low);
      row "tHIGH (ns)" lim.t_high false (fun p -> p.t_high);
      row "tHD;STA (ns)" lim.t_hd_sta false (fun p -> p.hd_sta);
      row "tSU;STA (ns)" lim.t_su_sta false (fun p -> p.su_sta);
      row "tSU;DAT (ns)" lim.t_su_dat false (fun p -> p.su_dat);
      row "tHD;DAT (ns)" lim.t_hd_dat false (fun p -> p.hd_dat);
      row "tVD;DAT, tVD;ACK (ns)" (Float.min lim.t_vd_dat lim.t_vd_ack) true (fun p -> p.vd_dat);
      row "tSU;STO (ns)" lim.t_su_sto false (fun p -> p.su_sto);
      row "tBUF (ns)" lim.t_buf false (fun p -> p.buf);
      List.iter (fun ((tr, tf), p, x, ok, ps, y) ->
          pr "  corner tr=%d tf=%d clocks: %d STARTs (%d repeated), %d STOPs; data %s; lockstep %d, %d clocks differ; with stretching: tLOW >= %.0f, tHIGH >= %.0f ns\n"
            tr tf p.starts p.restarts p.stops (if ok then "ok" else "WRONG") x.r.mismatches y.r.mismatches ps.t_low ps.t_high) results;
      let _, _, x, _, _, _ = List.hd results in
      pr "  target saw: %s\n  host got: %s\n  page: %d words\n"
        (String.concat " " (List.map Peers.I2c.event_to_string (List.rev x.tgt.events)))
        (String.concat " " (List.map (fun (t, b) -> Printf.sprintf "tag%d:%02x" t b) x.outs)) x.words) modes;
  pr "\nEach value is the least over every occurrence in the run (the greatest for fSCL and tVD), in ns;\n";
  pr "\"worst\" is over the four corners of the rise time tr and fall time tf (clocks: 0 or the\n";
  pr "specification's maximum, 1000/300 ns Standard, 300/300 ns Fast).\n";
  (* controls *)
  pr "\nControls (each must fail the check named):\n";
  let ctl name ok = pr "  %-84s %s\n" name (if ok then "CAUGHT" else "MISSED"); if not ok then all := false in
  let fast = Fw.fast_timing and lim = Fw.fast_mode in
  let tf = clocks_of lim.t_f in
  let p = measure (run ~timing:{ fast with low = 19 } ~tr:0 ~tf ops).w in
  ctl (Printf.sprintf "Fast-mode with low = 19 slots: tLOW %.0f ns < 1300" p.t_low) (p.t_low < lim.t_low);
  let p = measure (run ~timing:{ fast with high = 8 } ~tr:0 ~tf:0 ops).w in
  ctl (Printf.sprintf "Fast-mode with high = 8 slots: fSCL %.0f Hz > 400 kHz" p.f_scl) (p.f_scl > lim.f_max_hz);
  let p = measure (run ~timing:{ fast with su_sto = 5 } ~tr:0 ~tf:0 ops).w in
  ctl (Printf.sprintf "Fast-mode with su_sto = 5 slots: tSU;STO %.0f ns < 600" p.su_sto) (p.su_sto < lim.t_su_sto);
  let p = measure (run ~timing:{ fast with hd_sta = 7 } ~tr:0 ~tf:0 ops).w in
  ctl (Printf.sprintf "Fast-mode with hd_sta = 7 slots: tHD;STA %.0f ns < 600" p.hd_sta) (p.hd_sta < lim.t_hd_sta);
  let p = measure (run ~timing:{ fast with hd_dat = 22 } ~tr:(clocks_of lim.t_r) ~tf:0 ops).w in
  ctl (Printf.sprintf "Fast-mode with SDA changed 22 slots after SCL low: tSU;DAT %.0f ns < 100 or tVD %.0f > 900" p.su_dat p.vd_dat)
    (p.su_dat < lim.t_su_dat || p.vd_dat > lim.t_vd_dat);
  let show x = String.concat " " (List.map (fun (t, b) -> Printf.sprintf "tag%d:%02x" t b) x.outs) in
  let x = run ~timing:fast ~tr:0 ~tf:0 Fw.[ Start; Write [ 0xA2; 0x10 ]; Stop ] in
  ctl (Printf.sprintf "no target at 0x51: NACKs reported (host %s), STOP sent" (show x))
    (x.outs = [ (1, 1); (1, 1); (3, 0) ] && (measure x.w).stops = 1);
  let x = run ~timing:fast ~tr:0 ~tf:0 ~nack_after:2 Fw.[ Start; Write [ 0xA0; 0x10; 0x01; 0x02; 0x03 ]; Stop ] in
  ctl (Printf.sprintf "target NACKs from its third data byte on (host %s)" (show x))
    (x.outs = [ (1, 0); (1, 0); (1, 0); (1, 1); (1, 1); (3, 0) ]);
  let x = run ~timing:fast ~tr:0 ~tf:0 ~stretch_limit:200 ~clocks:60_000
      ~stretch:(let k = ref 0 in fun () -> incr k; if !k = 12 then 100_000 else 0) ops in
  let released = match List.find_opt (fun (_, t, _) -> t = 2) x.out_clocks with
    | Some (c, _, _) -> not x.w.c_sda_pull.(c + 2) | None -> false in
  ctl (Printf.sprintf "target holds SCL for ever, stretch limit 200 slots: timeout reported (host %s), SDA released" (show x))
    (List.mem (2, 0) x.outs && released);
  let good = run ~timing:fast ~tr:0 ~tf:0 ~t_vd:50 ops in
  let x = run ~fault:Fw.Ack_in_low_phase ~timing:fast ~tr:0 ~tf:0 ~t_vd:50 ops in
  ctl (Printf.sprintf "ACK read while SCL is low, target's ACK 50 clocks (833 ns, within tVD;ACK) after SCL falls: NACK seen (host %s)" (show x))
    (fst (check_run good) && not (fst (check_run x)));
  let x = run ~fault:Fw.No_stretch_wait ~timing:fast ~tr:0 ~tf:0 ~stretch:(fun () -> 150) ops in
  let good = run ~timing:fast ~tr:0 ~tf:0 ~stretch:(fun () -> 150) ops in
  let p = measure x.w in
  ctl (Printf.sprintf "no wait for SCL high, target stretching 150 clocks: tHIGH %.0f ns < 600 or data wrong" p.t_high)
    (fst (check_run good) && (p.t_high < 600. || not (fst (check_run x))));
  (* a slow host: each command 2,000 clocks after the previous; the controller holds SCL low *)
  let x = run ~timing:fast ~tr:0 ~tf:0 ~host_at:(fun i -> 2000 * i) ops in
  let p = measure x.w in
  pr "  (not a control) slow host, a command every 2,000 clocks: data %s, tLOW >= %.0f ns, fSCL <= %.0f Hz\n"
    (if fst (check_run x) then "ok" else "WRONG") p.t_low p.f_scl;
  if not (fst (check_run x)) then all := false;
  let x = run ~bug:Sequencer2.Wait_fail_early ~timing:fast ~tr:0 ~tf:0 ~stretch_limit:200 ~clocks:60_000
      ~stretch:(let k = ref 0 in fun () -> incr k; if !k = 12 then 100_000 else 0) ops in
  ctl (Printf.sprintf "lockstep: RTL mutant \"a wait times out at dl = 1\" (%d clocks differ)" x.r.mismatches) (x.r.mismatches > 0);
  pr "\nI2C controller: %s\n" (if !all then "PASS" else "FAIL");
  !all

(* sigrok's i2c decoder's annotations for a target's events *)
let annotations evs =
  List.concat_map (fun e ->
      let ack a = if a then "ACK" else "NACK" in
      match e with
      | Peers.I2c.Ev_start -> [ "Start" ] | Ev_restart -> [ "Start repeat" ] | Ev_stop -> [ "Stop" ]
      | Ev_addr (a, rw, k) -> [ Printf.sprintf "Address %s: %02X" (if rw = 1 then "read" else "write") a; ack k ]
      | Ev_write (b, k) -> [ Printf.sprintf "Data write: %02X" b; ack k ]
      | Ev_read (b, k) -> [ Printf.sprintf "Data read: %02X" b; ack k ]) evs

(* traces for tools/sigrok-judge: both modes at the slow corner, with stretching; judged against
   the intended transaction (expect_events), not against what the target recorded *)
let dump dir =
  List.iter (fun ((lim : Fw.i2c_limits), tm, name) ->
      let rng = Random.State.make [| 5 |] in
      let x = run ~timing:tm ~tr:(clocks_of lim.t_r) ~tf:(clocks_of lim.t_f)
          ~stretch:(fun () -> if Random.State.int rng 4 = 0 then Random.State.int rng 200 else 0) ops in
      let r = { x.r with levels = Bytes.init x.w.n (fun c -> Char.chr ((x.w.sda.(c) lsl sda) lor (x.w.scl.(c) lsl scl))) } in
      Bench.dump_trace ~dir ~stem:("i2c-ctl-" ^ name) r
        [ ("judge", "i2c"); ("i2c_sda", string_of_int sda); ("i2c_scl", string_of_int scl);
          ("i2c_expect", String.concat ";" (annotations (expect_events x.tgt.regs.(0x12)))) ])
    [ (Fw.standard_mode, Fw.standard_timing, "standard"); (Fw.fast_mode, Fw.fast_timing, "fast") ];
  true
