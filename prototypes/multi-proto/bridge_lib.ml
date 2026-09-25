(* Bridge firmware (UART receive/transmit, I2C and SPI masters executing a byte code) and the
   device models and transaction-level references they are checked against. Moved unchanged from
   bridges.ml so can_bridge.ml can reuse them. *)

let bit_slots = 16                        (* UART bit period: 64 clocks *)
let q = 6                                 (* I2C quarter period in slots *)
let h = 5                                 (* SPI half period in slots *)

(* ---------------- programmes ---------------- *)
open Asm

let wait b n = if n = 1 then emit b (W Isa.nop) else if n >= 2 then (emit b (W (Isa.ldd (n - 2))); emit b (W Isa.waitd))

(* UART receiver. Slot 0 is the poll that sees the start bit; samples at B/2 (start, glitch
   check), 3B/2 + kB (data), 19B/2 (stop). Re-arms at 19B/2 + 4 + late; the next start edge can
   come at 10B - 1, so the budget is B/2 - 5 slots and [late] NOPs spend it (the overrun control). *)
let uart_rx ?(late = 0) ~rx ~rts ~dst () =
  let b = create () in
  let bb = bit_slots in
  (match rts with Some p -> emit b (W (Isa.setp ~mask:(1 lsl p) ~value:0 ~oe:1)) | None -> ());
  label b "idle";
  origin b;
  emit b (waitp rx 0 "idle");
  label b "got";
  at b (bb / 2) (waitp rx 0 "idle");
  at b ((bb / 2) + 1) (W (Isa.ldc 8));
  pad b ((3 * bb / 2) - b.now);
  label b "bit";
  emit b (W (Isa.shi ~pin:rx ~msb:0)); emit b (W (Isa.ldd (bb - 4))); emit b (W Isa.waitd); emit b (jnz "bit");
  b.now <- (19 * bb / 2);
  label b "stopchk";
  emit b (waitp rx 1 "framing");
  for _ = 1 to late do emit b (W Isa.nop) done;
  emit b (send dst "overflow");
  (match rts with
   | Some p ->
     emit b (waitc (Isa_mb.cond_full dst) 0 "stop");
     (* RTS low again whenever there is room: without this, a byte that arrived while RTS was
        high (the late_start path) returned here with RTS still high, and a host that honours CTS
        then waited for ever. The over-budget control found it. *)
     emit b (W (Isa.setp ~mask:(1 lsl p) ~value:0 ~oe:1))
   | None -> ());
  label b "rearm";
  emit b (jmp "idle");
  (match rts with
   | Some p ->
     label b "stop";                                    (* inbox full: raise RTS, keep listening *)
     emit b (W (Isa.setp ~mask:(1 lsl p) ~value:1 ~oe:1));
     label b "rtsw";
     emit b (waitc (Isa_mb.cond_full dst) 0 "chk");
     emit b (W (Isa.setp ~mask:(1 lsl p) ~value:0 ~oe:1));
     emit b (jmp "idle");
     label b "chk";
     emit b (waitp rx 1 "late_start");
     emit b (jmp "rtsw");
     label b "late_start";                              (* the host ignored CTS *)
     emit b (jmp "got")
   | None -> ());
  label b "overflow"; emit b (W Isa.out); emit b (jmp "idle");
  label b "framing"; emit b (W (Isa.lda 0xFE)); emit b (W Isa.out); emit b (jmp "idle");
  assemble b

(* UART transmitter from its own inbox: start bit at slot 1 after the RECV, 10 bits exactly. *)
let uart_tx ~tx ~own () =
  let b = create () in
  let bb = bit_slots in
  emit b (W (Isa.setp ~mask:(1 lsl tx) ~value:1 ~oe:1));
  label b "top";
  origin b;
  emit b (recv own "top");
  at b 1 (W (Isa.setp ~mask:(1 lsl tx) ~value:0 ~oe:1));
  at b 2 (W (Isa.ldc 8));
  pad b ((1 + bb) - b.now);
  label b "bit";
  emit b (W (Isa.sho ~pin:tx ~msb:0 ())); emit b (W (Isa.ldd (bb - 4))); emit b (W Isa.waitd); emit b (jnz "bit");
  b.now <- 1 + (9 * bb);
  at b (1 + (9 * bb)) (W (Isa.setp ~mask:(1 lsl tx) ~value:1 ~oe:1));
  at b (1 + (10 * bb) - 2) (jmp "top");
  assemble b

