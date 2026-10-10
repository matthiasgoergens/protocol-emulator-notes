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

(* ------------------------------------------------------------------------------------------ *)
(* I2C controller, driven by the host: START, repeated START, STOP, write, read with ACK or NACK,
   clock stretching; Standard-mode and Fast-mode timing

   Both lines are open drain: drive low with SETP oe=1 value=0, release with oe=0.

   The programme is a fixed command loop, so its size does not grow with the transaction: the
   host sends commands (IN) and reads results (OUT):
     'S' (0x53) START, or a repeated START if the bus is ours; 'P' (0x50) STOP;
     'W' (0x57) then a data byte: write it, report the target's ACK (OUT tag 1: 0 ACK, 1 NACK);
     'R' (0x52) read a byte and ACK it; 'N' (0x4E) read a byte and NACK it (the last of a read);
       the byte goes to the host with tag 0.
   After a STOP the controller reports tag 3; when a target holds SCL low past the stretch limit
   it releases both lines, reports tag 2 and returns to the idle bus. Other commands are ignored.

   Schedule, in slots. One SCL clock ("pulse") from the slot a at which the controller drives SCL
   low:
     a              SETP scl low
     a + hd_dat     the SDA action of the bit: SHO od (write, msb first), release (read, ACK
                    clock of a write, repeated START), drive low (ACK of a read, STOP)
     a + low - 1    LDD [stretch limit]
     a + low        SCL released
     s              WAITP scl = 1 sees SCL high (s >= a + low + 1; later while a target
                    stretches the clock or the line rises slowly)
     s + smp        a read bit: SHI sda; a write's ACK: WAITP sda = 0 at dl = 0 (ACK proceeds,
                    NACK branches), then OUT tag 1 (0 ACK, 1 NACK) at s + smp + 1
     s + high       within a byte: SCL low again (JNZ at s + high - 1)
   so SCL is low for [low] slots as driven, and SDA changes exactly hd_dat slots after SCL is
   driven low, in every pulse; SCL is high for at least [high] slots from the slot it is seen
   high: the rise time and any stretching are never taken from it.
   Commands are fetched in a high phase: after a byte's ACK clock (once its ACK is sampled, or
   its OUT done), after a START or repeated START's SDA fall. From the JMP to the fetch, the next
   SCL low comes 6 slots later for a write or a read with ACK, 7 for a read with NACK or a
   repeated START, 8 for a STOP (the JMP, IN, the SKNE chain, the JMP to the command, IN and LDC);
   the wait before the JMP makes the fastest of them reach SCL low at s + high (or hd_sta after
   the START's SDA fall). So a later command, or a host that has no command ready, makes the high
   phase (or tHD;STA) longer, which the specification allows: it sets no maximum there.
     START (idle bus):  SDA low; the first command's SCL low at least hd_sta later.
     repeated START:    a pulse releasing SDA; SDA low at s + su_sta; SCL low >= hd_sta later.
     STOP:              a pulse driving SDA low; SDA released at s + su_sto; OUT tag 3; the
                        next START comes at least [buf] slots after the release.
     read:              8 pulses releasing SDA and sampling it, then the ACK clock with SDA
                        driven low (R) or released (N); OUT tag 0 of the byte at s + 1 of it. *)

type i2c_timing = {
  low : int; high : int;       (* SCL low as driven; SCL high from the slot it is seen high *)
  hd_dat : int;                (* SDA changes this long after SCL is driven low *)
  hd_sta : int;                (* START / repeated START: SDA low to SCL low *)
  su_sta : int;                (* repeated START: SCL seen high to SDA low *)
  su_sto : int;                (* STOP: SCL seen high to SDA released *)
  buf : int;                   (* STOP to the next START, at the least *)
  smp : int;                   (* a read bit or an ACK sampled this long after SCL is seen high *)
}

