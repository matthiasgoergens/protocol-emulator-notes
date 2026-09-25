// Lockstep testbench for ../../unified-pe/rtl/upe.v (compiled with -DNO_POP -DNO_LUT -DBITSEL).
// Reads one line of inputs per cycle (hex fields), applies them, prints every output, then clocks.
// Line format: clear cfg_in cfg_strobe init_in init_strobe en a a_valid b_in bc_in cb_in s15_in g_in
`timescale 1ns/1ps
module tb;
  reg clk = 0, clear, cfg_strobe, init_strobe, en, a_valid, b_in, bc_in, cb_in, s15_in, g_in;
  reg [7:0] cfg_in, init_in; reg [15:0] a;
  wire [7:0] cfg_out, init_out; wire [15:0] p_out, s_out;
  wire p_valid, b_out, cb_out, s15_out, g_out, flag;
  upe dut(.clk(clk), .clear(clear), .cfg_in(cfg_in), .cfg_strobe(cfg_strobe), .cfg_out(cfg_out),
    .init_in(init_in), .init_out(init_out), .init_strobe(init_strobe), .en(en), .a_in(a),
    .a_valid(a_valid), .p_out(p_out), .p_valid(p_valid), .b_in(b_in), .bc_in(bc_in), .b_out(b_out),
    .cb_in(cb_in), .cb_out(cb_out), .s15_in(s15_in), .g_in(g_in), .s15_out(s15_out), .g_out(g_out),
    .flag(flag), .s_out(s_out));
  integer fd, n, cyc;
  initial begin
    fd = $fopen(`STIM, "r"); cyc = 0;
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%h %h %h %h %h %h %h %h %h %h %h %h %h\n", clear, cfg_in, cfg_strobe,
        init_in, init_strobe, en, a, a_valid, b_in, bc_in, cb_in, s15_in, g_in);
      if (n == 13) begin
        #1;
        $display("%0d %h %h %h %h %h %h %h %h %h %h", cyc, cfg_out, init_out, p_out, p_valid, b_out,
          cb_out, s15_out, g_out, flag, s_out);
        #4 clk = 1; #5 clk = 0; cyc = cyc + 1;
      end
    end
    $finish;
  end
endmodule
