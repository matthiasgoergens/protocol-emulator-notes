// Line-packet ROM for the retro-console HDMI demo: the bytes game.ml would send, for a run of
// consecutive fields (demo/gen_packets.ml writes the hex file).  One cycle of read latency.
`default_nettype none
module packet_rom #(parameter DEPTH = 12960, parameter FILE = "packets.hex") (
  input  wire        clock,
  input  wire [16:0] addr,
  output reg  [7:0]  data
);
  reg [7:0] mem [0:DEPTH-1];
  initial $readmemh(FILE, mem);
  always @(posedge clock) data <= mem[addr];
endmodule
