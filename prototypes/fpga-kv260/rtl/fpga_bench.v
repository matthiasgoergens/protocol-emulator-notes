/*
 * SPDX-License-Identifier: Apache-2.0
 * The board-independent part of the FPGA test bench (../README.md): the chip as submitted to
 * Tiny Tapeout (tt_um_chip_top), a player that plays the host's side of the host link from a
 * stored list of frames, and a recorder that logs every change of the chip's pads with its clock
 * number. A processor reads and writes it through a small register bus; fpga_axil.v puts that bus
 * on AXI4-Lite.
 *
 * Everything, the bus included, runs on the chip's one clock (60 MHz on the chip). Once the
 * processor has loaded the frames and set start, the run is fixed clock by clock: the processor's
 * timing does not reach the chip, so a run on the board and a simulation of this file with the
 * same frames should record the same trace.
 *
 * Frames (written by ../chip-top/bin/fpga_ops.exe), one 32-bit word each:
 *   [15:0]  clocks to hold these levels, 1..65535; 0 ends the run
 *   [19:16] D, the level the host drives on the host link data lines uio[3:0]
 *   [20]    the host drives D (otherwise the lines are left to the chip)
 *   [21]    S, the host link strobe (uio[4])    [22] R, the read request (uio[5])
 *   [23]    sample the data lines at the start of the frame's first clock (the levels of the
 *           clock before, as ../chip-top/bin/edge_phase.ml's host sees them)
 *   [31:24] ui_in
 *
 * Register map (byte offsets; reads have side effects only where noted):
 *   0x00 R   identifier 0x46423031 ("FB01")
 *   0x04 W   bit 0: start (reset the chip for RESET_CLOCKS, then play from frame 0);
 *            bit 1: stop (back to idle, chip held in reset)
 *        R   bit 0 busy, bit 1 done, bit 2 trace full (entries were dropped),
 *            bit 3 ran off the end of the frame memory without an end frame
 *   0x08 RW  RESET_CLOCKS, clocks of reset before the first frame (default 16, at least 2)
 *   0x0C RW  UI_MASK: bits of ui_in taken from the ui_ext pins as well (ORed with the frames')
 *   0x10 RW  FRAME_ADDR, where the next FRAME_DATA write goes
 *   0x14 W   FRAME_DATA: store a frame at FRAME_ADDR and advance it (ignored while busy)
 *   0x18 R   clocks played since the first frame
 *   0x1C R   free-running clock counter (read it twice, some time apart, to measure the clock)
 *   0x20 R   samples taken
 *   0x24 RW  SAMPLE_ADDR
 *   0x28 R   the sample at SAMPLE_ADDR (bits 3:0); the read advances SAMPLE_ADDR
 *   0x2C R   trace entries recorded (bits 30:0); bit 31 set if the trace filled up
 *   0x30 RW  TRACE_ADDR
 *   0x34 R   entry TRACE_ADDR, word 0: the clock number
 *   0x38 R   word 1: {uio_out 2nd half, uio_out 1st half, uo_out 2nd half, uo_out 1st half}
 *   0x3C R   word 2: {7'b0, rst_n, uio_in, ui_in, uio_oe}; the read advances TRACE_ADDR
 *
 * Trace: one entry for the first clock played and one for every clock in which any recorded
 * level differs from the clock before. The chip's output stage changes pads on both clock edges,
 * so each output is recorded twice per clock: as it was just before the falling edge (first
 * half) and just before the next rising edge (second half). Inputs are recorded as the chip is
 * given them during the clock.
 */

