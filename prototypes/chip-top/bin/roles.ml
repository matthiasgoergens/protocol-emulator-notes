(* ../protocol-roles's firmware on the combined chip, through the host link.

     roles.exe uart         UART transmit (bytes from the host) and receive (bytes to the host)

   As demos.ml does for the earlier firmware: the chip's specification and its RTL run in lockstep
   on the same board (Board), compared on every pad every clock; the host loads the programmes
   through PROG, sets the boot pages and pcs and the pin map through REG, sets run, feeds HOSTIN
   and drains HOSTOUT; the outside world is the peer models of ../protocol-roles/peers.ml on the
   pads. DEMO_DRIVER=rtl makes the board follow the RTL's pads instead of the specification's.

   The programmes are ISA v2 pages as Fw emits them (8-bit addresses within a page), loaded at
   page boundaries: thread t's at page t (pages 0 and 1 are the hardened 512 x 16 macro). Threads
   without a programme are parked on a JMP to itself at page 1, word 255. *)

open Regs
module S = Chip_spec

let pr = Printf.printf

let driver = match Sys.getenv_opt "DEMO_DRIVER" with Some "rtl" -> `Rtl | _ -> `Spec

(* Run spec and RTL together for [clocks]; [world] gives the outside world's pad levels each
   clock from the pads the chip shows; [on_clock] sees each clock's outputs. Returns whether they
   agreed on every pad, every clock. *)
let run_board (b : Board.t) ~world ~clocks ~on_clock =
  let spec = S.create () and rtl = Chip_sim.create () in
  let cores = match driver with
    | `Spec -> [ Board.spec_core spec; Board.rtl_core rtl ]
    | `Rtl -> [ Board.rtl_core rtl; Board.spec_core spec ] in
  pr "  the board is driven by the %s's pads\n" (match driver with `Spec -> "specification" | `Rtl -> "RTL");
  let agree = ref true and first = ref None in
  for c = 0 to clocks - 1 do
    let smp = Board.samples b ~ext:(world ~clock:c b.out) in
    match Board.advance b cores ~smp ~reset:(c < 2) with
    | [ a; o ] ->
      if a.pad_nib <> o.pad_nib || a.uio_oe <> o.uio_oe then begin
        agree := false;
        if !first = None then first := Some c
      end;
      on_clock c a
    | _ -> assert false
  done;
  (match !first with Some c -> pr "  RTL and specification first differ at clock %d\n" c | None -> ());
  !agree

let park_page = 1 and park_pc = 255

(* Load [progs] (thread, (page words, used length)), thread t at page t, pc 0; park the others.
   Returns the number of words loaded. *)
let load (h : Host.t) progs =
  Host.wreg h r_ctrl 2;
  let words = ref 0 in
  List.iter (fun (t, (page, len)) ->
      if t = park_page && len > park_pc then failwith "programme on the parking page too long";
      words := !words + len;
      Host.submit h (Host.Write { tgt = t_prog; addr = 2 * (t lsl Isa2.pc_bits);
                                  data = List.concat_map (fun w -> [ w land 0xFF; w lsr 8 ]) (Array.to_list (Array.sub page 0 len)) })) progs;
  let park = Isa2.halt_at park_pc in
  Host.submit h (Host.Write { tgt = t_prog; addr = 2 * ((park_page lsl Isa2.pc_bits) lor park_pc); data = [ park land 0xFF; park lsr 8 ] });
  let has t = List.mem_assoc t progs in
  let pcs = List.init 4 (fun t -> if has t then 0 else park_pc) in
  let pages = List.fold_left (fun a t -> a lor ((if has t then t else park_page) lsl (2 * t))) 0 [ 0; 1; 2; 3 ] in
  Host.submit h (Host.Write { tgt = t_reg; addr = r_boot_pc 0; data = pcs @ [ pages ] });
  !words

let sel src undriven = src lor (undriven lsl 6)

