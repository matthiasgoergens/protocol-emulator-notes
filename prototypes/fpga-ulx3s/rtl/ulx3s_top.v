// ULX3S (ECP5-85F) top level for the emulator test bench.
//
// Clocks: the 25 MHz oscillator into one EHXPLLL giving 60 MHz (sequencer, streamer, sampler,
// host link, the chip's target clock) and 48 MHz (USB full-speed device, 4 samples per bit).
//
// Pins (constraints/ulx3s.lpf, names as in emard/ulx3s ulx3s_v20.lpf):
//   gp[0..7]  sequencer pins 0..7, bidirectional, weak pull-ups
//   gn[0..3]  pin streamer outputs 0..3
//   gn[4..7]  pin sampler inputs 0..3 (jumper gn[k] to gn[k+4] for the external stream loop)
//   ftdi_txd / ftdi_rxd  host link through the FT231X on US1, 1 Mbaud 8N1
//   flash_*   configuration flash; its clock pin is reached through USRMCLK
//   gpdi_sda / gpdi_scl  I2C bus shared with the MCP7940N RTC (and the GPDI connector's DDC)
//   usb_fpga_bd_dp / _dn  US2, bidirectional single-ended; usb_fpga_pu_dp  1.5k pull-up on D+
//   led[7:0]  0 heartbeat, 1 running, 2 trace overflow, 3 host link activity,
//             4 USB configured, 5 PLL locked, 6 USB address nonzero, 7 flash route on
//   btn[1] (FIRE1)  reset
`default_nettype none

module ulx3s_top (
  input  wire clk_25mhz,
  input  wire ftdi_txd,       // FPGA receives
  output wire ftdi_rxd,       // FPGA transmits
  input  wire [6:0] btn,
  output wire [7:0] led,
  inout  wire [7:0] gp,
  inout  wire [7:0] gn,
  output wire flash_csn,
  output wire flash_mosi,
  input  wire flash_miso,
  output wire flash_holdn,
  output wire flash_wpn,
  inout  wire gpdi_sda,
  inout  wire gpdi_scl,
  inout  wire usb_fpga_bd_dp,
  inout  wire usb_fpga_bd_dn,
  output wire usb_fpga_pu_dp,
  output wire usb_fpga_pu_dn,
  output wire wifi_en
);
  // ------------------------------------------------------------------ clocks and resets
  wire clk60, clk48, locked;
  pll_60_48 pll (.reset(1'b0), .clk25(clk_25mhz), .clk60(clk60), .clk48(clk48), .locked(locked));

  wire rst_async = !locked | btn[1];
  reg [3:0] rst60_sr = 4'hF, rst48_sr = 4'hF;
  always @(posedge clk60 or posedge rst_async)
    if (rst_async) rst60_sr <= 4'hF; else rst60_sr <= {rst60_sr[2:0], 1'b0};
  always @(posedge clk48 or posedge rst_async)
    if (rst_async) rst48_sr <= 4'hF; else rst48_sr <= {rst48_sr[2:0], 1'b0};
  wire rst60 = rst60_sr[3], rst48 = rst48_sr[3];

  // the ESP32 is not used; hold it in reset so it cannot drive shared pins
  assign wifi_en = 1'b0;

  // ------------------------------------------------------------------ the core
  wire [7:0] seq_out, seq_oe;
  wire [3:0] str_out, str_oe;
  wire spi_sclk, spi_mosi, spi_csn, sda_low, scl_low;
  wire [15:0] ctrl;
  wire running, trace_ovf, activity;
  reg  [7:0] usb_status_s1 = 8'd0, usb_status_s2 = 8'd0;
  wire [7:0] usb_status;

  emu_core #(.CLKS_PER_BIT(60), .TRACE_AW(11)) core (
    .clk(clk60), .rst(rst60),
    .uart_rx(ftdi_txd), .uart_tx(ftdi_rxd),
    .seq_pad_in(gp), .seq_pad_out(seq_out), .seq_pad_oe(seq_oe),
    .aux_spi_sclk(spi_sclk), .aux_spi_mosi(spi_mosi), .aux_spi_csn(spi_csn), .aux_spi_miso(flash_miso),
    .aux_sda_low(sda_low), .aux_scl_low(scl_low), .aux_sda_in(gpdi_sda), .aux_scl_in(gpdi_scl),
    .str_pad_out(str_out), .str_pad_oe(str_oe), .smp_pad_in(gn[7:4]),
    .board_status(usb_status_s2), .ctrl(ctrl),
    .running_o(running), .trace_ovf_o(trace_ovf), .host_activity(activity));

  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : seq_pads
      assign gp[i] = seq_oe[i] ? seq_out[i] : 1'bz;
    end
    for (i = 0; i < 4; i = i + 1) begin : str_pads
      assign gn[i] = str_oe[i] ? str_out[i] : 1'bz;
    end
  endgenerate
  // gn[7:4] are inputs only: never driven

  // ------------------------------------------------------------------ configuration flash
  // The flash's clock is the dedicated configuration clock pin, reachable only through USRMCLK.
  // Chip select stays high unless the host routes the sequencer to the flash (ctrl bit 0), and
  // the runner refuses any flash-routed programme that would send a non-read command.
  USRMCLK usrmclk (.USRMCLKI(spi_sclk), .USRMCLKTS(1'b0));
  assign flash_csn = spi_csn;
  assign flash_mosi = spi_mosi;
  assign flash_holdn = 1'b1;
  assign flash_wpn = 1'b1;

  // ------------------------------------------------------------------ RTC I2C bus, open drain
  assign gpdi_sda = sda_low ? 1'b0 : 1'bz;
  assign gpdi_scl = scl_low ? 1'b0 : 1'bz;

  // ------------------------------------------------------------------ USB full-speed device on US2
  wire usb_dp_out, usb_dm_out, usb_oe, usb_configured;
  wire [6:0] usb_addr;
  usb_fs_device usb (
    .clock(clk48), .clear(rst48),
    .dp_in(usb_fpga_bd_dp), .dm_in(usb_fpga_bd_dn),
    .dp_out(usb_dp_out), .dm_out(usb_dm_out), .oe(usb_oe),
    .addr(usb_addr), .configured(usb_configured));
  assign usb_fpga_bd_dp = usb_oe ? usb_dp_out : 1'bz;
  assign usb_fpga_bd_dn = usb_oe ? usb_dm_out : 1'bz;
  // attach: 1.5k pull-up on D+ signals a full-speed device (ctrl bit 4, on after reset)
  assign usb_fpga_pu_dp = ctrl[4] ? 1'b1 : 1'bz;
  assign usb_fpga_pu_dn = 1'bz;
  assign usb_status = {usb_configured, usb_addr};
  always @(posedge clk60) begin usb_status_s1 <= usb_status; usb_status_s2 <= usb_status_s1; end

  // ------------------------------------------------------------------ LEDs
  reg [25:0] heartbeat = 26'd0;
  always @(posedge clk60) heartbeat <= heartbeat + 26'd1;
  assign led = {ctrl[0], usb_status_s2[6:0] != 7'd0, locked, usb_status_s2[7], activity, trace_ovf, running, heartbeat[25]};
endmodule

`default_nettype wire
