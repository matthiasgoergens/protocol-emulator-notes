(* The programmes of ../protocol-roles (UART at the common baud rates, SPI controller in modes 0-3,
   I2C controller at 100 and 400 kHz, I2C target, SPI target) and their specifications.

   Images are Fw's output, ISA v2 words already. Each specification is written here from the
   timing that fw.ml's comments state, as closed forms in the protocol's parameters (the same
   rule as programmes.ml): if the generator and its comment disagree, verification fails. The
   closed forms are restated here, not imported from fw.ml. *)

open Spec
open Programmes

let ex = Interval.exactly
let at_least = Interval.at_least

(* ---- UART ---- *)

(* edge k of a frame at slot round(k s) after the start edge (fw.ml, "UART") *)
let uart_grid s k = int_of_float (Float.round (float k *. s))

(* Transmit, s slots a bit. Bytes: the idle level at slot 0, the first start edge after LDA
   (gap 2), every later edge at its grid slot (the start of byte i + 1 at grid 10 of byte i),
   data bit j of byte i the bit j - 1 of the byte (lsb first); then the thread halts. From the
   host: the start edge any time after the idle level (gap >= 2: LDA's place is IN) or after the
   stop bit has lasted its grid length; for ever. *)
let uart_tx_spec ~u ~s src =
  let g = uart_grid s in
  let len k = g (k + 1) - g k in
  let bl = builder () in
  step bl [ (u, Set H) ] (ex 0) "idle high";
  let frame ?bytes i start_gap =
    step bl [ (u, Set L) ] start_gap (Printf.sprintf "byte %d start bit" i);
    for j = 1 to 8 do
      let data = Option.map (fun _ -> (i, j - 1)) bytes in
      step ?data bl [ (u, Data_pp) ] (ex (len (j - 1))) (Printf.sprintf "byte %d data bit %d" i j)
    done;
    step bl [ (u, Set H) ] (ex (len 8)) (Printf.sprintf "byte %d stop bit" i) in
  match src with
  | Fw.Bytes l ->
    let bytes = Array.of_list l in
    List.iteri (fun i _ -> frame ~bytes i (if i = 0 then ex 2 else ex (len 9))) l;
    finish ~bytes bl ~name:(Printf.sprintf "uart tx s=%.3f bytes=%d" s (List.length l)) ~pins:[ u ]
  | Fw.From_host ->
    frame 0 (at_least 2);
    let stop = bl.cur in
    (* the next frames: the same, from the stop state back to it *)
    let st = fresh bl "start bit (host)" in
    add bl ~src:stop [ (u, Set L) ] (at_least (len 9)) ~dst:st "start bit (host)";
    bl.cur <- st;
    for j = 1 to 8 do step bl [ (u, Data_pp) ] (ex (len (j - 1))) (Printf.sprintf "data bit %d (host)" j) done;
    add bl ~src:bl.cur [ (u, Set H) ] (ex (len 8)) ~dst:stop "stop bit (host)";
    finish bl ~name:(Printf.sprintf "uart tx from host s=%.3f" s) ~pins:[ u ]

(* Receive on pin r, s slots a bit (fw.ml, uart_rx): sample k at m k = round((k + 1/2) s - 1/2)
   slots after the slot d in which the start edge is seen. Waiting for the idle line and for the
   start edge are polls (an expiry each slot the pin has the other value) with no deadline. The
   start check at d + m 0 sees 0 (a byte) or 1 (a glitch: back to the start wait); the samples of
   the data bits at d + m k; the stop check at d + m 9: 1, back to the start wait; 0, a framing
   error, back to the idle wait. *)
let uart_rx_spec ~r ~s =
  let m k = int_of_float (Float.round ((float k +. 0.5) *. s -. 0.5)) in
  let bl = builder () in
  let idle = 0 in
  let wait = fresh bl "start wait" in
  add bl ~src:idle [ (r, Timeout 1) ] (at_least 0) ~dst:idle "line low: wait for idle";
  add bl ~src:idle [ (r, Seen 1) ] (at_least 0) ~dst:wait "line idle";
  add bl ~src:wait [ (r, Timeout 0) ] (at_least 1) ~dst:wait "no start yet";
  bl.cur <- wait;
  step bl [ (r, Seen 0) ] (at_least 1) "start edge seen (slot d)";
  let seen = bl.cur in
  add bl ~src:seen [ (r, Timeout 0) ] (ex (m 0)) ~dst:wait "start check: glitch";
  step bl [ (r, Seen 0) ] (ex (m 0)) "start check at d + m 0";
  for k = 1 to 8 do step bl [ (r, Smp) ] (ex (m k - m (k - 1))) (Printf.sprintf "data bit %d sampled at d + m %d" k k) done;
  let last = bl.cur in
  add bl ~src:last [ (r, Seen 1) ] (ex (m 9 - m 8)) ~dst:wait "stop bit seen";
  add bl ~src:last [ (r, Timeout 1) ] (ex (m 9 - m 8)) ~dst:idle "stop bit low: framing error";
  finish bl ~name:(Printf.sprintf "uart rx s=%.3f" s) ~pins:[ r ]

let uart_rates = [ 9600; 19200; 38400; 57600; 115200; 230400; 460800; 921600; 1_000_000; 1_500_000; 2_000_000; 3_000_000 ]

let page (p, _) = p

(* the UART line from a peer transmitter at the nominal rate: random bytes at random phases;
   seeds divisible by 4 put noise on the line instead *)
let uart_line ~pin ~baud ~seed =
  let rng = Random.State.make [| seed; baud |] in
  let bit = Fw.clock_hz /. float baud in
  let frames = List.init 40 (fun i -> (30. +. (float i *. 11.3 *. bit) +. Random.State.float rng bit, Random.State.int rng 256)) in
  let line = Peers.Uart.tx ~bit frames in
  fun ~clock ~pin_out:_ ~pin_oe:_ ->
    let v = if seed mod 4 = 0 then Random.State.int rng 2 else line (clock + 1) in
    0xFF land lnot (1 lsl pin) lor (v lsl pin)

let uart_tx ?(thread = 0) ~baud src =
  let s = Fw.slots_of_hz (float baud) in
  { name = Printf.sprintf "uart2_tx_%d_%s" baud (match src with Fw.Bytes l -> Printf.sprintf "n%d" (List.length l) | Fw.From_host -> "host");
    words = page (Fw.uart_tx ~pin:0 ~s src); spec = uart_tx_spec ~u:0 ~s src; thread;
    env = (match src with Fw.Bytes _ -> Pull_up | Fw.From_host -> Random_inputs) }

let uart_rx ?(thread = 1) ~baud () =
  let s = Fw.slots_of_hz (float baud) in
  { name = Printf.sprintf "uart2_rx_%d" baud; words = page (Fw.uart_rx ~pin:1 ~s ()); spec = uart_rx_spec ~r:1 ~s; thread;
    env = Peer { seeds = [ 1; 2; 3; 4; 5 ]; host = None; world = (fun ~seed -> uart_line ~pin:1 ~baud ~seed) } }

let uart_images () =
  List.concat_map (fun baud ->
      [ uart_tx ~baud (Fw.Bytes [ 0x55; 0x00; 0xFF; 0x4F; 0xA5 ]); uart_tx ~baud (Fw.Bytes [ 0x4F ]);
        uart_tx ~baud Fw.From_host; uart_rx ~baud () ]) uart_rates

let uart_planted () =
  let opcode w = (w lsr 12) land 15 in
  let nth words o n =
    let rec go i k = if opcode words.(i) = o then (if k = n then i else go (i + 1) (k + 1)) else go (i + 1) k in go 0 0 in
  let tx = uart_tx ~baud:115200 (Fw.Bytes [ 0x55; 0x4F ]) in
  let rx = uart_rx ~baud:115200 () in
  [ with_words tx ~name:"PLANTED uart2 tx 115200, the third bit's wait one slot short" (fun w ->
        let i = nth w Isa2.op_ldd 2 in w.(i) <- w.(i) - 1; w);
    with_words tx ~name:"PLANTED uart2 tx 115200, sent msb first" (fun w ->
        Array.map (fun x -> if opcode x = Isa2.op_sho then x lor 0x100 else x) w);
    with_words rx ~name:"PLANTED uart2 rx 115200, the fourth sample one slot late" (fun w ->
        let i = nth w Isa2.op_ldd 4 in w.(i) <- w.(i) + 1; w) ]

(* ---- SPI controller ---- *)

(* fw.ml, spi_ctl: [act] = P/2 slots SCLK active, [idl] = P - act idle. Set-up: CS high, SCLK at
   CPOL, MOSI low on slots 0, 1, 2; CS low idl + 1 slots later. CPHA 0, per bit: MOSI written
   (1 or 0, from the data: two transitions) 3 slots after the previous trailing edge, 6 for the
   first bit of a later byte, 4 after CS for the very first; the leading edge idl - 3 slots
   later; MISO sampled 1 slot after it; the trailing edge act - 1 slots after the sample; CS high
   idl slots after the last trailing edge. CPHA 1, per bit: the leading edge idl after CS for the
   very first bit, idl + 2 after the previous sample for the first bit of a later byte, idl - 1
   after it otherwise; MOSI written 2 slots after the leading edge; the trailing edge act - 2
   later; MISO sampled 1 slot after it; CS high idl slots after the last sample. MOSI's value
   is not declared: it is written by SETP after a branch on the accumulator, and the analysis
   does not keep the accumulator once SHI has shifted an input into it. *)
let spi_ctl_spec ~sclk ~mosi ~miso ~cs ~(mode : Fw.spi_mode) ~period ~nbytes =
  let act = period / 2 in
  let idl = period - act in
  let active = if mode.cpol = 0 then H else L and idle = if mode.cpol = 0 then L else H in
  let bl = builder () in
  (* MOSI written with either level: two transitions to one state *)
  let mosi_write gap label =
    let src = bl.cur in
    step bl [ (mosi, Set H) ] (ex gap) label;
    add bl ~src [ (mosi, Set L) ] (ex gap) ~dst:bl.cur label in
  step bl [ (cs, Set H) ] (ex 0) "cs high";
  step bl [ (sclk, Set idle) ] (ex 1) "sclk idle";
  step bl [ (mosi, Set L) ] (ex 1) "mosi low";
  step bl [ (cs, Set L) ] (ex (idl + 1)) "cs low";
  for i = 0 to nbytes - 1 do
    for j = 1 to 8 do
      let l = Printf.sprintf "byte %d bit %d" i j in
      if mode.cpha = 0 then begin
        mosi_write (if j > 1 then 3 else if i = 0 then 4 else 6) (l ^ " mosi");
        step bl [ (sclk, Set active) ] (ex (idl - 3)) (l ^ " leading edge");
        step bl [ (miso, Smp) ] (ex 1) (l ^ " miso sampled");
        step bl [ (sclk, Set idle) ] (ex (act - 1)) (l ^ " trailing edge")
      end else begin
        step bl [ (sclk, Set active) ] (ex (if j > 1 then idl - 1 else if i = 0 then idl else idl + 2)) (l ^ " leading edge");
        mosi_write 2 (l ^ " mosi");
        step bl [ (sclk, Set idle) ] (ex (act - 2)) (l ^ " trailing edge");
        step bl [ (miso, Smp) ] (ex 1) (l ^ " miso sampled")
      end
    done
  done;
  step bl [ (cs, Set H) ] (ex idl) "cs high again";
  finish bl ~name:(Printf.sprintf "spi controller %s P=%d bytes=%d" (Fw.spi_mode_name mode) period nbytes)
    ~pins:[ sclk; mosi; miso; cs ]

let spi_modes = List.concat_map (fun (cpol, cpha) -> List.map (fun msb -> { Fw.cpol; cpha; msb }) [ true; false ])
    [ (0, 0); (0, 1); (1, 0); (1, 1) ]

(* the SPI target of peers.ml on the bus, in the controller's mode, with random replies and a
   random MISO delay; MISO is pin [miso] *)
let spi_target_world ~sclk ~mosi ~miso ~cs ~(mode : Fw.spi_mode) ~seed =
  let rng = Random.State.make [| seed; 77 |] in
  let t = Peers.Spi.target ~delay:(Random.State.int rng 12) ~mode:{ Peers.Spi.cpol = mode.cpol; cpha = mode.cpha; msb = mode.msb }
      (List.init 64 (fun _ -> Random.State.int rng 256)) in
  fun ~clock:_ ~pin_out ~pin_oe ->
    let lv p = if (pin_oe lsr p) land 1 = 1 then (pin_out lsr p) land 1 else 1 in
    let m = Peers.Spi.step t ~sclk:(lv sclk) ~mosi:(lv mosi) ~cs:(lv cs) in
    let bus = List.fold_left (fun a p -> a lor (lv p lsl p)) 0 [ 0; 1; 2; 3; 4; 5; 6; 7 ] in
    (bus land lnot (1 lsl miso)) lor ((match m with Some v -> v | None -> 1) lsl miso)

let spi_ctl ?fault ?(thread = 1) ?image ~(mode : Fw.spi_mode) ~period bytes =
  let sclk = 1 and mosi = 2 and miso = 3 and cs = 4 in
  let words = page (Fw.spi_ctl ?fault ~sclk ~mosi ~miso ~cs ~mode:(Option.value image ~default:mode) ~period bytes) in
  { name = Printf.sprintf "spi2_ctl_m%d%s_p%d_n%d" (2 * mode.cpol + mode.cpha) (if mode.msb then "msb" else "lsb") period (List.length bytes);
    words; spec = spi_ctl_spec ~sclk ~mosi ~miso ~cs ~mode ~period ~nbytes:(List.length bytes); thread;
    env = Peer { seeds = [ 1; 2; 3 ]; host = None; world = (fun ~seed -> spi_target_world ~sclk ~mosi ~miso ~cs ~mode ~seed) } }

let spi_images () =
  List.concat_map (fun (mode : Fw.spi_mode) ->
      List.concat_map (fun period -> [ spi_ctl ~mode ~period [ 0xA5 ]; spi_ctl ~mode ~period [ 0x00; 0xFF; 0x3C ] ])
        [ (if mode.cpha = 1 then 8 else 10); 15; 150 ]) spi_modes

let spi_planted () =
  let m0 = List.hd spi_modes and m1 = List.nth spi_modes 2 in
  [ { (spi_ctl ~fault:Fw.Sample_on_shift_edge ~mode:m0 ~period:15 [ 0xA5 ]) with name = "PLANTED spi2 mode 0, MISO sampled after the trailing edge" };
    { (spi_ctl ~fault:Fw.No_branch_balance ~mode:m0 ~period:15 [ 0xA5 ]) with name = "PLANTED spi2 mode 0, the MOSI = 0 path a slot short" };
    { (spi_ctl ~image:m1 ~mode:m0 ~period:15 [ 0xA5 ]) with name = "PLANTED spi2 mode 1 firmware against the mode 0 specification" } ]

(* ---- I2C controller (host commands) ---- *)

(* fw.ml, i2c_ctl, with t the timing and L the stretch limit. Events on SDA and SCL:
   - slot 0: both released. On an idle bus the START (SDA low) comes at least 4 slots after the
     start, buf + 3 after a STOP's SDA release, 6 after a timeout's release (IN, SKNE, JMP).
   - Every command's first event is SCL low: at least hd_sta after a START's or repeated START's
     SDA low, at least max(high - smp, 8) after a write's ACK sample, at least max(high, 8) after
     the slot SCL is seen high in a read's ACK clock (the command fetch's IN has no bound).
   - A pulse from SCL low at a: its SDA action at a + hd_dat, SCL released low - hd_dat later,
     SCL seen high within [1, L] slots, or a timeout at exactly L after which both lines are
     released 1 slot later and the bus is idle. Within a byte the next SCL low is [high] after SCL
     is seen high, or [high - smp] after the sample.
   - write: 8 pulses whose SDA action is SHO od (data from the host, not declared), then a pulse
     releasing SDA with the ACK sampled smp after SCL seen high (seen 0: ACK; timeout 0: NACK).
   - read: 8 pulses releasing SDA, sampled smp after SCL is seen high; then a pulse driving SDA
     low (ACK) or releasing it (NACK).
   - repeated START: a pulse releasing SDA, SDA low su_sta after SCL is seen high.
   - STOP: a pulse driving SDA low, SDA released su_sto after SCL is seen high. *)
