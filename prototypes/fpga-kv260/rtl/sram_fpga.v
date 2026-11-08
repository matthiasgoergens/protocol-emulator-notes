/*
 * SPDX-License-Identifier: Apache-2.0
 * FPGA stand-ins for the chip's two IHP SRAM macros, under the macros' own module names so that
 * the generated chip_tt.v is used unchanged.
 *
 * What they reproduce, from the PDK's behavioural model (IHP-Open-PDK,
 * libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v): one port, read and
 * write on the rising edge of A_CLK, the read data registered (one clock of latency), and a
 * write with A_REN set is a write-through (A_DOUT shows the new word). The chip ties A_MEN,
 * A_REN and A_DLY to 1, the bit mask A_BM to all ones and A_BIST_EN to 0 (tt/src/chip_tt.v),
 * so these models implement only that case; a simulation stops if any of those ties changes.
 * That case is a plain write-first block RAM, which Vivado and Yosys infer as such.
 *
 * Not reproduced: the macro's contents at power-up (unknown on the chip, zero here); the host
 * loads every word it uses before running.
 */

`default_nettype none

module sram_fpga_1p #(
    parameter integer AW = 9,
    parameter integer DW = 16
) (
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] addr,
    input  wire [DW-1:0] din,
    output reg  [DW-1:0] dout
);
  (* ram_style = "block" *) reg [DW-1:0] mem[0:(1<<AW)-1];
  integer i;
  initial begin
    for (i = 0; i < (1 << AW); i = i + 1) mem[i] = {DW{1'b0}};
    dout = {DW{1'b0}};
  end
  always @(posedge clk) begin
    if (we) begin
      mem[addr] <= din;
      dout <= din;
    end else dout <= mem[addr];
  end
endmodule

/* verilator lint_off UNUSEDSIGNAL */
module RM_IHPSG13_1P_512x16_c2_bm_bist (
    input  wire        A_CLK,
    input  wire        A_MEN,
    input  wire        A_WEN,
    input  wire        A_REN,
    input  wire [ 8:0] A_ADDR,
    input  wire [15:0] A_DIN,
    input  wire        A_DLY,
    output wire [15:0] A_DOUT,
    input  wire [15:0] A_BM,
    input  wire        A_BIST_CLK,
    input  wire        A_BIST_EN,
    input  wire        A_BIST_MEN,
    input  wire        A_BIST_WEN,
    input  wire        A_BIST_REN,
    input  wire [ 8:0] A_BIST_ADDR,
    input  wire [15:0] A_BIST_DIN,
    input  wire [15:0] A_BIST_BM
);
  sram_fpga_1p #(.AW(9), .DW(16)) ram (.clk(A_CLK), .we(A_WEN), .addr(A_ADDR), .din(A_DIN), .dout(A_DOUT));
`ifndef SYNTHESIS
  // the ties these models rely on (see the top of the file)
  always @(posedge A_CLK)
    if (A_MEN !== 1'b1 || A_REN !== 1'b1 || A_BM !== {16{1'b1}} || A_BIST_EN !== 1'b0) begin
      $display("%m: tie broken: MEN %b REN %b BM %h BIST_EN %b", A_MEN, A_REN, A_BM, A_BIST_EN);
      $finish(2);
    end
`endif
endmodule

module RM_IHPSG13_1P_1024x8_c2_bm_bist (
    input  wire       A_CLK,
    input  wire       A_MEN,
    input  wire       A_WEN,
    input  wire       A_REN,
    input  wire [9:0] A_ADDR,
    input  wire [7:0] A_DIN,
    input  wire       A_DLY,
    output wire [7:0] A_DOUT,
    input  wire [7:0] A_BM,
    input  wire       A_BIST_CLK,
    input  wire       A_BIST_EN,
    input  wire       A_BIST_MEN,
    input  wire       A_BIST_WEN,
    input  wire       A_BIST_REN,
    input  wire [9:0] A_BIST_ADDR,
    input  wire [7:0] A_BIST_DIN,
    input  wire [7:0] A_BIST_BM
);
  sram_fpga_1p #(.AW(10), .DW(8)) ram (.clk(A_CLK), .we(A_WEN), .addr(A_ADDR), .din(A_DIN), .dout(A_DOUT));
`ifndef SYNTHESIS
  // the ties these models rely on (see the top of the file)
  always @(posedge A_CLK)
    if (A_MEN !== 1'b1 || A_REN !== 1'b1 || A_BM !== {8{1'b1}} || A_BIST_EN !== 1'b0) begin
      $display("%m: tie broken: MEN %b REN %b BM %h BIST_EN %b", A_MEN, A_REN, A_BM, A_BIST_EN);
      $finish(2);
    end
`endif
endmodule
/* verilator lint_on UNUSEDSIGNAL */
