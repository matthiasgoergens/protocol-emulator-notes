// Simulation stand-ins for the two ECP5-specific pieces of hdmi_top.v (simulation only).
`timescale 1ps/1ps

// The PLLs: ideal clocks.  PIX_PHASE_PS delays the pixel clock against the bit clock, so a run
// can put the pixel edge on a bit-clock edge (0, the race the synchroniser must survive) or
// between edges (what the real PLL's phase setting aims for).
module pll_hdmi_sdr #(parameter PIX_PHASE_PS = 0) (input clkin, output reg clkout0 = 0, output reg clkout1 = 0, output reg locked = 0);
  initial begin #100000 locked = 1; end
  always #2000 clkout0 = ~clkout0;
  initial begin #(PIX_PHASE_PS); forever #20000 clkout1 = ~clkout1; end
endmodule

module pll_hdmi_ddr #(parameter PIX_PHASE_PS = 0) (input clkin, output reg clkout0 = 0, output reg clkout1 = 0, output reg locked = 0);
  initial begin #100000 locked = 1; end
  always #4000 clkout0 = ~clkout0;
  initial begin #(PIX_PHASE_PS); forever #20000 clkout1 = ~clkout1; end
endmodule

// ODDRX1F as Amaranth's ECP5 DDR buffer describes it: D0 and D1 sampled on the rising edge of
// SCLK, D0 driven for the high half of the period and D1 for the low half, two cycles later.
// (The latency only shifts all lanes equally; the D0-first order is what matters.)
module ODDRX1F (input SCLK, input RST, input D0, input D1, output Q);
  reg a0 = 0, a1 = 0, b0 = 0, b1 = 0;
  always @(posedge SCLK) begin a0 <= D0; a1 <= D1; b0 <= a0; b1 <= a1; end
`ifdef ODDR_SWAP
  assign Q = SCLK ? b1 : b0;   // negative control: wrong bit order
`else
  assign Q = SCLK ? b0 : b1;
`endif
endmodule
