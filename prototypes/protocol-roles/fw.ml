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
