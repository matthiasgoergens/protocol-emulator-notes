/*
 * SPDX-License-Identifier: Apache-2.0
 * Simulation of the test bench as the board's processor drives it, through the AXI4-Lite port:
 * load the frames, start, wait for done, read back the samples and the trace. Writes the same
 * files as ../host/kv260_run.py does on the board, so the two can be compared with diff.
 *
 *   +frames=FILE    frames, one hex word per line (../chip-top/bin/fpga_ops.exe)
 *   +out=PREFIX     writes PREFIX.info, PREFIX.samples and PREFIX.trace
 *
 * The uio[7:6] pins are pulled up and nothing else drives them, as on a board with nothing
 * plugged into those pins.
 */

`timescale 1ns / 1ps
`default_nettype none

module tb_bench;
  reg clk = 1'b0;
  always #8.333 clk = ~clk;                // 60 MHz

  reg aresetn = 1'b0;
  reg [7:0] awaddr = 0, araddr = 0;
  reg awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
  reg [31:0] wdata = 0;
  wire awready, wready, bvalid, arready, rvalid;
  wire [1:0] bresp, rresp;
  wire [31:0] rdata;
  wire [7:0] bus_addr;
  wire [31:0] bus_wdata, bus_rdata;
  wire bus_we, bus_re;

  fpga_axil axil (
      .s_axi_aclk(clk), .s_axi_aresetn(aresetn),
      .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
      .s_axi_wdata(wdata), .s_axi_wstrb(4'hF), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
      .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
      .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
      .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
      .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we), .bus_re(bus_re), .bus_rdata(bus_rdata)
  );

  wire [7:0] uo_out;
  wire [1:0] uio67_out, uio67_oe;
  // open drain with pull-ups: a pin is low only where the chip drives it low
  wire [1:0] uio67_pin = ~(uio67_oe & ~uio67_out);
  wire heartbeat;
  fpga_bench #(.HEARTBEAT_HALF(1000)) bench (
      .clk(clk), .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we), .bus_re(bus_re),
      .bus_rdata(bus_rdata), .uo_out(uo_out), .uio67_out(uio67_out), .uio67_oe(uio67_oe),
      .uio67_in(uio67_pin), .ui_ext(8'd0), .heartbeat(heartbeat)
  );

  task axi_write(input [7:0] a, input [31:0] d);
    begin
      @(posedge clk);
      awaddr <= a; wdata <= d; awvalid <= 1; wvalid <= 1; bready <= 1;
      fork
        begin @(posedge clk); while (!awready) @(posedge clk); awvalid <= 0; end
        begin @(posedge clk); while (!wready) @(posedge clk); wvalid <= 0; end
      join
      while (!bvalid) @(posedge clk);
      @(posedge clk);
      bready <= 0;
    end
  endtask

  task axi_read(input [7:0] a, output [31:0] d);
    begin
      @(posedge clk);
      araddr <= a; arvalid <= 1; rready <= 1;
      @(posedge clk);
      while (!arready) @(posedge clk);
      arvalid <= 0;
      while (!rvalid) @(posedge clk);
      d = rdata;
      @(posedge clk);
      rready <= 0;
    end
  endtask

  reg [31:0] frames[0:16383];
  reg [1023:0] frames_file, out, name;
  integer n_frames, i, f, n;
  reg [31:0] v, w0, w1, w2, status, played;

  initial begin
    if (!$value$plusargs("frames=%s", frames_file) || !$value$plusargs("out=%s", out)) begin
      $display("usage: +frames=FILE +out=PREFIX");
      $finish(2);
    end
    for (i = 0; i < 16384; i = i + 1) frames[i] = 32'hx;
    $readmemh(frames_file, frames);
    n_frames = 0;
    while (frames[n_frames] !== 32'd0) begin
      if (frames[n_frames] === 32'hx) begin $display("no end frame"); $finish(2); end
      n_frames = n_frames + 1;
    end
    repeat (4) @(posedge clk);
    aresetn <= 1;

    axi_read(8'h00, v);
    if (v !== 32'h46423031) begin $display("identifier %h", v); $finish(2); end
    axi_write(8'h10, 0);
    for (i = 0; i <= n_frames; i = i + 1) axi_write(8'h14, frames[i]);
    axi_read(8'h10, v);
    $display("tb: %0d frames loaded (FRAME_ADDR %0d)", n_frames + 1, v);
    axi_write(8'h04, 1);
    v = 1;
    while (v[0]) begin
      repeat (200) @(posedge clk);
      axi_read(8'h04, v);
    end
    status = v;
    axi_read(8'h18, played);
    $display("tb: status %h, %0d clocks played", status, played);
    $sformat(name, "%0s.info", out);
    f = $fopen(name, "w");
    $fwrite(f, "status %0d\nclocks %0d\n", status, played);
    $fclose(f);

    $sformat(name, "%0s.samples", out);
    f = $fopen(name, "w");
    axi_read(8'h20, v);
    n = v;
    axi_write(8'h24, 0);
    for (i = 0; i < n; i = i + 1) begin
      axi_read(8'h28, v);
      $fwrite(f, "%01x\n", v[3:0]);
    end
    $fclose(f);
    $display("tb: %0d samples", n);

    axi_read(8'h2C, v);
    n = v[30:0];
    if (v[31]) $display("tb: trace full");
    $sformat(name, "%0s.trace", out);
    f = $fopen(name, "w");
    axi_write(8'h30, 0);
    for (i = 0; i < n; i = i + 1) begin
      axi_read(8'h34, w0);
      axi_read(8'h38, w1);
      axi_read(8'h3C, w2);
      $fwrite(f, "%0d %08x %08x\n", w0, w1, w2);
    end
    $fclose(f);
    $display("tb: %0d trace entries", n);
    $finish(0);
  end

  initial begin
    #500_000_000;
    $display("tb: timeout");
    $finish(2);
  end
endmodule
