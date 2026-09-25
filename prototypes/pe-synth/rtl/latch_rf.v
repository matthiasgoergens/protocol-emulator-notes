// Latch register file of WORDS x WIDTH, the D1 option of ../systolic-storage
// (storage_options.py:latch_regfile estimates it from LEF cells). One write port, one read port.
//   data      one sg13g2_dlhq_1 per bit, instantiated (Yosys 0.62's dfflibmap leaves inferred
//             latches unmapped)
//   write     one-hot decode of the write address, and per word a glitch-free clock gate:
//             an enable latch transparent while the clock is low, ANDed with the clock
//   read      WORDS:1 multiplexer per bit, left to abc
module latch_rf #(parameter WORDS = 8, parameter WIDTH = 16, parameter AW = 3) (
  input  wire              clock,
  input  wire              we,
  input  wire [AW-1:0]     waddr,
  input  wire [WIDTH-1:0]  wdata,
  input  wire [AW-1:0]     raddr,
  output wire [WIDTH-1:0]  rdata
);
  wire [WIDTH-1:0] q [0:WORDS-1];
  genvar i, j;
  generate
    for (i = 0; i < WORDS; i = i + 1) begin : word
      wire en_l, gclk;
      (* keep *) sg13g2_dlhq_1 cg (.D(we & (waddr == i)), .GATE(~clock), .Q(en_l));
      assign gclk = en_l & clock;
      for (j = 0; j < WIDTH; j = j + 1) begin : bitc
        (* keep *) sg13g2_dlhq_1 l (.D(wdata[j]), .GATE(gclk), .Q(q[i][j]));
      end
    end
  endgenerate
  assign rdata = q[raddr];
endmodule
