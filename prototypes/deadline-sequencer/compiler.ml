(* Protocol compiler for the deadline sequencer: protocol descriptions become thread programmes
   whose timing is fixed by construction. Every derived delay below is worked out from the ISA's
   one-slot-per-instruction rule; the demo then checks the resulting edges against the closed
   forms on both the interpreter and the RTL. *)

type item = W of int | Label of string | Jmp of string | Jnz of string

let assemble items =
  let labels = Hashtbl.create 16 in
  let pos = ref 0 in
  List.iter (function Label l -> Hashtbl.replace labels l !pos | _ -> incr pos) items;
  if !pos > Isa.prog_len then failwith (Printf.sprintf "programme too long: %d words" !pos);
  let prog = Array.make Isa.prog_len Isa.halt in
  let pos = ref 0 in
  List.iter (function
    | Label _ -> ()
    | W w -> prog.(!pos) <- w; incr pos
    | Jmp l -> prog.(!pos) <- Isa.jmp (Hashtbl.find labels l); incr pos
    | Jnz l -> prog.(!pos) <- Isa.jnz (Hashtbl.find labels l); incr pos) items;
  prog, !pos

let slot = 4   (* cycles per slot: one instruction per thread every n_threads cycles *)

(* UART transmitter, 8N1, lsb first. bit_slots >= 5. Loop form: 12 words per byte.
   Start bit: SETP(0) LDD(1) WAITD(2..2+x) LDC(3+x) SHO(4+x): width 4+x = bit_slots, x = bit_slots-4.
   Data bit: SHO LDD WAITD(x+1) JNZ: 4+x. Stop: SETP LDD WAITD(x+1) then next LDA, SETP: 4+x. *)
type uart = { upin : int; bit_slots : int; ubytes : int list; stretch : (int * int) option }
(* stretch = Some (k, d): data bit k (1..8) of the FIRST byte is d slots longer (unrolled form). *)

let uart_tx u =
  assert (u.bit_slots >= 5);
  let x = u.bit_slots - 4 in
  let m = 1 lsl u.upin in
  let items = ref [ W (Isa.setp ~mask:m ~value:1 ~oe:1) ] in
  let emit i = items := i :: !items in
  List.iteri (fun bi b ->
    emit (W (Isa.lda b));
    emit (W (Isa.setp ~mask:m ~value:0 ~oe:1));
    emit (W (Isa.ldd x)); emit (W Isa.waitd);
    (match u.stretch with
     | Some (k, d) when bi = 0 ->
       (* unrolled: SHO LDD WAITD NOP = 4+x per bit, bit k gets x+d *)
       emit (W Isa.nop);   (* stands in for LDC so the start bit keeps its width *)
       for j = 1 to 8 do
         emit (W (Isa.sho ~pin:u.upin ~msb:0 ()));
         emit (W (Isa.ldd (if j = k then x + d else x))); emit (W Isa.waitd); emit (W Isa.nop)
       done
     | _ ->
       emit (W (Isa.ldc 8));
       let l = Printf.sprintf "ubit%d" bi in
       emit (Label l);
       emit (W (Isa.sho ~pin:u.upin ~msb:0 ()));
       emit (W (Isa.ldd x)); emit (W Isa.waitd); emit (Jnz l));
    emit (W (Isa.setp ~mask:m ~value:1 ~oe:1));
    emit (W (Isa.ldd x)); emit (W Isa.waitd)) u.ubytes;
  emit (W Isa.halt);
  assemble (List.rev !items)

(* SPI master, mode 0, msb first, cs active low, period P slots (even, >= 8).
   Bit: SHO(0) LDD a(1) WAITD(2..2+a) SETP sclk=1 (3+a) LDD b WAITD SETP sclk=0 (6+a+b) JNZ, next SHO at 8+a+b.
   High width 3+b = P/2, so b = P/2-3 and a = P-8-b. *)
type spi = { sclk : int; mosi : int; cs : int; period : int; sbytes : int list }

let spi_master s =
  assert (s.period >= 8 && s.period mod 2 = 0);
  let b = s.period / 2 - 3 in
  let a = s.period - 8 - b in
  let mk p = 1 lsl p in
  let items = ref [ W (Isa.setp ~mask:(mk s.cs) ~value:1 ~oe:1); W (Isa.setp ~mask:(mk s.sclk lor mk s.mosi) ~value:0 ~oe:1) ] in
  let emit i = items := i :: !items in
  List.iteri (fun bi byte ->
    emit (W (Isa.lda byte));
    emit (W (Isa.setp ~mask:(mk s.cs) ~value:0 ~oe:1));
    emit (W (Isa.ldc 8));
    let l = Printf.sprintf "sbit%d" bi in
    emit (Label l);
    emit (W (Isa.sho ~pin:s.mosi ~msb:1 ()));
    emit (W (Isa.ldd a)); emit (W Isa.waitd);
    emit (W (Isa.setp ~mask:(mk s.sclk) ~value:1 ~oe:1));
    emit (W (Isa.ldd b)); emit (W Isa.waitd);
    emit (W (Isa.setp ~mask:(mk s.sclk) ~value:0 ~oe:1));
    emit (Jnz l);
    emit (W (Isa.setp ~mask:(mk s.cs) ~value:1 ~oe:1))) s.sbytes;
  emit (W Isa.halt);
  assemble (List.rev !items)

