(* Task 1: UART at the common baud rates, transmit and receive, at the chip's 60 MHz.

   For each rate the transmitter (Fw.uart_tx) and the receiver (Fw.uart_rx) run on the ISA v2
   interpreter and the RTL in lockstep, against the ideal peers of peers.ml:
   - transmit: the peer receiver decodes the bytes; the bit timing is measured from the clocks at
     which the thread writes the pin (every one of the ten edges of a frame, including those that
     do not change the level): the worst displacement of an edge from the ideal grid, the shortest
     and longest bit, and the mean bit time over the frame;
   - receive: the peer transmitter sends random bytes at random phases against the core clock;
     the bytes the thread reports must be the bytes sent, and the clock of every sample (SHI) is
     compared with the ideal mid-bit instant; then the peer's baud rate is moved away from the
     nominal one until the receiver fails, which is its tolerance. *)

let pr = Printf.printf
let rates = [ 9600; 19200; 38400; 57600; 115200; 230400; 460800; 921600; 1_000_000; 1_500_000; 2_000_000; 3_000_000 ]
let bit_clocks baud = Fw.clock_hz /. float baud
let tx_bytes = [ 0x55; 0x00; 0xFF; 0x4F; 0xA5 ]

let op w = (w lsr 12) land 15

(* write instants (issue clocks of SETP and SHO) of thread [t], without the first (the idle level) *)
let writes (r : Bench.result) t =
  List.filter_map (fun (c, th, w) -> if th = t && (op w = 1 || op w = 7) then Some c else None) r.issues
  |> List.tl

let chunks n l =
  let rec go acc cur k = function
    | [] -> List.rev (if cur = [] then acc else List.rev cur :: acc)
    | x :: r -> if k = n then go (List.rev cur :: acc) [ x ] 1 r else go acc (x :: cur) (k + 1) r in
  go [] [] 0 l

type tx_meas = { decoded : int list; ok : bool; worst_edge : float; min_bit : int; max_bit : int; mean_bit : float;
                 mism : int; words : int; tr : Bench.result }