(* The limits of the I2C specification (NXP UM10204, rev. 7.0, table 10), in ns. *)
type i2c_limits = {
  name : string; f_max_hz : float; t_low : float; t_high : float; t_hd_sta : float; t_su_sta : float;
  t_su_dat : float; t_hd_dat : float; t_su_sto : float; t_buf : float; t_vd_dat : float; t_vd_ack : float;
  t_r : float; t_f : float;
}

let standard_mode = { name = "Standard-mode"; f_max_hz = 100e3; t_low = 4700.; t_high = 4000.; t_hd_sta = 4000.;
                      t_su_sta = 4700.; t_su_dat = 250.; t_hd_dat = 0.; t_su_sto = 4000.; t_buf = 4700.;
                      t_vd_dat = 3450.; t_vd_ack = 3450.; t_r = 1000.; t_f = 300. }
let fast_mode = { name = "Fast-mode"; f_max_hz = 400e3; t_low = 1300.; t_high = 600.; t_hd_sta = 600.;
                  t_su_sta = 600.; t_su_dat = 100.; t_hd_dat = 0.; t_su_sto = 600.; t_buf = 1300.;
                  t_vd_dat = 900.; t_vd_ack = 900.; t_r = 300.; t_f = 300. }

(* The slot counts, from the limits at 66.67 ns a slot. Where a phase starts at a falling edge
   the controller makes and ends at a rising one (tLOW, tHD;STA, tBUF) the count adds the largest
   fall time (300 ns) and a slot; SDA changes 5 slots (333 ns) after SCL is driven low, more than
   the largest fall time, so it never changes while SCL may still be falling. Phases counted from
   SCL seen high (tHIGH, tSU;STA, tSU;STO) need no margin for the rise.
   Standard: SCL 76 low + 74 high + at least 1 slot to see the rise = 151 slots, 99.3 kHz at the
   most. Fast: 25 + 12 + 1 = 38 slots, 394.7 kHz at the most. *)
let standard_timing = { low = 76; high = 74; hd_dat = 5; hd_sta = 66; su_sta = 71; su_sto = 61; buf = 86; smp = 37 }
let fast_timing = { low = 25; high = 12; hd_dat = 5; hd_sta = 15; su_sta = 10; su_sto = 10; buf = 25; smp = 6 }

let cmd_start = 0x53 and cmd_stop = 0x50 and cmd_write = 0x57 and cmd_read_ack = 0x52 and cmd_read_nack = 0x4E

type i2c_op =
  | Start                      (* START, or a repeated START when the bus is ours *)
  | Write of int list          (* bytes, each acknowledged by the target *)
  | Read of int                (* n bytes, ACK for all but the last, NACK for the last *)
  | Stop