(* I2C master write: START, bytes each followed by an ack clock whose sampled sda goes to the host,
   STOP. Quarter period q slots (q >= 4); bit period 4q. sda and scl are open drain: drive low
   with oe=1 value=0, release with oe=0.
   Bit: SHO od (0) LDD q-3 WAITD, scl release at q, LDD 2q-3 WAITD, scl low at 3q, LDD q-4 WAITD, JNZ, next at 4q.
   Ack: sda release (0), scl release at q, SHI at 2q, scl low at 3q, next at 4q, then OUT. *)
type i2c = { sda : int; scl : int; q : int; ibytes : int list }

let i2c_write c =
  assert (c.q >= 4);
  let q = c.q in
  let mk p = 1 lsl p in
  let drive_low p = W (Isa.setp ~mask:(mk p) ~value:0 ~oe:1) in
  let release p = W (Isa.setp ~mask:(mk p) ~value:0 ~oe:0) in
  let wait n = [ W (Isa.ldd n); W Isa.waitd ] in
  let items = ref [] in
  let emit i = items := i :: !items in
  let emits l = List.iter emit l in
  emit (W (Isa.setp ~mask:(mk c.sda lor mk c.scl) ~value:0 ~oe:0));
  (* START: sda low while scl high, then scl low q slots later *)
  emit (drive_low c.sda); emits (wait (q - 3)); emit (drive_low c.scl);
  List.iteri (fun bi byte ->
    emit (W (Isa.lda byte)); emit (W (Isa.ldc 8));
    let l = Printf.sprintf "ibit%d" bi in
    emit (Label l);
    emit (W (Isa.sho ~od:1 ~pin:c.sda ~msb:1 ()));
    emits (wait (q - 3)); emit (release c.scl);
    emits (wait (2 * q - 3)); emit (drive_low c.scl);
    emits (wait (q - 4)); emit (Jnz l);
    (* ack clock *)
    emit (release c.sda); emits (wait (q - 3)); emit (release c.scl);
    emits (wait (q - 3)); emit (W (Isa.shi ~pin:c.sda ~msb:1));
    emits (wait (q - 3)); emit (drive_low c.scl);
    emits (wait (q - 3)); emit (W Isa.out)) c.ibytes;
  (* STOP: sda low, scl release at q, sda release at 2q *)
  emit (drive_low c.sda); emits (wait (q - 3)); emit (release c.scl); emits (wait (q - 3)); emit (release c.sda);
  emit (W Isa.halt);
  assemble (List.rev !items)

let disassemble prog len =
  let buf = Buffer.create 256 in
  for i = 0 to len - 1 do
    let w = prog.(i) in
    let op = Isa.op_of_code ((w lsr 12) land 0xF) in
    let f = w land 0xFFF in
    let s = match op with
      | Isa.NOP -> "nop" | SETP -> Printf.sprintf "setp mask=%02x val=%d oe=%d" ((f lsr 4) land 0xFF) ((f lsr 3) land 1) ((f lsr 2) land 1)
      | LDC -> Printf.sprintf "ldc %d" f | LDD -> Printf.sprintf "ldd %d" f | LDA -> Printf.sprintf "lda 0x%02x" (f land 0xFF)
      | WAITP -> Printf.sprintf "waitp pin%d==%d fail=%d" ((f lsr 9) land 7) ((f lsr 8) land 1) (f land 0x3F)
      | WAITD -> "waitd" | SHO -> Printf.sprintf "sho pin%d %s%s" ((f lsr 9) land 7) (if (f lsr 8) land 1 = 1 then "msb" else "lsb") (if (f lsr 7) land 1 = 1 then " od" else "")
      | SHI -> Printf.sprintf "shi pin%d %s" ((f lsr 9) land 7) (if (f lsr 8) land 1 = 1 then "msb" else "lsb")
      | JMP -> Printf.sprintf "jmp %d" (f land 0x3F) | JNZ -> Printf.sprintf "jnz %d" (f land 0x3F)
      | OUT -> "out" | IN -> "in" | HALT -> "halt" in
    Buffer.add_string buf (Printf.sprintf "  %2d: %s\n" i s)
  done;
  Buffer.contents buf