(* HOSTOUT entries: {valid, tag} then the byte *)
let hostout_pairs l =
  let rec go = function t :: d :: r -> (if t land 0x80 <> 0 then [ (t land 7, d) ] else []) @ go r | _ -> [] in
  go l

(* drain HOSTOUT into [acc], every [every] clocks until [until]; [overflow] is set when the
   status register's sticky HOSTOUT overflow bit is seen (the FIFO holds 8 entries) *)
let overflow = ref false

let rec drain (b : Board.t) (h : Host.t) acc ~every ~until =
  Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 16; k = (fun l -> acc := !acc @ hostout_pairs l) });
  Host.submit h (Host.Read { tgt = t_reg; addr = r_status; n = 1; k = (fun l -> if List.hd l land 4 <> 0 then overflow := true) });
  Host.submit h (Host.Idle every);
  Host.submit h (Host.Call (fun () -> if b.clock < until then drain b h acc ~every ~until))

let level (o : S.outputs) p = (o.pad_nib.(p) lsr 3) land 1

(* ---- UART ---- *)

let uart () =
  let baud = 115200 in
  let s = Fw.slots_of_hz (float baud) in
  let bit = Fw.clock_hz /. float baud in
  pr "== UART at %d baud on the combined chip: thread 0 transmits the host's bytes (uo_out[0]),\n" baud;
  pr "   thread 1 receives from ui_in[0] and reports to the host\n";
  let tx = Fw.uart_tx ~pin:0 ~s Fw.From_host and rx = Fw.uart_rx ~pin:1 ~s () in
  pr "  programmes: transmit %d words, receive %d words (of 256 a page)\n" (snd tx) (snd rx);
  let b = Board.create () in
  let h = b.host in
  let words = load h [ (0, tx); (1, rx) ] in
  Host.submit h (Host.Write { tgt = t_reg; addr = r_padsel 0; data = [ sel (src_seq 0) 1 ] });
  Host.submit h (Host.Write { tgt = t_reg; addr = r_pinin 1; data = [ 0 ] });
  let sent = [ 0x48; 0x69; 0x21; 0x0A ] in
  Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = sent });
  let run_at = ref max_int in
  Host.submit h (Host.Call (fun () -> run_at := b.clock));
  Host.wreg h r_ctrl 3;
  let rx_bytes = [ 0xC3; 0x00; 0xFF; 0x5A; 0x81 ] in
  let line = ref (fun _ -> 1) in
  Host.submit h (Host.Call (fun () ->
      let frames = Peers.Uart.frames ~bit ~first:(float (b.clock + 700)) ~gap:10.7 rx_bytes in
      line := Peers.Uart.tx ~bit frames));
  let got = ref [] in
  let clocks = 9000 + int_of_float (bit *. 10.7 *. 6.) in
  drain b h got ~every:3000 ~until:(clocks - 2500);
  let pin = Array.make clocks 1 in
  let world ~clock (_ : S.outputs) =
    let smp = Array.make n_pads 0 in
    smp.(0) <- Board.rep4 (!line clock);
    smp in
  let agree = run_board b ~world ~clocks ~on_clock:(fun c o -> pin.(c) <- level o 0) in
  let dec = Peers.Uart.rx ~bit ~clocks (fun c -> if c < !run_at then 1 else pin.(c)) in
  let decoded = List.map (fun (_, v, ok) -> if ok then v else -1) dec in
  let received = List.map (fun (tag, v) -> if tag = 0 then v else -1 - v) !got in
  pr "  %d words loaded through the link; run from clock %d\n" words !run_at;
  pr "  transmitted (peer receiver on uo_out[0]): %s (sent by the host %s)\n"
    (String.concat " " (List.map (Printf.sprintf "%02x") decoded)) (String.concat " " (List.map (Printf.sprintf "%02x") sent));
  pr "  received (HOSTOUT): %s (peer sent %s)\n"
    (String.concat " " (List.map (Printf.sprintf "%02x") received)) (String.concat " " (List.map (Printf.sprintf "%02x") rx_bytes));
  pr "  RTL and specification agree on every pad, every clock: %b\n" agree;
  pr "  HOSTOUT overflow seen: %b\n" !overflow;
  let ok = agree && decoded = sent && received = rx_bytes && not !overflow in
  pr "UART on the combined chip: %s\n%!" (if ok then "PASS" else "FAIL");
  ok

