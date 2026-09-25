// Standard-cell periphery of one gain-cell bank (../gain-cell), the part that
// ../systolic-storage/storage_options.py:gain_array estimates. One port: one read or one
// write per cycle. The bit-cell array itself is not here; its word and bit lines are ports.
//
//   control   registered address, write and read enables (a bank's single port)
//   decode    ROWS-way one-hot row decoder from the registered address, gated into a
//             write word line (wwl) and a read word line (rwl) per row
//   drivers   one sg13g2_buf_2 per word line, instantiated so abc cannot remove it
//             (the estimate uses buf_1; a 38-cell word line is the load)
//   columns   per column: a write driver (sg13g2_ebufn_2, enabled only while writing), a
//             sense inverter on the read bit line (sg13g2_inv_1, instantiated), and a
//             transparent output latch (sg13g2_dlhq_1, instantiated: Yosys 0.62's dfflibmap
//             leaves an inferred latch unmapped, with no area)
//
// Not included, as in the estimate: read-bit-line precharge, any VLO level for the write
// drivers (the gain-cell level-shift trick), refresh control, Berger-check logic.
module gc_periph #(parameter ROWS = 32, parameter COLS = 64, parameter AW = 5) (
  input  wire              clk,
  input  wire [AW-1:0]     addr,
  input  wire              we,
  input  wire              re,
  input  wire [COLS-1:0]   din,
  output wire [ROWS-1:0]   wwl,
  output wire [ROWS-1:0]   rwl,
  output wire [COLS-1:0]   wbl,
  input  wire [COLS-1:0]   rbl,
  output wire [COLS-1:0]   dout
);
  reg [AW-1:0] addr_r;
  reg we_r, re_r;
  always @(posedge clk) begin
    addr_r <= addr;
    we_r <= we;
    re_r <= re;
  end

  genvar i;
  generate
    for (i = 0; i < ROWS; i = i + 1) begin : row
      wire hit = (addr_r == i);
      (* keep *) sg13g2_buf_2 wdrv (.A(hit & we_r), .X(wwl[i]));
      (* keep *) sg13g2_buf_2 rdrv (.A(hit & re_r), .X(rwl[i]));
    end
    for (i = 0; i < COLS; i = i + 1) begin : col
      wire sensed;
      // ebufn: Z = A when TE_B low; drive the write bit line only in a write cycle
      (* keep *) sg13g2_ebufn_2 wd (.A(din[i]), .TE_B(~we_r), .Z(wbl[i]));
      (* keep *) sg13g2_inv_1 sa (.A(rbl[i]), .Y(sensed));
      (* keep *) sg13g2_dlhq_1 lat (.D(sensed), .GATE(re_r), .Q(dout[i]));
    end
  endgenerate
endmodule