let i2c_ctl_spec ~sda ~scl ~(t : Fw.i2c_timing) ~lm =
  let bl = builder () in
  let state name = fresh bl name in
  let tr ?(gap = ex 0) src pats dst label = add bl ~src pats gap ~dst label in
  let idle_init = state "idle (after reset)" and post_stop = state "idle (after STOP)" and post_to = state "idle (after a timeout)" in
  let started = state "START: SDA low" and oplow = state "a command's SCL low" in
  tr 0 [ (sda, Set Z); (scl, Set Z) ] idle_init "both released" ~gap:(ex 0);
  List.iter (fun (src, g) -> tr src [ (sda, Set L) ] started "START" ~gap:(at_least g))
    [ (idle_init, 4); (post_stop, t.buf + 3); (post_to, 6) ];
  tr started [ (scl, Set L) ] oplow "first SCL low after START" ~gap:(at_least t.hd_sta);
  (* the rest of a pulse after its SDA action: SCL released, seen high or a timeout; returns the
     state after SCL is seen high *)
  let rest_of_pulse after_action label =
    let rel = state (label ^ ": SCL released") and seen = state (label ^ ": SCL seen high") and tout = state (label ^ ": timed out") in
    tr after_action [ (scl, Set Z) ] rel (label ^ ": SCL released") ~gap:(ex (t.low - t.hd_dat));
    tr rel [ (scl, Seen 1) ] seen (label ^ ": SCL seen high") ~gap:(Interval.range 1 lm);
    tr rel [ (scl, Timeout 1) ] tout (label ^ ": timeout") ~gap:(ex lm);
    tr tout [ (sda, Set Z); (scl, Set Z) ] post_to (label ^ ": released after the timeout") ~gap:(ex 1);
    seen in
  (* write *)
  let w_act = state "write bit 1: SDA" in
  tr oplow [ (sda, Data_od) ] w_act "write bit 1: SDA" ~gap:(ex t.hd_dat);
  let cur = ref (rest_of_pulse w_act "write bit 1") in
  for k = 2 to 8 do
    let low = state (Printf.sprintf "write bit %d: SCL low" k) and act = state (Printf.sprintf "write bit %d: SDA" k) in
    tr !cur [ (scl, Set L) ] low (Printf.sprintf "write bit %d: SCL low" k) ~gap:(ex t.high);
    tr low [ (sda, Data_od) ] act (Printf.sprintf "write bit %d: SDA" k) ~gap:(ex t.hd_dat);
    cur := rest_of_pulse act (Printf.sprintf "write bit %d" k)
  done;
  let alow = state "write ACK clock: SCL low" and aact = state "write ACK clock: SDA released" and wdone = state "write: ACK sampled" in
  tr !cur [ (scl, Set L) ] alow "write ACK clock: SCL low" ~gap:(ex t.high);
  tr alow [ (sda, Set Z) ] aact "write ACK clock: SDA released" ~gap:(ex t.hd_dat);
  let aseen = rest_of_pulse aact "write ACK clock" in
  tr aseen [ (sda, Seen 0) ] wdone "ACK" ~gap:(ex t.smp);
  tr aseen [ (sda, Timeout 0) ] wdone "NACK" ~gap:(ex t.smp);
  tr wdone [ (scl, Set L) ] oplow "next command's SCL low after a write" ~gap:(at_least (max (t.high - t.smp) 8));
  (* read, and the repeated START, which share their first pulse's SDA release *)
  let rel1 = state "read bit 1 or repeated START: SDA released" in
  tr oplow [ (sda, Set Z) ] rel1 "read bit 1 or repeated START: SDA released" ~gap:(ex t.hd_dat);
  let seen1 = rest_of_pulse rel1 "read bit 1 or repeated START" in
  let sr = state "repeated START: SDA low" in
  tr seen1 [ (sda, Set L) ] sr "repeated START" ~gap:(ex t.su_sta);
  tr sr [ (scl, Set L) ] oplow "first SCL low after a repeated START" ~gap:(at_least t.hd_sta);
  let smp1 = state "read bit 1 sampled" in
  tr seen1 [ (sda, Smp) ] smp1 "read bit 1 sampled" ~gap:(ex t.smp);
  let cur = ref smp1 in
  for k = 2 to 8 do
    let low = state (Printf.sprintf "read bit %d: SCL low" k) and act = state (Printf.sprintf "read bit %d: SDA released" k)
    and sm = state (Printf.sprintf "read bit %d sampled" k) in
    tr !cur [ (scl, Set L) ] low (Printf.sprintf "read bit %d: SCL low" k) ~gap:(ex (t.high - t.smp));
    tr low [ (sda, Set Z) ] act (Printf.sprintf "read bit %d: SDA released" k) ~gap:(ex t.hd_dat);
    let seen = rest_of_pulse act (Printf.sprintf "read bit %d" k) in
    tr seen [ (sda, Smp) ] sm (Printf.sprintf "read bit %d sampled" k) ~gap:(ex t.smp);
    cur := sm
  done;
  let rlow = state "read ACK clock: SCL low" and ract = state "read ACK clock: SDA set" in
  tr !cur [ (scl, Set L) ] rlow "read ACK clock: SCL low" ~gap:(ex (t.high - t.smp));
  tr rlow [ (sda, Set L) ] ract "read ACK clock: ACK" ~gap:(ex t.hd_dat);
  tr rlow [ (sda, Set Z) ] ract "read ACK clock: NACK" ~gap:(ex t.hd_dat);
  let rseen = rest_of_pulse ract "read ACK clock" in
  tr rseen [ (scl, Set L) ] oplow "next command's SCL low after a read" ~gap:(at_least (max t.high 8));
  (* STOP *)
  let slow = state "STOP: SDA low" in
  tr oplow [ (sda, Set L) ] slow "STOP: SDA low" ~gap:(ex t.hd_dat);
  let sseen = rest_of_pulse slow "STOP" in
  tr sseen [ (sda, Set Z) ] post_stop "STOP" ~gap:(ex t.su_sto);
  finish bl ~name:(Printf.sprintf "i2c controller low=%d high=%d limit=%d" t.low t.high lm) ~pins:[ sda; scl ]

(* the register-file target of peers.ml on the bus, stretching at random; the host's commands
   are mostly commands (i2c_host_byte) *)
let i2c_target_world ~sda ~scl ~seed =
  let rng = Random.State.make [| seed; 99 |] in
  let tgt = Peers.I2c.target ~t_vd:(Random.State.int rng 20) ~addr:0x50
      ~stretch:(fun () -> match Random.State.int rng 8 with 0 -> Random.State.int rng 300 | 1 -> Random.State.int rng 5000 | _ -> 0) () in
  let pull = ref (false, false) in
  fun ~clock:_ ~pin_out ~pin_oe ->
    let pulls p = (pin_oe lsr p) land 1 = 1 && (pin_out lsr p) land 1 = 0 in
    let s = if pulls sda || fst !pull then 0 else 1 and c = if pulls scl || snd !pull then 0 else 1 in
    pull := Peers.I2c.step tgt ~sda:s ~scl:c;
    0xFF land lnot ((1 - s) lsl sda) land lnot ((1 - c) lsl scl)

(* host bytes for the controller: mostly commands, START and writes to the target's address
   more often, so that runs get past the address *)
let i2c_host_byte rng =
  match Random.State.int rng 12 with
  | 0 | 1 -> Fw.cmd_start | 2 -> Fw.cmd_stop | 3 | 4 | 5 -> Fw.cmd_write | 6 -> 0xA0 | 7 -> 0xA1
  | 8 -> Fw.cmd_read_ack | 9 -> Fw.cmd_read_nack | _ -> Random.State.int rng 256

let i2c_ctl ?fault ?(thread = 2) ?(lm = 4095) ~name (t : Fw.i2c_timing) =
  let sda = 4 and scl = 5 in
  { name = Printf.sprintf "i2c2_ctl_%s_l%d" name lm; words = page (Fw.i2c_ctl ?fault ~stretch_limit:lm ~sda ~scl ~timing:t ());
    spec = i2c_ctl_spec ~sda ~scl ~t ~lm; thread;
    env = Peer { seeds = [ 1; 2; 3; 4; 5; 6 ]; host = Some i2c_host_byte; world = (fun ~seed -> i2c_target_world ~sda ~scl ~seed) } }

let i2c_images () =
  List.concat_map (fun lm -> [ i2c_ctl ~lm ~name:"standard" Fw.standard_timing; i2c_ctl ~lm ~name:"fast" Fw.fast_timing ])
    [ 7; 200; 4095 ]

let i2c_planted () =
  [ { (i2c_ctl ~fault:Fw.Ack_in_low_phase ~name:"fast" Fw.fast_timing) with name = "PLANTED i2c2 fast, the ACK read while SCL is low" };
    { (i2c_ctl ~fault:Fw.No_stretch_wait ~name:"fast" Fw.fast_timing) with name = "PLANTED i2c2 fast, no wait for SCL high" };
    { (i2c_ctl ~name:"fast" { Fw.fast_timing with low = 19 }) with name = "PLANTED i2c2 fast, SCL low 19 slots against 25";
                                                                spec = i2c_ctl_spec ~sda:4 ~scl:5 ~t:Fw.fast_timing ~lm:4095 } ]

(* ---- I2C target ---- *)

(* fw.ml, i2c_target, with [su] its set-up wait. Every wait for a level is a poll, an expiry each
   slot the level is not there (gap at least 1, no deadline: the controller and the host set the
   pace), then an observation. What is exact is the target's response to what it sees:
   - SCL seen high: SDA sampled (SHI) 1 slot later; in a read's ACK clock, SDA looked at 1 slot
     later (seen 0: ACK; expiry: NACK).
   - while SCL is high after a byte's first bit (the "poll"): SCL looked at 2 slots after each look
     at SDA (or after the sample), SDA 1 slot after each look at SCL; SDA moved: a START (it was
     1) or a STOP (it was 0); SCL low: the byte goes on (or, in the monitor, the next SCL high is
     awaited).
   - after the address's 8th bit, SCL seen low: SDA driven low (ACK) 3 or 4 slots later (write or
     read address), or, not addressed, the monitor's next look at SCL 4 slots later.
   - after a byte written, SCL seen low: SCL pulled low 2 slots later (stretching); then, after the
     host's answer (IN, unbounded), SDA low (ACK) at least 5 slots after the stretch began and SCL
     released su + 1 after that, or (NACK) SCL released at least su + 4 after the stretch began.
   - a read: SCL pulled low 1 or 2 slots after SCL seen low; after the host's byte (IN), the first
     bit (SHO od) at least 3 slots after; SCL released su + 1 after it; each later bit 1 slot after
     SCL seen low; SDA released 1 slot after SCL seen low at the end of the 8th bit. *)
