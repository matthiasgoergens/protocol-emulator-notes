// SPDX-License-Identifier: Apache-2.0
// Makes a stimulus file for the runner (tools/asm, "CLOCK NET LEVEL" lines) from Alex Forencich's
// uart_tx (tools/peers/vendor/verilog-uart, MIT, unmodified): the peer transmits BYTES on net NET,
// back to back, PRESCALE*8 clocks a bit, starting at clock START; every change of its txd is a
// line. One clock of this bench is one chip clock.
`timescale 1ns / 1ps
module uart_tx_stim;
  parameter PRESCALE = 8;
  parameter START = 200;
  parameter NET = 0;
  reg clk = 0, rst = 1;
  reg [7:0] tdata = 0;
  reg tvalid = 0;
  wire tready, txd, busy;
  uart_tx #(.DATA_WIDTH(8)) peer (
    .clk(clk), .rst(rst), .s_axis_tdata(tdata), .s_axis_tvalid(tvalid), .s_axis_tready(tready),
    .txd(txd), .busy(busy), .prescale(PRESCALE[15:0]));
  always #5 clk = ~clk;
  integer clock = -8, k, n, fd;
  reg [7:0] bytes [0:15];
  reg last = 1'bx;
  reg [8*256-1:0] path;
  always @(posedge clk) begin
    clock <= clock + 1;
    if (clock >= 0 && txd !== last) begin
      $fdisplay(fd, "%0d %0d %0d", clock, NET, txd);
      last <= txd;
    end
  end
  initial begin
    if (!$value$plusargs("OUT=%s", path)) begin $display("no +OUT"); $finish; end
    fd = $fopen(path, "w");
    $fdisplay(fd, "# made by tools/asm/examples/peers/uart_tx_stim.v around alexforencich/verilog-uart uart_tx (unmodified)");
    $fdisplay(fd, "# net %0d, %0d clocks a bit, from clock %0d", NET, PRESCALE * 8, START);
    bytes[0] = 8'h48; bytes[1] = 8'h69; bytes[2] = 8'h21; bytes[3] = 8'h0a;
    bytes[4] = 8'h00; bytes[5] = 8'hff; bytes[6] = 8'h55; bytes[7] = 8'ha5;
    n = 8;
    repeat (4) @(posedge clk);
    rst <= 0;
    while (clock < START) @(posedge clk);
    for (k = 0; k < n; k = k + 1) begin
      tdata <= bytes[k]; tvalid <= 1;
      @(posedge clk);
      while (!tready) @(posedge clk);
      tvalid <= 0;
    end
    while (busy) @(posedge clk);
    repeat (PRESCALE * 8 * 2) @(posedge clk);
    $fclose(fd);
    $finish;
  end
endmodule
