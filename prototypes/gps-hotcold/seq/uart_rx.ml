(* UART receiver (8N1, lsb first) as a deadline-sequencer programme, for the GPS module's NMEA
   stream at 9600 baud. Thread 0 only; the other three threads halt.

   Clock: 65.472 MHz = 4 x 16.368 MHz, the GPS front end's sample clock in tier 2, so one bit is
   65.472e6 / 9600 = 6820 cycles = 1705 slots exactly (B below).

   Slot accounting (one instruction per slot; WAITD after LDD n occupies n+1 slots):
     0 idle:  WAITP rx=0, fail=idle      polls every slot while dl = 0 (start edge seen at slot t0)
     1        LDD a
     2        WAITD                      a+1 slots
     3        WAITP rx=0, fail=idle      mid start bit at t0+3+a: a glitch returns to idle
     4        LDC 8
     5 bit:   LDD c
     6        WAITD                      c+1 slots
     7        SHI rx, lsb first          SHI to SHI = 1 (SHI) + 1 (JNZ) + 1 (LDD) + c+1 = c+4 = B
     8        JNZ bit
     9        LDD c
    10        WAITD
    11        WAITP rx=1, fail=ferr      mid stop bit, B after the last data bit
    12        OUT                        byte to the host
    13        JMP idle                   idle again half a bit before the next start edge
    14 ferr:  WAITP rx=1, fail=ferr      framing error: wait for the line to go idle
    15        JMP idle
   with a = B/2 - 3 (mid start bit) and c = B - 4.

   Modes:
     uart_rx.exe interp FILE NBYTES PPM OUT   interpreter; transmitter baud off by PPM parts per
                                              million; received bytes to OUT
     uart_rx.exe rtl FILE NBYTES              RTL (Cyclesim) and interpreter in lockstep
     uart_rx.exe sweep FILE NBYTES            baud error sweep, interpreter *)

let f_clk = 65_472_000.0
let baud = 9600.0
let bslots = 1705
let rx_pin = 0

let program () =
  let a = bslots / 2 - 3 and c = bslots - 4 in
  let p = Array.make Isa.prog_len Isa.halt in
  let code =
    [ Isa.waitp ~pin:rx_pin ~value:0 ~fail:0; Isa.ldd a; Isa.waitd;
      Isa.waitp ~pin:rx_pin ~value:0 ~fail:0; Isa.ldc 8;
      Isa.ldd c; Isa.waitd; Isa.shi ~pin:rx_pin ~msb:0; Isa.jnz 5;
      Isa.ldd c; Isa.waitd; Isa.waitp ~pin:rx_pin ~value:1 ~fail:14; Isa.out; Isa.jmp 0;
      Isa.waitp ~pin:rx_pin ~value:1 ~fail:14; Isa.jmp 0 ] in
  List.iteri (fun i w -> p.(i) <- w) code;
  let idle = Array.make Isa.prog_len Isa.halt in
  [| p; idle; idle; idle |]

let read_bytes file n =
  let ic = open_in_bin file in
  let len = min n (in_channel_length ic) in
  let s = really_input_string ic len in
  close_in ic;
  Array.init len (fun i -> Char.code s.[i])

