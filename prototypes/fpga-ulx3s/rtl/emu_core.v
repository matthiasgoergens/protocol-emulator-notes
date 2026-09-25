// emu_core: the board-independent part of the FPGA test bench.
//
// Wraps the Hardcaml-generated deadline_sequencer, pin_streamer and pin_sampler with:
//   - a UART host link (8N1, CLKS_PER_BIT clocks per bit) and a small command engine,
//   - the sequencer's instruction memory (256 x 16, one-cycle synchronous read, standing in for
//     the SRAM macro; block RAM on the FPGA),
//   - a change-compressed trace recorder of everything the sequencer sees and does, so that the
//     host can replay the run through the OCaml interpreter cycle for cycle,
//   - a 64-word stream buffer feeding the streamer, and a 256-entry capture of the sampler.
//
// The same module runs on the ULX3S (ulx3s_top.v supplies pads, PLL and USB) and under Verilator
// (sim/sim_main.cpp supplies board models), so the host runner is proven before hardware.
//
// Host protocol (all multi-byte fields big-endian). Every command gets a reply:
//   'I'                        -> "EMU1" TRACE_AW CTRL_hi CTRL_lo 'k'        identify
//   'W' a1 a0 d1 d0            -> 'k'        imem[a] <- d                      (idle only)
//   'R' a1 a0                  -> d1 d0      read imem[a]                      (idle only)
//   'K' r  d1 d0               -> 'k'        config register r <- d
//   'H' b                      -> 'k' | 'f'  push b into the host_in FIFO ('f': full)
//   'B' a1 a0 c d1 d0          -> 'k'        stream buffer[a] <- {c[3:0], d}
//   'G' n3 n2 n1 n0            -> 'g'        run n cycles, reply when done ('X' aborts)
//   'T'                        -> cnt1 cnt0 ovf t3 t2 t1 t0, then cnt entries of 10 bytes
//   'S'                        -> cnt1 cnt0, then cnt entries of 3 bytes {count, data1, data0}
//   'Z'                        -> usb_status smp_overflows trace_ovf 'k'
//   anything else              -> '?'
//
// Run semantics. 'G' passes through one PRIME cycle (sequencer, streamer and sampler held in
// clear, imem read address forced to 0, trace reset) and then RUN for n cycles, numbered from 0.
// Cycle 0 is the first cycle out of clear, exactly as in deadline-sequencer/harness.ml.
//
// Trace entry, 80 bits, recorded in cycle c when c = 0 or any field differs from cycle c-1:
//   [79:48] c   [47:40] pin_in seen by the core in c   [39:32] pin_out   [31:24] pin_oe
//   [23:16] flags {5'b0, host_in_valid, host_in_ready, host_out_valid}
//   [15:8] host_out   [7:0] host_in
// pin_out, pin_oe, host_out and host_out_valid are the core's registered outputs as visible in
// cycle c, i.e. the state after the instruction of cycle c-1. host_in_ready is combinational in
// cycle c. If the buffer fills, recording stops; 'T' reports ovf=1 and the first cycle whose
// change was dropped, and the host checks only the cycles before it.
`default_nettype none

module emu_uart_rx #(parameter CLKS_PER_BIT = 60) (
  input wire clk, input wire rst, input wire rx,
  output reg [7:0] data, output reg valid
);
  reg [1:0] sync = 2'b11;
  reg busy = 1'b0;
  reg [15:0] cnt = 16'd0;
  reg [3:0] bitn = 4'd0;
  reg [7:0] sh = 8'd0;
  always @(posedge clk) begin
    sync <= {sync[0], rx};
    valid <= 1'b0;
    if (rst) begin
      busy <= 1'b0;
    end else if (!busy) begin
      if (!sync[1]) begin busy <= 1'b1; cnt <= CLKS_PER_BIT / 2; bitn <= 4'd0; end
    end else if (cnt != 16'd0) begin
      cnt <= cnt - 16'd1;
    end else begin
      cnt <= CLKS_PER_BIT - 1;
      bitn <= bitn + 4'd1;
      if (bitn == 4'd0) begin
        if (sync[1]) busy <= 1'b0;                  // glitch, not a start bit
      end else if (bitn <= 4'd8) begin
        sh <= {sync[1], sh[7:1]};
      end else begin
        busy <= 1'b0;
        if (sync[1]) begin data <= sh; valid <= 1'b1; end   // framing error: drop
      end
    end
  end
endmodule

module emu_uart_tx #(parameter CLKS_PER_BIT = 60) (
  input wire clk, input wire rst, input wire [7:0] data, input wire start,
  output reg tx, output wire busy
);
  reg [9:0] sh = 10'h3FF;
  reg [3:0] n = 4'd0;
  reg [15:0] cnt = 16'd0;
  reg act = 1'b0;
  assign busy = act;
  initial tx = 1'b1;
  always @(posedge clk) begin
    if (rst) begin
      act <= 1'b0; tx <= 1'b1;
    end else if (!act) begin
      if (start) begin sh <= {1'b1, data, 1'b0}; act <= 1'b1; n <= 4'd0; cnt <= 16'd0; end
    end else if (cnt != 16'd0) begin
      cnt <= cnt - 16'd1;
    end else if (n == 4'd10) begin
      act <= 1'b0; tx <= 1'b1;
    end else begin
      tx <= sh[0]; sh <= {1'b1, sh[9:1]}; n <= n + 4'd1; cnt <= CLKS_PER_BIT - 1;
    end
  end
endmodule

module emu_core #(
  parameter CLKS_PER_BIT = 60,
  parameter TRACE_AW = 11
) (
  input wire clk,
  input wire rst,
  // host link
  input wire uart_rx,
  output wire uart_tx,
  // sequencer pins on the header (pad levels in, drive out); routed pins are released here
  input wire [7:0] seq_pad_in,
  output wire [7:0] seq_pad_out,
  output wire [7:0] seq_pad_oe,
  // auxiliary SPI (on the ULX3S: the configuration flash through USRMCLK)
  output wire aux_spi_sclk, output wire aux_spi_mosi, output wire aux_spi_csn,
  input wire aux_spi_miso,
  // auxiliary I2C (on the ULX3S: the RTC bus), open drain: *_low = pull the line low
  output wire aux_sda_low, output wire aux_scl_low,
  input wire aux_sda_in, input wire aux_scl_in,
  // streamer pins and sampler pins on the header
  output wire [3:0] str_pad_out, output wire [3:0] str_pad_oe,
  input wire [3:0] smp_pad_in,
  // board status in (already synchronised), control out
  input wire [7:0] board_status,
  output wire [15:0] ctrl,
  output wire running_o,
  output wire trace_ovf_o,
  output wire flash_blocked_o,
  output wire host_activity
`ifdef EMU_MULTIPHASE
  // four-phase variant (ulx3s_top.v with EMU_MULTIPHASE): pin_sub to the stage, quad samples
  // from it
  , output wire [31:0] seq_pin_sub
  , input wire [7:0] quad_pins            // which pins take their samples from quad_samples
  , input wire [31:0] quad_samples        // bit 4i+p: pin i at quarter p, already retimed to clk
