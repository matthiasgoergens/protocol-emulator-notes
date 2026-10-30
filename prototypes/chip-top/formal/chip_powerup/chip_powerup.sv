// Power-up determinism of the whole chip as submitted (tt/src/chip_tt.v: core, PE array, bit
// assists, host link, loader, pin stage on both clock edges, reset synchroniser), the method of
// ../../../formal/powerup/powerup.sv and ../array_powerup.sv. Two copies start from independent,
// arbitrary register contents and get the same inputs. rst_n is held low for the first
// RESET_CLOCKS clocks and is free (but shared) afterwards. From then on, at every half clock:
//   - the pins agree: uo_out, uio_oe, and uio_out wherever it is enabled;
//   - every SRAM write agrees: enable, and address, data and mask when enabled.
// The SRAM macros are outside the copies (stub_sram.py): both copies read one memory of arbitrary
// contents, so they get the same word when they read the same address and independent words
// otherwise. The write assertion is what makes that sound: once the writes agree, so do the two
// memories, except at addresses written before reset took hold, which the host reloads anyway.
// So what is proved is: after reset, the pins depend only on the inputs and the memory contents.
module chip_powerup #(parameter RESET_CLOCKS = 4) (
    input rst_n_in, input [7:0] ui_in, input [7:0] uio_in,
    input [7:0] dout1_a, input [7:0] dout1_b, input [15:0] dout2_a, input [15:0] dout2_b
);
  // The only initialised registers: the clock and the half-clock counter.
  reg clk = 1'b0;
  always @($global_clock) clk <= !clk;
  reg [7:0] half = 8'd0;
  always @($global_clock) if (half != 8'hff) half <= half + 8'd1;
  wire in_reset = half < 2 * RESET_CLOCKS;
  wire rst_n = in_reset ? 1'b0 : rst_n_in;

  wire [9:0] raddr1_a, raddr1_b; wire [8:0] raddr2_a, raddr2_b;
  wire [26:0] in1_a, in1_b; wire [41:0] in2_a, in2_b;
  wire [7:0] uo_a, uo_b, uio_out_a, uio_out_b, oe_a, oe_b;
  // one memory: the same word for the same address
  wire [7:0] d1_b = (raddr1_a == raddr1_b) ? dout1_a : dout1_b;
  wire [15:0] d2_b = (raddr2_a == raddr2_b) ? dout2_a : dout2_b;

  chip_pu copy_a (.rst_n(rst_n), .clk(clk), .ui_in(ui_in), .uio_in(uio_in),
    .uo_out(uo_a), .uio_out(uio_out_a), .uio_oe(oe_a),
    .pu_raddr_1(raddr1_a), .pu_dout_1(dout1_a), .pu_in_1(in1_a),
    .pu_raddr_2(raddr2_a), .pu_dout_2(dout2_a), .pu_in_2(in2_a));
  chip_pu copy_b (.rst_n(rst_n), .clk(clk), .ui_in(ui_in), .uio_in(uio_in),
    .uo_out(uo_b), .uio_out(uio_out_b), .uio_oe(oe_b),
    .pu_raddr_1(raddr1_b), .pu_dout_1(d1_b), .pu_in_1(in1_b),
    .pu_raddr_2(raddr2_b), .pu_dout_2(d2_b), .pu_in_2(in2_b));

  // pu_in_N = {wen, addr, din, bm}; wen is the top bit
  wire wen1 = in1_a[26], wen2 = in2_a[41];
  always @(*) if (!in_reset) begin
    a_uo: assert (uo_a == uo_b);
    a_oe: assert (oe_a == oe_b);
    a_uio: assert ((uio_out_a & oe_a) == (uio_out_b & oe_b));
    a_wen1: assert (in1_a[26] == in1_b[26]);
    a_wen2: assert (in2_a[41] == in2_b[41]);
    a_wr1: assert (!wen1 || in1_a == in1_b);
    a_wr2: assert (!wen2 || in2_a == in2_b);
  end
endmodule
