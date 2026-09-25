(* Protocol bridges on the mailbox variant, run cycle by cycle on the interpreter and the RTL in
   lockstep, against independent models of both sides.

   Bridge A, UART <-> I2C master (a UART command interface to an I2C sensor):
     T0 UART receiver (pin 0) -> inbox 1; RTS (pin 2) is raised when inbox 1 is full.
     T1 I2C master (SDA pin 3, SCL pin 4, open drain, clock stretching honoured everywhere),
        executing a byte code from the UART: START, STOP, WRITE b, READ, ACK, NACK.
        Every op but START/STOP answers one byte (the acknowledge bit, or the byte read) -> inbox 2.
     T2 UART transmitter (pin 1) from inbox 2.
     T3 unrelated: an SPI master loop on pins 5..7.
   Bridge B, UART <-> SPI master:
     T0 as above (no RTS: no pin left), T1 SPI master mode 0 (SCLK 2, MOSI 3, MISO 4, CS 5) with
        ops CS_LOW, CS_HIGH, XFER b (answers the MISO byte), T2 as above,
     T3 unrelated: an I2C master write loop on pins 6, 7 with its own slave.

   The host side is a UART model that honours CTS at each byte start (or, in a control, ignores
   it), with random gaps and a baud error; its receiver is Decoders.uart on our TX pin. The device
   side is a bit-level I2C slave with random clock stretching, or a bit-level SPI memory. The
   expected answers come from separate transaction-level reference models of the devices. *)

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

