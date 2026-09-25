(* Value-interval trace of the deadline sequencer's storage, from its executable specification
   (Isa.step, unchanged), running the demo's three compiled protocols at realistic rates for a
   50 MHz clock. Each stored value gets one row:
     kernel,loc,width,value,t_def,t_last
   in cycles; t_last = -1 means the value was never read (dead, needs no storage lifetime).
   Locations: per thread pc, acc, cnt, dl, and each of the 4 x 64 instruction words (imem). *)

let uart_pin = 0 and sclk = 1 and mosi = 2 and cs = 3 and sda = 4 and scl = 5

(* I2C slave model, copied from ../../deadline-sequencer/demo.ml *)
type slave = { mutable started : bool; mutable nbits : int; mutable pull : bool; mutable p_sda : int; mutable p_scl : int }
let new_slave () = { started = false; nbits = 0; pull = false; p_sda = 1; p_scl = 1 }

(* bus levels from the master's outputs and the slave; returns (bus, pin_in for the core) *)
let resolve sl ~pin_out ~pin_oe =
  let drives p = (pin_oe lsr p) land 1 = 1 in
  let out p = (pin_out lsr p) land 1 in
  let scl_l = if drives scl then out scl else 1 in
  let sda_l = if drives sda && out sda = 0 then 0 else if sl.pull then 0 else if drives sda then out sda else 1 in
  (* slave state machine on the resolved lines *)
  if sl.p_scl = 1 && scl_l = 1 && sl.p_sda = 1 && sda_l = 0 then (sl.started <- true; sl.nbits <- 0);
  if sl.p_scl = 1 && scl_l = 1 && sl.p_sda = 0 && sda_l = 1 && not sl.pull then sl.started <- false;
  if sl.started && sl.p_scl = 0 && scl_l = 1 then sl.nbits <- sl.nbits + 1;
  if sl.started && sl.p_scl = 1 && scl_l = 0 then begin
    if sl.nbits = 8 then sl.pull <- true
    else if sl.nbits = 9 then (sl.pull <- false; sl.nbits <- 0)
  end;
  sl.p_sda <- sda_l; sl.p_scl <- scl_l;
  let others = List.fold_left (fun acc p -> if drives p then acc lor (out p lsl p) else acc lor (1 lsl p)) 0 [0; 1; 2; 3; 6; 7] in
  others lor (sda_l lsl sda) lor (scl_l lsl scl)

(* per-location bookkeeping *)
type cell = { mutable v : int; mutable def : int; mutable last : int; width : int }
let out = ref []
let emit name c = out := Printf.sprintf "seq,%s,%d,%d,%d,%d" name c.width c.v c.def c.last :: !out
let write name c v t = emit name c; c.v <- v; c.def <- t; c.last <- -1
let read c t = c.last <- t

let () =
  let cycles_per_slot = Compiler.slot in
  let clk = 50e6 in
  (* realistic rates: UART 115200 baud, SPI 1 MHz, I2C 100 kHz *)
  let slot_s = float cycles_per_slot /. clk in
  let bit_slots = int_of_float (Float.round (1. /. 115200. /. slot_s)) in
  let spi_period = 2 * (int_of_float (1e-6 /. slot_s) / 2) in
  let q = int_of_float (1e-5 /. slot_s /. 4.) in
  Printf.eprintf "bit_slots %d  spi_period %d  i2c q %d\n" bit_slots spi_period q;
  let u, ul = Compiler.uart_tx { upin = uart_pin; bit_slots; ubytes = [ 0x4F; 0x4B; 0x21; 0x0A ]; stretch = None } in
  let sp, sl = Compiler.spi_master { sclk; mosi; cs; period = spi_period; sbytes = [ 0xA5; 0x3C; 0x00; 0xFF ] } in
  let ic, il = Compiler.i2c_write { sda; scl; q; ibytes = [ 0xA0; 0x5A ] } in
  Printf.eprintf "programme words: uart %d spi %d i2c %d\n" ul sl il;
  let mem = [| u; sp; ic; Array.make Isa.prog_len Isa.halt |] in
  let st = Isa.init () in
  let slave = new_slave () in
  let bus = ref (resolve slave ~pin_out:0 ~pin_oe:0) in
  let mk w = { v = 0; def = 0; last = -1; width = w } in
  let imem = Array.init 4 (fun t -> Array.init Isa.prog_len (fun a -> { (mk 16) with v = mem.(t).(a) })) in
  let pc = Array.init 4 (fun _ -> mk 6) and acc = Array.init 4 (fun _ -> mk 8)
  and cnt = Array.init 4 (fun _ -> mk 12) and dl = Array.init 4 (fun _ -> mk 12) in
  let halted = Array.make 4 false in
  let t = ref 0 in
  while not (Array.for_all Fun.id halted) do
    let th = st.Isa.thread in
    let p = st.pcs.(th) in
    let instr = mem.(th).(p) in
    let op = Isa.op_of_code ((instr lsr 12) land 0xF) in
    let now = !t in
    read pc.(th) now; read imem.(th).(p) now;
    if st.dls.(th) <> 0 && op <> Isa.LDD then read dl.(th) now;   (* the decrement reads dl *)
    (match op with
     | Isa.WAITP ->
       let pin = (instr lsr 9) land 7 and pv = (instr lsr 8) land 1 in
       if (!bus lsr pin) land 1 <> pv then read dl.(th) now   (* dl only matters on a mismatch *)
     | WAITD -> read dl.(th) now
     | SHO | SHI -> read acc.(th) now; read cnt.(th) now
     | JNZ -> read cnt.(th) now
     | OUT -> read acc.(th) now
     | HALT -> halted.(th) <- true
     | _ -> ());
    let d0 = st.dls.(th) in
    let pin_in = !bus in
    ignore (Isa.step st ~mem ~pin_in ~host_in:0 ~host_in_valid:false);
    bus := resolve slave ~pin_out:st.pin_out ~pin_oe:st.pin_oe;
    (* a register is rewritten when the instruction targets it; dl also whenever it counts *)
    let wr_acc = (match op with LDA | SHO | SHI -> true | _ -> false) in   (* IN: host_in_valid is always false here *)
    let wr_cnt = (match op with LDC | SHO | SHI -> true | _ -> false) in
    let wr_dl = op = LDD || d0 <> 0 in
    let name r = Printf.sprintf "t%d.%s" th r in
    if wr_acc then write (name "acc") acc.(th) st.accs.(th) (now + 1);
    if wr_cnt then write (name "cnt") cnt.(th) st.cnts.(th) (now + 1);
    if wr_dl then write (name "dl") dl.(th) st.dls.(th) (now + 1);
    write (name "pc") pc.(th) st.pcs.(th) (now + 1);
    incr t
  done;
  (* flush: every location's final value *)
  for th = 0 to 3 do
    let name r = Printf.sprintf "t%d.%s" th r in
    emit (name "acc") acc.(th); emit (name "cnt") cnt.(th); emit (name "dl") dl.(th); emit (name "pc") pc.(th);
    Array.iteri (fun a c -> emit (Printf.sprintf "t%d.imem%02d" th a) c) imem.(th)
  done;
  print_endline "kernel,loc,width,value,t_def,t_last";
  List.iter print_endline (List.rev !out);
  Printf.eprintf "cycles %d (%.1f us)\n" !t (float !t /. clk *. 1e6)
