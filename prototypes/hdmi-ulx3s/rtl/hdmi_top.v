// ULX3S HDMI (DVI) output, 640x480@60, test pattern.  Board-specific glue around the
// Hardcaml-generated modules in gen/: the PLL, resets, the output pads and the LEDs.
//
// Build variants (build.sh):
//   default         10:1 serialiser at 250 MHz, one bit per clock, plain output flip-flops
//   -DHDMI_DDR      5:1 serialiser at 125 MHz, two bits per clock into ODDRX1F (first bit on D0)
//
// Pins: gpdi_dp[3:0] = blue, green, red, clock (+ side).  The LPF makes them LVCMOS33D, so each
// pad pair is driven as a complementary pair by the I/O buffer and gpdi_dn needs no logic.
//
// wifi_gpio0 is tied high.  Gergo Erdi's ULX3S HDMI top (clash-flappysquare, ulx3s-hdmi branch,
// MIT) does this with the comment "keeps the board from rebooting".  We have not traced the
// mechanism on the schematic; it is copied as a known-good habit.
//
// LEDs: 0 blinks at 1 Hz from the 25 MHz pixel clock, 1 at 1 Hz from the bit clock; both must
// blink at 1 Hz and in step (Gergo's standing first check: see BRINGUP.md).  2 PLL locked,
// 3 serialiser armed, 4 serialiser slip (sticky; must stay off).
`default_nettype none
module hdmi_top (
  input  wire       clk_25mhz,
  output wire [7:0] led,
  output wire [3:0] gpdi_dp,
  output wire       wifi_gpio0
);
  assign wifi_gpio0 = 1'b1;

  wire clk_pix, clk_bit, locked;
`ifdef HDMI_DDR
  pll_hdmi_ddr pll (.clkin(clk_25mhz), .clkout0(clk_bit), .clkout1(clk_pix), .locked(locked));
`else
  pll_hdmi_sdr pll (.clkin(clk_25mhz), .clkout0(clk_bit), .clkout1(clk_pix), .locked(locked));
`endif

  // Synchronous clears, held for 16 cycles of each domain after the PLL locks.
  reg [4:0] por_pix = 0, por_bit = 0;
  reg [1:0] lock_pix = 0, lock_bit = 0;
  always @(posedge clk_pix) begin
    lock_pix <= {lock_pix[0], locked};
    por_pix <= lock_pix[1] ? (por_pix[4] ? por_pix : por_pix + 5'd1) : 5'd0;
  end
  always @(posedge clk_bit) begin
    lock_bit <= {lock_bit[0], locked};
    por_bit <= lock_bit[1] ? (por_bit[4] ? por_bit : por_bit + 5'd1) : 5'd0;
  end
  wire clear_pix = ~por_pix[4], clear_bit = ~por_bit[4];

  wire [9:0] word_b, word_g, word_r;
  wire toggle, led_pix;
  hdmi_pixel pixel (
    .clock(clk_pix), .clear(clear_pix),
    .word_b(word_b), .word_g(word_g), .word_r(word_r), .toggle(toggle), .led_1hz(led_pix));

  wire armed, slip, led_bit;
`ifdef HDMI_DDR
  wire [1:0] lane0, lane1, lane2, lane3;
  hdmi_serial_ddr serial (
`else
  wire lane0, lane1, lane2, lane3;
  hdmi_serial_sdr serial (
`endif
    .clock(clk_bit), .clear(clear_bit), .toggle(toggle),
    .word_b(word_b), .word_g(word_g), .word_r(word_r),
    .lane0(lane0), .lane1(lane1), .lane2(lane2), .lane3(lane3),
    .armed(armed), .slip(slip), .led_1hz(led_bit));

`ifdef HDMI_DDR
  // ODDRX1F: D0 leaves first (after the rising edge of SCLK), then D1.  Amaranth's ECP5 DDR
  // buffer maps its o[0] (the rising-edge value) to D0, and documents two cycles of latency.
  ODDRX1F ddr0 (.SCLK(clk_bit), .RST(1'b0), .D0(lane0[0]), .D1(lane0[1]), .Q(gpdi_dp[0]));
  ODDRX1F ddr1 (.SCLK(clk_bit), .RST(1'b0), .D0(lane1[0]), .D1(lane1[1]), .Q(gpdi_dp[1]));
  ODDRX1F ddr2 (.SCLK(clk_bit), .RST(1'b0), .D0(lane2[0]), .D1(lane2[1]), .Q(gpdi_dp[2]));
  ODDRX1F ddr3 (.SCLK(clk_bit), .RST(1'b0), .D0(lane3[0]), .D1(lane3[1]), .Q(gpdi_dp[3]));
`else
  // The serialiser's lane outputs are register outputs already; one more register per lane
  // keeps the path to the pad free of logic and lets the tools pack it into the I/O cell.
  reg [3:0] q = 0;
  always @(posedge clk_bit) q <= {lane3, lane2, lane1, lane0};
  assign gpdi_dp = q;
`endif

  assign led = {3'b000, slip, armed, locked, led_bit, led_pix};
endmodule
