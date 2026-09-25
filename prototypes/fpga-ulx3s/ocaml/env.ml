(* Model of everything outside the sequencer core: the routing in rtl/emu_core.v, the header
   pads with pull-ups, optional jumper wires, and the devices on the ULX3S (the configuration
   flash, the RTC on the I2C bus) or on the header (an acknowledging I2C slave).

   sim/sim_main.cpp implements the same models in C++ for the Verilator run, statement for
   statement, so that a simulated run must match the OCaml prediction exactly. On the real board
   the devices are real and only the core's outputs are expected to match exactly (see
   fpga_tests.ml). *)

(* ctrl register bits, as in emu_core.v *)
let ctrl_flash = 0x01 and ctrl_i2c = 0x02 and ctrl_uloop = 0x04 and ctrl_sloop = 0x08
let ctrl_usb = 0x10

type wiring = {
  jumper_0_7 : bool;        (* a wire from header seq pin 0 to seq pin 7 *)
  header_i2c_slave : bool;  (* an I2C slave on seq pins 4 (sda), 5 (scl) *)
  header_slave_addr : int;  (* its 7-bit address, or -1: acknowledge everything (demo.ml's slave) *)
  header_flash : bool;      (* an SPI flash on seq pins 1 (sclk), 2 (mosi), 3 (cs), 6 (miso) *)
  rtc_addr : int;           (* 7-bit address of the RTC on the board's I2C bus *)
}

(* The ULX3S schematic (power.sch) fits an MCP7940NT at 0x6F, with a PCF8523T (0x68) as the
   alternative part, so a given board has one or the other. *)
let rtc_mcp7940n = 0x6F and rtc_pcf8523 = 0x68
let no_wiring = { jumper_0_7 = false; header_i2c_slave = false; header_slave_addr = -1;
                  header_flash = false; rtc_addr = rtc_mcp7940n }

(* I2C slave on a resolved bus. [addr = None] acknowledges everything (the demo's slave);
   [Some a] acknowledges only its 7-bit address and the bytes that follow it. *)
type i2c_slave = {
  addr : int option;
  mutable started : bool; mutable nbits : int; mutable cur : int; mutable first : bool;
  mutable addressed : bool; mutable pull : bool; mutable p_sda : int; mutable p_scl : int;
}

let new_slave addr =
  { addr; started = false; nbits = 0; cur = 0; first = false; addressed = false; pull = false;
    p_sda = 1; p_scl = 1 }

(* Update on this cycle's line levels (after the slave's own pull, which is taken from before the
   update, as in deadline-sequencer/demo.ml). *)
let slave_update sl ~sda ~scl =
  if sl.p_scl = 1 && scl = 1 && sl.p_sda = 1 && sda = 0 then begin
    sl.started <- true; sl.nbits <- 0; sl.cur <- 0; sl.first <- true; sl.addressed <- false
  end else if sl.p_scl = 1 && scl = 1 && sl.p_sda = 0 && sda = 1 && not sl.pull then begin
    sl.started <- false; sl.addressed <- false
  end else if sl.started && sl.p_scl = 0 && scl = 1 then begin
    if sl.nbits < 8 then sl.cur <- ((sl.cur lsl 1) lor sda) land 0xFF;
    sl.nbits <- sl.nbits + 1
  end else if sl.started && sl.p_scl = 1 && scl = 0 then begin
    if sl.nbits = 8 then begin
      if sl.first then begin
        sl.addressed <- (match sl.addr with None -> true | Some a -> sl.cur lsr 1 = a);
        sl.first <- false
      end;
      sl.pull <- sl.addressed
    end else if sl.nbits = 9 then begin
      sl.pull <- false; sl.nbits <- 0; sl.cur <- 0
    end
  end;
  sl.p_sda <- sda; sl.p_scl <- scl

(* SPI NOR flash: answers JEDEC READ ID (0x9F) with [id], MSB first, changing MISO on falling
   edges of SCLK (mode 0). Records every command byte so that the runner can prove no write or
   erase command was ever sent. *)
type flash = {
  id : int list;
  mutable p_sclk : int; mutable p_csn : int; mutable nbits : int; mutable cmd : int;
  mutable nout : int; mutable miso : int; mutable commands : int list;
}

let new_flash id = { id; p_sclk = 0; p_csn = 1; nbits = 0; cmd = 0; nout = 0; miso = 1; commands = [] }

let flash_update f ~sclk ~mosi ~csn =
  if csn = 1 then begin f.nbits <- 0; f.nout <- 0; f.miso <- 1 end
  else begin
    if f.p_csn = 1 then begin f.nbits <- 0; f.cmd <- 0; f.nout <- 0 end;
    if f.p_sclk = 0 && sclk = 1 && f.nbits < 8 then begin
      f.cmd <- ((f.cmd lsl 1) lor mosi) land 0xFF;
      f.nbits <- f.nbits + 1;
      if f.nbits = 8 then f.commands <- f.cmd :: f.commands
    end else if f.p_sclk = 1 && sclk = 0 && f.nbits = 8 then begin
      let n = List.length f.id in
      f.miso <- (if f.cmd = 0x9F && f.nout < 8 * n then
                   (List.nth f.id (f.nout / 8) lsr (7 - (f.nout mod 8))) land 1
                 else 1);
      f.nout <- f.nout + 1
    end
  end;
  f.p_sclk <- sclk; f.p_csn <- csn

(* The simulated board's flash reports a Winbond W25Q128JV; see BRINGUP.md for real parts. The
   header breakout is a W25Q64. *)
let sim_flash_id = [ 0xEF; 0x40; 0x18 ]
let header_flash_id = [ 0xEF; 0x40; 0x17 ]

type t = {
  ctrl : int; wiring : wiring;
  header_slave : i2c_slave; rtc : i2c_slave; flash : flash; hflash : flash;
}

let create ~ctrl ~wiring =
  { ctrl; wiring;
    header_slave = new_slave (if wiring.header_slave_addr < 0 then None else Some wiring.header_slave_addr);
    rtc = new_slave (Some wiring.rtc_addr); flash = new_flash sim_flash_id; hflash = new_flash header_flash_id }

let bit v i = (v lsr i) land 1

(* One cycle: from the core's outputs visible in this cycle, the raw pin vector presented to the
   core's synchroniser in this cycle (emu_core.v: pin_raw). *)
let step e ~pin_out ~pin_oe =
  let has b = e.ctrl land b <> 0 in
  let routed = (if has ctrl_flash then 0x4E else 0) lor (if has ctrl_i2c then 0x30 else 0) in
  let driven i = bit pin_oe i = 1 && bit routed i = 0 in
  (* header pads: pull-ups everywhere, then jumpers and devices *)
  let pad = Array.init 8 (fun i -> if driven i then bit pin_out i else 1) in
  if e.wiring.header_i2c_slave then begin
    let sl = e.header_slave in
    let drv i = driven i in
    let scl = if drv 5 then bit pin_out 5 else 1 in
    let sda = if drv 4 && bit pin_out 4 = 0 then 0 else if sl.pull then 0
      else if drv 4 then bit pin_out 4 else 1 in
    slave_update sl ~sda ~scl;
    pad.(4) <- sda; pad.(5) <- scl
  end;
  if e.wiring.header_flash then begin
    flash_update e.hflash ~sclk:pad.(1) ~mosi:pad.(2) ~csn:pad.(3);
    if not (driven 6) then pad.(6) <- e.hflash.miso
  end;
  if e.wiring.jumper_0_7 && not (driven 7) then pad.(7) <- pad.(0);
  let raw = Array.copy pad in
  if has ctrl_flash then begin
    let sclk = bit pin_oe 1 land bit pin_out 1 and mosi = bit pin_oe 2 land bit pin_out 2 in
    let csn = if bit pin_oe 3 = 0 || bit pin_out 3 = 1 then 1 else 0 in
    flash_update e.flash ~sclk ~mosi ~csn;
    raw.(1) <- bit pin_out 1; raw.(2) <- bit pin_out 2; raw.(3) <- bit pin_out 3;
    raw.(6) <- e.flash.miso
  end;
  if has ctrl_i2c then begin
    let low i = bit pin_oe i = 1 && bit pin_out i = 0 in
    let scl = if low 5 then 0 else 1 in
    let sda = if low 4 || e.rtc.pull then 0 else 1 in
    slave_update e.rtc ~sda ~scl;
    raw.(4) <- sda; raw.(5) <- scl
  end;
  if has ctrl_uloop then raw.(7) <- (if bit pin_oe 0 = 1 then bit pin_out 0 else pad.(0));
  Array.fold_left (fun (acc, i) v -> (acc lor (v lsl i), i + 1)) (0, 0) raw |> fst