(* ---------------- the host's UART ---------------- *)
type host = {
  bytes : int array; mutable next : int; mutable t_next : float; mutable cur : int; mutable bitn : int;
  period : float; gap_bits : int; respect_cts : bool; rnd : Random.State.t; mutable cts_waits : int;
}

let new_host ~seed ~bytes ~err ~gap_bits ~respect_cts =
  { bytes = Array.of_list bytes; next = 0; t_next = 200.0; cur = 0; bitn = -1; period = float (4 * bit_slots) *. (1.0 +. err);
    gap_bits; respect_cts; rnd = Random.State.make [| seed |]; cts_waits = 0 }

(* level on the host's TX at clock n; [cts] = our RTS pin level (0 = send) *)
let host_level hs ~now ~cts =
  let t = float now in
  if hs.bitn < 0 then begin
    if hs.next < Array.length hs.bytes && t >= hs.t_next then begin
      if hs.respect_cts && cts = 1 then (hs.cts_waits <- hs.cts_waits + 1; 1)
      else begin hs.cur <- hs.bytes.(hs.next); hs.next <- hs.next + 1; hs.bitn <- 0; hs.t_next <- t; 0 end
    end else 1
  end else begin
    let k = int_of_float ((t -. hs.t_next) /. hs.period) in
    if k >= 10 then begin
      hs.bitn <- -1;
      hs.t_next <- hs.t_next +. (10.0 +. float (Random.State.int hs.rnd (hs.gap_bits + 1))) *. hs.period;
      1
    end else if k = 0 then 0 else if k <= 8 then (hs.cur lsr (k - 1)) land 1 else 1
  end

(* ---------------- running a bridge ---------------- *)
type which = A | B
type neigh = Compiled | Rand of int | Off

type cfg = {
  which : which; seed : int; ntx : int; rtl : bool; neigh : neigh; fault : Isa_mb.fault; late : int;
  respect_cts : bool; err : float; gap_bits : int; max_stretch : int; bridge : bool; depth : int;
}

let base = { which = A; seed = 1; ntx = 12; rtl = true; neigh = Compiled; fault = Isa_mb.No_fault; late = 0;
             respect_cts = true; err = 0.01; gap_bits = 2; max_stretch = 400; bridge = true; depth = 2 }

type outcome = {
  answers : int list; expected : int list; regs_ok : bool; bus_ok : bool; mism : int; reports : (int * int) list;
  bridge_hash : int; neigh_hash : int; cycles : int; rts_cycles : int; max_fill : int; stretched : int;
  min_slack : int; neigh_ok : bool; n_ops : int; cts_waits : int; ntr : int array; swapped : (int * int) option;
}

(* two neighbour traces agree on their common prefix (runs end at different times) *)
let same_prefix a b = let n = min (Array.length a) (Array.length b) in n > 50_000 && Array.sub a 0 n = Array.sub b 0 n

let random_i2c rnd n ~addr =
  List.init n (fun _ ->
    let a = if Random.State.int rnd 10 = 0 then 0x21 else addr in
    if Random.State.bool rnd then Wr (a, Random.State.int rnd 256, List.init (1 + Random.State.int rnd 4) (fun _ -> Random.State.int rnd 256))
    else Rd (a, Random.State.int rnd 256, 1 + Random.State.int rnd 3))

let random_spi rnd n =
  List.init n (fun _ -> match Random.State.int rnd 5 with
    | 0 | 1 -> Sw (Random.State.int rnd 256, List.init (1 + Random.State.int rnd 4) (fun _ -> Random.State.int rnd 256))
    | 2 | 3 -> Sr (Random.State.int rnd 256, 1 + Random.State.int rnd 4)
    | _ -> Ss)

let run (c : cfg) =
  let ic = Isa_mb.cfg ~pc_bits:7 ~depth:c.depth ~fault:c.fault () in
  let halt = Array.make 128 Isa.halt in
  let rnd = Random.State.make [| c.seed |] in
  let dev_addr = 0x48 in
  let rx = 0 and tx = 1 in
  let (t0, _, l0), (t1, _, _), (t2, _, _) =
    match c.which with
    | A -> uart_rx ~late:c.late ~rx ~rts:(Some 2) ~dst:1 (), i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 (), uart_tx ~tx ~own:2 ()
    | B -> uart_rx ~late:c.late ~rx ~rts:None ~dst:1 (), spi_master ~sclk:2 ~mosi:3 ~miso:4 ~cs:5 ~own:1 ~reply:2 (), uart_tx ~tx ~own:2 () in
  let rearm_pc = Hashtbl.find l0 "rearm" and stopchk_pc = Hashtbl.find l0 "stopchk" in
  let t0, t1, t2 = if c.bridge then t0, t1, t2 else halt, halt, halt in
  let neigh_pins = match c.which with A -> 0xE0 | B -> 0xC0 in
  let t3 = match c.neigh with
    | Off -> halt
    | Rand s -> Random.init s; Dual.random_neighbour ~plen:128 ~pins:neigh_pins ~own:[ 3 ]
    | Compiled -> (match c.which with
        | A -> Asm.of_base ~loop:true (Compiler.spi_master { sclk = 5; mosi = 6; cs = 7; period = 12; sbytes = [ 0x96 ] }) ~plen:128
        | B -> Asm.of_base ~loop:true (Compiler.i2c_write { sda = 6; scl = 7; q = 4; ibytes = [ 0xA0; 0x3C ] }) ~plen:128) in
  let mem = [| t0; t1; t2; t3 |] in
  let d = Dual.make ~rtl:c.rtl ic mem in
  let i2c_txs = random_i2c rnd c.ntx ~addr:dev_addr and spi_txs = random_spi rnd c.ntx in
  let ops = if c.bridge then (match c.which with A -> i2c_ops i2c_txs | B -> spi_ops spi_txs) else [] in
  let expected, expect_bus, ref_mem = match c.which with
    | A -> i2c_reference ~addr:dev_addr i2c_txs
    | B -> let a, m = spi_reference spi_txs in a, [], m in
  let expected = if c.bridge then expected else [] in
  let hs = new_host ~seed:(c.seed + 1000) ~bytes:ops ~err:c.err ~gap_bits:c.gap_bits ~respect_cts:c.respect_cts in
  let slave = new_i2c_slave ~max_stretch:c.max_stretch ~bit_stretch:0.02 ~seed:(c.seed + 7) dev_addr in
  let nslave = new_i2c_slave ~seed:5 0x50 in               (* bridge B's neighbour bus: 0xA0 >> 1 *)
  let sdev = new_spi_dev () in
  let tr = ref (Array.make 1_000_000 0) in
  let reports = ref [] in
  let rts_cycles = ref 0 and max_fill = ref 0 and min_slack = ref max_int in
  let bridge_hash = ref 0 and neigh_hash = ref 0 in
  let t_stop = ref (-1) in
  (* an online count of the bytes on our TX, only to know when to stop *)
  let txs_state = ref (-1) and txs_count = ref 0 and last_tx = ref 0 in
  let n = ref 0 and fin = ref false in
  while not !fin do
    let now = !n in
    let po = Dual.pin_out d and oe = Dual.pin_oe d in
    let drv p = (oe lsr p) land 1 = 1 in
    let pushpull p = if drv p then (po lsr p) land 1 else 1 in
    let od_low p = drv p && (po lsr p) land 1 = 0 in
    let bus = ref 0 in
    let setb p v = if v = 1 then bus := !bus lor (1 lsl p) in
    let cts = pushpull 2 in
    let hl = host_level hs ~now ~cts:(match c.which with A -> cts | B -> 0) in
    setb rx hl; setb tx (pushpull tx);
    (match c.which with
     | A ->
       setb 2 cts;
       let sda, scl = i2c_slave_step slave ~now ~m_sda_low:(od_low 3) ~m_scl_low:(od_low 4) in
       setb 3 sda; setb 4 scl;
       List.iter (fun p -> setb p (pushpull p)) [ 5; 6; 7 ];
       if cts = 1 then incr rts_cycles
     | B ->
       let sclk = pushpull 2 and mosi = pushpull 3 and cs = pushpull 5 in
       let miso = spi_dev_step sdev ~sclk ~mosi ~cs in
       setb 2 sclk; setb 3 mosi; setb 4 miso; setb 5 cs;
       let sda, scl = i2c_slave_step nslave ~now ~m_sda_low:(od_low 6) ~m_scl_low:(od_low 7) in
       setb 6 sda; setb 7 scl);
    let pin_in = !bus in
    if now >= Array.length !tr then (let a = Array.make (2 * now) 0 in Array.blit !tr 0 a 0 now; tr := a);
    (!tr).(now) <- pin_in;
    let nb = lnot neigh_pins land 0xFF in
    bridge_hash := Hashtbl.hash (!bridge_hash, pin_in land nb, po land nb, oe land nb);
    neigh_hash := Hashtbl.hash (!neigh_hash, pin_in land neigh_pins, po land neigh_pins, oe land neigh_pins);
    let pc0 = d.st.pcs.(0) and th = d.st.thread in
    let e = Dual.step d { Isa_mb.idle_io with pin_in } in
    (* receive budget: from the stop-bit check to the poll at idle, in slots *)
    if th = 0 && c.bridge then begin
      if pc0 = stopchk_pc then t_stop := now;
      if pc0 = rearm_pc && !t_stop >= 0 then begin
        let used = (now - !t_stop) / 4 + 1 in
        (* at exact baud the next start edge has the same phase against the poll, so the poll must
           run no later than B/2 slots after the stop check; a drifting host takes one more slot *)
        let slack = (bit_slots / 2) - used in
        if slack < !min_slack then min_slack := slack;
        t_stop := -1
      end
    end;
    (match e.host_out with Some v when th = 0 -> reports := (th, v) :: !reports | _ -> ());
    let fill = List.length d.st.inbox.(1) in if fill > !max_fill then max_fill := fill;
    let txl = pushpull tx in
    (if !txs_state < 0 then (if txl = 0 then txs_state := now)
     else if now - !txs_state >= 10 * 4 * bit_slots then (txs_state := -1; incr txs_count; last_tx := now));
    incr n;
    let sent_all = hs.next >= Array.length hs.bytes && hs.bitn < 0 in
    if (c.bridge && sent_all && ((!txs_count >= List.length expected && now - !last_tx > 20000) || now - max !last_tx 0 > 400000))
       || now >= 6_000_000 || ((not c.bridge) && now >= 400_000) then fin := true
  done;
  if Sys.getenv_opt "DEBUG" <> None then
    Printf.printf "end state: pcs %s, inbox fills %s, inbox1 %s, pin_out %02x oe %02x, t1 acc %02x dl %d\n"
      (String.concat "," (Array.to_list (Array.map string_of_int d.st.pcs)))
      (String.concat "," (Array.to_list (Array.map (fun l -> string_of_int (List.length l)) d.st.inbox)))
      (String.concat " " (List.map (Printf.sprintf "%02x") d.st.inbox.(1))) d.st.pin_out d.st.pin_oe d.st.accs.(1) d.st.dls.(1);
  let trace = List.init !n (fun i -> { Decoders.c = i; bus = (!tr).(i) }) in
  let answers = List.map (fun (_, b, ok) -> if ok then b else -1) (Decoders.uart trace ~pin:tx ~bit_cycles:(4 * bit_slots)) in
  let answers = if c.bridge then answers else [] in
  let regs_ok, bus_ok = match c.which with
    | A -> let got, _ = Decoders.i2c trace ~sda:3 ~scl:4 in (slave.regs = ref_mem, (not c.bridge) || got = expect_bus)
    | B -> (sdev.mem = ref_mem, true) in
  let neigh_ok = match c.neigh, c.which with
    | Compiled, A -> let got = Decoders.spi trace ~sclk:5 ~mosi:6 ~cs:7 in got <> [] && List.for_all (fun x -> x = 0x96) got
    | Compiled, B -> let got, _ = Decoders.i2c trace ~sda:6 ~scl:7 in got <> [] && List.for_all (fun (x, a) -> (x = 0xA0 || x = 0x3C) && a) got
    | _ -> true in
  { answers; expected; regs_ok; bus_ok; mism = d.mismatches; reports = List.rev !reports; bridge_hash = !bridge_hash;
    neigh_hash = !neigh_hash; cycles = !n; rts_cycles = !rts_cycles; max_fill = !max_fill; stretched = slave.stretched;
    min_slack = (if !min_slack = max_int then 0 else !min_slack); neigh_ok; n_ops = List.length ops; cts_waits = hs.cts_waits;
    ntr = Array.init !n (fun i -> (!tr).(i) land neigh_pins); swapped = d.st.swapped }

let pass o = o.answers = o.expected && o.regs_ok && o.bus_ok && o.mism = 0 && o.reports = [] && o.neigh_ok

let describe name o =
  let first_diff =
    let rec go i a b = match a, b with
      | [], [] -> "none" | x :: r1, y :: r2 -> if x = y then go (i + 1) r1 r2 else Printf.sprintf "answer %d: got %d expected %d" i x y
      | [], _ -> Printf.sprintf "%d answers missing" (List.length b) | _, [] -> Printf.sprintf "%d extra answers" (List.length a) in
    go 0 o.answers o.expected in
  let rec agree a b = match a, b with x :: r1, y :: r2 when x = y -> 1 + agree r1 r2 | _ -> 0 in
  Printf.printf "%-50s %s: %d bytes in, answers %d/%d in agreement before the first difference (%s); device %s, bus %s; \
                 RTL mismatches %d; T0 reports %d; %d cycles; RTS high %d cycles; host waited on CTS %d cycles; \
                 max inbox fill %d; slave stretched %d cycles; receive slack %d slots\n%!"
    name (if pass o then "PASS" else "FAIL") o.n_ops (agree o.answers o.expected) (List.length o.expected) first_diff
    (if o.regs_ok then "ok" else "WRONG") (if o.bus_ok then "ok" else "WRONG")
    o.mism (List.length o.reports) o.cycles o.rts_cycles o.cts_waits o.max_fill o.stretched o.min_slack

let () =
  let t0 = Unix.gettimeofday () in
  let mode = try Sys.argv.(1) with _ -> "all" in
  List.iter (fun (name, (_, len, _)) -> Printf.printf "programme %-22s %3d words of 128\n" name len)
    [ ("T0 UART receive (RTS)", uart_rx ~rx:0 ~rts:(Some 2) ~dst:1 ()); ("T1 I2C master", i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 ());
      ("T1 SPI master", spi_master ~sclk:2 ~mosi:3 ~miso:4 ~cs:5 ~own:1 ~reply:2 ()); ("T2 UART transmit", uart_tx ~tx:1 ~own:2 ()) ];
  if mode = "iso" then begin
    let full = run { base with rtl = false } and nalone = run { base with rtl = false; bridge = false } in
    let n = min (Array.length full.ntr) (Array.length nalone.ntr) in
    let first = ref (-1) in
    for i = n - 1 downto 0 do if full.ntr.(i) <> nalone.ntr.(i) then first := i done;
    Printf.printf "lengths %d %d (prefix compared: %b), first difference at %d: full %02x idle %02x\n" (Array.length full.ntr) (Array.length nalone.ntr) (same_prefix full.ntr nalone.ntr) !first
      (if !first >= 0 then full.ntr.(!first) else 0) (if !first >= 0 then nalone.ntr.(!first) else 0)
  end;
  if mode = "late" then describe "late" (run { base with rtl = false; late = 6; gap_bits = 0 });
  if mode = "smoke" then begin
    describe "A smoke" (run { base with ntx = 3 });
    describe "B smoke" (run { base with which = B; ntx = 3 })
  end;
  if mode = "all" then begin
    let all_ok = ref true in
    let expect_pass name o = describe name o; if not (pass o) then all_ok := false in
    let expect_fail name o = describe name o; if pass o then (all_ok := false; print_endline "  ^ CONTROL DID NOT FAIL") in
    (* main runs, RTL in lockstep *)
    let a = run base in expect_pass "A: UART<->I2C, SPI neighbour, RTL+interp" a;
    let b = run { base with which = B } in expect_pass "B: UART<->SPI, I2C neighbour, RTL+interp" b;
    (* constrained random: seeds, both bridges, fast host (no gaps), baud error, slow slave *)
    let ok = ref 0 and tot = ref 0 in
    for seed = 2 to 13 do
      List.iter (fun which ->
        let c = { base with which; seed; rtl = seed <= 4; gap_bits = seed mod 3; err = (float (seed mod 5) -. 2.0) *. 0.008;
                  max_stretch = (seed mod 4) * 300 } in
        let o = run c in incr tot; if pass o then incr ok else describe (Printf.sprintf "  random seed %d %s" seed (if which = A then "A" else "B")) o) [ A; B ]
    done;
    Printf.printf "constrained random: %d of %d runs pass (12 seeds x 2 bridges; RTL in lockstep for seeds 2..4)\n%!" !ok !tot;
    if !ok <> !tot then all_ok := false;
    (* isolation *)
    List.iter (fun which ->
      let nm = if which = A then "A" else "B" in
      let full = run { base with which; rtl = false } in
      let alone = run { base with which; rtl = false; neigh = Off } in
      let nalone = run { base with which; rtl = false; bridge = false } in
      let same = ref 0 in
      for s = 1 to 6 do if (run { base with which; rtl = false; neigh = Rand s }).bridge_hash = full.bridge_hash then incr same done;
      let traffic = run { base with which; rtl = false; seed = 77 } in
      Printf.printf "isolation %s: bridge pins identical without the neighbour %b, under 6 random neighbours %d/6; \
                     neighbour pins identical with the bridge idle %b and under other traffic %b\n%!"
        nm (alone.bridge_hash = full.bridge_hash) !same (same_prefix nalone.ntr full.ntr) (same_prefix traffic.ntr full.ntr);
      if not (alone.bridge_hash = full.bridge_hash && !same = 6 && same_prefix nalone.ntr full.ntr && same_prefix traffic.ntr full.ntr)
      then all_ok := false) [ A; B ];
    (* controls, each must fail *)
    expect_fail "control A: mailbox drops push 40 (interp)" (run { base with rtl = false; fault = Isa_mb.Drop_push 40 });
    expect_fail "control A: mailbox pops newest first (interp)" (run { base with rtl = false; fault = Isa_mb.Lifo });
    expect_fail "control B: mailbox drops push 40 (interp)" (run { base with which = B; rtl = false; fault = Isa_mb.Drop_push 40 });
    describe "control B: mailbox pops newest first (interp; vacuous)" (run { base with which = B; rtl = false; fault = Isa_mb.Lifo });
    print_endline "  (B's inbox never holds two bytes, so newest-first equals oldest-first: an ordering fault needs occupancy >= 2 to show)";
    List.iter (fun which ->
      let obs = ref 0 and caught = ref 0 and same = ref 0 in
      for k = 20 to 69 do
        let o = run { base with which; rtl = false; fault = Isa_mb.Swap_pair k } in
        match o.swapped with
        | Some (x, y) when x <> y -> incr obs; if not (pass o) then incr caught
        | Some _ -> incr same
        | None -> ()
      done;
      Printf.printf "control %s: two pushes delivered swapped, at pushes 20..69: %d swaps of different bytes, caught %d; %d swaps of equal bytes (unobservable by any checker)\n%!"
        (if which = A then "A" else "B") !obs !caught !same;
      if !caught <> !obs || !obs = 0 then all_ok := false) [ A; B ];
 expect_pass "budget edge A: +3 slots in the receiver (slack 0), exact baud" (run { base with rtl = false; late = 3; gap_bits = 0; ntx = 16; err = 0.0 });
    expect_fail "budget edge A: +4 slots (slack -1), exact baud" (run { base with rtl = false; late = 4; gap_bits = 0; ntx = 16; err = 0.0 });
    expect_pass "budget edge B: +5 slots (slack 0), exact baud" (run { base with which = B; rtl = false; late = 5; gap_bits = 0; ntx = 16; err = 0.0 });
    expect_fail "budget edge B: +6 slots (slack -1), exact baud" (run { base with which = B; rtl = false; late = 6; gap_bits = 0; ntx = 16; err = 0.0 });
    expect_fail "control A: receiver over budget by 6 slots" (run { base with rtl = false; late = 6; gap_bits = 0 });
    let ig = run { base with rtl = false; respect_cts = false; gap_bits = 0; max_stretch = 1500; ntx = 16 } in
    expect_fail "control A: host ignores CTS, slow slave" ig;
    Printf.printf "  (overflow reported by T0 on the host channel: %d bytes)\n" (List.length ig.reports);
    (* backpressure: the fast host against a slow device, with and without flow control *)
    let slow = run { base with rtl = true; gap_bits = 0; max_stretch = 1500; ntx = 16 } in
    expect_pass "backpressure A: no host gaps, slave stretches <=1500 cycles" slow;
    let d1 = run { base with rtl = false; gap_bits = 0; max_stretch = 1500; ntx = 16; depth = 1 } in
    expect_pass "backpressure A: same, inbox depth 1" d1;
    let d4 = run { base with rtl = false; gap_bits = 0; max_stretch = 1500; ntx = 16; depth = 4 } in
    expect_pass "backpressure A: same, inbox depth 4" d4;
    print_endline (if !all_ok then "BRIDGES PASS" else "BRIDGES FAIL")
  end;
  Printf.printf "elapsed %.0f s\n" (Unix.gettimeofday () -. t0)