(* ---- SPI controller ---- *)

let spi () =
  pr "== SPI controller on the combined chip: thread 0 in mode 0 msb first at 1 MHz (SCLK, MOSI, CS on\n";
  pr "   uo_out[0,1,3], MISO from ui_in[2]), thread 1 in mode 3 lsb first at 1.5 MHz (uo_out[4,5,7],\n";
  pr "   ui_in[6]), each against a peer target in its mode; received bytes to the host\n";
  let m0 = { Fw.cpol = 0; cpha = 0; msb = true } and m3 = { Fw.cpol = 1; cpha = 1; msb = false } in
  let tx0 = [ 0x9F; 0x00; 0x00; 0x00 ] and tx1 = [ 0x0B; 0x12; 0x34; 0xA5; 0x5A ] in
  let rp0 = [ 0xFF; 0xEF; 0x40; 0x18 ] and rp1 = [ 0x3C; 0xC3; 0x01; 0x80; 0x7E ] in
  let p0 = Fw.spi_ctl ~tag:1 ~sclk:0 ~mosi:1 ~miso:2 ~cs:3 ~mode:m0 ~period:15 tx0 in
  let p1 = Fw.spi_ctl ~tag:2 ~sclk:4 ~mosi:5 ~miso:6 ~cs:7 ~mode:m3 ~period:10 tx1 in
  pr "  programmes: %d and %d words\n" (snd p0) (snd p1);
  let b = Board.create () in
  let h = b.host in
  let words = load h [ (0, p0); (1, p1) ] in
  Host.submit h (Host.Write { tgt = t_reg; addr = r_padsel 0; data = List.init 8 (fun k -> sel (src_seq k) 1) });
  Host.submit h (Host.Write { tgt = t_reg; addr = r_pinin 2; data = [ 2 ] });
  Host.submit h (Host.Write { tgt = t_reg; addr = r_pinin 6; data = [ 6 ] });
  let pm (m : Fw.spi_mode) = { Peers.Spi.cpol = m.cpol; cpha = m.cpha; msb = m.msb } in
  let t0 = Peers.Spi.target ~delay:3 ~mode:(pm m0) rp0 and t1 = Peers.Spi.target ~delay:3 ~mode:(pm m3) rp1 in
  (* the targets are held in reset until the host has set the pads' undriven level high: before
     that, CS shows the reset level 0 *)
  let ready = ref false in
  Host.submit h (Host.Call (fun () -> ready := true));
  Host.wreg h r_ctrl 3;
  let got = ref [] in
  let clocks = 12000 in
  drain b h got ~every:300 ~until:(clocks - 1500);
  let world ~clock:_ (o : S.outputs) =
    let smp = Array.make n_pads 0 in
    let l p = if !ready then level o p else 1 in
    let m0v = Peers.Spi.step t0 ~sclk:(l 0) ~mosi:(l 1) ~cs:(l 3) in
    let m1v = Peers.Spi.step t1 ~sclk:(l 4) ~mosi:(l 5) ~cs:(l 7) in
    smp.(2) <- Board.rep4 (Option.value m0v ~default:1);
    smp.(6) <- Board.rep4 (Option.value m1v ~default:1);
    smp in
  let agree = run_board b ~world ~clocks ~on_clock:(fun _ _ -> ()) in
  let by tag = List.filter_map (fun (t, v) -> if t = tag then Some v else None) !got in
  let hex l = String.concat " " (List.map (Printf.sprintf "%02x") l) in
  let g0 = List.map fst (List.rev t0.got) and g1 = List.map fst (List.rev t1.got) in
  pr "  %d words loaded through the link\n" words;
  pr "  thread 0: peer received %s (sent %s); host read %s (peer replied %s)\n" (hex g0) (hex tx0) (hex (by 1)) (hex rp0);
  pr "  thread 1: peer received %s (sent %s); host read %s (peer replied %s)\n" (hex g1) (hex tx1) (hex (by 2)) (hex rp1);
  pr "  RTL and specification agree on every pad, every clock: %b\n" agree;
  pr "  HOSTOUT overflow seen: %b\n" !overflow;
  let ok = agree && g0 = tx0 && g1 = tx1 && by 1 = rp0 && by 2 = rp1 && not !overflow in
  pr "SPI controller on the combined chip: %s\n%!" (if ok then "PASS" else "FAIL");
  ok