(* line level at cycle c: [idle_bits] of idle, then the bytes back to back (the worst case: a
   GPS module's burst), transmitter bit rate baud * (1 + ppm / 1e6), then idle *)
let line ~bytes ~ppm ~offset =
  let br = baud *. (1.0 +. ppm /. 1e6) in
  let idle_bits = 3.0 in
  let n = Array.length bytes in
  fun c ->
    let bp = (float (c - offset)) *. br /. f_clk -. idle_bits in
    if bp < 0.0 then 1
    else
      let bi = int_of_float bp in
      let k = bi / 10 and j = bi mod 10 in
      if k >= n then 1
      else if j = 0 then 0
      else if j = 9 then 1
      else (bytes.(k) lsr (j - 1)) land 1

let cycles_for ~n ~ppm = int_of_float ((float n *. 10.0 +. 6.0) *. f_clk /. (baud *. (1.0 +. ppm /. 1e6))) + 100

let run_interp ~bytes ~ppm ~offset =
  let mem = program () in
  let st = Isa.init () in
  let lv = line ~bytes ~ppm ~offset in
  let out = Buffer.create (Array.length bytes) in
  let cyc = cycles_for ~n:(Array.length bytes) ~ppm + offset in
  for c = 0 to cyc - 1 do
    let pin_in = 0xFE lor lv c in
    match (Isa.step st ~mem ~pin_in ~host_in:0 ~host_in_valid:false).host_out with
    | Some b -> Buffer.add_char out (Char.chr b)
    | None -> ()
  done;
  Buffer.contents out, cyc

let compare_bytes bytes got =
  let n = Array.length bytes and m = String.length got in
  let bad = ref 0 in
  for i = 0 to min n m - 1 do if Char.code got.[i] <> bytes.(i) then incr bad done;
  !bad + abs (n - m)

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ "interp"; file; nb; ppm; outf ] ->
    let bytes = read_bytes file (int_of_string nb) in
    let ppm = float_of_string ppm in
    let t0 = Unix.gettimeofday () in
    let got, cyc = run_interp ~bytes ~ppm ~offset:3 in
    let oc = open_out_bin outf in output_string oc got; close_out oc;
    Printf.printf "interp: %d bytes sent, %d received, %d differ; %d cycles (%.3f s at 65.472 MHz); %.1f s wall\n"
      (Array.length bytes) (String.length got) (compare_bytes bytes got) cyc (float cyc /. f_clk)
      (Unix.gettimeofday () -. t0)
  | [ "rtl"; file; nb ] ->
    let bytes = read_bytes file (int_of_string nb) in
    let mem = program () in
    let s = Harness.make mem in
    let st = Isa.init () in
    let lv = line ~bytes ~ppm:0.0 ~offset:3 in
    let cyc = cycles_for ~n:(Array.length bytes) ~ppm:0.0 + 3 in
    let mism = ref 0 and got_r = Buffer.create 64 and got_i = Buffer.create 64 in
    for c = 0 to cyc - 1 do
      let pin_in = 0xFE lor lv c in
      let e = Isa.step st ~mem ~pin_in ~host_in:0 ~host_in_valid:false in
      let o = Harness.cycle s ~pin_in ~host_in:0 ~host_in_valid:false in
      if o.host_out <> e.host_out || o.pin_out <> st.pin_out || o.pcs <> Array.to_list st.pcs then incr mism;
      (match o.host_out with Some b -> Buffer.add_char got_r (Char.chr b) | None -> ());
      (match e.host_out with Some b -> Buffer.add_char got_i (Char.chr b) | None -> ())
    done;
    Printf.printf "rtl lockstep: %d cycles, %d mismatching cycles (host_out, pins, pcs); RTL received %d bytes, %d differ from sent; interpreter %d bytes\n"
      cyc !mism (Buffer.length got_r) (compare_bytes bytes (Buffer.contents got_r)) (Buffer.length got_i);
    Printf.printf "RTL text: %S\n" (Buffer.contents got_r)
  | [ "sweep"; file; nb ] ->
    let bytes = read_bytes file (int_of_string nb) in
    Printf.printf "baud error sweep, %d bytes back to back, 4 start-phase offsets each\n" (Array.length bytes);
    Printf.printf "%8s %10s %10s\n" "ppm" "bad_bytes" "of";
    List.iter (fun ppm ->
      let bad = ref 0 in
      List.iter (fun off ->
        let got, _ = run_interp ~bytes ~ppm ~offset:off in
        bad := !bad + compare_bytes bytes got) [ 0; 1; 2; 3 ];
      Printf.printf "%8.0f %10d %10d\n%!" ppm !bad (4 * Array.length bytes))
      [ -60000.; -50000.; -45000.; -40000.; -30000.; -20000.; -10000.; 0.; 10000.; 20000.; 30000.; 40000.; 45000.; 50000.; 60000. ]
  | _ -> prerr_endline "usage: see header"; exit 2
