// SPDX-License-Identifier: Apache-2.0
// RTL check of tt_um_chip_sram_probe against IHP's behavioural SRAM models (-DFUNCTIONAL):
// writes a few words to each macro over the TT pins, reads them back, checks byte masks.
//   iverilog -g2012 -DFUNCTIONAL -o probe.vvp tb_probe.v ../src/project.v $SRAM/verilog/{RM_IHPSG13_1P_512x16_c2_bm_bist,RM_IHPSG13_1P_1024x8_c2_bm_bist,RM_IHPSG13_1P_core_behavioral_bm_bist}.v && vvp probe.vvp
`timescale 1ns/1ps
`default_nettype none
module tb;
  reg clk = 0, rst_n = 0;
  reg [7:0] ui_in = 0, uio_in = 0;
  wire [7:0] uo_out, uio_out, uio_oe;
  integer errors = 0;
  tt_um_chip_sram_probe dut (.ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out),
                             .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n));
  always #10 clk = ~clk;

  task wr(input [3:0] idx, input [7:0] val);
    begin
      @(negedge clk); uio_in[3:0] = idx; uio_in[4] = 1; ui_in = val;
      @(negedge clk); uio_in[4] = 0;
    end
  endtask
  task go;
    begin
      @(negedge clk); uio_in[5] = 1;
      @(negedge clk); uio_in[5] = 0;
      repeat (3) @(negedge clk);
    end
  endtask
  // access: sel 0 = 512x16, 1 = 1024x8
  task access(input sel, input w, input [9:0] a, input [15:0] d, input [15:0] m);
    begin
      wr(1, {sel, ~w, w, 3'b0, a[9:8]}); wr(0, a[7:0]);  // register 1 first: it selects the macro
      wr(2, d[7:0]); wr(3, d[15:8]); wr(4, m[7:0]); wr(5, m[15:8]);
      go;
    end
  endtask
  task expect_byte(input [1:0] s, input [7:0] want);
    begin
      @(negedge clk); uio_in[7:6] = s; #1;
      if (uo_out !== want) begin
        errors = errors + 1;
        $display("FAIL sel %0d: got %h want %h at %0t", s, uo_out, want, $time);
      end
    end
  endtask

  initial begin
    repeat (3) @(negedge clk); rst_n = 1;
    access(0, 1, 10'd5,   16'hBEEF, 16'hFFFF);
    access(0, 1, 10'd511, 16'h1234, 16'hFFFF);
    access(1, 1, 10'd1023, 16'h00A5, 16'h00FF);
    access(1, 1, 10'd7,   16'h003C, 16'h00FF);
    access(0, 0, 10'd5, 0, 0);     expect_byte(0, 8'hEF); expect_byte(1, 8'hBE);
    access(0, 0, 10'd511, 0, 0);   expect_byte(0, 8'h34); expect_byte(1, 8'h12);
    access(1, 0, 10'd1023, 0, 0);  expect_byte(2, 8'hA5);
    access(1, 0, 10'd7, 0, 0);     expect_byte(2, 8'h3C);
    // bit mask: overwrite only the high byte of word 5
    access(0, 1, 10'd5, 16'h7700, 16'hFF00);
    access(0, 0, 10'd5, 0, 0);     expect_byte(0, 8'hEF); expect_byte(1, 8'h77);
    if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
    $finish;
  end
endmodule