(* keep HOSTIN topped up from [bytes] (it holds 16): read the count, write what fits, repeat *)
let rec feed (b : Board.t) (h : Host.t) bytes ~every =
  match !bytes with
  | [] -> ()
  | _ ->
    Host.submit h (Host.Read { tgt = t_reg; addr = r_hostin_count; n = 1; k = (fun l ->
        let free = 16 - List.hd l in
        let now = List.filteri (fun i _ -> i < free) !bytes in
        bytes := List.filteri (fun i _ -> i >= free) !bytes;
        if now <> [] then Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = now });
        Host.submit h (Host.Idle every);
        Host.submit h (Host.Call (fun () -> feed b h bytes ~every))) })

(* ---- I2C controller ---- *)

(* the open-drain pins uio[6] (SDA, logical pin 4) and uio[7] (SCL, pin 5) with the target of
   peers.ml on the bus and rise and fall times; returns the world and the bus levels seen *)
let i2c_bus ~tr ~tf (pull_target : sda:int -> scl:int -> bool * bool) ~ready =
  let sl = Peers.I2c.line ~tr ~tf and cl = Peers.I2c.line ~tr ~tf in
  let t_pull = ref (false, false) in
  let trace = ref [] in
  let world ~clock (o : S.outputs) =
    let chip_pulls pad = (o.uio_oe lsr (pad - 8)) land 1 = 1 && level o pad = 0 in
    let s = Peers.I2c.line_step sl ~pulled:(chip_pulls 14 || fst !t_pull)
    and c = Peers.I2c.line_step cl ~pulled:(chip_pulls 15 || snd !t_pull) in
    if !ready then (t_pull := pull_target ~sda:s ~scl:c; trace := (clock, s, c) :: !trace);
    let smp = Array.make n_pads 0 in
    smp.(14) <- Board.rep4 s;
    smp.(15) <- Board.rep4 c;
    smp in
  world, trace

let i2c_pins h =
  Host.submit h (Host.Write { tgt = t_reg; addr = r_padsel 14; data = [ sel (src_seq 4) 0; sel (src_seq 5) 0 ] });
  Host.submit h (Host.Write { tgt = t_reg; addr = r_pinin 4; data = [ 14; 15 ] })