let i2c_target_spec ~sda ~scl ~su =
  let bl = builder () in
  let st name = fresh bl name in
  let tr ~gap src pats dst label = add bl ~src pats gap ~dst label in
  let any = at_least 1 in
  (* a poll at state [s]: an expiry stays, an observation goes to a new state *)
  let wait_for s pin v name =
    let d = st name in
    tr ~gap:any s [ (pin, Timeout v) ] s (name ^ ": not yet");
    tr ~gap:any s [ (pin, Seen v) ] d name; d in
  let mon = st "monitor: waiting for SCL high" and started = st "START: waiting for SCL low" in
  tr ~gap:(ex 0) 0 [ (sda, Set Z); (scl, Set Z) ] mon "both released";
  (* the poll while SCL is high, from the state after a sample: [on_low] is where SCL low leads *)
  let poll ps ~on_low label =
    let b = st (label ^ ": SCL still high") in
    tr ~gap:(ex 2) ps [ (scl, Seen 1) ] b (label ^ ": SCL still high");
    tr ~gap:(ex 2) ps [ (scl, Timeout 1) ] on_low (label ^ ": SCL low");
    tr ~gap:(ex 1) b [ (sda, Seen 1) ] ps (label ^ ": SDA still 1");
    tr ~gap:(ex 1) b [ (sda, Seen 0) ] ps (label ^ ": SDA still 0");
    tr ~gap:(ex 1) b [ (sda, Timeout 1) ] started (label ^ ": SDA fell: START");
    tr ~gap:(ex 1) b [ (sda, Timeout 0) ] mon (label ^ ": SDA rose: STOP") in
  (* the monitor *)
  let mseen = wait_for mon scl 1 "monitor: SCL high" in
  let msmp = st "monitor: SDA sampled" in
  tr ~gap:(ex 1) mseen [ (sda, Smp) ] msmp "monitor: SDA sampled";
  poll msmp ~on_low:mon "monitor";
  (* the address byte *)
  let cur = ref started in
  for k = 1 to 8 do
    let l = wait_for !cur scl 0 (Printf.sprintf "address bit %d: SCL low" k) in
    let h = wait_for l scl 1 (Printf.sprintf "address bit %d: SCL high" k) in
    let sm = st (Printf.sprintf "address bit %d sampled" k) in
    tr ~gap:(ex 1) h [ (sda, Smp) ] sm (Printf.sprintf "address bit %d sampled" k);
    cur := sm
  done;
  let alow = wait_for !cur scl 0 "address: SCL low after bit 8" in
  let acked = st "address ACK: SDA low" in
  tr ~gap:(Interval.range 3 4) alow [ (sda, Set L) ] acked "address matched: ACK";
  tr ~gap:(ex 4) alow [ (scl, Timeout 1) ] mon "not addressed: back to the monitor (SCL low)";
  tr ~gap:(ex 4) alow [ (scl, Seen 1) ] mseen "not addressed: back to the monitor (SCL high)";
  let ah = wait_for acked scl 1 "address ACK clock: SCL high" in
  let al = wait_for ah scl 0 "address ACK clock: SCL low" in
  (* write: SDA released, then bytes *)
  let wrel = st "write: waiting for a byte's first SCL high" in
  tr ~gap:(ex 1) al [ (sda, Set Z) ] wrel "write: ACK released";
  let w1h = wait_for wrel scl 1 "write bit 1: SCL high" in
  let w1s = st "write bit 1 sampled" in
  tr ~gap:(ex 1) w1h [ (sda, Smp) ] w1s "write bit 1 sampled";
  let wbits = st "write bits 2-8: waiting for SCL high" in
  poll w1s ~on_low:wbits "write bit 1";
  let cur = ref wbits in
  for k = 2 to 8 do
    let h = wait_for !cur scl 1 (Printf.sprintf "write bit %d: SCL high" k) in
    let sm = st (Printf.sprintf "write bit %d sampled" k) in
    tr ~gap:(ex 1) h [ (sda, Smp) ] sm (Printf.sprintf "write bit %d sampled" k);
    cur := wait_for sm scl 0 (Printf.sprintf "write bit %d: SCL low" k)
  done;
  let wstr = st "write: stretching, waiting for the host" in
  tr ~gap:(ex 2) !cur [ (scl, Set L) ] wstr "write: SCL pulled low (stretch)";
  let wack = st "write: ACK set" in
  tr ~gap:(at_least 5) wstr [ (sda, Set L) ] wack "write: the host says ACK";
  let wrel2 = st "write ACK: SCL released" and wnrel = st "write NACK: SCL released" in
  tr ~gap:(ex (su + 1)) wack [ (scl, Set Z) ] wrel2 "write ACK: SCL released";
  tr ~gap:(at_least (su + 4)) wstr [ (scl, Set Z) ] wnrel "write: the host says NACK, SCL released";
  let h = wait_for wrel2 scl 1 "write ACK clock: SCL high" in
  let l = wait_for h scl 0 "write ACK clock: SCL low" in
  tr ~gap:(ex 1) l [ (sda, Set Z) ] wrel "write: ACK released, next byte";
  let h = wait_for wnrel scl 1 "write NACK clock: SCL high" in
  let l = wait_for h scl 0 "write NACK clock: SCL low" in
  tr ~gap:any l [ (scl, Seen 1) ] w1h "write after a NACK: next byte's SCL high";
  tr ~gap:any l [ (scl, Timeout 1) ] wrel "write after a NACK: waiting for SCL high";
  (* read *)
  let rstr = st "read: stretching, waiting for the host" in
  tr ~gap:(ex 1) al [ (scl, Set L) ] rstr "read: SCL pulled low (stretch)";
  let rb = st "read bit 1 set" in
  tr ~gap:(at_least 3) rstr [ (sda, Data_od) ] rb "read: the host's byte, bit 1";
  let rrel = st "read bit 1: SCL released" in
  tr ~gap:(ex (su + 1)) rb [ (scl, Set Z) ] rrel "read bit 1: SCL released";
  let cur = ref rrel in
  for k = 2 to 8 do
    let h = wait_for !cur scl 1 (Printf.sprintf "read bit %d: SCL high" (k - 1)) in
    let l = wait_for h scl 0 (Printf.sprintf "read bit %d: SCL low" (k - 1)) in
    let b = st (Printf.sprintf "read bit %d set" k) in
    tr ~gap:(ex 1) l [ (sda, Data_od) ] b (Printf.sprintf "read bit %d set" k);
    cur := b
  done;
  let h = wait_for !cur scl 1 "read bit 8: SCL high" in
  let l = wait_for h scl 0 "read bit 8: SCL low" in
  let rack = st "read ACK clock: SDA released" in
  tr ~gap:(ex 1) l [ (sda, Set Z) ] rack "read: SDA released for the controller's ACK";
  let rh = wait_for rack scl 1 "read ACK clock: SCL high" in
  let racked = st "read: ACK seen" and rnack = st "read: NACK seen" in
  tr ~gap:(ex 1) rh [ (sda, Seen 0) ] racked "read: ACK";
  tr ~gap:(ex 1) rh [ (sda, Timeout 0) ] rnack "read: NACK";
  let rl = wait_for racked scl 0 "read ACK clock: SCL low" in
  tr ~gap:(ex 2) rl [ (scl, Set L) ] rstr "read: next byte, SCL pulled low (stretch)";
  let nsmp = st "after a NACK: SDA sampled" in
  tr ~gap:(ex 3) rnack [ (sda, Smp) ] nsmp "after a NACK: SDA sampled";
  poll nsmp ~on_low:mon "after a NACK";
  finish bl ~name:(Printf.sprintf "i2c target su=%d" su) ~pins:[ sda; scl ]

