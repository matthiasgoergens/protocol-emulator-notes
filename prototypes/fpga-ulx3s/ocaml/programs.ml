(* The FPGA test programmes. Each test is a full image of the four threads' instruction memory, a
   run length, the emu_core configuration registers, and the checks to apply to what comes back.
   Programmes come from deadline-sequencer/compiler.ml where it has them; the two it lacks (a UART
   receiver and an SPI read) are written here in the same style, with their timing worked out
   from the one-slot-per-instruction rule, and the replay against the interpreter then checks the
   hardware against exactly that arithmetic. *)

open Compiler

type expect =
  | Uart_on_pin of { pin : int; bit_cycles : int; bytes : int list }
  | Host_bytes of int list
  | Host_bytes_one_of of int list list   (* e.g. several flash vendors' JEDEC IDs *)
  | Spi_bytes of { sclk : int; mosi : int; cs : int; bytes : int list }
  | I2c_bytes of { sda : int; scl : int; bytes : int list; acks : bool list option }
  | Capture_uart of int list             (* sampler capture, timed mode, 10-bit frames *)
  | Trace_overflows                      (* the run must overflow the trace buffer *)

type test = {
  name : string;
  doc : string;
  mem : int array array;
  cycles : int;
  ctrl : int;
  cfg : (int * int) list;             (* extra configuration registers (index, value) *)
  host_in : int list;
  stream : (int * int) list;          (* stream buffer: (count, word) *)
  wiring : Env.wiring;                (* what the simulator attaches; the board must match *)
  needs : string list;                (* external parts or wires the board needs for this test *)
  board_only_lenient : bool;          (* on the board, outputs depend on when an external edge
                                         arrives relative to the clock (a wire into WAITP), so they
                                         may shift by a cycle; only the replay is exact then *)
  expects : expect list;
  forbid_flash_cmds_except : int list option;
}

let idle = Array.make Isa.prog_len Isa.halt
let image threads = Array.init Isa.n_threads (fun t -> match List.assoc_opt t threads with Some p -> p | None -> idle)

(* UART receiver on [pin], 8N1, bit_slots per bit (>= 8, even), bytes to the host with OUT.
   WAITP with a zero deadline and itself as the fail address is a plain wait. After the start edge
   is seen at slot s0: LDD a WAITD takes a+2 slots, LDC one, then each bit is LDD b WAITD SHI JNZ =
   b+4 = B slots, so SHI k (k = 1..8) lands at s0 + 6 + a + b + (k-1) B.
   Mid-bit k is s0 + B/2 + k B: b = B - 4 and a = B/2 - 2. The fail addresses 0 and 1 are the
   WAITPs themselves ("idle" is word 0, "start" is word 1). *)
let uart_rx ~pin ~bit_slots =
  let bs = bit_slots in
  assert (bs >= 8 && bs mod 2 = 0);
  let a = bs / 2 - 2 and b = bs - 4 in
  let items = [
    Label "idle";
    W (Isa.waitp ~pin ~value:1 ~fail:0);          (* wait for a high line (fail: self, fixed below) *)
    Label "start";
    W (Isa.waitp ~pin ~value:0 ~fail:1);          (* wait for the start edge *)
    W (Isa.ldd a); W Isa.waitd;
    W (Isa.ldc 8);
    Label "bit";
    W (Isa.ldd b); W Isa.waitd;
    W (Isa.shi ~pin ~msb:0);
    Jnz "bit";
    W Isa.out;
    Jmp "idle";
  ] in
  let prog, len = assemble items in
  prog, len

(* SPI read of [n_read] bytes after sending [cmd], mode 0, MSB first, period p slots (even, >= 12).
   Write bit (as Compiler.spi_master): SHO LDD a WAITD SETP(sclk 1) LDD b WAITD SETP(sclk 0) JNZ
   = a + b + 8 = p; high phase b + 3 = p/2. Read bit: LDD a' WAITD SETP(sclk 1) LDD c WAITD SHI
   LDD d WAITD SETP(sclk 0) JNZ = a' + c + d + 10 = p, high phase c + d + 6 = p/2, sampling c + 3
   slots after the rising edge, while the flash holds the bit it changed on the falling edge. *)
let spi_read ~sclk ~mosi ~cs ~miso ~p ~cmd ~n_read =
  assert (p >= 16 && p mod 2 = 0);
  let mk x = 1 lsl x in
  let b = p / 2 - 3 in
  let a = p - 8 - b in
  let c = (p / 2 - 6) / 2 in
  let d = p / 2 - 6 - c in
  let a' = p - 10 - c - d in
  let items = ref [] in
  let emit i = items := i :: !items in
  emit (W (Isa.setp ~mask:(mk cs) ~value:1 ~oe:1));
  emit (W (Isa.setp ~mask:(mk sclk lor mk mosi) ~value:0 ~oe:1));
  emit (W (Isa.lda cmd));
  emit (W (Isa.setp ~mask:(mk cs) ~value:0 ~oe:1));
  emit (W (Isa.ldc 8));
  emit (Label "wbit");
  emit (W (Isa.sho ~pin:mosi ~msb:1 ()));
  emit (W (Isa.ldd a)); emit (W Isa.waitd);
  emit (W (Isa.setp ~mask:(mk sclk) ~value:1 ~oe:1));
  emit (W (Isa.ldd b)); emit (W Isa.waitd);
  emit (W (Isa.setp ~mask:(mk sclk) ~value:0 ~oe:1));
  emit (Jnz "wbit");
  for k = 1 to n_read do
    let l = Printf.sprintf "rbit%d" k in
    emit (W (Isa.ldc 8));
    emit (Label l);
    emit (W (Isa.ldd a')); emit (W Isa.waitd);
    emit (W (Isa.setp ~mask:(mk sclk) ~value:1 ~oe:1));
    emit (W (Isa.ldd c)); emit (W Isa.waitd);
    emit (W (Isa.shi ~pin:miso ~msb:1));
    emit (W (Isa.ldd d)); emit (W Isa.waitd);
    emit (W (Isa.setp ~mask:(mk sclk) ~value:0 ~oe:1));
    emit (Jnz l);
    emit (W Isa.out)
  done;
  emit (W (Isa.setp ~mask:(mk cs) ~value:1 ~oe:1));
  emit (W Isa.halt);
  assemble (List.rev !items)

let ok_bytes = [ 0x4F; 0x4B; 0x21 ]   (* "OK!", as in demo.ml *)
let bit_slots = 16

let uart_pair ~ctrl ~wiring ~name ~doc ~needs ~lenient =
  let tx, _ = uart_tx { upin = 0; bit_slots; ubytes = ok_bytes; stretch = None } in
  let rx, _ = uart_rx ~pin:7 ~bit_slots in
  { name; doc; mem = image [ (0, tx); (1, rx) ]; cycles = 2600; ctrl; cfg = []; host_in = [];
    stream = []; wiring; needs; board_only_lenient = lenient;
    expects = [ Uart_on_pin { pin = 0; bit_cycles = bit_slots * slot; bytes = ok_bytes };
                Uart_on_pin { pin = 7; bit_cycles = bit_slots * slot; bytes = ok_bytes };
                Host_bytes ok_bytes ];
    forbid_flash_cmds_except = None }

(* demo.ml's three protocols on three threads, unchanged *)
let demo3 ~slave =
  let u, _ = uart_tx { upin = 0; bit_slots = 16; ubytes = ok_bytes; stretch = None } in
  let sp, _ = spi_master { sclk = 1; mosi = 2; cs = 3; period = 16; sbytes = [ 0xA5; 0x3C ] } in
  let ic, _ = i2c_write { sda = 4; scl = 5; q = 4; ibytes = [ 0xA0; 0x5A ] } in
  { name = (if slave then "demo3" else "demo3_noslave");
    doc = "demo.ml's UART, SPI and I2C programmes on three threads, header pins"
          ^ (if slave then ", with an acknowledging I2C slave on pins 4/5" else ", nothing on the I2C pins (NACKs)");
    mem = image [ (0, u); (1, sp); (2, ic) ]; cycles = 6000; ctrl = 0; cfg = []; host_in = []; stream = [];
    wiring = { Env.no_wiring with header_i2c_slave = slave };
    needs = (if slave then [ "i2c-slave-on-4-5" ] else []);
    board_only_lenient = false;
    expects = [ Uart_on_pin { pin = 0; bit_cycles = 64; bytes = ok_bytes };
                Spi_bytes { sclk = 1; mosi = 2; cs = 3; bytes = [ 0xA5; 0x3C ] };
                I2c_bytes { sda = 4; scl = 5; bytes = [ 0xA0; 0x5A ]; acks = (if slave then Some [ true; true ] else None) } ]
               @ (if slave then [ Host_bytes [ 0; 0 ] ] else []);
    forbid_flash_cmds_except = None }

(* The RTC on the ULX3S's I2C bus: an MCP7940N (0x6F) or, as the schematic's alternative part, a
   PCF8523 (0x68). The write only sets its register pointer: no register is changed. Quarter
   period 40 slots = 160 cycles, about 94 kHz at 60 MHz, inside both parts' 100 kHz standard mode. *)
let rtc ~name ~rtc_addr ~needs ~addr_byte ~bytes ~acks =
  let ic, _ = i2c_write { sda = 4; scl = 5; q = 40; ibytes = addr_byte :: bytes } in
  let n = 1 + List.length bytes in
  { name;
    doc = Printf.sprintf "I2C write to 0x%02x (7-bit 0x%02x) on the on-board RTC bus; expected %s" addr_byte (addr_byte lsr 1)
            (if List.for_all Fun.id acks then "acknowledged" else "not acknowledged (no device there)");
    mem = image [ (2, ic) ]; cycles = 700 + (n * 9 * 160 * 4) + 3000; ctrl = Env.ctrl_i2c; cfg = [];
    host_in = []; stream = []; wiring = { Env.no_wiring with rtc_addr }; needs; board_only_lenient = false;
    expects = [ I2c_bytes { sda = 4; scl = 5; bytes = addr_byte :: bytes; acks = Some acks };
                Host_bytes (List.map (fun a -> if a then 0 else 1) acks) ];
    forbid_flash_cmds_except = None }

(* JEDEC ID of the configuration flash, through USRMCLK on the board. The runner refuses to load
   any flash-routed programme whose command byte is not a read-only command. *)
(* flash.sch lists IS25LP128F (first), IS25LP032D, W25Q128JVSIM/JVSIQ and S25FL128L *)
let known_flash_ids = [ [ 0x9D; 0x60; 0x18 ] (* ISSI IS25LP128F *); [ 0x9D; 0x60; 0x16 ] (* ISSI IS25LP032D *);
                        [ 0xEF; 0x40; 0x18 ] (* Winbond W25Q128JV-IQ *); [ 0xEF; 0x70; 0x18 ] (* W25Q128JV-IM *);
                        [ 0x01; 0x60; 0x18 ] (* Cypress S25FL128L *) ]
let flash_id () =
  let prog, _ = spi_read ~sclk:1 ~mosi:2 ~cs:3 ~miso:6 ~p:24 ~cmd:0x9F ~n_read:3 in
  { name = "flash_id"; doc = "JEDEC READ ID (0x9F) from the configuration flash via USRMCLK";
    mem = image [ (0, prog) ]; cycles = 4 * 24 * 4 * 8 + 400; ctrl = Env.ctrl_flash; cfg = []; host_in = [];
    stream = []; wiring = Env.no_wiring; needs = []; board_only_lenient = false;
    expects = [ Spi_bytes { sclk = 1; mosi = 2; cs = 3; bytes = [ 0x9F ] }; Host_bytes_one_of known_flash_ids ];
    forbid_flash_cmds_except = Some [ 0x9F ] }

(* Streamer to sampler: UART bytes precomputed into streamer words (width 1), captured by the
   sampler in timed mode (trigger on the falling start edge, 10 vectors from mid start bit), with
   the internal loop or with jumpers from the streamer pins to the sampler pins. *)
let stream_bytes = [ 0x48; 0x69; 0x21 ]   (* "Hi!" *)
let stream_period = 64
let stream_words bytes =
  let bits = List.concat_map (fun b -> [ 1; 1; 0 ] @ List.init 8 (fun i -> (b lsr i) land 1) @ [ 1 ]) bytes @ [ 1; 1 ] in
  (* 16 vectors per word; a short last word carries its vector count *)
  let rec chunk acc = function
    | [] -> List.rev acc
    | l ->
      let n = min 16 (List.length l) in
      let w = List.fold_left (fun w (i, b) -> if i < n then w lor (b lsl i) else w) 0 (List.mapi (fun i b -> (i, b)) l) in
      chunk (((if n = 16 then 0 else n), w) :: acc) (List.filteri (fun i _ -> i >= n) l) in
  chunk [] bits

let stream ~loop =
  let words = stream_words stream_bytes in
  let p = stream_period in
  { name = (if loop then "stream_loop" else "stream_jumper");
    doc = "pin streamer sends \"Hi!\" as UART, pin sampler receives it (timed mode)"
          ^ (if loop then ", internal loop" else ", jumpers from streamer pins to sampler pins");
    mem = image []; cycles = (List.length words * 16 + 8) * p + 200;
    ctrl = (if loop then Env.ctrl_sloop else 0);
    cfg = [ (1, p); (2, 0x1101 (* idle_oe 1, idle_out 1, width 1 *)); (3, List.length words);
            (4, p); (5, p / 2 - 1); (6, (10 lsl 8) lor 0x01 (* frame 10, timed, trig pin 0 falling, width 1 *)) ];
    host_in = []; stream = words; wiring = Env.no_wiring;
    needs = (if loop then [] else [ "jumpers-streamer-to-sampler" ]); board_only_lenient = false;
    expects = [ Capture_uart stream_bytes ]; forbid_flash_cmds_except = None }

(* Pin 0 toggling as fast as one thread can (two edges every three slots), for longer than the
   2048-entry trace holds: the checker must see the overflow and check only the cycles before it. *)
let overflow () =
  let p = Array.make Isa.prog_len Isa.halt in
  p.(0) <- Isa.setp ~mask:1 ~value:1 ~oe:1; p.(1) <- Isa.setp ~mask:1 ~value:0 ~oe:1; p.(2) <- Isa.jmp 0;
  { name = "trace_overflow"; doc = "pin 0 toggles every slot for 20000 cycles; the 2048-entry trace must overflow";
    mem = image [ (0, p) ]; cycles = 20000; ctrl = 0; cfg = []; host_in = []; stream = [];
    wiring = Env.no_wiring; needs = []; board_only_lenient = false; expects = [ Trace_overflows ];
    forbid_flash_cmds_except = None }

(* Host bytes in through the host_in FIFO (IN), back out with OUT, and onto a pin as UART: the
   host_in path and IN's stall-until-valid semantics under replay. *)
let host_echo () =
  let bytes = [ 0x12; 0x34; 0x56; 0xA5 ] in
  let x = bit_slots - 4 in
  let items = [ W (Isa.setp ~mask:1 ~value:1 ~oe:1);
                Label "next"; W Isa.in_; W Isa.out;
                W (Isa.setp ~mask:1 ~value:0 ~oe:1); W (Isa.ldd x); W Isa.waitd; W (Isa.ldc 8);
                Label "bit"; W (Isa.sho ~pin:0 ~msb:0 ()); W (Isa.ldd x); W Isa.waitd; Jnz "bit";
                W (Isa.setp ~mask:1 ~value:1 ~oe:1); W (Isa.ldd x); W Isa.waitd; Jmp "next" ] in
  let p, _ = assemble items in
  { name = "host_echo"; doc = "bytes from the host through IN, back with OUT and out on pin 0 as UART";
    mem = image [ (0, p) ]; cycles = 3200; ctrl = 0; cfg = []; host_in = bytes; stream = [];
    wiring = Env.no_wiring; needs = []; board_only_lenient = false;
    expects = [ Host_bytes bytes; Uart_on_pin { pin = 0; bit_cycles = bit_slots * slot; bytes } ];
    forbid_flash_cmds_except = None }

(* Parts on the header (see BRINGUP.md for what to buy). An I2C EEPROM (24LC256 / AT24C256
   breakout, address 0x50): the write sends one of the two address-pointer bytes and stops, which
   writes nothing (a three-byte write does not fit in 64 words), at the
   same 94 kHz as the RTC test, because demo3's roughly 1 MHz bus is beyond a 24LC256's 400 kHz. *)
let eeprom () =
  let bytes = [ 0xA0; 0x00 ] in
  let ic, _ = i2c_write { sda = 4; scl = 5; q = 40; ibytes = bytes } in
  { name = "eeprom_ack"; doc = "I2C write of the first address byte (no data, so nothing is written) to a 24LC256 EEPROM (0x50) on header pins 4/5";
    mem = image [ (2, ic) ]; cycles = 700 + (2 * 9 * 160 * 4) + 3000; ctrl = 0; cfg = []; host_in = []; stream = [];
    wiring = { Env.no_wiring with header_i2c_slave = true; header_slave_addr = 0x50 };
    needs = [ "eeprom-on-4-5" ]; board_only_lenient = false;
    expects = [ I2c_bytes { sda = 4; scl = 5; bytes; acks = Some [ true; true ] }; Host_bytes [ 0; 0 ] ];
    forbid_flash_cmds_except = None }

(* A W25Q64 SPI flash breakout on the header: sclk 1, mosi 2, cs 3, miso 6, JEDEC ID read *)
let header_flash () =
  let prog, _ = spi_read ~sclk:1 ~mosi:2 ~cs:3 ~miso:6 ~p:24 ~cmd:0x9F ~n_read:3 in
  { name = "spi_flash_header"; doc = "JEDEC READ ID from a W25Q64 breakout on header pins 1 (sclk), 2 (mosi), 3 (cs), 6 (miso)";
    mem = image [ (0, prog) ]; cycles = 4 * 24 * 4 * 8 + 400; ctrl = 0; cfg = []; host_in = []; stream = [];
    wiring = { Env.no_wiring with header_flash = true }; needs = [ "w25q64-on-header" ]; board_only_lenient = false;
    expects = [ Spi_bytes { sclk = 1; mosi = 2; cs = 3; bytes = [ 0x9F ] };
                Host_bytes_one_of [ [ 0xEF; 0x40; 0x17 ] (* W25Q64JV-IQ *); [ 0xEF; 0x70; 0x17 ] (* W25Q64JV-IM *);
                                    [ 0xEF; 0x40; 0x18 ] (* W25Q128 fitted instead *) ] ];
    forbid_flash_cmds_except = None }

(* UART to a USB-serial adapter (CP2102 or FT232) at 115,384 baud: 130 slots per bit, 0.16 %
   from 115,200. The decoder checks the pin; the adapter's terminal should show the text. *)
let uart_adapter () =
  let text = List.map Char.code [ 'O'; 'K'; '!'; '\r'; '\n' ] in
  let tx, _ = uart_tx { upin = 0; bit_slots = 130; ubytes = text; stretch = None } in
  { name = "uart_adapter"; doc = "UART at 115,384 baud on header pin 0 into a USB-serial adapter (terminal shows OK!)";
    mem = image [ (0, tx) ]; cycles = (5 * 10 + 2) * 130 * 4 + 400; ctrl = 0; cfg = []; host_in = []; stream = [];
    wiring = Env.no_wiring; needs = [ "usb-serial-rx-on-0" ]; board_only_lenient = false;
    expects = [ Uart_on_pin { pin = 0; bit_cycles = 130 * 4; bytes = text } ]; forbid_flash_cmds_except = None }

let all () = [
  uart_pair ~ctrl:Env.ctrl_uloop ~wiring:Env.no_wiring ~name:"uart_loop" ~needs:[] ~lenient:false
    ~doc:"UART transmitter (thread 0, pin 0) into UART receiver (thread 1, pin 7) through the internal loop";
  uart_pair ~ctrl:0 ~wiring:{ Env.no_wiring with jumper_0_7 = true } ~name:"uart_jumper" ~needs:[ "jumper-0-7" ] ~lenient:true
    ~doc:"as uart_loop, through a wire from header seq pin 0 to seq pin 7";
  demo3 ~slave:false;
  demo3 ~slave:true;
  rtc ~name:"rtc_ack" ~rtc_addr:Env.rtc_mcp7940n ~needs:[] ~addr_byte:(Env.rtc_mcp7940n lsl 1) ~bytes:[ 0x00 ] ~acks:[ true; true ];
  rtc ~name:"rtc_ack_pcf8523" ~rtc_addr:Env.rtc_pcf8523 ~needs:[ "rtc-pcf8523" ] ~addr_byte:(Env.rtc_pcf8523 lsl 1) ~bytes:[ 0x00 ] ~acks:[ true; true ];
  rtc ~name:"rtc_nack" ~rtc_addr:Env.rtc_mcp7940n ~needs:[] ~addr_byte:0x90 ~bytes:[] ~acks:[ false ];
  flash_id ();
  stream ~loop:true;
  stream ~loop:false;
  overflow ();
  host_echo ();
  eeprom ();
  header_flash ();
  uart_adapter ();
]