let op_start = 0x01 and op_stop = 0x02 and op_write = 0x04 and op_read = 0x08 and op_ack = 0x10 and op_nack = 0x20
let op_csl = 0x01 and op_csh = 0x02 and op_xfer = 0x04

(* I2C master executing the byte code. Every SCL release waits for the line to be seen high
   (clock stretching), bounded by the deadline: a line held low beyond 4095 slots answers 0xFD. *)
let i2c_master ~sda ~scl ~own ~reply () =
  let b = create () in
  let m p = 1 lsl p in
  let rel p = W (Isa.setp ~mask:(m p) ~value:0 ~oe:0) and low p = W (Isa.setp ~mask:(m p) ~value:0 ~oe:1) in
  let scl_rise () = emit b (rel scl); emit b (W (Isa.ldd 4095)); emit b (waitp scl 1 "buserr") in
  emit b (W (Isa.setp ~mask:(m sda lor m scl) ~value:0 ~oe:0));
  label b "top";
  emit b (recv own "top");
  emit b (br_set 0 "start"); emit b (br_set 1 "stop"); emit b (br_set 2 "write");
  emit b (br_set 3 "read"); emit b (br_set 4 "ack"); emit b (br_set 5 "nack");
  emit b (jmp "top");
  label b "start";
  emit b (rel sda); wait b q; scl_rise (); wait b q; emit b (low sda); wait b q; emit b (low scl); wait b q; emit b (jmp "top");
  label b "stop";
  emit b (low sda); wait b q; scl_rise (); wait b q; emit b (rel sda); wait b (2 * q); emit b (jmp "top");
  label b "write";
  emit b (W (Isa.ldd 4095)); emit b (recv own "protoerr");
  emit b (W (Isa.ldc 8));
  label b "wbit";
  emit b (W (Isa.sho ~od:1 ~pin:sda ~msb:1 ())); wait b q; scl_rise (); wait b (2 * q); emit b (low scl); wait b q;
  emit b (jnz "wbit");
  emit b (rel sda); emit b (jmp "ninth");
  label b "ack"; emit b (W (Isa.lda 0)); emit b (low sda); emit b (jmp "ninth");
  label b "nack"; emit b (W (Isa.lda 0)); emit b (rel sda);
  label b "ninth";
  wait b q; scl_rise (); wait b q; emit b (W (Isa.shi ~pin:sda ~msb:1)); wait b q;
  emit b (low scl); emit b (rel sda); wait b q;
  block_send b reply; emit b (jmp "top");
  label b "read";
  emit b (rel sda); emit b (W (Isa.ldc 8));
  label b "rbit";
  wait b q; scl_rise (); wait b q; emit b (W (Isa.shi ~pin:sda ~msb:1)); wait b q; emit b (low scl);
  emit b (jnz "rbit");
  wait b q;
  block_send b reply; emit b (jmp "top");
  label b "buserr";
  emit b (W (Isa.setp ~mask:(m sda lor m scl) ~value:0 ~oe:0)); emit b (W (Isa.lda 0xFD)); block_send b reply; emit b (jmp "top");
  label b "protoerr";
  emit b (W (Isa.lda 0xFC)); block_send b reply; emit b (jmp "top");
  assemble b

