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
    env = Peer { seeds = [ 1; 2; 3; 4; 5 ]; host = false; world = (fun ~seed -> uart_line ~pin:1 ~baud ~seed) } }

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
    env = Peer { seeds = [ 1; 2; 3 ]; host = false; world = (fun ~seed -> spi_target_world ~sclk ~mosi ~miso ~cs ~mode ~seed) } }

let spi_images () =
  List.concat_map (fun (mode : Fw.spi_mode) ->
      List.concat_map (fun period -> [ spi_ctl ~mode ~period [ 0xA5 ]; spi_ctl ~mode ~period [ 0x00; 0xFF; 0x3C ] ])
        [ (if mode.cpha = 1 then 8 else 10); 15; 150 ]) spi_modes

let spi_planted () =
  let m0 = List.hd spi_modes and m1 = List.nth spi_modes 2 in
  [ { (spi_ctl ~fault:Fw.Sample_on_shift_edge ~mode:m0 ~period:15 [ 0xA5 ]) with name = "PLANTED spi2 mode 0, MISO sampled after the trailing edge" };
    { (spi_ctl ~fault:Fw.No_branch_balance ~mode:m0 ~period:15 [ 0xA5 ]) with name = "PLANTED spi2 mode 0, the MOSI = 0 path a slot short" };
    { (spi_ctl ~image:m1 ~mode:m0 ~period:15 [ 0xA5 ]) with name = "PLANTED spi2 mode 1 firmware against the mode 0 specification" } ]

let sweep () = uart_images () @ spi_images ()
let planted () = uart_planted () @ spi_planted ()