(* the host's command bytes for a list of operations *)
let i2c_commands ops =
  List.concat_map (function
      | Start -> [ cmd_start ] | Stop -> [ cmd_stop ]
      | Write l -> List.concat_map (fun b -> [ cmd_write; b ]) l
      | Read n -> List.init n (fun i -> if i = n - 1 then cmd_read_nack else cmd_read_ack)) ops

(* [fault] is for the controls only *)
type i2c_fault = Ack_in_low_phase | No_stretch_wait

let i2c_ctl ?fault ?(stretch_limit = 4095) ~sda ~scl ~(timing : i2c_timing) () =
  let t = timing in
  if t.smp < 3 || t.high - t.smp < 2 || t.low - t.hd_dat < 3 || t.hd_dat < 2 || t.su_sta < 2 || t.hd_sta < 7
     || t.su_sto < 1 || t.buf < 4 || stretch_limit < 1 then invalid_arg "i2c_ctl: timing too tight";
  let scl_up =
    [ W (Isa2.ldd stretch_limit); release scl ]
    @ (if fault = Some No_stretch_wait then [] else [ Waitp { pin = scl; value = 1; fail = "timeout" } ]) in
  (* a pulse up to SCL seen high: SCL low at a, [action] at a + hd_dat, SCL released at a + low *)
  let pulse action = [ drive_low scl; Wait (t.hd_dat - 1); action; Wait (t.low - t.hd_dat - 2) ] @ scl_up in
  (* the end of a high phase whose slots s + 1 .. s + used are taken: the command fetch, timed
     so that the fastest command (write, or read with ACK) drives SCL low at s + high: the JMP is
     at s + used + w + 1 and that SCL low 6 slots after it *)
  let to_fetch ~used = [ Wait (max 0 (t.high - used - 7)); Jmp "fetch" ] in
  let items =
    [ setp ~pins:(bit sda lor bit scl) ~value:0 ~oe:0;
      (* idle bus: wait for 'S' *)
      Label "idle"; W Isa2.in_; W (Isa2.skne cmd_start); Jmp "start"; Jmp "idle";
      Label "start"; drive_low sda; Wait (t.hd_sta - 7); Jmp "fetch";
      (* the next command, with SCL high (or, after a START, SDA just pulled low) *)
      Label "fetch"; W Isa2.in_;
      W (Isa2.skne cmd_write); Jmp "write"; W (Isa2.skne cmd_read_ack); Jmp "read_ack";
      W (Isa2.skne cmd_read_nack); Jmp "read_nack"; W (Isa2.skne cmd_start); Jmp "restart";
      W (Isa2.skne cmd_stop); Jmp "stop"; Jmp "fetch";
      (* write: the data byte, eight bits, the target's ACK *)
      Label "write"; W Isa2.in_; W (Isa2.ldc 8);
      Label "wbit" ] @ pulse (W (Isa2.sho ~od:1 ~pin:sda ~msb:1 ())) @ [ Wait (t.high - 2); Jnz "wbit" ]
    @ (if fault = Some Ack_in_low_phase then
         (* the control: the ACK read 3 slots after SDA is released, while SCL is still low *)
         [ drive_low scl; Wait (t.hd_dat - 1); release sda; Wait 2; Waitp { pin = sda; value = 0; fail = "nack" };
           Wait (t.low - t.hd_dat - 6) ] @ scl_up @ [ Wait t.smp; W (Isa2.outi ~tag:1 0) ]
       else
         pulse (release sda) @ [ Wait (t.smp - 1); Waitp { pin = sda; value = 0; fail = "nack" }; W (Isa2.outi ~tag:1 0) ])
    @ to_fetch ~used:(t.smp + 1)
    @ [ Label "nack"; W (Isa2.outi ~tag:1 1) ] @ to_fetch ~used:(t.smp + 1)
    (* read with ACK and read with NACK: the same eight bits, then the ACK clock *)
    @ List.concat_map (fun (name, ack) ->
        [ Label name; W (Isa2.ldc 8); Label (name ^ "_bit") ] @ pulse (release sda)
        @ [ Wait (t.smp - 1); W (Isa2.shi ~pin:sda ~msb:1 ()); Wait (t.high - t.smp - 2); Jnz (name ^ "_bit") ]
        @ pulse ack @ [ W (Isa2.out ~tag:0 ()) ] @ to_fetch ~used:1)
      [ ("read_ack", drive_low sda); ("read_nack", release sda) ]
    (* repeated START *)
    @ [ Label "restart" ] @ pulse (release sda)
    @ [ Wait (t.su_sta - 1); drive_low sda; Wait (t.hd_sta - 7); Jmp "fetch" ]
    (* STOP *)
    @ [ Label "stop" ] @ pulse (drive_low sda)
    @ [ Wait (t.su_sto - 1); release sda; W (Isa2.outi ~tag:3 0); Wait (t.buf - 3); Jmp "idle" ]
    (* a target held SCL past the stretch limit *)
    @ [ Label "timeout"; setp ~pins:(bit sda lor bit scl) ~value:0 ~oe:0; W (Isa2.outi ~tag:2 0); Jmp "idle" ] in
  assemble items