`endif
);
  localparam TRACE_DEPTH = 1 << TRACE_AW;
  localparam [7:0] TAW8 = TRACE_AW;

  // ---------------------------------------------------------------- configuration registers
  // 0 CTRL: b0 route seq pins 1,2,3 (sclk, mosi, csn) and pin_in[6] (miso) to the aux SPI
  //         b1 route seq pins 4,5 (sda, scl) to the aux I2C
  //         b2 internal UART loop: pin_in[7] <- level of seq pin 0
  //         b3 internal stream loop: sampler pins <- streamer levels
  //         b4 USB attach (pull-up on D+), used by the board top
  // 1 streamer period  2 streamer {idle_oe, idle_out, od_mask, 1'b0, width}  3 streamer length
  // 4 sampler period   5 sampler offset
  // 6 sampler {frame_len[7:0], 1'b0, trig_val, trig_pin[1:0], clocked, width[2:0]}
  reg [15:0] cfg [0:7];
  integer ci;
  initial begin
    for (ci = 0; ci < 8; ci = ci + 1) cfg[ci] = 16'd0;
    cfg[0] = 16'h0010;
  end
  assign ctrl = cfg[0];
  wire r_flash = cfg[0][0], r_i2c = cfg[0][1], r_uloop = cfg[0][2], r_sloop = cfg[0][3];

  // ---------------------------------------------------------------- UART
  wire [7:0] rx_data; wire rx_valid;
  emu_uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) urx (.clk(clk), .rst(rst), .rx(uart_rx), .data(rx_data), .valid(rx_valid));

  // transmit FIFO, 64 bytes
  reg [7:0] txf [0:63];
  reg [5:0] txf_wr = 6'd0, txf_rd = 6'd0;
  reg [6:0] txf_cnt = 7'd0;
  wire txf_full = txf_cnt[6];
  reg txf_push; reg [7:0] txf_din;
  wire tx_busy;
  reg tx_kick = 1'b0;   // one cycle for the transmitter to raise busy
  wire tx_start = (txf_cnt != 7'd0) && !tx_busy && !tx_kick;
  emu_uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) utx (.clk(clk), .rst(rst), .data(txf[txf_rd]), .start(tx_start), .tx(uart_tx), .busy(tx_busy));
  always @(posedge clk) begin
    tx_kick <= tx_start;
    if (rst) begin
      txf_wr <= 6'd0; txf_rd <= 6'd0; txf_cnt <= 7'd0;
    end else begin
      if (txf_push && !txf_full) begin txf[txf_wr] <= txf_din; txf_wr <= txf_wr + 6'd1; end
      if (tx_start) txf_rd <= txf_rd + 6'd1;
      txf_cnt <= txf_cnt + ((txf_push && !txf_full) ? 7'd1 : 7'd0) - (tx_start ? 7'd1 : 7'd0);
    end
  end

  // activity stretch for an LED
  reg [21:0] act_cnt = 22'd0;
  always @(posedge clk) act_cnt <= rx_valid ? 22'h3FFFFF : (act_cnt != 22'd0 ? act_cnt - 22'd1 : 22'd0);
  assign host_activity = act_cnt != 22'd0;

  // ---------------------------------------------------------------- run control
  localparam S_IDLE = 3'd0, S_PRIME = 3'd1, S_RUN = 3'd2;
  reg [2:0] rstate = S_IDLE;
  reg [31:0] run_len = 32'd0, cycle = 32'd0;
  wire running = rstate == S_RUN;
  wire in_clear = !running;
  assign running_o = running;

  // ---------------------------------------------------------------- pins and routing
  wire [7:0] core_pin_out, core_pin_oe;
  // what the pads and the aux buses present, before synchronisation
  wire seq0_level = core_pin_oe[0] ? core_pin_out[0] : seq_pad_in[0];
  reg [7:0] pin_raw;
  always @* begin
    pin_raw = seq_pad_in;
    if (r_flash) begin
      pin_raw[1] = core_pin_out[1]; pin_raw[2] = core_pin_out[2]; pin_raw[3] = core_pin_out[3];
      pin_raw[6] = aux_spi_miso;
    end
    if (r_i2c) begin pin_raw[4] = aux_sda_in; pin_raw[5] = aux_scl_in; end
    if (r_uloop) pin_raw[7] = seq0_level;
  end
  reg [7:0] pin_s1 = 8'hFF, pin_s2 = 8'hFF;   // two-flop synchroniser; pin_s2 is what the core sees
  always @(posedge clk) begin pin_s1 <= pin_raw; pin_s2 <= pin_s1; end

  wire [7:0] routed_away = {1'b0, (r_flash ? 1'b1 : 1'b0), (r_i2c ? 2'b11 : 2'b00), (r_flash ? 3'b111 : 3'b000), 1'b0};
  assign seq_pad_out = core_pin_out;
  assign seq_pad_oe = core_pin_oe & ~routed_away;
  // Flash interlock, in hardware, behind the runner's software allow-list: the first byte after
  // chip select falls must stay a prefix of a read-only command (0x9F RDID, 0x03 READ, 0x0B FAST
  // READ, 0x05 RDSR). Each rising SCLK edge the core is about to make is checked against the bit
  // on MOSI; on the first bit that leaves every allowed prefix, that edge is suppressed and chip
  // select is forced high until the programme raises it, so a write, erase or status-write
  // command never gets its eighth bit and the flash discards it. After eight good bits the rest
  // (address, dummy, data) passes.
  wire f_sclk = core_pin_oe[1] & core_pin_out[1];
  wire f_mosi = core_pin_oe[2] & core_pin_out[2];
  wire f_csn = ~core_pin_oe[3] | core_pin_out[3];
  reg f_sclk_q = 1'b0, f_blocked = 1'b0;
  reg [3:0] f_nbits = 4'd0;
  reg [7:0] f_prefix = 8'd0;
  wire f_rise = f_sclk & ~f_sclk_q;
  wire [7:0] f_cand = {f_prefix[6:0], f_mosi};   // the first f_nbits+1 bits, right-aligned
  function prefix_ok(input [7:0] cand, input [3:0] n);   // n = bits in cand, 1..8
    reg [7:0] c9f, c03, c0b, c05;
    begin
      c9f = 8'h9F >> (4'd8 - n); c03 = 8'h03 >> (4'd8 - n);
      c0b = 8'h0B >> (4'd8 - n); c05 = 8'h05 >> (4'd8 - n);
      prefix_ok = (cand == c9f) | (cand == c03) | (cand == c0b) | (cand == c05);
    end
  endfunction
  wire f_bad_edge = r_flash & ~f_csn & f_rise & (f_nbits < 4'd8) & ~prefix_ok(f_cand & (8'hFF >> (4'd7 - f_nbits)), f_nbits + 4'd1);
  wire f_block_now = f_blocked | f_bad_edge;
  always @(posedge clk) begin
    f_sclk_q <= f_sclk;
    if (!r_flash || f_csn) begin f_nbits <= 4'd0; f_prefix <= 8'd0; f_blocked <= 1'b0; end
    else if (f_bad_edge) f_blocked <= 1'b1;
    else if (f_rise && !f_blocked && f_nbits < 4'd8) begin f_prefix <= f_cand; f_nbits <= f_nbits + 4'd1; end
  end
  assign flash_blocked_o = f_blocked;
  assign aux_spi_sclk = r_flash ? (f_sclk & ~f_block_now) : 1'b0;
  assign aux_spi_mosi = r_flash ? f_mosi : 1'b0;
  assign aux_spi_csn = r_flash ? (f_csn | f_block_now) : 1'b1;
  // I2C is open drain whatever the programme does: an enabled 1 is treated as released
  assign aux_sda_low = r_i2c & core_pin_oe[4] & ~core_pin_out[4];
  assign aux_scl_low = r_i2c & core_pin_oe[5] & ~core_pin_out[5];

  // ---------------------------------------------------------------- instruction memory
  reg [15:0] imem [0:255];
  reg [15:0] imem_q = 16'd0;
  wire [7:0] core_imem_addr;
  reg imem_we = 1'b0; reg [7:0] imem_wa = 8'd0; reg [15:0] imem_wd = 16'd0;
  reg [7:0] host_ra = 8'd0;
  wire [7:0] imem_ra = running ? core_imem_addr : (rstate == S_PRIME ? 8'd0 : host_ra);
  always @(posedge clk) begin
    if (imem_we) imem[imem_wa] <= imem_wd;
    imem_q <= imem[imem_ra];
  end

  // ---------------------------------------------------------------- host_in FIFO, 16 bytes
  reg [7:0] hin [0:15];
  reg [3:0] hin_wr = 4'd0, hin_rd = 4'd0;
  reg [4:0] hin_cnt = 5'd0;
  reg hin_push = 1'b0; reg [7:0] hin_din = 8'd0;
  wire host_in_valid = hin_cnt != 5'd0;
  wire [7:0] host_in = hin[hin_rd];
  wire host_in_ready;
  wire hin_pop = host_in_ready && host_in_valid && running;
  always @(posedge clk) begin
    if (rst) begin hin_wr <= 4'd0; hin_rd <= 4'd0; hin_cnt <= 5'd0; end
    else begin
      if (hin_push && !hin_cnt[4]) begin hin[hin_wr] <= hin_din; hin_wr <= hin_wr + 4'd1; end
      if (hin_pop) hin_rd <= hin_rd + 4'd1;
      hin_cnt <= hin_cnt + ((hin_push && !hin_cnt[4]) ? 5'd1 : 5'd0) - (hin_pop ? 5'd1 : 5'd0);
    end
  end

  // ---------------------------------------------------------------- the sequencer
  wire [7:0] host_out; wire host_out_valid; wire [23:0] pcs;
  // The sub-slot sequencer (deadline-sequencer after the multiphase merge) also takes pin_in4,
  // four samples per pin and clock, for SHI's quad mode. Pins without a quad sampler present
  // their one synchronised sample in all four quarters, which is what Isa.step assumes when
  // called without ?pin_in4, so the replay stays exact. pin_sub (each pin's level per quarter)
  // only matters to the four-phase stage; the plain build leaves it unconnected and drives the
  // pads from pin_out, which equals quarter 3 of pin_sub.
  wire [31:0] pin_in4;
  wire [31:0] pin_sub_w;
  genvar qi;
  generate for (qi = 0; qi < 8; qi = qi + 1) begin : quad
`ifdef EMU_MULTIPHASE
    assign pin_in4[4*qi+3:4*qi] = quad_pins[qi] ? quad_samples[4*qi+3:4*qi] : {4{pin_s2[qi]}};
