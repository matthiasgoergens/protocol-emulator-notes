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
  board_only_lenient : bool;          (* on the board, input-dependent outputs may shift in time *)
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

let uart_pair ~ctrl ~wiring ~name ~doc ~needs =
  let tx, _ = uart_tx { upin = 0; bit_slots; ubytes = ok_bytes; stretch = None } in
  let rx, _ = uart_rx ~pin:7 ~bit_slots in
  { name; doc; mem = image [ (0, tx); (1, rx) ]; cycles = 2600; ctrl; cfg = []; host_in = [];
    stream = []; wiring; needs; board_only_lenient = true;
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
    board_only_lenient = true;
    expects = [ Uart_on_pin { pin = 0; bit_cycles = 64; bytes = ok_bytes };
                Spi_bytes { sclk = 1; mosi = 2; cs = 3; bytes = [ 0xA5; 0x3C ] };
                I2c_bytes { sda = 4; scl = 5; bytes = [ 0xA0; 0x5A ]; acks = (if slave then Some [ true; true ] else None) } ]
               @ (if slave then [ Host_bytes [ 0; 0 ] ] else []);
    forbid_flash_cmds_except = None }

(* The RTC (MCP7940N, 7-bit address 0x6F) on the ULX3S's I2C bus. The write only sets its register
   pointer: no register is changed. Quarter period 40 slots = 160 cycles, about 94 kHz at 60 MHz,
   inside the part's 100 kHz standard mode. *)
let rtc ~addr_byte ~bytes ~acks =
  let ic, _ = i2c_write { sda = 4; scl = 5; q = 40; ibytes = addr_byte :: bytes } in
  let n = 1 + List.length bytes in
  { name = (if List.for_all Fun.id acks then "rtc_ack" else "rtc_nack");
    doc = Printf.sprintf "I2C write to 0x%02x on the on-board RTC bus; expected %s" addr_byte
            (if List.for_all Fun.id acks then "acknowledged (MCP7940N at 0x6F)" else "not acknowledged (no device)");
    mem = image [ (2, ic) ]; cycles = 700 + (n * 9 * 160 * 4) + 3000; ctrl = Env.ctrl_i2c; cfg = [];
    host_in = []; stream = []; wiring = Env.no_wiring; needs = []; board_only_lenient = true;
    expects = [ I2c_bytes { sda = 4; scl = 5; bytes = addr_byte :: bytes; acks = Some acks };
                Host_bytes (List.map (fun a -> if a then 0 else 1) acks) ];
    forbid_flash_cmds_except = None }

(* JEDEC ID of the configuration flash, through USRMCLK on the board. The runner refuses to load
   any flash-routed programme whose command byte is not a read-only command. *)
let known_flash_ids = [ [ 0xEF; 0x40; 0x18 ] (* Winbond W25Q128JV *); [ 0x9D; 0x60; 0x18 ] (* ISSI IS25LP128 *);
                        [ 0xEF; 0x70; 0x18 ] (* W25Q128JV-M *); [ 0xC2; 0x20; 0x18 ] (* Macronix MX25L128 *);
                        [ 0x20; 0xBA; 0x18 ] (* Micron N25Q128 *) ]
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

let all () = [
  uart_pair ~ctrl:Env.ctrl_uloop ~wiring:Env.no_wiring ~name:"uart_loop" ~needs:[]
    ~doc:"UART transmitter (thread 0, pin 0) into UART receiver (thread 1, pin 7) through the internal loop";
  uart_pair ~ctrl:0 ~wiring:{ Env.no_wiring with jumper_0_7 = true } ~name:"uart_jumper" ~needs:[ "jumper-0-7" ]
    ~doc:"as uart_loop, through a wire from header seq pin 0 to seq pin 7";
  demo3 ~slave:false;
  demo3 ~slave:true;
  rtc ~addr_byte:(Env.rtc_address lsl 1) ~bytes:[ 0x00 ] ~acks:[ true; true ];
  rtc ~addr_byte:0x90 ~bytes:[] ~acks:[ false ];
  flash_id ();
  stream ~loop:true;
  stream ~loop:false;
]
