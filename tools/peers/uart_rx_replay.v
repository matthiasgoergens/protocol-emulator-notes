// SPDX-License-Identifier: Apache-2.0
// Replays a recorded pin trace (one 0/1 per line in $TRACE, one line per clock) into alexforencich's
// uart_rx, unmodified, and prints every byte it receives and every error flag it raises.
// PRESCALE: the peer takes a bit as PRESCALE*8 clocks.
`timescale 1ns / 1ps
module uart_rx_replay;
  parameter PRESCALE = 8;
  reg clk = 0, rst = 1;
  reg rxd = 1;
  wire [7:0] tdata;
  wire tvalid, busy, overrun_error, frame_error;
  uart_rx #(.DATA_WIDTH(8)) peer (
    .clk(clk), .rst(rst), .m_axis_tdata(tdata), .m_axis_tvalid(tvalid), .m_axis_tready(1'b1),
    .rxd(rxd), .busy(busy), .overrun_error(overrun_error), .frame_error(frame_error),
    .prescale(PRESCALE[15:0]));
  integer fd, rc, bit_in, n;
  reg [8*256-1:0] path;
  always #5 clk = ~clk;
  initial begin
    if (!$value$plusargs("TRACE=%s", path)) begin $display("no +TRACE"); $finish; end
    fd = $fopen(path, "r");
    n = 0;
    repeat (4) @(posedge clk);
    rst <= 0;
    while (!$feof(fd)) begin
      rc = $fscanf(fd, "%d\n", bit_in);
      if (rc == 1) begin @(posedge clk); rxd <= bit_in[0]; n = n + 1; end
    end
    repeat (PRESCALE * 8 * 12) @(posedge clk);
    $display("samples %0d", n);
    $finish;
  end
  always @(posedge clk) begin
    if (tvalid) $display("RX %02x", tdata);
    if (frame_error) $display("FRAME_ERROR");
    if (overrun_error) $display("OVERRUN_ERROR");
  end
endmodule
