(* The programmes under check. The protocol programmes are the real compiler's output
   (../deadline-sequencer/compiler.ml, base ISA), translated word by word to ISA v2 by
   ../sequencer-v2/compat.ml, exactly as the v2 ports of the demo run them; thread t's programme
   sits at page t, pc 0. Planted bugs are made by editing the compiled words, as a compiler bug
   would. *)

let addr ~thread pc = (thread lsl Isa2.pc_bits) lor pc

let store_of (progs : int array array) =
  let s = Array.make Isa2.store_len 0 in
  Array.iteri (fun t p ->
      for pc = 0 to Isa2.page_len - 1 do
        s.(addr ~thread:t pc) <- (if pc < Array.length p then Compat.of_base ~pc_bits:Isa.pc_bits ~addr:pc p.(pc) else 0)
      done) progs;
  s

let idle = Array.make Isa.prog_len Isa.halt

let opcode w = (w lsr 12) land 0xF
let replace_op ~op ~by p = Array.map (fun w -> if opcode w = op then by w else w) p

(* UART transmitter on pin 0, 8N1, lsb first *)
let uart ?stretch ~bit_slots bytes =
  fst (Compiler.uart_tx { upin = 0; bit_slots; ubytes = bytes; stretch })

(* the same, taking each byte from the host (IN) instead of an immediate (LDA): the data is an
   input, so the model checker covers every byte *)
let uart_from_host ?stretch ~bit_slots n =
  replace_op ~op:4 ~by:(fun _ -> Isa.in_) (uart ?stretch ~bit_slots (List.init n (fun _ -> 0)))

(* period 10 is the shortest the compiler's arithmetic supports: it accepts 8 (its assertion and
   the README say "at least eight slots") but then computes a = P - 8 - (P/2 - 3) = -1 and emits
   LDD 4095 (README.md, "Findings") *)
let spi_with ~period = fst (Compiler.spi_master { sclk = 1; mosi = 2; cs = 3; period; sbytes = [ 0xA5 ] })
let spi = spi_with ~period:10
let i2c_with ?stretch_limit () = fst (Compiler.i2c_write ?stretch_limit { sda = 4; scl = 5; q = 4; ibytes = [ 0xA0 ] })
let i2c = i2c_with ()

(* ../deadline-sequencer/main.ml's deadline programme: wait up to the deadline for pin 1 to rise;
   pin 6 reports the event, pin 7 the timeout. [ldd] is its deadline immediate (20 there). *)
let deadline_program ~ldd =
  let p = Array.make Isa.prog_len Isa.nop in
  p.(0) <- Isa.setp ~mask:0x80 ~value:0 ~oe:1;
  p.(1) <- Isa.ldd ldd;
  p.(2) <- Isa.waitp ~pin:1 ~value:1 ~fail:5;
  p.(3) <- Isa.setp ~mask:0x40 ~value:1 ~oe:1;
  p.(4) <- Isa.halt;
  p.(5) <- Isa.setp ~mask:0x80 ~value:1 ~oe:1;
  p.(6) <- Isa.halt;
  p

(* A watchdog for the fourth thread of the ownership check: wait up to 21 slots for pin 6 to
   rise, and raise pin 7 on a timeout. [timeout_mask] is the pin mask its timeout writes
   (0x80; the planted bug is a mistyped 0x01, the UART's pin). *)
let watchdog ~timeout_mask =
  let p = Array.make Isa.prog_len Isa.halt in
  p.(0) <- Isa.setp ~mask:0x80 ~value:0 ~oe:1;
  p.(1) <- Isa.ldd 20;
  p.(2) <- Isa.waitp ~pin:6 ~value:1 ~fail:4;
  p.(3) <- Isa.halt;
  p.(4) <- Isa.setp ~mask:timeout_mask ~value:1 ~oe:1;
  p.(5) <- Isa.halt;
  p

(* every WAITD of thread [thread]'s base-ISA programme that directly follows an LDD n, with the
   ISA's rule as its contract: the WAITD occupies n + 1 slots, counted from the LDD *)
let waitd_contracts ~thread (p : int array) : Props.contract list =
  let l = ref [] in
  for pc = 1 to Array.length p - 1 do
    if opcode p.(pc) = 6 && opcode p.(pc - 1) = 3 then
      l := { Props.thread; anchor = addr ~thread (pc - 1); wait = addr ~thread pc; fail = addr ~thread (pc + 1);
             slots = (p.(pc - 1) land 0xFFF) + 1; kind = Waitd } :: !l
  done;
  List.rev !l

(* every WAITP of thread [thread]'s base-ISA programme whose deadline is loaded by an LDD n one or
   two words before it (the I2C master's "LDD stretch_limit; release SCL; WAITP scl=1"), with the
   ISA's rule as its contract: the window is n + 1 slots counted from the LDD, the wait proceeds
   on the slot its pin shows the value, and on the last slot of the window it takes its fail
   target. Nothing between the LDD and the WAITP may load the deadline register again. *)
let waitp_contracts ~thread (p : int array) : Props.contract list =
  let l = ref [] in
  for pc = 1 to Array.length p - 1 do
    if opcode p.(pc) = 5 then begin
      let anchor = if opcode p.(pc - 1) = 3 then Some (pc - 1)
        else if pc >= 2 && opcode p.(pc - 2) = 3 && opcode p.(pc - 1) <> 3 && opcode p.(pc - 1) <> 6 then Some (pc - 2)
        else None in
      match anchor with
      | None -> ()
      | Some a ->
        let w = p.(pc) in
        let pin = (w lsr 9) land 7 and value = (w lsr 8) land 1 and fail = w land (Isa.prog_len - 1) in
        l := { Props.thread; anchor = addr ~thread a; wait = addr ~thread pc; fail = addr ~thread fail;
               slots = (p.(a) land 0xFFF) + 1; kind = Waitp (pin, value) } :: !l
    end
  done;
  List.rev !l