let tx_run ?bug ?(rtl = true) ?(mutate = Fun.id) ~baud () =
  let s = Fw.slots_of_hz (float baud) in
  let page, words = Fw.uart_tx ~pin:0 ~s (Fw.Bytes tx_bytes) in
  let page = mutate (Array.copy page) in
  let t = bit_clocks baud in
  let clocks = int_of_float (t *. 10. *. float (List.length tx_bytes + 1)) + 200 in
  let r = Bench.run ?bug ~rtl ~record_issues:true ~pages:[| Some page; None; None; None |] ~clocks
      ~world:(fun ~clock:_ ~pin_out ~pin_oe -> Bench.driven ~idle:0xFF ~pin_out ~pin_oe ()) (Bench.host []) in
  let dec = Peers.Uart.rx ~bit:t ~clocks:r.clocks (fun c -> Bench.level r c 0) in
  let decoded = List.map (fun (_, b, ok) -> if ok then b else -1) dec in
  let frames = chunks 10 (writes r 0) in
  let worst = ref 0. and mn = ref max_int and mx = ref 0 and means = ref [] in
  List.iter (fun f ->
      let a = Array.of_list f in
      if Array.length a = 10 then begin
        Array.iteri (fun k w -> worst := Float.max !worst (Float.abs (float (w - a.(0)) -. (float k *. t)))) a;
        for k = 0 to 8 do let d = a.(k + 1) - a.(k) in mn := min !mn d; mx := max !mx d done;
        means := float (a.(9) - a.(0)) /. 9. :: !means
      end) frames;
  (* the stop bit: the next frame's start edge, where there is one *)
  List.iter2 (fun f g -> match f, g with
      | a0 :: _, b0 :: _ -> worst := Float.max !worst (Float.abs (float (b0 - a0) -. (10. *. t)))
      | _ -> ()) (List.filteri (fun i _ -> i < List.length frames - 1) frames) (List.tl frames);
  let mean = List.fold_left ( +. ) 0. !means /. float (List.length !means) in
  { decoded; ok = decoded = tx_bytes && r.mismatches = 0; worst_edge = !worst; min_bit = !mn; max_bit = !mx;
    mean_bit = mean; mism = r.mismatches; words; tr = r }

(* the transmitter fed by the host, one byte at a time (IN): the same decoder *)
let tx_host_run ~baud =
  let s = Fw.slots_of_hz (float baud) in
  let page, words = Fw.uart_tx ~pin:0 ~s Fw.From_host in
  let t = bit_clocks baud in
  let clocks = int_of_float (t *. 10. *. float (List.length tx_bytes + 1)) + 200 in
  let r = Bench.run ~pages:[| Some page; None; None; None |] ~clocks
      ~world:(fun ~clock:_ ~pin_out ~pin_oe -> Bench.driven ~idle:0xFF ~pin_out ~pin_oe ()) (Bench.host tx_bytes) in
  let dec = Peers.Uart.rx ~bit:t ~clocks:r.clocks (fun c -> Bench.level r c 0) in
  List.map (fun (_, b, ok) -> if ok then b else -1) dec = tx_bytes && r.mismatches = 0, words, r.mismatches

type rx_meas = { rx_ok : bool; worst_sample : float; rx_mism : int; rx_words : int; got : int list; sent : int list;
                 rtr : Bench.result }

(* the receiver on thread 1, pin 1; the peer sends [n] random bytes at random phases, at a bit
   time [scale] times the nominal one *)
let rx_run ?bug ?(rtl = true) ?(mutate = Fun.id) ?(scale = 1.0) ?(n = 8) ?(stop0 = []) ~seed ~baud () =
  let rng = Random.State.make [| seed; baud |] in
  let s = Fw.slots_of_hz (float baud) in
  let page, words = Fw.uart_rx ~pin:1 ~s () in
  let page = mutate (Array.copy page) in
  let t = bit_clocks baud in
  let tp = t *. scale in
  let bytes = List.init n (fun _ -> Random.State.int rng 256) in
  (* the first start a random fraction of a slot after clock 40, then each frame 10 to 12.5 bits
     after the previous one's start (10: back to back, one stop bit) *)
  let first = 40. +. Random.State.float rng 8. in
  let starts = ref [] and at = ref first in
  List.iteri (fun i b ->
      starts := (!at, b) :: !starts;
      at := !at +. (tp *. (if i mod 3 = 0 then 10. else 10. +. Random.State.float rng 2.5))) bytes;
  let frames = List.rev !starts in
  let line = Peers.Uart.tx ~bit:tp frames in
  (* frames whose stop bit is forced low (framing-error tests) *)
  let line c = if List.exists (fun i -> let st, _ = List.nth frames i in
                                float c >= st +. (9. *. tp) && float c < st +. (10. *. tp)) stop0 then 0 else line c in
  let clocks = int_of_float (!at +. (2. *. tp)) + 100 in
  let r = Bench.run ?bug ~rtl ~record_issues:true ~pages:[| None; Some page; None; None |] ~clocks
      ~world:(fun ~clock ~pin_out:_ ~pin_oe:_ -> 0xFD lor (line (clock + 1) lsl 1)) (Bench.host []) in
  let got = List.map (fun (_, tag, b) -> if tag = 0 then b else -1 - b) r.outs in
  (* sample instants: the clocks of the SHIs of thread 1, eight a frame *)
  let shis = List.filter_map (fun (c, th, w) -> if th = 1 && op w = 8 then Some c else None) r.issues in
  let worst = ref 0. in
  List.iteri (fun i f -> match List.nth_opt frames i with
      | Some (st, _) -> List.iteri (fun k c -> worst := Float.max !worst (Float.abs (float c -. (st +. ((float k +. 1.5) *. tp))) /. tp)) f
      | None -> ()) (chunks 8 shis);
  let expect = List.mapi (fun i b -> if List.mem i stop0 then -1 - b else b) bytes in
  { rx_ok = got = expect && r.mismatches = 0; worst_sample = !worst; rx_mism = r.mismatches; rx_words = words; got; sent = expect;
    rtr = r }

(* the largest bit-time error of the peer, in steps of 0.25 %, at which every one of [runs]
   random runs is received correctly (interpreter only; the lockstep runs above cover the RTL) *)
let tolerance ~baud ~sign =
  let ok e = List.for_all (fun seed -> (rx_run ~rtl:false ~n:6 ~scale:(1. +. (sign *. e /. 100.)) ~seed ~baud ()).rx_ok)
      [ 11; 12; 13; 14 ] in
  let rec go e = if e > 15. then e else if ok e then go (e +. 0.25) else e -. 0.25 in
  go 0.25

let run () =
  pr "== Task 1: UART 8N1 at the common baud rates, 60 MHz core clock (1 slot = 4 clocks = 66.67 ns)\n";
  pr "Each edge of a transmitted frame is placed on the slot nearest its ideal time (Fw.uart_tx);\n";
  pr "the receiver samples at the slot nearest each bit's middle (Fw.uart_rx).\n\n";
  pr "%-9s %-10s | %-35s | %-24s | %-7s | %s\n" "baud" "slots/bit" "transmit" "receive" "lockstep" "words";
  pr "%-9s %-10s | %-35s | %-24s | %-7s | %s\n" "" "(ideal)" "bit (clocks) worst-edge whole-slots" "worst-sample tolerance" "mism" "tx/rx";
  let all_ok = ref true in
  List.iter (fun baud ->
      let t = bit_clocks baud in
      let s = Fw.slots_of_hz (float baud) in
      let tx = tx_run ~baud () in
      let hx, hw, hm = tx_host_run ~baud in
      let rxs = List.map (fun seed -> rx_run ~seed ~baud ()) [ 1; 2; 3 ] in
      let rx_ok = List.for_all (fun x -> x.rx_ok) rxs in
      let worst_sample = List.fold_left (fun m x -> Float.max m x.worst_sample) 0. rxs in
      let tol_lo = if rx_ok then tolerance ~baud ~sign:(-1.) else nan in
      let tol_hi = if rx_ok then tolerance ~baud ~sign:1. else nan in
      let mism = tx.mism + hm + List.fold_left (fun m x -> m + x.rx_mism) 0 rxs in
      let ok = tx.ok && hx && rx_ok in
      if not ok then all_ok := false;
      (* the error every bit would have if each were a whole number of slots, round(s) *)
      let whole = 100. *. (Float.round s -. s) /. s in
      pr "%-9d %-10.3f | %4d..%-4d %5.2f%%     %+6.2f%%     | %5.1f%%  -%.2f/+%.2f%% | %-7d | %d/%d %s\n" baud s
        tx.min_bit tx.max_bit (100. *. tx.worst_edge /. t) whole
        (100. *. worst_sample) tol_lo tol_hi mism hw (List.hd rxs).rx_words
        (if ok then "" else Printf.sprintf "FAIL (tx %s host %b rx %s)" (String.concat "," (List.map string_of_int tx.decoded)) hx
             (String.concat ";" (List.map (fun x -> String.concat "," (List.map string_of_int x.got)) rxs)))) rates;
  pr "\nColumns: bit = shortest..longest transmitted bit in clocks (ideal 60e6/baud); worst-edge = largest\n";
  pr "distance of an edge from the ideal grid, in %% of a bit (every edge of every frame, start to the\n";
  pr "next start); whole-slots = the bit-time error if every bit were round(slots/bit) slots, which\n";
  pr "the firmware avoids by placing each edge on its nearest slot (an error that accumulates over a\n";
  pr "frame: at 9.5 bits, 16 %% of a bit at 921600); worst-sample = largest distance of a receive\n";
  pr "sample from the ideal mid-bit instant,\n";
  pr "in %% of a bit, over 3 runs of 8 random bytes at random phases; tolerance = the peer's bit-time\n";
  pr "error the receiver accepts (4 runs of 6 bytes, every byte correct), short bits / long bits;\n";
  pr "mism = clocks where interpreter and RTL differ (all runs of the row; the host-fed transmitter\n";
  pr "included); words = the host-fed transmitter (the test image with five constant bytes\n";
  pr "unrolled is %d words) and the receiver.\n" (snd (Fw.uart_tx ~pin:0 ~s:130.2 (Fw.Bytes tx_bytes)));
  (* controls: each must be flagged by the checks above *)
  pr "\nControls (each must fail the check named):\n";
  let baud = 115200 in
  let t = bit_clocks baud in
  let nth_op page o n =
    let k = ref (-1) and i = ref 0 and res = ref (-1) in
    while !res < 0 do (if op page.(!i) = o then (incr k; if !k = n then res := !i)); incr i done; !res in
  let ctl name ok = pr "  %-70s %s\n" name (if ok then "CAUGHT" else "MISSED"); if not ok then all_ok := false in
  let c1 = tx_run ~baud ~mutate:(fun p -> let i = nth_op p 3 2 in p.(i) <- p.(i) - 1; p) () in
  ctl (Printf.sprintf "tx: the third bit's wait one slot short (worst edge %.1f clocks > 2)" c1.worst_edge) (c1.worst_edge > 2.0);
  let c2 = tx_run ~baud ~mutate:(fun p -> Array.map (fun w -> if op w = 7 then w lor 0x100 else w) p) () in
  ctl "tx: shifted msb first (peer decodes other bytes)" (not c2.ok);
  let c3 = rx_run ~seed:5 ~baud ~mutate:(fun p ->
      (* every receive sample half a bit late: the first wait after the start check longer by s/2 *)
      let i = nth_op p 3 0 in p.(i) <- p.(i) + int_of_float (Fw.slots_of_hz (float baud) /. 2.); p) () in
  ctl "rx: samples half a bit late (bytes received differ)" (not c3.rx_ok);
  let c4 = rx_run ~seed:6 ~baud ~stop0:[ 2 ] () in
  ctl "rx: a frame with its stop bit low is reported as a framing error (tag 1)" c4.rx_ok;
  let c5 = rx_run ~seed:7 ~baud ~scale:1.08 () in
  ctl "rx: the peer 8 % slow is not received" (not c5.rx_ok);
  let c6 = tx_run ~bug:Sequencer2.Waitd_early ~baud () in
  ctl (Printf.sprintf "lockstep: RTL mutant \"WAITD leaves at dl = 1\" under tx (%d clocks differ)" c6.mism) (c6.mism > 0);
  (* (the receiver's waits for the line all run at dl = 0, so the mutant "a wait times out at
     dl = 1" cannot show under it; the receiver's sample spacing is WAITD) *)
  let c7 = rx_run ~bug:Sequencer2.Waitd_early ~seed:8 ~baud () in
  ctl (Printf.sprintf "lockstep: RTL mutant \"WAITD leaves at dl = 1\" under rx (%d clocks differ)" c7.rx_mism) (c7.rx_mism > 0);
  ignore t;
  pr "\nUART: %s\n" (if !all_ok then "PASS" else "FAIL");
  !all_ok

(* [main.exe dump DIR]: traces for tools/sigrok-judge, at every rate: the transmitter's pin, and
   the line the receiver read with the bytes it reported *)
let dump dir =
  let ints l = String.concat "," (List.map string_of_int l) in
  List.iter (fun baud ->
      let tx = tx_run ~baud () in
      Bench.dump_trace ~dir ~stem:(Printf.sprintf "uart-tx-%d" baud) tx.tr
        [ ("judge", "uart"); ("uart_pin", "0"); ("uart_baud", string_of_int baud);
          ("uart_bit_cycles", Printf.sprintf "%.0f" (bit_clocks baud)); ("uart_bytes", ints tx_bytes) ];
      let rx = rx_run ~seed:1 ~baud () in
      Bench.dump_trace ~dir ~stem:(Printf.sprintf "uart-rx-%d" baud) rx.rtr
        [ ("judge", "uart"); ("uart_pin", "1"); ("uart_baud", string_of_int baud);
          ("uart_bit_cycles", Printf.sprintf "%.0f" (bit_clocks baud)); ("uart_bytes", ints rx.got);
          ("# the line the receiver read (from the peer transmitter); uart_bytes are the bytes the receiver reported", "") ]) rates;
  true
