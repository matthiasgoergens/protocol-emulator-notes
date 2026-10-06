// The SRAM macro wrappers of src/tt_top.ml against the behaviour the core's lockstep assumed
// (Chip_rtl.behavioural_mem): the word at the address of clock k is on the output during clock
// k + 1, and a write in clock k shows its new data in clock k + 1 (write first). Random reads and
// writes, often to the same address back to back, on IHP's FUNCTIONAL model of each macro, with
// the wrapper's tie-offs (MEN 1, REN 1, BM all ones, DLY 1, BIST off). Run by sim/macro_check.sh.
`timescale 1ns/1ps
module check #(parameter ABITS = 9, parameter W = 16) ();
  reg clk = 0, we = 0;
  reg [ABITS-1:0] addr = 0;
  reg [W-1:0] din = 0;
  wire [W-1:0] dout;
  reg [W-1:0] ref_mem [0:(1<<ABITS)-1];
  reg [ABITS-1:0] addr_r;
  integer i, errors = 0, checks = 0;
  generate
    if (W == 16) begin : m
      RM_IHPSG13_1P_512x16_c2_bm_bist u (.A_CLK(clk), .A_MEN(1'b1), .A_WEN(we), .A_REN(1'b1), .A_ADDR(addr),
        .A_DIN(din), .A_DLY(1'b1), .A_DOUT(dout), .A_BM({W{1'b1}}), .A_BIST_CLK(1'b0), .A_BIST_EN(1'b0),
        .A_BIST_MEN(1'b0), .A_BIST_WEN(1'b0), .A_BIST_REN(1'b0), .A_BIST_ADDR({ABITS{1'b0}}),
        .A_BIST_DIN({W{1'b0}}), .A_BIST_BM({W{1'b0}}));
    end else begin : m
      RM_IHPSG13_1P_1024x8_c2_bm_bist u (.A_CLK(clk), .A_MEN(1'b1), .A_WEN(we), .A_REN(1'b1), .A_ADDR(addr),
        .A_DIN(din), .A_DLY(1'b1), .A_DOUT(dout), .A_BM({W{1'b1}}), .A_BIST_CLK(1'b0), .A_BIST_EN(1'b0),
        .A_BIST_MEN(1'b0), .A_BIST_WEN(1'b0), .A_BIST_REN(1'b0), .A_BIST_ADDR({ABITS{1'b0}}),
        .A_BIST_DIN({W{1'b0}}), .A_BIST_BM({W{1'b0}}));
    end
  endgenerate
  initial begin
    // fill every word first, so that no read sees an uninitialised word
    for (i = 0; i < (1 << ABITS); i = i + 1) begin
      addr = i; din = $random; we = 1; ref_mem[i] = din;
      #5 clk = 1; #5 clk = 0;
    end
    we = 0;
    for (i = 0; i < 200000; i = i + 1) begin
      // address: often the same as last clock, often the ends
      case ($random & 3) 0: ; 1: addr = (($random & 1) ? 0 : {ABITS{1'b1}}); default: addr = $random; endcase
      we = ($random & 3) == 0; din = $random;
      #5 clk = 1;
      addr_r = addr;
`ifndef CONTROL_READ_FIRST
      if (we) ref_mem[addr] = din;
`endif
      #1;
      if (dout !== ref_mem[addr_r]) begin
        errors = errors + 1;
        if (errors < 5) $display("%0d x %0d: clock %0d addr %0d dout %h expected %h", 1 << ABITS, W, i, addr_r, dout, ref_mem[addr_r]);
      end
`ifdef CONTROL_READ_FIRST
      if (we) ref_mem[addr_r] = din;   // control: a read-first expectation must fail
`endif
      checks = checks + 1;
      #4 clk = 0;
    end
    $display("%0d x %0d macro: %0d reads compared with the behavioural memory, %0d differ", 1 << ABITS, W, checks, errors);
  end
endmodule
module tb ();
  check #(.ABITS(9), .W(16)) prog ();
  check #(.ABITS(10), .W(8)) bank ();
endmodule
