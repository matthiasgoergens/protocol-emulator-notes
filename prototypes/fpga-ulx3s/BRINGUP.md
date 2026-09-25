# ULX3S bring-up checklist

Everything here runs from `prototypes/fpga-ulx3s/`. Nothing has touched a real board yet. The
expected outputs below are what the Verilator model of the same RTL produced (`evidence/`) or what
the ULX3S schematic says. Anything marked *unverified* is a guess that the board should settle.

## 0. Before the board arrives (done, repeat after any change)

- Toolchain: `export PATH=~/prog/janestreet/fabulous-notes/oss-cad-suite/bin:$PATH`.
- Checker: `cd ocaml && opam exec --switch=5.3.0 -- dune build`.
- Simulated board: `sim/build.sh 60` (the board's divider, 60 clocks per UART bit) and `sim/build.sh 8` (fast).
- `uv run host/emu_runner.py --sim --cpb 60 --controls` should end with `18 of 18 as expected`.
  The two controls must *fail*: one flips a bit in a captured trace, the other loads a programme
  one bit different from the one the checker replays. The second one still decodes "OK!" perfectly,
  so only the cycle-by-cycle replay catches it.
- Bitstream: `bitstream/ulx3s_85f.bit` (sha256 in `bitstream/ulx3s_85f.bit.sha256`), or rebuild
  with `./build.sh` (a few minutes). With the same tool versions and nextpnr seed the rebuild
  has been bit-identical, so the hash should match.

## 1. Host setup (once)

- udev rules, so neither programming nor the serial port needs root:
  ```
  # /etc/udev/rules.d/80-ulx3s.rules
  SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", MODE="0664", GROUP="plugdev"
  SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", MODE="0664", GROUP="dialout"
  # the gateware USB device on US2 (pid.codes test ID)
  SUBSYSTEM=="usb", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="0001", MODE="0666"
  ```
  Then `sudo udevadm control --reload-rules && sudo udevadm trigger`, and add yourself to `plugdev`
  and `dialout`.
- 0403:6015 is the FT231X on US1. openFPGALoader lists the `ulx3s` board on the `ft231X` cable
  (0x0403:6015), which is how it finds it.

## 2. Board inspection (unpowered)

Read the markings. They decide which test variants apply:

- the FPGA is `LFE5U-85F`: the bitstream is for the 85F only;
- the flash is IS25LP128F on the schematic's first line, with IS25LP032D, W25Q128JV and S25FL128L
  as alternates. `flash_id` accepts any of their JEDEC IDs, and the marking says which one to expect;
- the RTC is MCP7940N (address 0x6F) or PCF8523 (address 0x68). The schematic lists both.
  `rtc_ack` assumes the MCP7940N; on a PCF8523 board run `--have rtc-pcf8523 --only rtc_ack_pcf8523`;
- whether the GPIO headers are populated (if not, solder them before steps 7 onwards).

## 3. First power and programming (SRAM only)

Plug US1 (the FTDI port, next to the power circuitry) into the PC.

```
openFPGALoader --board ulx3s --detect
openFPGALoader --board ulx3s bitstream/ulx3s_85f.bit       # SRAM: lost at power-off
```

- `--detect` should report a Lattice ECP5 LFE5U-85. The IDCODE should be 0x41113043 (*from
  memory; unverified*).
- Do **not** use `--write-flash` until everything below works. SRAM loading cannot brick
  anything, and a power cycle restores the factory image.
- LEDs after loading: LED 5 on (PLL locked); LED 0 blinks with a period of 1.12 s (bit 25 of a
  60 MHz counter, so the blink also measures the PLL); LED 1 off (not running); LED 7 off (flash
  not routed). With nothing on US2, LED 4 is off.
- If LED 5 is off, the PLL did not lock. Rebuild with `ecppll`'s own 60/50 MHz dividers to tell
  the hand-edited 48 MHz dividers apart from a board problem.
- **Checkpoint:** the heartbeat blinks at the right period, so the clock tree and the bitstream work.

## 4. Host link

```
uv run host/emu_runner.py --port /dev/ttyUSB0 --only uart_loop
```

- The runner first sends `I` and prints `identify: {'trace_aw': 11, 'ctrl': 16}`. That proves
  the 1 Mbaud UART both ways and the command engine.
- If `identify` times out, check `ftdi_txd` and `ftdi_rxd` (L4 is the FPGA's output, M1 its input,
  per the LPF comments). Also check the baud rate: 1,000,000 is 3 MHz / 3 on the FT231X, and
  60 MHz / 60 on the FPGA.
- pyserial raises DTR and RTS when it opens the port. The FPGA ignores them (`ftdi_ndtr` and
  `ftdi_nrts` are not in the design).

## 5. Tests that need nothing but the board

Run them all with `uv run host/emu_runner.py --port /dev/ttyUSB0`. Tests that need parts are
skipped and listed. Each test writes `results/<time>-board/<test>.trace`, `.capture` and
`.check.txt`.

| Test | What it proves | Expected |
| --- | --- | --- |
| `uart_loop` | Instruction memory load and readback; cycle-exact execution (replay); the trace recorder; thread 0 transmits and thread 1 receives through the internal loop | replay PASS on 2,600 cycles; "OK!" decoded on pins 0 and 7; host bytes 4f 4b 21 |
| `host_echo` | The host-to-core byte path: the FIFO, IN stalling until data arrives, OUT | host bytes 12 34 56 a5, and the same bytes as UART on pin 0 |
| `trace_overflow` | Truncation: the recorder stops cleanly at 2,048 entries and the checker checks only the recorded prefix | overflow reported; replay PASS on the first 6,145 cycles; LED 2 lights |
| `stream_loop` | Pin streamer and pin sampler at speed, internal loop | sampler decodes 48 69 21 ("Hi!") |
| `rtc_nack` | The real I2C bus and the open-drain drive; a NACK from an empty address (control) | byte 90, NACK; host byte 01 |
| `rtc_ack` | A real I2C device acknowledging: address 0x6F plus one register-pointer byte, nothing written | bytes de 00, both ACKed; host bytes 00 00 |
| `flash_id` | USRMCLK and the configuration-flash route, SPI read with MISO sampled by SHI | one of the known JEDEC IDs, e.g. 9d 60 18 for IS25LP128F |
| `demo3_noslave` | demo.ml's three programmes, on the header pins | UART "OK!", SPI a5 3c, I2C a0 5a with NACKs (no slave) |

The checker's verdicts on the board:

1. **replay** must pass exactly. The interpreter, fed the pins the core actually saw, must
   produce every output on every cycle. A failure here is an RTL, synthesis or timing problem on
   the FPGA, and the first differing cycle says where.
2. **prediction (outputs)** compares the pins and the moments bytes appear with the OCaml board
   model. It must pass except for `uart_jumper`, where a real wire can move an edge across a
   clock boundary. Byte *values* can legitimately differ (a different flash ID); those are
   judged by the replay and the expectations.
3. **decoders and expectations**: the protocols, read off the pins by
   `deadline-sequencer/decoders.ml`.

**Flash safety.** The flash holds the board's configuration once anything is written with
`--write-flash`. Its chip select stays high unless a test sets the flash route. The runner then
refuses any programme whose command bytes, as the OCaml model predicts them, are not on that test's
read-only allow-list (`flash_id`: only 0x9F). Behind that, an interlock in the RTL cuts off any
first byte that is not a read command (0x9F, 0x03, 0x0B, 0x05) before its eighth bit, and lights
LED 7. `flash_interlock` exercises it in simulation only; the runner will not run it on the board.

**I2C pull-ups (open question).** The RTC tests rely on pull-ups on the RTC's I2C bus. The FPGA
pads add weak ones. The schematic has 4.7 k resistors to +5 V on the HDMI side of the DDC lines,
but I have not traced which resistors sit on the RTC's side. If `rtc_nack` reads an ACK, or
`rtc_ack` shows a missing START, look at SDA and SCL rise times with the scope (on the GPDI
connector's DDC pins, or at the RTC).

## 6. USB full-speed device (US2)

Plug a second cable into US2 (the connector wired to FPGA pins). The design attaches (the D+
pull-up) after reset.

- `dmesg -w` should show a new full-speed device; `lsusb -d 1209:0001` lists it; LED 4
  (configured) lights once Linux sets the configuration, and LED 6 once it has an address.
- `uv run host/usb_check.py` checks the descriptors and runs 8 loopback rounds on endpoint 1.
  Expect `USB PASS`. This is the first test of the USB engine against a real host; so far it has
  only met `usb-fs-device/host.ml`. *Untested script.*
- If enumeration fails: `dmesg` says at which stage (`device descriptor read/64, error -71` means
  no valid reply at all). Things to check: the pull-up (`usb_fpga_pu_dp` driven high; on the
  schematic it goes through 1.1 k and a diode to D+), the direction of the bidirectional pads,
  and the 48 MHz clock (LED 0's period checks 60 MHz only; both come from one PLL).

## 7. Wires and cheap parts

Pass what is fitted with `--have` (comma-separated):

| `--have` | Wiring | Test | Expected |
| --- | --- | --- | --- |
| `jumper-0-7` | wire GP0 to GP7 | `uart_jumper` | as `uart_loop`, through a real wire; the prediction may move by a cycle, the replay may not |
| `jumpers-streamer-to-sampler` | GN0-GN4, GN1-GN5, GN2-GN6, GN3-GN7 | `stream_jumper` | "Hi!" through real pads |
| `eeprom-on-4-5` | 24LC256 / AT24C256 breakout: SDA to GP4, SCL to GP5, 3.3 V, GND, pull-ups on the breakout or 4.7 k to 3.3 V | `eeprom_ack` | a0 00, both ACKed |
| `w25q64-on-header` | W25Q64 breakout: CLK GP1, DI GP2, CS GP3, DO GP6, 3.3 V, GND, /WP and /HOLD to 3.3 V | `spi_flash_header` | ef 40 17 |
| `usb-serial-rx-on-0` | CP2102 or FT232 adapter RX to GP0, GND to GND; terminal at 115200 8N1 on the adapter's port | `uart_adapter` | the terminal shows `OK!`; the decoder agrees |
| `i2c-slave-on-4-5` | any I2C slave acknowledging 0xA0 at about 1 MHz (a 24FC256; a 24LC256 is rated to 400 kHz only) | `demo3` | acks on both bytes |

Everything is 3.3 V: nothing 5 V on any pin. Silkscreen labels GP0 to GP7 and GN0 to GN7 name the pins.
The J1 and J2 pin numbers depend on the header style (the schematic swaps odd and even between
angled female and vertical male headers), so go by the silkscreen, not by the number.

## 8. Capturing pin traces

Three ways, from most to least exact:

1. **The trace recorder (built in).** Every test already records it: what the core saw on its
   inputs (after the two-flop synchroniser) and drove on its outputs, cycle-exact at 60 MHz, up to
   2,048 changes per run. `results/.../<test>.trace` is plain text; `ocaml/_build/default/fpga_tests.exe
   predict <test>` writes the model's expectation in the same format, so `diff` shows the first
   divergence.
2. **The pin sampler reading back real pins.** Wire GPk to GN(4+k) and configure the sampler in
   timed mode with period 1. It captures up to 256 words of four pins, 1,024 cycles at width 4.
   This is the sampler looking at the pads from the outside, not the core's own view. No test
   does this yet; it needs a runner option for the sampler registers.
3. **A cheap logic analyser** (8 channels, 24 MS/s, fx2lafw, sigrok/PulseView) on the header:
   `sigrok-cli --driver fx2lafw --config samplerate=24m --channels D0-D7 --time 20ms -o run.sr`,
   then the uart, spi and i2c decoders in PulseView. At 24 MS/s it cannot resolve 60 MHz cycles,
   but it does see the protocols (≤ 1 MHz here), and it is independent of everything on the FPGA:
   the check that the recorder is not fooling us.

## 9. Only then: the flash

When everything above passes: `openFPGALoader --board ulx3s --write-flash --verify
bitstream/ulx3s_85f.bit`, power-cycle, repeat step 5.

## 10. Four-phase variant

`./build_multiphase.sh` builds sequencer pins 0 and 1 through `prototypes/multiphase`'s stage
(to `/var/tmp/fpga-ulx3s/build-mp/ulx3s_mp.bit`). Load it like the base bitstream. The quarter-clock
edges (4.17 ns apart at 60 MHz) need an oscilloscope of at least 350 MHz; a 24 MS/s logic analyser
cannot see them. See README, "Four-phase output stage on the ECP5".
