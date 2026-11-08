/*
 * SPDX-License-Identifier: Apache-2.0
 * The FPGA stand-in (../rtl/sram_fpga.v) against IHP's behavioural SRAM model
 * (IHP-Open-PDK libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v), both
 * with the chip's ties (MEN, REN = 1, BM all ones, no BIST), under random reads and writes,
 * write-throughs included. Compared every clock once the model's word is defined (the model
 * starts unknown, the stand-in at zero), after a first pass that writes every address.
 *   +seed=N  +clocks=N
 */

`timescale 1ns / 1ps
`default_nettype none

module tb_sram_equiv;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg we16 = 0, we8 = 0;
  reg [8:0] a16 = 0;
  reg [9:0] a8 = 0;
  reg [15:0] d16 = 0;
  reg [7:0] d8 = 0;
  wire [15:0] q16_ihp, q16_fpga;
  wire [7:0] q8_ihp, q8_fpga;

  SRAM_1P_behavioral_bm_bist #(.P_DATA_WIDTH(16), .P_ADDR_WIDTH(9)) ihp16 (
      .A_ADDR(a16), .A_DIN(d16), .A_BM(16'hFFFF), .A_MEN(1'b1), .A_WEN(we16), .A_REN(1'b1),
      .A_CLK(clk), .A_DLY(1'b1), .A_DOUT(q16_ihp), .A_BIST_EN(1'b0), .A_BIST_ADDR(9'd0),
      .A_BIST_DIN(16'd0), .A_BIST_BM(16'd0), .A_BIST_MEN(1'b0), .A_BIST_WEN(1'b0),
      .A_BIST_REN(1'b0), .A_BIST_CLK(1'b0));
  SRAM_1P_behavioral_bm_bist #(.P_DATA_WIDTH(8), .P_ADDR_WIDTH(10)) ihp8 (
      .A_ADDR(a8), .A_DIN(d8), .A_BM(8'hFF), .A_MEN(1'b1), .A_WEN(we8), .A_REN(1'b1),
      .A_CLK(clk), .A_DLY(1'b1), .A_DOUT(q8_ihp), .A_BIST_EN(1'b0), .A_BIST_ADDR(10'd0),
      .A_BIST_DIN(8'd0), .A_BIST_BM(8'd0), .A_BIST_MEN(1'b0), .A_BIST_WEN(1'b0),
      .A_BIST_REN(1'b0), .A_BIST_CLK(1'b0));
  sram_fpga_1p #(.AW(9), .DW(16)) fpga16 (.clk(clk), .we(we16), .addr(a16), .din(d16), .dout(q16_fpga));
  sram_fpga_1p #(.AW(10), .DW(8)) fpga8 (.clk(clk), .we(we8), .addr(a8), .din(d8), .dout(q8_fpga));

  integer seed = 1, clocks = 200000, i, compared = 0, writes = 0, bad = 0;
  initial begin
    void'($value$plusargs("seed=%d", seed));
    void'($value$plusargs("clocks=%d", clocks));
    // fill every address once, so that the model's words are defined
    for (i = 0; i < 1024; i = i + 1) begin
      @(negedge clk);
      we16 = i < 512; a16 = i[8:0]; d16 = $random(seed);
      we8 = 1; a8 = i[9:0]; d8 = $random(seed);
    end
    for (i = 0; i < clocks; i = i + 1) begin
      @(negedge clk);
      if (q16_ihp !== q16_fpga || q8_ihp !== q8_fpga) begin
        bad = bad + 1;
        if (bad <= 5) $display("clock %0d: 512x16 ihp %h fpga %h; 1024x8 ihp %h fpga %h", i, q16_ihp, q16_fpga, q8_ihp, q8_fpga);
      end
      compared = compared + 1;
      // writes a third of the time; small address ranges, so a write is often read back at once
      we16 = ($random(seed) % 3) == 0; a16 = $random(seed) % 16; d16 = $random(seed);
      we8 = ($random(seed) % 3) == 0; a8 = $random(seed) % 16; d8 = $random(seed);
      writes = writes + we16 + we8;
    end
    $display("sram equivalence: %0d clocks compared, %0d writes, %0d differ: %s", compared, writes, bad,
             bad == 0 ? "PASS" : "FAIL");
    $finish(bad == 0 ? 0 : 1);
  end
endmodule
