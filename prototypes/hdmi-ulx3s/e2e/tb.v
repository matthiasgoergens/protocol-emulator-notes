// End-to-end testbench: hdmi_top with ideal clocks, the serial lanes sampled once per bit time
// and written to a file, one hex digit per bit time (bit i = gpdi_dp[i]).
`timescale 1ps/1ps
module tb;
  reg clk_25mhz = 0;
  wire [7:0] led;
  wire [3:0] gpdi_dp;
  wire wifi_gpio0;
  hdmi_top dut (.clk_25mhz(clk_25mhz), .led(led), .gpdi_dp(gpdi_dp), .wifi_gpio0(wifi_gpio0));
  defparam dut.pll.PIX_PHASE_PS = `PIX_PHASE_PS;
  integer f, n;
  // One bit time is 4 ns in both variants.  Sample in the middle of each: the SDR outputs change
  // on bit-clock rising edges (2 ns mod 4 ns), the DDR outputs on both edges (0 mod 4 ns).
  localparam BIT_PS = 4000;
`ifdef HDMI_DDR
  localparam START_PS = 202000;
`else
  localparam START_PS = 200000;
`endif
  initial begin
    f = $fopen(`CAPTURE, "w");
    #(START_PS);
    for (n = 0; n < `BITS; n = n + 1) begin
      $fwrite(f, "%h", gpdi_dp);
      #(BIT_PS);
    end
    $fclose(f);
    $display("leds %b wifi_gpio0 %b", led, wifi_gpio0);
    $finish;
  end
endmodule