let i2c () =
  pr "== I2C controller in Fast-mode on the combined chip: thread 0 on uio[6] (SDA) and uio[7] (SCL),\n";
  pr "   the host's commands through HOSTIN, results through HOSTOUT; the register-file target of\n";
  pr "   peers.ml at 0x50 on the bus, stretching the clock at random; rise and fall 300 ns\n";
  let prog = Fw.i2c_ctl ~sda:4 ~scl:5 ~timing:Fw.fast_timing () in
  pr "  programme: %d words\n" (snd prog);
  let b = Board.create () in
  let h = b.host in
  let words = load h [ (0, prog) ] in
  i2c_pins h;
  let rng = Random.State.make [| 3 |] in
  let tgt = Peers.I2c.target ~t_vd:10 ~addr:0x50 ~stretch:(fun () -> if Random.State.int rng 4 = 0 then Random.State.int rng 300 else 0) () in
  let ready = ref false in
  let world, trace = i2c_bus ~tr:18 ~tf:18 (fun ~sda ~scl -> Peers.I2c.step tgt ~sda ~scl) ~ready in
  Host.submit h (Host.Call (fun () -> ready := true));
  Host.wreg h r_ctrl 3;
  let ops = Fw.[ Start; Write [ 0xA0; 0x10; 0x55; 0xAA ]; Stop; Start; Write [ 0xA0; 0x10 ]; Start; Write [ 0xA1 ]; Read 3; Stop ] in
  feed b h (ref (Fw.i2c_commands ops)) ~every:400;
  let got = ref [] in
  let clocks = 40_000 in
  drain b h got ~every:300 ~until:(clocks - 1500);
  let agree = run_board b ~world ~clocks ~on_clock:(fun _ _ -> ()) in
  let evs = List.rev tgt.events in
  let r12 = tgt.regs.(0x12) in
  let want_evs = Peers.I2c.[ Ev_start; Ev_addr (0x50, 0, true); Ev_write (0x10, true); Ev_write (0x55, true); Ev_write (0xAA, true); Ev_stop;
                             Ev_start; Ev_addr (0x50, 0, true); Ev_write (0x10, true); Ev_restart; Ev_addr (0x50, 1, true);
                             Ev_read (0x55, true); Ev_read (0xAA, true); Ev_read (r12, false); Ev_stop ] in
  let want_out = [ (1, 0); (1, 0); (1, 0); (1, 0); (3, 0); (1, 0); (1, 0); (1, 0); (0, 0x55); (0, 0xAA); (0, r12); (3, 0) ] in
  (* the SCL period on the bus: the shortest rise to rise *)
  let rises = List.filter_map (fun ((c, _, s1), (_, _, s0)) -> if s1 = 1 && s0 = 0 then Some c else None)
      (let l = List.rev !trace in List.combine (List.tl l) (List.filteri (fun i _ -> i < List.length l - 1) l)) in
  let rec gaps = function a :: (b :: _ as r) -> (b - a) :: gaps r | _ -> [] in
  let shortest = List.fold_left min max_int (gaps rises) in
  pr "  %d words loaded through the link\n" words;
  pr "  target saw: %s\n" (String.concat " " (List.map Peers.I2c.event_to_string evs));
  pr "  host read: %s\n" (String.concat " " (List.map (fun (t, v) -> Printf.sprintf "tag%d:%02x" t v) !got));
  pr "  shortest SCL period on the bus: %d clocks (%.1f kHz)\n" shortest (Fw.clock_hz /. float shortest /. 1000.);
  pr "  RTL and specification agree on every pad, every clock: %b\n" agree;
  pr "  HOSTOUT overflow seen: %b\n" !overflow;
  let ok = agree && evs = want_evs && !got = want_out && not !overflow && Fw.clock_hz /. float shortest <= 400e3 in
  pr "I2C controller on the combined chip: %s\n%!" (if ok then "PASS" else "FAIL");
  ok

(* ---- I2C target ---- *)