`default_nettype none

module fpga_bench #(
    parameter integer FRAME_AW = 14,       // 16384 frames
    parameter integer TRACE_AW = 14,       // 16384 trace entries
    parameter integer SAMPLE_AW = 10,      // 1024 samples
    parameter integer HEARTBEAT_HALF = 30_000_000
) (
    input  wire        clk,
    // register bus: one-clock read and write strobes, read data in the clock after re
    input  wire [ 7:0] bus_addr,
    input  wire [31:0] bus_wdata,
    input  wire        bus_we,
    input  wire        bus_re,
    output reg  [31:0] bus_rdata = 32'd0,
    // the chip's general pins, for the board's connectors
    output wire [ 7:0] uo_out,
    output wire [ 1:0] uio67_out,          // uio[7:6]: the open-drain capable pins
    output wire [ 1:0] uio67_oe,
    input  wire [ 1:0] uio67_in,           // the levels on the uio[7:6] pins
    input  wire [ 7:0] ui_ext,             // inputs from the board, enabled by UI_MASK
    output reg         heartbeat = 1'b0    // toggles every HEARTBEAT_HALF clocks
);
  // ---------------------------------------------------------------- control registers
  localparam [1:0] IDLE = 2'd0, RESET = 2'd1, RUN = 2'd2, DONE = 2'd3;
  reg [1:0] state = IDLE;
  reg [15:0] reset_clocks = 16'd16;
  reg [7:0] ui_mask = 8'd0;
  reg [15:0] reset_left = 16'd0;
  reg ran_off = 1'b0;
  reg [31:0] cycles = 32'd0, free = 32'd0;
  reg [31:0] beat = 32'd0;

  // ---------------------------------------------------------------- frame memory and player
  (* ram_style = "block" *) reg [31:0] frames[0:(1<<FRAME_AW)-1];
  reg [FRAME_AW-1:0] frame_waddr = 0;
  reg [FRAME_AW:0] ptr = 0;                // next frame to load; the top bit marks running off
  reg [31:0] frame_q = 32'd0;              // frames[read address of the clock before]
  reg [15:0] left = 16'd0;                 // clocks left in the current frame
  reg [3:0] f_d = 4'd0;
  reg f_drive = 1'b0, f_s = 1'b0, f_r = 1'b0;
  reg [7:0] f_ui = 8'd0;
  reg rst_n = 1'b0;

  // the chip
  wire [7:0] chip_uo, chip_uio_out, chip_uio_oe;
  // the host link data lines: the chip's where it drives them, else the host's, else 0
  wire [3:0] d_line = (chip_uio_oe[3:0] & chip_uio_out[3:0]) |
                      (~chip_uio_oe[3:0] & (f_drive ? f_d : 4'd0));
  wire [7:0] ui_in = f_ui | (ui_ext & ui_mask);
  wire [7:0] uio_in = {uio67_in, f_r, f_s, d_line};

  tt_um_chip_top chip (
      .ui_in(ui_in), .uo_out(chip_uo), .uio_in(uio_in), .uio_out(chip_uio_out),
      .uio_oe(chip_uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n)
  );
  assign uo_out = chip_uo;
  assign uio67_out = chip_uio_out[7:6];
  assign uio67_oe = chip_uio_oe[7:6];

  // a frame is loaded at the end of the last reset clock and at the end of each frame's last clock
  wire load = (state == RESET && reset_left == 16'd1) || (state == RUN && left == 16'd1);
  wire end_frame = frame_q[15:0] == 16'd0 || ptr[FRAME_AW];
  wire [FRAME_AW-1:0] frame_raddr = load ? ptr[FRAME_AW-1:0] + 1'b1 : ptr[FRAME_AW-1:0];
  always @(posedge clk) frame_q <= frames[frame_raddr];

  // samples
  reg [3:0] samples[0:(1<<SAMPLE_AW)-1];
  reg [SAMPLE_AW:0] n_samples = 0;
  reg [SAMPLE_AW-1:0] sample_raddr = 0;

  wire start = bus_we && bus_addr == 8'h04 && bus_wdata[0];
  wire stop = bus_we && bus_addr == 8'h04 && bus_wdata[1];

  always @(posedge clk) begin
    free <= free + 1'b1;
    if (beat == HEARTBEAT_HALF - 1) begin
      beat <= 32'd0;
      heartbeat <= ~heartbeat;
    end else beat <= beat + 1'b1;

    if (bus_we && bus_addr == 8'h14 && (state == IDLE || state == DONE)) begin
      frames[frame_waddr] <= bus_wdata;
      frame_waddr <= frame_waddr + 1'b1;
    end
    if (bus_we && bus_addr == 8'h10) frame_waddr <= bus_wdata[FRAME_AW-1:0];

    if (stop) begin
      state <= IDLE;
      rst_n <= 1'b0;
    end else if (start && state != RESET && state != RUN) begin
      state <= RESET;
      rst_n <= 1'b0;
      // at least 2, so that frame 0 is read before it is loaded
      reset_left <= reset_clocks < 16'd2 ? 16'd2 : reset_clocks;
      ptr <= 0;
      cycles <= 32'd0;
      n_samples <= 0;
      ran_off <= 1'b0;
      {f_d, f_drive, f_s, f_r, f_ui} <= 0;
    end else begin
      case (state)
        RESET: reset_left <= reset_left - 1'b1;
        RUN: begin
          cycles <= cycles + 1'b1;
          left <= left - 1'b1;
        end
        default: ;
      endcase
      if (load) begin
        if (end_frame) begin
          state <= DONE;
          ran_off <= ptr[FRAME_AW];
          // the levels of the last frame stay, and the chip keeps running
        end else begin
          state <= RUN;
          rst_n <= 1'b1;
          ptr <= ptr + 1'b1;
          left <= frame_q[15:0];
          f_d <= frame_q[19:16];
          f_drive <= frame_q[20];
          f_s <= frame_q[21];
          f_r <= frame_q[22];
          f_ui <= frame_q[31:24];
          if (frame_q[23] && !n_samples[SAMPLE_AW]) begin
            samples[n_samples[SAMPLE_AW-1:0]] <= d_line;
            n_samples <= n_samples + 1'b1;
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------- recorder
  reg [7:0] uo_h1 = 8'd0, uio_h1 = 8'd0;   // captured at the falling edge: the first half
  always @(negedge clk) begin
    uo_h1 <= chip_uo;
    uio_h1 <= chip_uio_out;
  end
  // this clock's levels, complete at its end
  wire [31:0] w1 = {chip_uio_out, uio_h1, chip_uo, uo_h1};
  wire [31:0] w2 = {7'd0, rst_n, uio_in, ui_in, chip_uio_oe};
  (* ram_style = "block" *) reg [95:0] trace[0:(1<<TRACE_AW)-1];
  reg [TRACE_AW:0] n_trace = 0;
  reg trace_full = 1'b0;
  reg [63:0] last = 64'd0;
  reg first = 1'b0;
  reg [TRACE_AW-1:0] trace_raddr = 0;
  reg [95:0] trace_q = 96'd0;
  always @(posedge clk) begin
    trace_q <= trace[trace_raddr];
    if (start && state != RESET && state != RUN) begin
      n_trace <= 0;
      trace_full <= 1'b0;
      first <= 1'b1;
    end else if (state == RUN) begin
      // [cycles] is this clock's number: it advances at this same edge
      if (first || {w2, w1} != last) begin
        if (n_trace[TRACE_AW]) trace_full <= 1'b1;
        else begin
          trace[n_trace[TRACE_AW-1:0]] <= {w2, w1, cycles};
          n_trace <= n_trace + 1'b1;
        end
      end
      last <= {w2, w1};
      first <= 1'b0;
    end
  end

  // ---------------------------------------------------------------- register reads
  always @(posedge clk) begin
    if (bus_we && bus_addr == 8'h08) reset_clocks <= bus_wdata[15:0];
    if (bus_we && bus_addr == 8'h0C) ui_mask <= bus_wdata[7:0];
    if (bus_we && bus_addr == 8'h24) sample_raddr <= bus_wdata[SAMPLE_AW-1:0];
    if (bus_we && bus_addr == 8'h30) trace_raddr <= bus_wdata[TRACE_AW-1:0];
    if (bus_re && bus_addr == 8'h28) sample_raddr <= sample_raddr + 1'b1;
    if (bus_re && bus_addr == 8'h3C) trace_raddr <= trace_raddr + 1'b1;
    if (bus_re)
      case (bus_addr)
        8'h00: bus_rdata <= 32'h46423031;
        8'h04: bus_rdata <= {28'd0, ran_off, trace_full, state == DONE, state == RESET || state == RUN};
        8'h08: bus_rdata <= {16'd0, reset_clocks};
        8'h0C: bus_rdata <= {24'd0, ui_mask};
        8'h10: bus_rdata <= frame_waddr;
        8'h18: bus_rdata <= cycles;
        8'h1C: bus_rdata <= free;
        8'h20: bus_rdata <= n_samples;
        8'h24: bus_rdata <= sample_raddr;
        8'h28: bus_rdata <= {28'd0, samples[sample_raddr]};
        8'h2C: bus_rdata <= {trace_full, {(31 - TRACE_AW - 1) {1'b0}}, n_trace};
        8'h30: bus_rdata <= trace_raddr;
        8'h34: bus_rdata <= trace_q[31:0];
        8'h38: bus_rdata <= trace_q[63:32];
        8'h3C: bus_rdata <= trace_q[95:64];
        default: bus_rdata <= 32'hDEADBEEF;
      endcase
  end
endmodule
