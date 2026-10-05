// ULX3S HDMI (DVI) output, 640x480@60, stand-alone bitstream: hdmi_out.v (the PLL, resets, the
// Hardcaml-generated modules in gen/ and the output registers) plus the board's LEDs and
// wifi_gpio0.
//
// Build variants (build.sh):
//   default         10:1 serialiser at 250 MHz, one bit per clock, plain output flip-flops
//   -DHDMI_DDR      5:1 serialiser at 125 MHz, two bits per clock into ODDRX1F (first bit on D0)
//   -DHDMI_DEMO     the retro console's game (demo/console_hdmi.ml) instead of the test pattern
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
  wire [4:0] status;
  hdmi_out hdmi (.clk_25mhz(clk_25mhz), .gpdi_dp(gpdi_dp), .status(status));
  assign led = {3'b000, status};
endmodule