let i2c_ctl_world ~sda ~scl ~(ct : Peers.I2c.ctiming) ~seed =
  let rng = Random.State.make [| seed; 101 |] in
  let byte () = Random.State.int rng 256 in
  let ops = List.concat (List.init 6 (fun _ ->
      let a = if Random.State.int rng 3 = 0 then byte () else 0xA0 lor Random.State.int rng 2 in
      Peers.I2c.([ C_start; C_write a ] @
                 (if a land 1 = 0 then List.init (1 + Random.State.int rng 3) (fun _ -> C_write (byte ()))
                  else let n = 1 + Random.State.int rng 3 in List.init n (fun i -> C_read (i < n - 1)))
                 @ (if Random.State.bool rng then [ C_stop ] else [ C_restart; C_write 0xA1; C_read false; C_stop ])))) in
  let c = Peers.I2c.controller ct ops in
  let pull = ref (false, false) in
  fun ~clock:_ ~pin_out ~pin_oe ->
    let pulls p = (pin_oe lsr p) land 1 = 1 && (pin_out lsr p) land 1 = 0 in
    let s = if pulls sda || fst !pull then 0 else 1 and k = if pulls scl || snd !pull then 0 else 1 in
    pull := Peers.I2c.controller_step c ~sda:s ~scl:k;
    0xFF land lnot ((1 - s) lsl sda) land lnot ((1 - k) lsl scl)

