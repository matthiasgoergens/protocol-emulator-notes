// Dedicated protocol assists, written as AREA PROBES for notes/architecture-v0.md (not verified).
// Each is the smallest generic version: programmable, protocol-agnostic.

// Programmable CRC / LFSR, W bits, N bits per clock (N = 1: bit-serial; N = 8: byte-wise).
// Left-aligned Galois form: any polynomial of width <= W; dir = 1 shifts right (reflected
// CRCs such as Ethernet's and USB's), dir = 0 shifts left. The polynomial and the state are
// loaded over a byte bus (ld_poly / ld_state shift a byte in); the state is read back whole.
// With din held at 0 it is a free-running LFSR (scrambler, whitening, PRBS, Gold-code half).
module crc_unit #(parameter W = 32, parameter N = 1) (
  input  wire         clk,
  input  wire         clear,
  input  wire [7:0]   bus,
  input  wire         ld_poly,
  input  wire         ld_state,
  input  wire         dir,
  input  wire         en,
  input  wire [N-1:0] din,
  output wire [W-1:0] state,
  output wire         zero        // state == 0: residue check after the complement trick
);
  reg [W-1:0] s, poly;
  reg [W-1:0] nx;
  integer k;
  always @* begin
    nx = s;
    for (k = 0; k < N; k = k + 1) begin
      if (dir) nx = (nx >> 1) ^ ((nx[0] ^ din[k]) ? poly : {W{1'b0}});
      else     nx = (nx << 1) ^ ((nx[W-1] ^ din[k]) ? poly : {W{1'b0}});
    end
  end
  always @(posedge clk) begin
    if (clear) s <= {W{1'b0}};
    else if (ld_state) s <= {s[W-9:0], bus};
    else if (en) s <= nx;
    if (ld_poly) poly <= {poly[W-9:0], bus};
  end
  assign state = s;
  assign zero = (s == {W{1'b0}});
endmodule

// Bit stuffing / destuffing with a programmable run length (USB: 6 ones; CAN: 5 equal bits).
// TX (rx = 0): pulls bits from a FIFO (in_valid / in_ready) and emits one bit per strobe; after
// run equal bits (of value val, or of either value when either = 1) it emits the complement
// instead of pulling. RX (rx = 1): drops the bit after a run (out_valid low) and flags an error
// if that bit does not break the run (a stuffing violation: CAN error frame, USB EOP/abort).
module stuff_unit (
  input  wire       clk,
  input  wire       clear,
  input  wire [3:0] run,
  input  wire       val,
  input  wire       either,
  input  wire       rx,
  input  wire       strobe,       // one bit time
  input  wire       in_bit,
  input  wire       in_valid,
  output wire       in_ready,
  output reg        out_bit,
  output reg        out_valid,
  output reg        err
);
  reg [3:0] cnt;
  reg       last;
  wire full = (cnt == run);
  wire stuff_now = full;
  assign in_ready = strobe & (rx | ~stuff_now);
  wire b = (~rx & stuff_now) ? ~last : in_bit;
  wire counts = either ? (b == last) : (b == val);
  always @(posedge clk) begin
    if (clear) begin
      cnt <= 4'd0; last <= 1'b0; out_bit <= 1'b0; out_valid <= 1'b0; err <= 1'b0;
    end else if (strobe & (in_valid | (~rx & stuff_now))) begin
      out_bit <= b;
      out_valid <= ~(rx & full);
      err <= rx & full & counts;
      cnt <= (full | ~counts) ? (either ? 4'd1 : {3'd0, b == val}) : cnt + 4'd1;
      last <= b;
    end else begin
      out_valid <= 1'b0;
    end
  end
endmodule

// Line coding on one bit stream: NRZI (USB, 100BASE-FX), Manchester (10BASE-T) and differential
// Manchester, encode or decode (NRZI only; Manchester decode is edge timing, done by the
// oversampling front end and a PE), optional inversion. Manchester doubles the rate: the unit
// emits two half-bits per bit and asks for a new bit every second strobe.
module linecode_unit (
  input  wire       clk,
  input  wire       clear,
  input  wire [1:0] mode,          // 0 pass, 1 NRZI, 2 Manchester, 3 differential Manchester
  input  wire       dec,           // NRZI decode
  input  wire       inv,
  input  wire       strobe,        // one half-bit (Manchester) or one bit time
  input  wire       in_bit,
  output wire       in_ready,
  output reg        out_bit
);
  reg prev, half, level;
  assign in_ready = strobe & ((mode[1] == 1'b0) | half);
  always @(posedge clk) begin
    if (clear) begin
      prev <= 1'b0; half <= 1'b1; level <= 1'b0; out_bit <= 1'b0;
    end else if (strobe) begin
      case (mode)
        2'd0: out_bit <= in_bit ^ inv;
        2'd1: begin
          if (dec) begin out_bit <= ~(in_bit ^ prev) ^ inv; prev <= in_bit; end
          else begin level <= level ^ ~in_bit; out_bit <= (level ^ ~in_bit) ^ inv; end
        end
        2'd2: begin
          out_bit <= (half ? ~in_bit : in_bit) ^ inv;   // IEEE 802.3: 1 is low then high
          half <= ~half;
        end
        default: begin
          if (half) level <= level ^ ~in_bit;            // transition at start for a 0
          out_bit <= (half ? (level ^ ~in_bit) : ~level) ^ inv;
          half <= ~half;
        end
      endcase
    end
  end
endmodule

// Segment interconnect for a partitionable array of NPE PEs cut into segments of KSEG PEs.
// At each segment start the PE's A input picks one of: the previous segment's end (join), its
// own segment's end (loop into a ring), one of NSRC external sources (sequencer push registers,
// sampler word, memory read ports), or zero. Each of NDST destinations (sequencer pull
// registers, memory write data, the streamer) picks one segment end. 17 bits per port (16 data +
// valid). Only the multiplexers are counted: the PEs are outside.
module seg_xbar #(parameter NPE = 16, parameter KSEG = 4, parameter NSRC = 8, parameter NDST = 8) (
  input  wire                         clk,
  input  wire [NPE*17-1:0]            pe_p,        // every PE's P lane + valid
  input  wire [NSRC*17-1:0]           src,
  input  wire [(NPE/KSEG)*8-1:0]      sel_in,      // per segment start: 0 join, 1 loop, 2.. src, 255 zero
  input  wire [NDST*8-1:0]            sel_out,     // per destination: segment index
  output reg  [(NPE/KSEG)*17-1:0]     seg_a,       // A input of each segment's first PE
  output reg  [NDST*17-1:0]           dst
);
  localparam NS = NPE / KSEG;
  integer s, q;
  reg [7:0] m;
  always @* begin
    for (s = 0; s < NS; s = s + 1) begin
      m = sel_in[s*8 +: 8];
      if (m == 8'd0 && s > 0)      seg_a[s*17 +: 17] = pe_p[(s*KSEG-1)*17 +: 17];
      else if (m == 8'd1)          seg_a[s*17 +: 17] = pe_p[((s+1)*KSEG-1)*17 +: 17];
      else if (m >= 8'd2 && m < 8'd2 + NSRC) seg_a[s*17 +: 17] = src[(m-2)*17 +: 17];
      else                         seg_a[s*17 +: 17] = 17'd0;
    end
    for (q = 0; q < NDST; q = q + 1) begin
      m = sel_out[q*8 +: 8];
      dst[q*17 +: 17] = 17'd0;
      for (s = 0; s < NS; s = s + 1)
        if (m == s) dst[q*17 +: 17] = pe_p[((s+1)*KSEG-1)*17 +: 17];
    end
  end
endmodule

// Wrapper that registers the crossbar's configuration (so selects are not free inputs) and
// its inputs and outputs are ports; the configuration costs flops like everything else.
module seg_xbar_cfg #(parameter NPE = 16, parameter KSEG = 4, parameter NSRC = 8, parameter NDST = 8) (
  input  wire                         clk,
  input  wire [7:0]                   cfg_in,
  input  wire                         cfg_strobe,
  input  wire [NPE*17-1:0]            pe_p,
  input  wire [NSRC*17-1:0]           src,
  output wire [(NPE/KSEG)*17-1:0]     seg_a,
  output wire [NDST*17-1:0]           dst
);
  localparam NS = NPE / KSEG;
  localparam SW_IN = 4, SW_OUT = 3;            // select widths actually needed
  reg [NS*SW_IN + NDST*SW_OUT - 1:0] cfg;
  always @(posedge clk) if (cfg_strobe) cfg <= {cfg[NS*SW_IN + NDST*SW_OUT - 9:0], cfg_in};
  wire [NS*8-1:0] si;
  wire [NDST*8-1:0] so;
  genvar s;
  generate
    for (s = 0; s < NS; s = s + 1) begin : gi
      assign si[s*8 +: 8] = {4'd0, cfg[s*SW_IN +: SW_IN]};
    end
    for (s = 0; s < NDST; s = s + 1) begin : go
      assign so[s*8 +: 8] = {5'd0, cfg[NS*SW_IN + s*SW_OUT +: SW_OUT]};
    end
  endgenerate
  seg_xbar #(.NPE(NPE), .KSEG(KSEG), .NSRC(NSRC), .NDST(NDST)) x (
    .clk(clk), .pe_p(pe_p), .src(src), .sel_in(si), .sel_out(so), .seg_a(seg_a), .dst(dst));
endmodule

// Pin NCO (area probe): a phase accumulator evaluated at the four quarter points of each clock,
// so the four-phase output stage can place the carrier's edges on the quarter grid
// (prototypes/multiphase/nco.ml is the verified original). Output: the phase MSB at quarters
// 0..3 as a nibble. Also an 8-bit phase output for a PE (colour subcarrier phase, AM, PWM).
module pin_nco #(parameter W = 24) (
  input  wire         clk,
  input  wire         clear,
  input  wire [7:0]   bus,
  input  wire         ld_inc,
  input  wire         en,
  output wire [3:0]   nibble,
  output wire [7:0]   phase
);
  reg [W-1:0] acc, inc;
  wire [W-1:0] q1 = acc + {2'b00, inc[W-1:2]};
  wire [W-1:0] q2 = acc + {1'b0, inc[W-1:1]};
  wire [W-1:0] q3 = q2 + {2'b00, inc[W-1:2]};
  always @(posedge clk) begin
    if (clear) acc <= {W{1'b0}};
    else if (en) acc <= acc + inc;
    if (ld_inc) inc <= {inc[W-9:0], bus};
  end
  assign nibble = {q3[W-1], q2[W-1], q1[W-1], acc[W-1]};
  assign phase = acc[W-1:W-8];
endmodule

// Oversampling front end with resynchronisation (area probe): one input pin's four quarter
// samples per clock (from the four-phase stage) -> recovered bits. NRZ mode: a fractional
// bit-period counter in quarters (8.4 fixed point) re-aligned to half a period on every edge,
// sampling mid-bit (UART, USB, CAN, 100BASE-FX after NRZI). Manchester mode: an edge more than
// 3/4 of a bit after the last counted edge is a mid-bit edge and emits the new level (10BASE-T).
module cdr_unit (
  input  wire        clk,
  input  wire        clear,
  input  wire [3:0]  s4,            // quarter samples of this clock, s4[0] first
  input  wire [11:0] period,        // bit period in quarters, 8.4 fixed point
  input  wire        manchester,
  output reg         bit_out,
  output reg         bit_valid
);
  reg        last;
  reg [11:0] ctr;                   // quarters since the reference point, 8.4
  reg [11:0] since;                 // quarters since the last counted edge (Manchester)
  // first edge position within this clock's four samples
  wire e0 = s4[0] ^ last, e1 = s4[1] ^ s4[0], e2 = s4[2] ^ s4[1], e3 = s4[3] ^ s4[2];
  wire edge_any = e0 | e1 | e2 | e3;
  wire [1:0] epos = e0 ? 2'd0 : e1 ? 2'd1 : e2 ? 2'd2 : 2'd3;
  wire [11:0] half = {1'b0, period[11:1]};
  wire [11:0] three_q = half + {2'b00, period[11:2]};
  wire [11:0] ctr_next = ctr + 12'd64;               // four quarters per clock, 8.4
  wire [11:0] since_e = since + {6'd0, epos, 4'd0};
  always @(posedge clk) begin
    if (clear) begin
      last <= 1'b0; ctr <= 12'd0; since <= 12'd0; bit_out <= 1'b0; bit_valid <= 1'b0;
    end else begin
      last <= s4[3];
      bit_valid <= 1'b0;
      if (manchester) begin
        if (edge_any && since_e >= three_q) begin
          bit_out <= s4[3]; bit_valid <= 1'b1; since <= 12'd64 - {6'd0, epos, 4'd0};
        end else since <= since + 12'd64;
      end else begin
        if (edge_any) ctr <= half + 12'd64 - {6'd0, epos, 4'd0};
        else if (ctr_next >= period) begin
          ctr <= ctr_next - period; bit_out <= s4[1]; bit_valid <= 1'b1;
        end else ctr <= ctr_next;
      end
    end
  end
endmodule
