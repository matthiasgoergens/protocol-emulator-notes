(* Task 4: I2C target with a 7-bit address: ACK and NACK, writes drained by the host, reads
   supplied by the host, clock stretching while it waits for the host; at Standard-mode and
   Fast-mode, and how much faster it can follow.

   The controller is the peer of peers.ml (a script at the specification's timing that waits
   for SCL to read high, so it honours stretching), on the bus model with edge times. The target
   runs on the interpreter and the RTL in lockstep. Checked: what the controller sees (every ACK,
   every byte read), what the host gets (address, bytes written, the controller's ACKs, STOPs),
   and the target's own timing on the trace: its SDA changes only while SCL is low, set at least
   tSU;DAT before SCL's next rise, within tVD after SCL falls where it did not stretch the clock,
   and it pulls SCL only while SCL is already low. *)

let pr = Printf.printf
let sda = 6 and scl = 7
let addr = 0x50

type run = {
  r : Bench.result; c : Peers.I2c.controller; outs : (int * int) list; words : int;
  n : int; bsda : int array; bscl : int array;
  t_sda_pull : bool array; t_scl_pull : bool array;   (* the target (the thread) pulling *)
  t_sda : int array;                                   (* SDA as the target alone makes it, with edge times *)
  scl_pull : bool array;
}

let run ?bug ?(rtl = true) ?(record_issues = false) ?(clocks = 600_000) ?(tr = 0) ?(tf = 0) ?(host_at = fun _ -> 0) ?reactive ?(phase = 0) ~su ~(ct : Peers.I2c.ctiming) ~host cops =
  let page, words = Fw.i2c_target ~sda ~scl ~addr ~su () in
  let c = Peers.I2c.controller ct cops in
  (* [phase]: the controller starts this many clocks late, which moves its edges against the slots *)
  if phase > 0 then (let q = Queue.copy c.q in Queue.clear c.q; Queue.push (Peers.I2c.Delay phase) c.q; Queue.transfer q c.q);
  let sl = Peers.I2c.line ~tr ~tf and cl = Peers.I2c.line ~tr ~tf and vl = Peers.I2c.line ~tr ~tf in
  let mk v = Array.make clocks v in
  let bsda = mk 1 and bscl = mk 1 and tsp = mk false and tcp = mk false and tsd = mk 1 and scp = mk false in
  let c_pull = ref (false, false) and cur = ref 0 in
  let h = Bench.host [] in
  (* [reactive = Some d]: the host answers each request d clocks after the target makes it (a byte
     written: tag 0; addressed for a read: tag 1 with R/W 1; a byte read and ACKed: tag 2, 0);
     otherwise every byte is queued, the i-th available from clock [host_at i] *)
  let pending = ref host and seen = ref 0 in
  (match reactive with None -> List.iteri (fun i b -> Bench.push_host h ~at:(host_at i) b) host | Some _ -> ());
  let react clock = match reactive with
    | None -> ()
    | Some d ->
      let outs = List.rev h.outs in
      List.iteri (fun i (_, tag, b) ->
          if i >= !seen && (tag = 0 || (tag = 1 && b land 1 = 1) || (tag = 2 && b = 0)) then
            match !pending with x :: r -> Bench.push_host h ~at:(clock + d) x; pending := r | [] -> ()) outs;
      seen := List.length outs in
  let world ~clock ~pin_out ~pin_oe =
    cur := clock;
    let pulls p = (pin_oe lsr p) land 1 = 1 && (pin_out lsr p) land 1 = 0 in
    let ts = pulls sda and tc = pulls scl in
    let s = Peers.I2c.line_step sl ~pulled:(ts || fst !c_pull) and k = Peers.I2c.line_step cl ~pulled:(tc || snd !c_pull) in
    let v = Peers.I2c.line_step vl ~pulled:ts in
    let i = clock + 1 in
    if i < clocks then (bsda.(i) <- s; bscl.(i) <- k; tsp.(i) <- ts; tcp.(i) <- tc; tsd.(i) <- v; scp.(i) <- tc || snd !c_pull);
    c_pull := Peers.I2c.controller_step c ~sda:s ~scl:k;
    react clock;
    0xFF land lnot ((1 - s) lsl sda) land lnot ((1 - k) lsl scl) in
  let fin = ref max_int in
  let stop () = (if c.done_ && !fin = max_int then fin := !cur + 2000); !cur > !fin in
  let r = Bench.run ?bug ~rtl ~record_issues ~stop ~pages:[| None; Some page; None; None |] ~clocks ~world h in
  { r; c; outs = List.map (fun (_, t, b) -> (t, b)) r.outs; words; n = r.clocks; bsda; bscl;
    t_sda_pull = tsp; t_scl_pull = tcp; t_sda = tsd; scl_pull = scp }

type tparams = {
  hd_dat : int; su_dat : int; vd : int;     (* clocks: least, least, greatest (unstretched phases) *)
  sda_in_high : int;                        (* the target's SDA changes while SCL is high *)
  scl_glitch : int;                         (* the target starting to pull SCL while SCL is high *)
  longest_stretch : int;                    (* clocks *)
  stretches : int;
}

let measure (x : run) =
  let n = x.n in
  let idx = List.init (n - 1) (fun i -> i + 1) in
  let falls = List.filter (fun c -> x.bscl.(c - 1) = 1 && x.bscl.(c) = 0) idx in
  let fall_starts = List.filter (fun c -> (not x.scl_pull.(c - 1)) && x.scl_pull.(c)) idx in
  let rise_starts = List.filter (fun c -> x.scl_pull.(c - 1) && not x.scl_pull.(c)) idx in
  let last_before l c = List.fold_left (fun a y -> if y < c then Some y else a) None l in
  let next_after l c = List.find_opt (fun y -> y > c) l in
  let changes = List.filter (fun c -> x.t_sda_pull.(c) <> x.t_sda_pull.(c - 1)) idx in
  let ends = List.filter (fun c -> x.t_sda.(c) <> x.t_sda.(c - 1)) idx in
  (* stretched low phases: the target pulled SCL somewhere in them *)
  let stretched f = match next_after rise_starts f with
    | Some r -> List.exists (fun c -> x.t_scl_pull.(c)) (List.init (r - f) (fun i -> f + i)) | None -> true in
  let sda_in_high = List.length (List.filter (fun c -> x.bscl.(c) = 1 && x.bscl.(c - 1) = 1) changes) in
  let hd = List.filter_map (fun c -> Option.map (fun f -> c - f) (last_before falls c)) changes in
  (* set-up: from the end of SDA's edge to the start of the first SCL rise after the change began
     (negative when SCL starts to rise before SDA has finished) *)
  let su = List.filter_map (fun c -> match next_after ends (c - 1) with
      | Some e -> Option.map (fun r -> r - e) (next_after rise_starts c) | None -> None) changes in
  (* tVD from SCL low (UM10204: its 30 % point, where the model's line reads low) to SDA valid *)
  let vd = List.filter_map (fun c -> match last_before falls (c + 1), next_after ends (c - 1) with
      | Some f, Some e when not (stretched f) -> Some (e - f) | _ -> None) changes in
  ignore fall_starts;
  let glitch = List.length (List.filter (fun c -> (not x.t_scl_pull.(c - 1)) && x.t_scl_pull.(c) && x.bscl.(c) = 1) idx) in
  (* the target's stretches: runs of its SCL pull *)
  let runs = ref [] and len = ref 0 in
  for c = 1 to n - 1 do
    if x.t_scl_pull.(c) then incr len else if !len > 0 then (runs := !len :: !runs; len := 0)
  done;
  let mn l = List.fold_left min max_int l and mx l = List.fold_left max min_int l in
  { hd_dat = mn hd; su_dat = mn su; vd = mx vd; sda_in_high; scl_glitch = glitch;
    longest_stretch = mx !runs; stretches = List.length !runs }

(* the transactions: write 0x10 0x55 to the target; read three bytes from it; then a write to
   another address (0x52), which it must not acknowledge *)
let cops = Peers.I2c.[ C_start; C_write 0xA0; C_write 0x10; C_write 0x55; C_stop;
                       C_start; C_write 0xA1; C_read true; C_read true; C_read false; C_stop;
                       C_start; C_write 0xA4; C_write 0x00; C_stop ]
let host_bytes = [ 0x00; 0x00; 0x3C; 0xC3; 0x5A ]     (* ACK, ACK for the two bytes written; the three to read *)
let want_outs = [ (1, 0xA0); (0, 0x10); (0, 0x55); (3, 0); (1, 0xA1); (2, 0); (2, 0); (2, 1); (3, 0); (3, 0) ]
let want_acks = [ true; true; true; true; false; false ]     (* A0 10 55 | A1 | A4 00 *)
let want_reads = [ 0x3C; 0xC3; 0x5A ]

let check (x : run) =
  x.outs = want_outs && List.rev x.c.acks = want_acks && List.rev x.c.reads = want_reads && x.r.mismatches = 0 && x.c.done_

let clocks_of ns = int_of_float (Float.ceil (ns *. Fw.clock_hz /. 1e9))
let ns c = float c *. 1e9 /. Fw.clock_hz

let modes = [ (Fw.standard_mode, Peers.I2c.c_standard, 19); (Fw.fast_mode, Peers.I2c.c_fast, 6) ]

let run_all () =
  pr "== Task 4: I2C target at address 0x%02x, Standard-mode and Fast-mode, 60 MHz core clock\n" addr;
  pr "The controller (peers.ml) writes 0x10 0x55, reads three bytes (ACK, ACK, NACK), then writes to\n";
  pr "0x52, which the target must not acknowledge. The host answers ACK to each byte written and\n";
  pr "supplies the three bytes read, all queued at the start (so the stretches are short), or only\n";
  pr "50 us after the target asks (so it holds SCL low for that long).\n";
  let all = ref true in
  let page = Fw.i2c_target ~sda ~scl ~addr ~su:6 () in
  pr "Page: %d words.\n" (snd page);
  List.iter (fun ((lim : Fw.i2c_limits), (ct : Peers.I2c.ctiming), su) ->
      pr "\n-- %s: the controller's SCL %d clocks low, %d high from seen high; target set-up %d slots\n" lim.name ct.c_low ct.c_high su;
      let tr = clocks_of lim.t_r and tf = clocks_of lim.t_f in
      List.iter (fun (tr, tf) ->
          let x = run ~su ~ct ~tr ~tf ~host:host_bytes cops in
          let p = measure x in
          let ok = check x && p.sda_in_high = 0 && p.scl_glitch = 0 && ns p.vd <= lim.t_vd_dat && ns p.su_dat >= lim.t_su_dat && p.hd_dat >= 0 in
          if not ok then all := false;
          pr "  tr %3d tf %3d clocks: %s; lockstep %d; target SDA: hold >= %.0f ns, set-up >= %.0f ns (>= %.0f), valid <= %.0f ns (<= %.0f) where not stretched; SDA changes with SCL high %d; SCL pulled while high %d; %d stretches, longest %d clocks%s\n"
            tr tf (if check x then "all bytes, ACKs and host reports right" else "WRONG") x.r.mismatches (ns p.hd_dat) (ns p.su_dat)
            lim.t_su_dat (ns p.vd) lim.t_vd_dat p.sda_in_high p.scl_glitch p.stretches p.longest_stretch (if ok then "" else "  FAIL");
          if not (check x) then
            pr "    host %s; controller acks %s reads %s\n" (String.concat " " (List.map (fun (t, b) -> Printf.sprintf "%d:%02x" t b) x.outs))
              (String.concat "" (List.map (fun a -> if a then "A" else "N") (List.rev x.c.acks)))
              (String.concat " " (List.map (Printf.sprintf "%02x") (List.rev x.c.reads)))) [ (0, 0); (tr, 0); (0, tf); (tr, tf) ];
      (* a slow host: it answers each request 50 us after the target makes it; the target holds
         SCL low meanwhile *)
      List.iter (fun (tr, tf) ->
          let x = run ~su ~ct ~tr ~tf ~host:host_bytes ~reactive:3000 cops in
          let p = measure x in
          let ok = check x && p.sda_in_high = 0 && p.scl_glitch = 0 && ns p.su_dat >= lim.t_su_dat in
          if not ok then all := false;
          pr "  host answering 50 us after each request, tr %d tf %d: %s; the target stretched %d times, the longest %d clocks (%.1f us); its set-up before releasing SCL >= %.0f ns; lockstep %d\n"
            tr tf (if ok then "all right" else "WRONG") p.stretches p.longest_stretch (ns p.longest_stretch /. 1000.) (ns p.su_dat) x.r.mismatches)
        [ (0, 0); (tr, tf) ]) modes;
  (* how fast can it follow: the Fast-mode controller scaled down *)
  pr "\n-- The fastest controller it follows (the Fast-mode script with every time scaled by k; tr = tf = 0):\n";
  let fastest = ref 0. in
  pr "  (each speed run at 12 phases of the controller against the core clock; right = every run right)\n";
  let broken = ref false in
  List.iter (fun k ->
      let (ct : Peers.I2c.ctiming) = Peers.I2c.c_scaled Peers.I2c.c_fast k in
      let xs = List.init 12 (fun ph -> run ~rtl:false ~phase:ph ~su:6 ~ct ~host:host_bytes cops) in
      let good = List.filter (fun x -> let p = measure x in check x && p.sda_in_high = 0 && p.scl_glitch = 0) xs in
      let f = Fw.clock_hz /. float (ct.c_low + ct.c_high + 1) in
      let ok = List.length good = 12 in
      if ok && not !broken then fastest := f;
      if not ok then broken := true;
      pr "  k %.2f: SCL low %d high %d clocks (%.0f kHz): %d of 12 right; target SDA valid <= %.0f ns where not stretched\n" k ct.c_low ct.c_high (f /. 1000.)
        (List.length good) (List.fold_left (fun m x -> Float.max m (ns (measure x).vd)) 0. xs)) [ 1.0; 0.8; 0.6; 0.5; 0.4; 0.35; 0.3; 0.25; 0.22; 0.2; 0.18; 0.15 ];
  pr "  fastest with every run right (and every slower one too): %.0f kHz\n" (!fastest /. 1000.);
  (* controls *)
  pr "\nControls (each must fail the check named):\n";
  let ctl name ok = pr "  %-86s %s\n" name (if ok then "CAUGHT" else "MISSED"); if not ok then all := false in
  let ct = Peers.I2c.c_fast in
  let x = run ~su:6 ~ct ~host:[ 0x00; 0x01; 0x3C; 0xC3; 0x5A ] cops in
  ctl (Printf.sprintf "the host NACKs the second byte written: the controller sees it (acks %s)"
         (String.concat "" (List.map (fun a -> if a then "A" else "N") (List.rev x.c.acks))))
    (List.rev x.c.acks = [ true; true; false; true; false; false ]);
  let x = run ~su:6 ~ct ~host:host_bytes Peers.I2c.[ C_start; C_write 0xA2; C_write 0x10; C_stop ] in
  ctl "addressed at 0x51: no ACK, nothing to the host but the STOP" (List.rev x.c.acks = [ false; false ] && x.outs = [ (3, 0) ]);
  (* with the host late the target's stretch outlasts the controller's low phase, so its own
     SCL release starts the rise *)
  (* the first byte read starts with a 1, so SDA rises from the address ACK's low when the target
     releases it, just before it releases SCL; set-up must cover the rise *)
  let hb = [ 0x00; 0x00; 0xC3; 0x3C; 0x5A ] in
  let x = run ~su:1 ~ct ~tr:(clocks_of Fw.fast_mode.t_r) ~host:hb ~reactive:600 cops in
  let good = run ~su:6 ~ct ~tr:(clocks_of Fw.fast_mode.t_r) ~host:hb ~reactive:600 cops in
  let p = measure x and pg = measure good in
  ctl (Printf.sprintf "set-up 1 slot against 6, 300 ns rise, host late, SDA rising: tSU;DAT %.0f ns < 100 (6 slots: %.0f)" (ns p.su_dat) (ns pg.su_dat))
    (ns p.su_dat < 100. && ns pg.su_dat >= 100.);
  let bad = { ct with Peers.I2c.c_hd_dat = 6 } in
  let x = run ~su:6 ~ct:bad ~tf:(clocks_of Fw.fast_mode.t_f) ~host:host_bytes cops in
  ctl "a controller without the 300 ns internal SDA hold (100 ns), 300 ns fall: the target sees a false STOP (wrong)"
    (not (check x));
  let x = run ~bug:Sequencer2.Waitd_early ~su:6 ~ct ~host:host_bytes cops in
  ctl (Printf.sprintf "lockstep: RTL mutant \"WAITD leaves at dl = 1\" (%d clocks differ)" x.r.mismatches) (x.r.mismatches > 0);
  pr "\nI2C target: %s\n" (if !all then "PASS" else "FAIL");
  !all

(* traces for tools/sigrok-judge: both modes at the slowest edges, the host answering 50 us after
   each request (so the target stretches the clock); judged against the intended transaction *)
let dump dir =
  let want = String.concat ";"
      [ "Start"; "Address write: 50"; "ACK"; "Data write: 10"; "ACK"; "Data write: 55"; "ACK"; "Stop";
        "Start"; "Address read: 50"; "ACK"; "Data read: 3C"; "ACK"; "Data read: C3"; "ACK"; "Data read: 5A"; "NACK"; "Stop";
        "Start"; "Address write: 52"; "NACK"; "Data write: 00"; "NACK"; "Stop" ] in
  List.iter (fun ((lim : Fw.i2c_limits), ct, su, name) ->
      let x = run ~su ~ct ~tr:(clocks_of lim.t_r) ~tf:(clocks_of lim.t_f) ~host:host_bytes ~reactive:3000 cops in
      let r = { x.r with levels = Bytes.init x.n (fun c -> Char.chr ((x.bsda.(c) lsl sda) lor (x.bscl.(c) lsl scl))) } in
      Bench.dump_trace ~dir ~stem:("i2c-target-" ^ name) r
        [ ("judge", "i2c"); ("i2c_sda", string_of_int sda); ("i2c_scl", string_of_int scl); ("i2c_expect", want) ])
    [ (Fw.standard_mode, Peers.I2c.c_standard, 19, "standard"); (Fw.fast_mode, Peers.I2c.c_fast, 6, "fast") ];
  true