let i2c_target ?(thread = 3) ~su ~name ct =
  let sda = 6 and scl = 7 in
  { name = Printf.sprintf "i2c2_target_%s_su%d" name su; words = page (Fw.i2c_target ~sda ~scl ~addr:0x50 ~su ());
    spec = i2c_target_spec ~sda ~scl ~su; thread;
    env = Peer { seeds = [ 1; 2; 3; 4; 5; 6 ]; host = Some (fun rng -> if Random.State.int rng 2 = 0 then 0 else Random.State.int rng 256);
                 world = (fun ~seed -> i2c_ctl_world ~sda ~scl ~ct ~seed) } }

let i2c_target_images () =
  [ i2c_target ~su:19 ~name:"standard" Peers.I2c.c_standard; i2c_target ~su:6 ~name:"fast" Peers.I2c.c_fast;
    i2c_target ~su:1 ~name:"fast" Peers.I2c.c_fast ]

let i2c_target_planted () =
  let opcode w = (w lsr 12) land 15 in
  let t = i2c_target ~su:6 ~name:"fast" Peers.I2c.c_fast in
  [ with_words t ~name:"PLANTED i2c2 target, a read's first bit swapped with the set-up's LDD" (fun w ->
        (* the first SHO (a read's first bit) one slot later, so SCL is released one slot after it *)
        let i = ref 0 in
        while not (opcode w.(!i) = Isa2.op_sho) do incr i done;
        let x = w.(!i) in w.(!i) <- w.(!i + 1); w.(!i + 1) <- x; w);
    { t with name = "PLANTED i2c2 target, set-up 6 slots against a declared 7"; spec = i2c_target_spec ~sda:6 ~scl:7 ~su:7 } ]

let sweep () = uart_images () @ spi_images () @ i2c_images () @ i2c_target_images ()
let planted () = uart_planted () @ spi_planted () @ i2c_planted () @ i2c_target_planted ()
