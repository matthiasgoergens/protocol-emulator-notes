(* Firmware generators for ISA v2: UART transmit and receive at any baud rate, SPI controller in
   modes 0-3, I2C controller at Standard and Fast mode, I2C target and SPI target.

   Each generator returns the thread's 256-word page (Asm.assemble, which fails if it does not
   fit) and the number of words used. Times are in slots: one instruction of one thread, four
   clocks, 66.67 ns at the chip's 60 MHz. Every timing below is stated as the slot on which an
   instruction issues, counted from a named event; one word is one slot except where a wait is
   named. [Wait n] is exactly n slots (Asm). *)

open Asm

let clock_hz = 60_000_000.
let slot_clocks = 4
let slot_ns = 1e9 /. clock_hz *. float slot_clocks
let slots_of_hz hz = clock_hz /. float slot_clocks /. hz      (* slots per period, fractional *)

let bit p = 1 lsl p
let setp ~pins ~value ~oe = W (Isa2.setp ~mask:pins ~value ~oe ())
let drive p v = setp ~pins:(bit p) ~value:v ~oe:1
let release p = setp ~pins:(bit p) ~value:0 ~oe:0
let drive_low p = drive p 0

(* ------------------------------------------------------------------------------------------ *)
(* UART, 8N1, lsb first

   Bit times are not whole slots at most baud rates (115200 baud is 130.21 slots), so the
   firmware places each edge of a frame on the slot nearest to the ideal one: edge k (0 the start
   bit's, 1..8 the data bits', 9 the stop bit's, 10 the next start) is at slot round(k s) after
   the start edge, s = 15e6 / baud. Every edge is then within half a slot (2 clocks) of its ideal
   position, and the frame has no accumulated error; a single bit lasts floor(s) or ceil(s)
   slots. With a whole s every bit is exactly s. *)

let grid s k = int_of_float (Float.round (float k *. s))

type uart_src = Bytes of int list | From_host

(* Transmit on [pin]. Bytes [Bytes l] are sent and the thread halts with the line idle;
   [From_host] sends each byte the host supplies (IN), for ever.

   Slots, from the start edge of a frame (SETP tx=0) at slot 0:
     data bit j (SHO, lsb first) at grid j, stop bit (SETP tx=1) at grid 9;
     the next frame's start edge at grid 10 when the next byte is ready: Bytes: the stop bit is
     followed by Wait (grid 10 - grid 9 - 2) and LDA; From_host: by Wait (... - 3), JMP and IN,
     which waits for the host (the stop bit then lasts longer, which UART allows).
   Before the first frame, the line is set high (idle) at slot 0 of the thread. *)
let uart_tx ~pin ~s src =
  let g = grid s in
  let len k = g (k + 1) - g k in
  if s < 3. then invalid_arg "uart_tx: needs at least 3 slots a bit";
  let frame load stop_tail =
    [ load; drive pin 0; Wait (len 0 - 1) ]
    @ List.concat (List.init 8 (fun j -> [ W (Isa2.sho ~pin ~msb:0 ()); Wait (len (j + 1) - 1) ]))
    @ [ drive pin 1 ] @ stop_tail in
  let items =
    [ drive pin 1 ]
    @ (match src with
        | Bytes l ->
          List.concat (List.mapi (fun i b ->
              let last = i = List.length l - 1 in
              frame (W (Isa2.lda b)) (if last then [ Halt ] else [ Wait (len 9 - 2) ])) l)
        | From_host -> [ Label "next" ] @ frame (W Isa2.in_) [ Wait (len 9 - 3); Jmp "next" ]) in
  assemble items

(* Receive on [pin]; each byte goes to the host (OUT tag 0), a frame whose stop bit reads 0 goes
   with tag 1 (framing error) and the receiver then waits for the line to go idle.

   Start detection: WAITP rx=0 with its fail target itself and dl = 0 polls the line once a slot
   (it branches to itself while the line is high). Let d be the slot in which it sees 0. The
   falling edge happened in the slot before, on average half a slot earlier, so sample k
   (0: the start bit again, 1..8: data, 9: stop) is taken at slot d + m k with
   m k = round((k + 1/2) s - 1/2): the middle of the bit for an edge half a slot before d.
     slot d + m 0   WAITP rx=0, dl = 0: still low, else a glitch: back to the start wait
     slot d + m k   SHI lsb (k = 1..8)
     slot d + m 9   WAITP rx=1, dl = 0: the stop bit; if low, a framing error
     then OUT (d + m 9 + 1), JMP (+2), and the start wait again from d + m 9 + 3.
   The next start edge comes 10 s after this one at the earliest, and is first seen on slot
   d + 10 s or later (the edge falls in the slot before its detection); the wait is there in time
   when m 9 + 3 <= 10 s, i.e. 9.5 s + 2.5 <= 10 s: s >= 5 slots a bit, 3 Mbaud. *)
let uart_rx_m ~s k = int_of_float (Float.round ((float k +. 0.5) *. s -. 0.5))

let uart_rx ~pin ~s () =
  let m = uart_rx_m ~s in
  if m 0 < 1 then invalid_arg "uart_rx: bit too short";
  let items =
    [ Label "idle"; Waitp { pin; value = 1; fail = "idle" };     (* the line must be idle first *)
      Label "wait"; Waitp { pin; value = 0; fail = "wait" };     (* slot d *)
      Wait (m 0 - 1); Waitp { pin; value = 0; fail = "wait" } ]
    @ List.concat (List.init 8 (fun j -> [ Wait (m (j + 1) - m j - 1); W (Isa2.shi ~pin ~msb:0 ()) ]))
    @ [ Wait (m 9 - m 8 - 1); Waitp { pin; value = 1; fail = "ferr" };
        W (Isa2.out ~tag:0 ()); Jmp "wait";
        Label "ferr"; W (Isa2.out ~tag:1 ()); Jmp "idle" ] in
  assemble items

(* ------------------------------------------------------------------------------------------ *)
(* SPI controller, modes 0-3, msb or lsb first, full duplex

   Mode = (CPOL, CPHA). SCLK idles at CPOL; the leading edge of a bit leaves the idle level, the
   trailing edge returns to it. CPHA 0: data is sampled on the leading edge and changed after the
   trailing one (the first bit is set before the first leading edge); CPHA 1: changed after the
   leading edge, sampled on the trailing one.

   Full duplex with one accumulator. The bit going out and the bit coming in cannot share a
   shift (SHO with capture would sample MISO at the moment MOSI changes, i.e. on the shift edge,
   not on the sampling edge). So MOSI is written without shifting, by a branch on the outgoing
   accumulator bit (WAITC on acc bit 7, or bit 0 lsb first, at dl = 0, then SETP mosi = 1 or 0,
   both paths three slots), and MISO is sampled by SHI one slot after the sampling edge, which
   shifts the accumulator by one: the bit just sent leaves at the top (msb first) and the bit
   received enters at the bottom. After eight bits the accumulator is the received byte.

   Schedule of one bit, [act] slots SCLK active and [idl] slots idle (period act + idl):
   CPHA 0, from the slot B of the WAITC:
     B+1 MOSI written; B+3+w1 leading edge L (w1 = idl - 5); L+1 SHI (sample);
     L+act trailing edge T (w2 = act - 2 slots after the SHI); T+1 JNZ; T+2 the next WAITC.
     So MOSI changes 3 slots after the trailing edge, idl - 3 slots before the next leading edge.
   CPHA 1, from the leading edge L:
     L+1 WAITC; L+2 MOSI written; L+act trailing edge T (w2 = act - 4); T+1 SHI (sample);
     T+2+w1 JNZ (w1 = idl - 3); T+idl the next leading edge.
     So MOSI changes 2 slots after the leading edge, act - 2 slots before the trailing edge.
   CPHA 0 needs idl >= 5 and act >= 2, CPHA 1 act >= 4 and idl >= 3: a period of at least 10
   slots (1.5 MHz at 60 MHz) for mode 0 and 2 with the duty kept at half, 8 (1.875 MHz) for 1 and 3.

   A transaction: SETP cs=1, sclk=CPOL, mosi=0 (slots 0..2), Wait [idl], CS low at slot c; per
   byte LDA, LDC 8, the eight bits, OUT of the received byte (with [tag], 0 by default).
   CPHA 0: the first MOSI write at c+4, the first leading edge at c+idl+1. CPHA 1: a Wait after the
   first LDA/LDC so that the first leading edge is at c+idl. Between bytes SCLK idles 3 slots
   longer than [idl] (OUT, LDA, LDC). CS rises [idl] slots after the last trailing edge (CPHA 0)
   or after the last sample, one slot after that edge (CPHA 1). Then the thread halts.

   [fault] is for the controls only: [Sample_on_shift_edge] samples one slot after the other
   edge (the wrong one), [No_branch_balance] makes the MOSI = 0 path one slot shorter. *)
type spi_mode = { cpol : int; cpha : int; msb : bool }
type spi_fault = Sample_on_shift_edge | No_branch_balance

let spi_mode_name m = Printf.sprintf "mode %d %s" (2 * m.cpol + m.cpha) (if m.msb then "msb" else "lsb")

let spi_ctl ?fault ?(tag = 0) ~sclk ~mosi ~miso ~cs ~mode ~period bytes =
  let act = period / 2 in
  let idl = period - act in
  let active = 1 - mode.cpol in
  let accbit = if mode.msb then 7 else 0 in
  if mode.cpha = 0 && (idl < 5 || act < 2) then invalid_arg "spi_ctl: CPHA 0 needs a period of at least 10 slots";
  if mode.cpha = 1 && (act < 4 || idl < 3) then invalid_arg "spi_ctl: CPHA 1 needs a period of at least 8 slots";
  let n = ref 0 in
  let lbl s = incr n; Printf.sprintf "%s%d" s !n in
  (* MOSI <- the outgoing accumulator bit, three slots, the write in the second *)
  let mosi_out () =
    let z = lbl "z" and j = lbl "j" in
    [ Waitc { cond = Isa2.c_acc accbit; fail = z }; drive mosi 1; Jmp j;
      Label z; drive mosi 0 ] @ (if fault = Some No_branch_balance then [] else [ W Isa2.nop ]) @ [ Label j ] in
  let sample = W (Isa2.shi ~pin:miso ~msb:(if mode.msb then 1 else 0) ()) in
  let lead = drive sclk active and trail = drive sclk mode.cpol in
  let bit_loop () =
    let b = lbl "bit" in
    let wrong = fault = Some Sample_on_shift_edge in
    match mode.cpha, wrong with
    | 0, false -> [ Label b ] @ mosi_out () @ [ Wait (idl - 5); lead; sample; Wait (act - 2); trail; Jnz b ]
    | 0, true -> [ Label b ] @ mosi_out () @ [ Wait (idl - 5); lead; Wait (act - 1); trail; sample; Jnz b ]
    | _, false -> [ Label b; lead ] @ mosi_out () @ [ Wait (act - 4); trail; sample; Wait (idl - 3); Jnz b ]
    | _, true -> [ Label b; lead; sample ] @ mosi_out () @ [ Wait (act - 5); trail; Wait (idl - 2); Jnz b ] in
  let items =
    [ setp ~pins:(bit cs) ~value:1 ~oe:1; setp ~pins:(bit sclk) ~value:mode.cpol ~oe:1;
      setp ~pins:(bit mosi) ~value:0 ~oe:1; Wait idl; drive cs 0 ]
    @ List.concat (List.mapi (fun i b ->
        [ W (Isa2.lda b); W (Isa2.ldc 8) ]
        @ (if mode.cpha = 1 && i = 0 then [ Wait (idl - 3) ] else [])
        @ bit_loop () @ [ W (Isa2.out ~tag ()) ]) bytes)
    @ [ Wait (if mode.cpha = 0 then idl - 3 else 0); drive cs 1; Halt ] in
  assemble items