let i2c_target () =
  pr "== I2C target at 0x50 on the combined chip: thread 0 on uio[6] (SDA) and uio[7] (SCL), against the\n";
  pr "   Fast-mode controller of peers.ml, rise and fall 300 ns; the host reads HOSTOUT and answers\n";
  pr "   through HOSTIN as the target asks (ACK for bytes written, the bytes to read), while the target\n";
  pr "   holds SCL low\n";
  let prog = Fw.i2c_target ~sda:4 ~scl:5 ~addr:0x50 ~su:6 () in
  pr "  programme: %d words\n" (snd prog);
  let b = Board.create () in
  let h = b.host in
  let words = load h [ (0, prog) ] in
  i2c_pins h;
  let cops = Peers.I2c.[ C_start; C_write 0xA0; C_write 0x10; C_write 0x55; C_stop;
                         C_start; C_write 0xA1; C_read true; C_read true; C_read false; C_stop;
                         C_start; C_write 0xA4; C_write 0x00; C_stop ] in
  let c = Peers.I2c.controller Peers.I2c.c_fast cops in
  let ready = ref false in
  let world, trace = i2c_bus ~tr:18 ~tf:18 (fun ~sda ~scl -> Peers.I2c.controller_step c ~sda ~scl) ~ready in
  Host.submit h (Host.Call (fun () -> ready := true));
  Host.wreg h r_ctrl 3;
  (* the host: poll HOSTOUT; answer each request *)
  let got = ref [] and to_read = ref [ 0x3C; 0xC3; 0x5A ] and until = ref max_int in
  let rec serve () =
    Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 16; k = (fun l ->
        let es = hostout_pairs l in
        got := !got @ es;
        List.iter (fun (tag, v) ->
            let answer = match tag with
              | 0 -> Some 0x00
              | 1 when v land 1 = 1 -> (match !to_read with x :: r -> to_read := r; Some x | [] -> None)
              | 2 when v = 0 -> (match !to_read with x :: r -> to_read := r; Some x | [] -> None)
              | _ -> None in
            match answer with Some x -> Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = [ x ] }) | None -> ()) es) });
    Host.submit h (Host.Idle 200);
    (* go on 3,000 clocks after the controller is done, for the target's last report *)
    Host.submit h (Host.Call (fun () ->
        if c.done_ && !until = max_int then until := b.clock + 3000;
        if b.clock < !until then serve ())) in
  serve ();
  let clocks = 60_000 in
  let agree = run_board b ~world ~clocks ~on_clock:(fun _ _ -> ()) in
  (* the target's stretches: SCL low on the bus while the controller has released it *)
  pr "  %d words loaded through the link\n" words;
  pr "  controller saw: ACKs %s, read %s (done: %b)\n"
    (String.concat "" (List.map (fun a -> if a then "A" else "N") (List.rev c.acks)))
    (String.concat " " (List.map (Printf.sprintf "%02x") (List.rev c.reads))) c.done_;
  pr "  host read: %s\n" (String.concat " " (List.map (fun (t, v) -> Printf.sprintf "tag%d:%02x" t v) !got));
  let lows = let l = List.rev !trace in
    let rec go acc cur = function
      | (_, _, 0) :: r -> go acc (cur + 1) r
      | _ :: r -> go (if cur > 0 then cur :: acc else acc) 0 r
      | [] -> acc in go [] 0 l in
  pr "  longest SCL low phase on the bus: %d clocks (the controller's own is 80: the rest is the target waiting for the host)\n"
    (List.fold_left max 0 lows);
  pr "  RTL and specification agree on every pad, every clock: %b\n" agree;
  let ok = agree && c.done_ && List.rev c.acks = [ true; true; true; true; false; false ] && List.rev c.reads = [ 0x3C; 0xC3; 0x5A ]
           && !got = [ (1, 0xA0); (0, 0x10); (0, 0x55); (3, 0); (1, 0xA1); (2, 0); (2, 0); (2, 1); (3, 0); (3, 0) ] in
  pr "I2C target on the combined chip: %s\n%!" (if ok then "PASS" else "FAIL");
  ok

let demos = [ ("uart", uart); ("spi", spi); ("i2c", i2c); ("i2c-target", i2c_target) ]

let () =
  let ok = match Array.to_list Sys.argv with
    | [ _; "list" ] -> List.iter (fun (n, _) -> print_endline n) demos; true
    | [ _; name ] when List.mem_assoc name demos -> (List.assoc name demos) ()
    | _ -> prerr_endline ("usage: roles.exe list | " ^ String.concat " | " (List.map fst demos)); exit 2 in
  exit (if ok then 0 else 1)
