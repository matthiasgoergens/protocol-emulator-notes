// 256 x 256 x 8-bit frame buffer (240 lines used), one write port and one registered read port
// on the same clock: the shape yosys maps to ECP5 DP16KD block RAM.
`default_nettype none
module frame_buffer (
  input  wire        clock,
  input  wire        we,
  input  wire [15:0] waddr,
  input  wire [7:0]  wdata,
  input  wire [15:0] raddr,
  output reg  [7:0]  rdata
);
  reg [7:0] mem [0:65535];
  always @(posedge clock) begin
    if (we) mem[waddr] <= wdata;
    rdata <= mem[raddr];
  end
endmodule