(* SPI master, mode 0, msb first, with the capture option for full duplex. *)
let spi_master ~sclk ~mosi ~miso ~cs ~own ~reply () =
  let b = create () in
  let m p = 1 lsl p in
  emit b (W (Isa.setp ~mask:(m cs) ~value:1 ~oe:1));
  emit b (W (Isa.setp ~mask:(m sclk lor m mosi) ~value:0 ~oe:1));
  label b "top";
  emit b (recv own "top");
  emit b (br_set 0 "csl"); emit b (br_set 1 "csh"); emit b (br_set 2 "xfer");
  emit b (jmp "top");
  label b "csl"; emit b (W (Isa.setp ~mask:(m cs) ~value:0 ~oe:1)); wait b h; emit b (jmp "top");
  label b "csh"; wait b h; emit b (W (Isa.setp ~mask:(m cs) ~value:1 ~oe:1)); wait b h; emit b (jmp "top");
  label b "xfer";
  emit b (W (Isa.ldd 4095)); emit b (recv own "protoerr");
  emit b (W (Isa.ldc 8));
  emit b (W (Isa.sho ~pin:mosi ~msb:1 ()));             (* MOSI = bit 7 before the first rise *)
  wait b h;
  label b "xb";
  emit b (W (Isa.setp ~mask:(m sclk) ~value:1 ~oe:1)); wait b (h - 1);
  emit b (W (Isa_mb.shx ~pin:mosi ~cpin:miso ()));      (* next MOSI out, this MISO in *)
  emit b (W (Isa.setp ~mask:(m sclk) ~value:0 ~oe:1)); wait b (h - 2);
  emit b (jnz "xb");
  emit b (W (Isa.setp ~mask:(m sclk) ~value:1 ~oe:1)); wait b (h - 1);
  emit b (W (Isa.shi ~pin:miso ~msb:1));
  emit b (W (Isa.setp ~mask:(m sclk) ~value:0 ~oe:1));
  block_send b reply; emit b (jmp "top");
  label b "protoerr"; emit b (W (Isa.lda 0xFC)); block_send b reply; emit b (jmp "top");
  assemble b

(* ---------------- device models (bit level) ---------------- *)

(* I2C slave with a 256-byte register file, 7-bit address [addr]; auto-increment pointer.
   Clock stretching: after the ninth clock of every byte it holds SCL low for a random time,
   and occasionally after other falling edges. Written from the I2C specification. *)
type i2c_slave = {
  addr : int; regs : int array; rnd : Random.State.t; max_stretch : int; bit_stretch : float;
  mutable started : bool; mutable addressed : bool; mutable rw : int; mutable bitcnt : int; mutable sh : int;
  mutable first_data : bool; mutable ptr : int; mutable drive_low : bool; mutable tx_byte : int; mutable tx : bool;
  mutable hold_until : int; mutable pscl : int; mutable psda : int; mutable stretched : int;
  mutable is_addr_phase : bool;
}

let new_i2c_slave ?(max_stretch = 0) ?(bit_stretch = 0.0) ~seed addr =
  { addr; regs = Array.init 256 (fun i -> (i * 37 + 11) land 0xFF); rnd = Random.State.make [| seed |];
    max_stretch; bit_stretch; started = false; addressed = false; rw = 0; bitcnt = 0; sh = 0; first_data = false; ptr = 0;
    drive_low = false; tx_byte = 0; tx = false; hold_until = 0; pscl = 1; psda = 1; stretched = 0; is_addr_phase = true }