`else
    assign pin_in4[4*qi+3:4*qi] = {4{pin_s2[qi]}};
`endif
  end endgenerate
`ifdef EMU_MULTIPHASE
  assign seq_pin_sub = pin_sub_w;
`endif
  deadline_sequencer seq (
    .pin_in4(pin_in4), .pin_sub(pin_sub_w),
    .clock(clk), .clear(in_clear),
    .imem_data(imem_q), .imem_addr(core_imem_addr),
    .pin_in(pin_s2), .pin_out(core_pin_out), .pin_oe(core_pin_oe),
    .host_in(host_in), .host_in_valid(host_in_valid && running), .host_in_ready(host_in_ready),
    .host_out(host_out), .host_out_valid(host_out_valid), .pcs(pcs));

  // ---------------------------------------------------------------- trace recorder
  wire [7:0] tr_flags = {5'd0, host_in_valid && running, host_in_ready, host_out_valid};
  wire [47:0] tr_fields = {pin_s2, core_pin_out, core_pin_oe, tr_flags, host_out, host_in};
  reg [47:0] tr_prev = 48'd0;
  reg [79:0] trace [0:TRACE_DEPTH-1];
  reg [TRACE_AW:0] tr_cnt = 0;
  reg tr_ovf = 1'b0;
  reg [31:0] tr_trunc = 32'd0;
  reg [TRACE_AW-1:0] tr_ra = 0;
  reg [79:0] tr_q = 80'd0;
  wire tr_want = running && (cycle == 32'd0 || tr_fields != tr_prev);
  wire tr_full = tr_cnt == TRACE_DEPTH;
  always @(posedge clk) begin
    if (running) tr_prev <= tr_fields;
    if (tr_want && !tr_full && !tr_ovf) trace[tr_cnt[TRACE_AW-1:0]] <= {cycle, tr_fields};
    tr_q <= trace[tr_ra];
    if (rstate == S_PRIME) begin tr_cnt <= 0; tr_ovf <= 1'b0; tr_trunc <= 32'd0; end
    else if (tr_want && !tr_ovf) begin
      if (tr_full) begin tr_ovf <= 1'b1; tr_trunc <= cycle; end
      else tr_cnt <= tr_cnt + 1'b1;
    end
  end
  assign trace_ovf_o = tr_ovf;
  wire [15:0] tr_cnt16 = tr_cnt;

  // ---------------------------------------------------------------- streamer and its buffer
  reg [19:0] sbuf [0:63];
  reg [6:0] s_idx = 7'd0;
  wire str_full;
  wire [11:0] str_period = cfg[1][11:0];
  wire [6:0] str_len = cfg[3][6:0];
  wire str_push = running && (s_idx < str_len) && !str_full;
  wire [19:0] s_entry = sbuf[s_idx[5:0]];
  wire [3:0] str_out, str_oe;
  pin_streamer str (
    .clock(clk), .clear(in_clear),
    .period(str_period), .width(cfg[2][2:0]), .od_mask(cfg[2][7:4]),
    .idle_out(cfg[2][11:8]), .idle_oe(cfg[2][15:12]),
    .host_data(s_entry[15:0]), .host_count(s_entry[19:16]), .host_push(str_push),
    .pin_out(str_out), .pin_oe(str_oe), .full(str_full));
  always @(posedge clk) begin
    if (rstate == S_PRIME) s_idx <= 7'd0;
    else if (str_push) s_idx <= s_idx + 7'd1;
  end
  assign str_pad_out = str_out;
  assign str_pad_oe = str_oe;
  wire [3:0] str_level = (str_oe & str_out) | ~str_oe;   // released lines float high (pull-up)

  // ---------------------------------------------------------------- sampler and its capture
  reg [3:0] smp_s1 = 4'hF, smp_s2 = 4'hF;
  always @(posedge clk) begin smp_s1 <= r_sloop ? str_level : smp_pad_in; smp_s2 <= smp_s1; end
  wire [15:0] smp_data; wire [3:0] smp_count; wire smp_valid; wire [7:0] smp_ovf;
  pin_sampler smp (
    .clock(clk), .clear(in_clear), .pins(smp_s2),
    .clocked(cfg[6][3]), .period(cfg[4][11:0]), .width(cfg[6][2:0]),
    .trig_pin(cfg[6][5:4]), .trig_val(cfg[6][6]), .offset(cfg[5][11:0]),
    .frame_len(cfg[6][15:8]), .pop(smp_valid && running),
    .data(smp_data), .count(smp_count), .valid(smp_valid), .overflows(smp_ovf));
  reg [19:0] cap [0:255];
  reg [8:0] cap_cnt = 9'd0;
  reg [7:0] cap_ra = 8'd0;
  reg [19:0] cap_q = 20'd0;
  reg [7:0] smp_ovf_hold = 8'd0;
  always @(posedge clk) begin
    if (running && smp_valid && !cap_cnt[8]) cap[cap_cnt[7:0]] <= {smp_count, smp_data};
    cap_q <= cap[cap_ra];
    if (rstate == S_PRIME) cap_cnt <= 9'd0;
    else if (running && smp_valid && !cap_cnt[8]) cap_cnt <= cap_cnt + 9'd1;
    if (running) smp_ovf_hold <= smp_ovf;
  end

  // ---------------------------------------------------------------- command engine
  localparam C_OP = 4'd0, C_ARG = 4'd1, C_EXEC = 4'd2, C_REPLY = 4'd3, C_WAITRUN = 4'd4,
             C_TR_HDR = 4'd5, C_TR_RD = 4'd6, C_TR_WAIT = 4'd7, C_TR_SEND = 4'd8,
             C_CAP_HDR = 4'd9, C_CAP_RD = 4'd10, C_CAP_WAIT = 4'd11, C_CAP_SEND = 4'd12;
  reg [3:0] cst = C_OP;
  reg [7:0] op = 8'd0;
  reg [39:0] args = 40'd0;
  reg [2:0] need = 3'd0;
  reg [79:0] rbuf = 80'd0;     // reply bytes, sent MSB first
  reg [3:0] rlen = 4'd0;       // bytes left in rbuf
  reg [TRACE_AW:0] didx = 0;   // dump index
  reg [3:0] rnext = 4'd0;      // state after the reply drains (as a C_* code)

  function [2:0] nargs(input [7:0] o);
    case (o)
      "W": nargs = 3'd4; "R": nargs = 3'd2; "K": nargs = 3'd3; "H": nargs = 3'd1;
      "B": nargs = 3'd5; "G": nargs = 3'd4;
      default: nargs = 3'd0;
    endcase
  endfunction

  always @(posedge clk) begin
    txf_push <= 1'b0;
    imem_we <= 1'b0;
    hin_push <= 1'b0;
    // run sequencing
    case (rstate)
      S_PRIME: begin rstate <= S_RUN; cycle <= 32'd0; end
      S_RUN: begin
        if (cycle == run_len - 32'd1 || (rx_valid && rx_data == "X")) rstate <= S_IDLE;
        cycle <= cycle + 32'd1;
      end
      default: ;
    endcase
    if (rst) begin
      cst <= C_OP; rstate <= S_IDLE; rlen <= 4'd0;
    end else case (cst)
      C_OP: if (rx_valid) begin
        op <= rx_data; need <= nargs(rx_data); args <= 40'd0;
        cst <= (nargs(rx_data) == 3'd0) ? C_EXEC : C_ARG;
      end
      C_ARG: if (rx_valid) begin
        args <= {args[31:0], rx_data};
        need <= need - 3'd1;
        if (need == 3'd1) cst <= C_EXEC;
      end
      C_EXEC: begin
        cst <= C_REPLY; rnext <= C_OP;
        case (op)
          "I": begin rbuf <= {"EMU1", TAW8, cfg[0], "k", 16'd0}; rlen <= 4'd8; end
          "W": begin
            if (!running) begin imem_we <= 1'b1; imem_wa <= args[23:16]; imem_wd <= args[15:0]; end
            rbuf <= {"k", 72'd0}; rlen <= 4'd1;
          end
          "R": begin host_ra <= args[7:0]; cst <= C_TR_WAIT; rnext <= C_OP; didx <= 0; rlen <= 4'd0; end
          "K": begin cfg[args[18:16]] <= args[15:0]; rbuf <= {"k", 72'd0}; rlen <= 4'd1; end
          "H": begin
            hin_push <= !hin_cnt[4]; hin_din <= args[7:0];
            rbuf <= {(hin_cnt[4] ? "f" : "k"), 72'd0}; rlen <= 4'd1;
          end
          "B": begin sbuf[args[29:24]] <= args[19:0]; rbuf <= {"k", 72'd0}; rlen <= 4'd1; end
          "G": begin
            run_len <= args[31:0];
            if (args[31:0] != 32'd0) begin rstate <= S_PRIME; cst <= C_WAITRUN; end
            else begin rbuf <= {"g", 72'd0}; rlen <= 4'd1; end
          end
          "T": begin rbuf <= {tr_cnt16, 7'd0, tr_ovf, tr_trunc, 24'd0}; rlen <= 4'd7; rnext <= C_TR_RD; didx <= 0; end
          "S": begin rbuf <= {7'd0, cap_cnt, 64'd0}; rlen <= 4'd2; rnext <= C_CAP_RD; didx <= 0; end
          "Z": begin rbuf <= {board_status, smp_ovf_hold, 7'd0, tr_ovf, "k", 48'd0}; rlen <= 4'd4; end
          default: begin rbuf <= {"?", 72'd0}; rlen <= 4'd1; end
        endcase
      end
      C_WAITRUN: if (rstate == S_IDLE) begin rbuf <= {"g", 72'd0}; rlen <= 4'd1; cst <= C_REPLY; rnext <= C_OP; end
      C_REPLY: begin
        if (rlen == 4'd0) cst <= rnext;
        else if (!txf_full && !txf_push) begin
          txf_push <= 1'b1; txf_din <= rbuf[79:72]; rbuf <= {rbuf[71:0], 8'd0}; rlen <= rlen - 4'd1;
        end
      end
      // imem readback ('R'): address set, wait one cycle for the synchronous read
      C_TR_WAIT: begin cst <= C_TR_SEND; end
      C_TR_SEND: begin
        if (op == "R") begin rbuf <= {imem_q, 64'd0}; rlen <= 4'd2; rnext <= C_OP; cst <= C_REPLY; end
        else begin rbuf <= tr_q; rlen <= 4'd10; rnext <= C_TR_RD; cst <= C_REPLY; didx <= didx + 1'b1; end
      end
      C_TR_RD: begin
        if (didx == tr_cnt) cst <= C_OP;
        else begin tr_ra <= didx[TRACE_AW-1:0]; cst <= C_TR_WAIT; end
      end
      C_CAP_RD: begin
        if (didx[8:0] == cap_cnt) cst <= C_OP;
        else begin cap_ra <= didx[7:0]; cst <= C_CAP_WAIT; end
      end
      C_CAP_WAIT: cst <= C_CAP_SEND;
      C_CAP_SEND: begin rbuf <= {4'd0, cap_q, 56'd0}; rlen <= 4'd3; rnext <= C_CAP_RD; cst <= C_REPLY; didx <= didx + 1'b1; end
      default: cst <= C_OP;
    endcase
  end
endmodule

`default_nettype wire