(* resolve and advance one cycle. m_sda_low / m_scl_low: the master is pulling the line low *)
let i2c_slave_step s ~now ~m_sda_low ~m_scl_low =
  let scl_held = now < s.hold_until in
  let scl = if m_scl_low || scl_held then 0 else 1 in
  let sda = if m_sda_low || s.drive_low then 0 else 1 in
  if scl_held then s.stretched <- s.stretched + 1;
  if s.pscl = 1 && scl = 1 && s.psda = 1 && sda = 0 then begin
    s.started <- true; s.bitcnt <- 0; s.sh <- 0; s.is_addr_phase <- true; s.tx <- false; s.drive_low <- false
  end else if s.pscl = 1 && scl = 1 && s.psda = 0 && sda = 1 then begin
    s.started <- false; s.addressed <- false; s.tx <- false; s.drive_low <- false
  end else if s.started && s.pscl = 0 && scl = 1 then begin
    (* rising edge: sample *)
    if s.bitcnt < 8 then s.sh <- ((s.sh lsl 1) lor sda) land 0xFF
    else if s.tx then (if sda = 1 then s.tx <- false);   (* master NACKed: stop transmitting *)
    s.bitcnt <- s.bitcnt + 1
  end else if s.started && s.pscl = 1 && scl = 0 then begin
    (* falling edge: drive *)
    if s.bitcnt = 8 then begin
      if s.is_addr_phase then begin
        if s.sh lsr 1 = s.addr then (s.addressed <- true; s.rw <- s.sh land 1; s.first_data <- true; s.drive_low <- true)
        else (s.addressed <- false; s.drive_low <- false)
      end else if s.addressed && s.rw = 0 then begin
        if s.first_data then (s.ptr <- s.sh; s.first_data <- false) else (s.regs.(s.ptr) <- s.sh; s.ptr <- (s.ptr + 1) land 0xFF);
        s.drive_low <- true
      end else s.drive_low <- false                     (* transmitting: release for the master's ACK *)
    end else if s.bitcnt = 9 then begin
      s.drive_low <- false; s.bitcnt <- 0; s.sh <- 0;
      let was_addr = s.is_addr_phase in
      s.is_addr_phase <- false;
      if s.addressed && s.rw = 1 && (was_addr || s.tx) then begin
        s.tx <- true; s.tx_byte <- s.regs.(s.ptr); s.ptr <- (s.ptr + 1) land 0xFF;
        s.drive_low <- s.tx_byte land 0x80 = 0
      end else s.tx <- false;
      if s.max_stretch > 0 then s.hold_until <- now + Random.State.int s.rnd (s.max_stretch + 1)
    end else begin
      if s.tx && s.bitcnt < 8 then s.drive_low <- (s.tx_byte lsr (7 - s.bitcnt)) land 1 = 0;
      if s.bit_stretch > 0.0 && Random.State.float s.rnd 1.0 < s.bit_stretch then s.hold_until <- now + Random.State.int s.rnd 200
    end
  end;
  s.pscl <- scl; s.psda <- sda;
  (sda, scl)

(* SPI memory, mode 0: 0x02 WRITE addr data.., 0x03 READ addr -> data.., 0x05 RDSR -> 0x5A.
   MISO changes on SCLK falling edges (and at CS falling for the first bit). *)
type spi_dev = {
  mem : int array; mutable active : bool; mutable nbits : int; mutable inb : int; mutable idx : int;
  mutable cmd : int; mutable a : int; mutable outb : int; mutable miso : int; mutable psclk : int; mutable pcs : int;
}
let new_spi_dev () = { mem = Array.init 256 (fun i -> (i * 91 + 7) land 0xFF); active = false; nbits = 0; inb = 0; idx = 0;
                       cmd = 0; a = 0; outb = 0xFF; miso = 1; psclk = 0; pcs = 1 }
let spi_out d = if d.idx >= 1 && d.cmd = 0x05 then 0x5A
  else if d.idx >= 2 && d.cmd = 0x03 then d.mem.((d.a + d.idx - 2) land 0xFF) else 0xFF
let spi_dev_step d ~sclk ~mosi ~cs =
  if d.pcs = 1 && cs = 0 then begin d.active <- true; d.nbits <- 0; d.idx <- 0; d.cmd <- 0; d.inb <- 0; d.outb <- spi_out d; d.miso <- (d.outb lsr 7) land 1 end;
  if cs = 1 then d.active <- false;
  if d.active && d.psclk = 0 && sclk = 1 then begin
    d.inb <- ((d.inb lsl 1) lor mosi) land 0xFF; d.nbits <- d.nbits + 1;
    if d.nbits = 8 then begin
      (match d.idx with
       | 0 -> d.cmd <- d.inb
       | 1 -> d.a <- d.inb
       | i -> if d.cmd = 0x02 then d.mem.((d.a + i - 2) land 0xFF) <- d.inb);
      d.idx <- d.idx + 1; d.nbits <- 0
    end
  end;
  if d.active && d.psclk = 1 && sclk = 0 then begin
    if d.nbits = 0 then d.outb <- spi_out d;
    d.miso <- (d.outb lsr (7 - d.nbits)) land 1
  end;
  d.psclk <- sclk; d.pcs <- cs;
  d.miso

(* ---------------- transaction-level references ---------------- *)

type i2c_tx = Wr of int * int * int list | Rd of int * int * int

let i2c_ops txs =
  List.concat_map (function
    | Wr (a, r, ds) -> [ op_start; op_write; a lsl 1; op_write; r ] @ List.concat_map (fun d -> [ op_write; d ]) ds @ [ op_stop ]
    | Rd (a, r, n) ->
      [ op_start; op_write; a lsl 1; op_write; r; op_start; op_write; (a lsl 1) lor 1 ]
      @ List.concat (List.init n (fun i -> [ op_read; (if i = n - 1 then op_nack else op_ack) ])) @ [ op_stop ]) txs

(* answers, the bytes on the bus with their acknowledge (as an I2C decoder reports them), and the
   final register file, from the transactions alone *)
let i2c_reference ~addr txs =
  let regs = Array.init 256 (fun i -> (i * 37 + 11) land 0xFF) in
  let ptr = ref 0 in
  let ans = ref [] and bus = ref [] in
  let say x = ans := x :: !ans and on_bus b a = bus := (b, a) :: !bus in
  List.iter (function
    | Wr (a, r, ds) ->
      let ok = a = addr in
      let ak = if ok then 0 else 1 in
      say ak; say ak; on_bus (a lsl 1) ok; on_bus r ok;
      if ok then ptr := r;
      List.iter (fun d -> say ak; on_bus d ok; if ok then (regs.(!ptr) <- d; ptr := (!ptr + 1) land 0xFF)) ds
    | Rd (a, r, n) ->
      let ok = a = addr in
      let ak = if ok then 0 else 1 in
      say ak; say ak; on_bus (a lsl 1) ok; on_bus r ok; if ok then ptr := r;
      say ak; on_bus ((a lsl 1) lor 1) ok;
      for i = 0 to n - 1 do
        let v = if ok then (let v = regs.(!ptr) in ptr := (!ptr + 1) land 0xFF; v) else 0xFF in
        say v; on_bus v (i < n - 1);
        say (if i = n - 1 then 1 else 0)
      done) txs;
  List.rev !ans, List.rev !bus, regs

type spi_tx = Sw of int * int list | Sr of int * int | Ss

let spi_ops txs =
  let x b = [ op_xfer; b ] in
  List.concat_map (function
    | Sw (a, ds) -> [ op_csl ] @ x 0x02 @ x a @ List.concat_map x ds @ [ op_csh ]
    | Sr (a, n) -> [ op_csl ] @ x 0x03 @ x a @ List.concat (List.init n (fun _ -> x 0)) @ [ op_csh ]
    | Ss -> [ op_csl ] @ x 0x05 @ x 0 @ [ op_csh ]) txs

let spi_reference txs =
  let mem = Array.init 256 (fun i -> (i * 91 + 7) land 0xFF) in
  let ans = ref [] in
  let say x = ans := x :: !ans in
  List.iter (function
    | Sw (a, ds) -> say 0xFF; say 0xFF; List.iteri (fun i d -> say 0xFF; mem.((a + i) land 0xFF) <- d) ds
    | Sr (a, n) -> say 0xFF; say 0xFF; for i = 0 to n - 1 do say mem.((a + i) land 0xFF) done
    | Ss -> say 0xFF; say 0x5A) txs;
  List.rev !ans, mem

