// Unified processing element (UPE), version 0: an AREA PROBE for notes/architecture-v0.md.
// It is written to be synthesised, not yet verified: there is no executable specification or
// lockstep test for it yet (that is gap G1 in the architecture note). Every feature can be
// compiled out with a define, so that the incremental area of each mode can be measured:
//   NO_GF2    no XOR/AND/OR, no shifts with serial input, no operand gating by g (and no POP result)
//   NO_SHIFT, NO_LOGIC, NO_GATE   the three parts of NO_GF2 one at a time
//   NO_POP    no popcount-match unit (correlator/sync-word tap, parity) and no threshold flag
//   NO_LUT    no 16-entry truth-table lookup of g
//   NO_WIN    no position window (sprite/tile cell) and no colour merge on the P lane
//   NO_LANES  no valid/stream stepping, no bit lane, no pair and carry-back wires
//   BITSEL    (adds) g may test any bit of A, chosen by op[39:36]
// The configuration recommended in the architecture note is -DNO_POP -DNO_LUT -DBITSEL ("upe_v0").
// With all five defined the PE is close to prototypes/pe-synth's pe16 (add/sub/max/min with
// saturation, x from state or neighbour, y from k or state), plus a wrapping add.
//
// Registers: S (16-bit state), P (16-bit pipeline to the right neighbour), F (flag), B lane bits,
// and a configuration chain of 8 bytes (op, 6 bytes; K, 2 bytes), shifted in by cfg_strobe.
// The bit lane doubles as the "tag lane" of prototypes/gps-hotcold (on master): a one-bit value
// beside the word that can negate an operand (ym = 2 with gs = b_in), act as carry-in (cinb),
// or carry the MSB or the carry-out onward (bsel), so two PEs make a 32-bit accumulator/NCO.
// S can be loaded per line through the init chain (as in prototypes/semiring-ring).
//
// op fields (48 bits):
//   [2:0]   f    ALU: 0 ADD saturating, 1 ADD wrapping, 2 MAX, 3 MIN, 4 XOR, 5 AND, 6 OR,
//                7 POP (result = A + popcount(mask(len) & (popsrc ? S & Y : ~(S ^ Y))))
//   [4:3]   xs   X = S | A | S << 1 with sin | S >> 1 with sin
//   [6:5]   ys   Y = K | A | S | 1
//   [8:7]   ym   Y' = Y | (g ? Y : 0) | (g ? -Y : Y) | -Y   (for XOR/AND/OR, -Y means ~Y)
//   [11:9]  gs   g = 1 | A[0] | b_in | A[0]^b_in | fb | F | lut/window | g_in
//                fb = (pairlo ? cb_in : S[15]) ^ A[0]      (Galois LFSR / CRC feedback)
//   [13:12] sw   S <= hold | result | X | (g ? result : hold)
//   [15:14] pw   P <= A | result | loser of MAX/MIN | (g ? {A[15:8], K[7:0]} : A)
//   [17:16] sins sin = b_in | s15_in | parity (popcount bit 0) | g
//   [18]    popsrc
//   [22:19] len  popcount mask: low len bits, 0 = all 16
//   [27:23] thr  F <= (result >= thr) in POP mode, else F <= g
//   [29:28] ix   lookup: g_lut = K[A[3:0]] | K[S[3:0]] | K[{b_in, A[0], S[1:0]}] |
//                window: d = A[15:8] - K[15:8]; g = (d < 16) & S[15 - d]
//   [30]    stream  step only when a_valid
//   [41],[31] bsel  b_out = lane register | S[15] | carry-out register | g
//   [32]    drop    p_valid = a_valid & ~g (deletes a bit: destuffing, compaction)
//   [33]    bcast   the lane input is the segment's broadcast bit bc_in (else b_in)
//   [34]    pairlo  fb uses cb_in (the right neighbour's S[15]) instead of S[15]
//   [35]    outs    s_out shows S (else P)
//   [39:36] ib   with BITSEL defined, gs = 1 tests A[ib] instead of A[0] (bit test)
//   [40]    cinb    the adder's carry-in is the lane input (multi-word add, ones' complement)
//   [42]    zf      F <= (result == 0) instead of g (CRC residue checks, equality tests)
//   [47:43] spare
module upe (
  input  wire        clk,
  input  wire        clear,
  input  wire [7:0]  cfg_in,
  input  wire        cfg_strobe,
  output wire [7:0]  cfg_out,
  input  wire [7:0]  init_in,
  input  wire        init_strobe,
  input  wire        en,
  input  wire [15:0] a_in,
  input  wire        a_valid,
  output reg  [15:0] p_out,
  output reg         p_valid,
  input  wire        b_in,
  input  wire        bc_in,
  output wire        b_out,
  input  wire        cb_in,
  output wire        cb_out,
  input  wire        s15_in,
  input  wire        g_in,
  output wire        s15_out,
  output wire        g_out,
  output wire        flag,
  output wire [15:0] s_out
);
  // configuration chain: 7 bytes, first shifted byte ends in c[6]
  reg [7:0] c [0:7];
  integer j;
  always @(posedge clk) if (cfg_strobe) begin
    c[0] <= cfg_in;
    for (j = 1; j < 8; j = j + 1) c[j] <= c[j-1];
  end
  assign cfg_out = c[7];
  wire [47:0] op = {c[7], c[6], c[5], c[4], c[3], c[2]};
  wire [15:0] K  = {c[1], c[0]};

  wire [2:0] f    = op[2:0];
  wire [1:0] xs   = op[4:3];
  wire [1:0] ys   = op[6:5];
  wire [1:0] ym   = op[8:7];
  wire [2:0] gs   = op[11:9];
  wire [1:0] sw   = op[13:12];
  wire [1:0] pw   = op[15:14];
  wire [1:0] sins = op[17:16];
  wire       popsrc = op[18];
  wire [3:0] len  = op[22:19];
  wire [4:0] thr  = op[27:23];
  wire [1:0] ix   = op[29:28];
  wire       stream = op[30];
  wire [1:0] bsel = {op[41], op[31]};
  wire       drop = op[32];
  wire       bcast = op[33];
  wire       pairlo = op[34];
  wire       outs = op[35];
  wire [3:0] ib   = op[39:36];
  wire       cinb = op[40];
  wire       zf   = op[42];

  reg  [15:0] S;
  reg         F;
  reg         b1, cr;
  wire [15:0] A = a_in;

`ifdef NO_LANES
  wire step = en;
  wire bi = 1'b0, cbi = 1'b0, s15i = 1'b0, gi = 1'b0;
`else
  wire step = en & (~stream | a_valid);
  wire bi = bcast ? bc_in : b_in, cbi = cb_in, s15i = s15_in, gi = g_in;
`endif

  // ---- popcount-match unit ----
  wire [15:0] X, Y;
`ifdef NO_POP
  wire [4:0] pop = 5'd0;
`else
  wire [15:0] lenmask = (len == 4'd0) ? 16'hffff : ((16'h1 << len) - 16'h1);
  wire [15:0] psrc = lenmask & (popsrc ? (S & Y) : ~(S ^ Y));   // on S, not X: no loop through sin
  reg  [4:0] pop;
  integer i;
  always @* begin
    pop = 5'd0;
    for (i = 0; i < 16; i = i + 1) pop = pop + {4'd0, psrc[i]};
  end
`endif

  // ---- condition bit g ----
  wire fb = (pairlo ? cbi : S[15]) ^ A[0];
  wire [7:0] d = A[15:8] - K[15:8];
  wire g_lk;
`ifdef NO_LUT
  wire g_lut = 1'b0;
`else
  wire [3:0] lidx = (ix == 2'd0) ? A[3:0] : (ix == 2'd1) ? S[3:0] : {bi, A[0], S[1:0]};
  wire g_lut = K[lidx];
`endif
`ifdef NO_WIN
  wire g_win = 1'b0;
`else
  wire g_win = (d[7:4] == 4'd0) & S[4'd15 - d[3:0]];
`endif
  assign g_lk = (ix == 2'd3) ? g_win : g_lut;
  reg g;
  always @* case (gs)
    3'd0: g = 1'b1;
`ifdef BITSEL
    3'd1: g = A[ib];
`else
    3'd1: g = A[0];
`endif
    3'd2: g = bi;
    3'd3: g = A[0] ^ bi;
    3'd4: g = fb;
    3'd5: g = F;
    3'd6: g = g_lk;
    default: g = gi;
  endcase
  assign g_out = g;

  // ---- serial input and X ----
  reg sin;
  always @* case (sins)
    2'd0: sin = bi;
    2'd1: sin = s15i;
    2'd2: sin = pop[0];
    default: sin = g;
  endcase
`ifdef NO_GF2
  assign X = xs[0] ? A : S;
`elsif NO_SHIFT
  assign X = xs[0] ? A : S;
`else
  assign X = (xs == 2'd0) ? S : (xs == 2'd1) ? A : (xs == 2'd2) ? {S[14:0], sin} : {sin, S[15:1]};
`endif
  assign Y = (ys == 2'd0) ? K : (ys == 2'd1) ? A : (ys == 2'd2) ? S : 16'd1;

  // ---- ALU ----
  wire is_mm = (f == 3'd2) | (f == 3'd3);
`ifdef NO_GF2
  wire [15:0] Yg = Y;
  wire neg = is_mm | (ym == 2'd3) | ((ym == 2'd2) & g);
`elsif NO_GATE
  wire [15:0] Yg = Y;
  wire neg = is_mm | (ym == 2'd3) | ((ym == 2'd2) & g);
`else
  wire [15:0] Yg = ((ym == 2'd1) & ~g) ? 16'd0 : Y;
  wire neg = is_mm | (ym == 2'd3) | ((ym == 2'd2) & g);
`endif
  wire [15:0] Yn = neg ? ~Yg : Yg;
  wire cin = neg | (cinb & bi);
  wire [16:0] t = {X[15], X} + {Yn[15], Yn} + {16'd0, cin};
  wire cout = (X[15] & Yn[15]) | ((X[15] ^ Yn[15]) & ~t[15]);   // unsigned carry out of bit 15
  wire ovf = t[16] ^ t[15];
  wire [15:0] sat = ovf ? (t[16] ? 16'h8000 : 16'h7fff) : t[15:0];
  wire lt = t[16];                       // X - Y < 0 when is_mm
  wire [15:0] mx = lt ? Y : X;
  wire [15:0] mn = lt ? X : Y;
  reg  [15:0] r;
  always @* case (f)
    3'd0: r = sat;
    3'd1: r = t[15:0];
    3'd2: r = mx;
    3'd3: r = mn;
`ifdef NO_GF2
    default: r = t[15:0];
`elsif NO_LOGIC
    default: r = A + {11'd0, pop};
`else
    3'd4: r = X ^ Yn;
    3'd5: r = X & Yn;
    3'd6: r = X | Yn;
    default: r = A + {11'd0, pop};
`endif
  endcase
  wire [15:0] loser = (f == 3'd2) ? mn : mx;

  // ---- state, pipeline, flag, lanes ----
  always @(posedge clk) begin
    if (clear) begin
      S <= 16'd0; p_out <= 16'd0; p_valid <= 1'b0; F <= 1'b0; b1 <= 1'b0; cr <= 1'b0;
    end else if (init_strobe) begin
      S <= {S[7:0], init_in};
    end else if (step) begin
      case (sw)
        2'd0: S <= S;
        2'd1: S <= r;
        2'd2: S <= X;
        default: S <= g ? r : S;
      endcase
      case (pw)
        2'd0: p_out <= A;
        2'd1: p_out <= r;
        2'd2: p_out <= loser;
`ifdef NO_WIN
        default: p_out <= A;
`else
        default: p_out <= g ? {A[15:8], K[7:0]} : A;
`endif
      endcase
`ifdef NO_POP
      F <= zf ? (r == 16'd0) : g;
`else
      F <= (f == 3'd7) ? (r >= {11'd0, thr}) : g;
`endif
`ifdef NO_LANES
      p_valid <= 1'b1;
`else
      p_valid <= stream ? (a_valid & ~(drop & g)) : 1'b1;
      b1 <= bi;
      cr <= cout;
`endif
    end
  end
`ifdef NO_LANES
  assign b_out = 1'b0; assign cb_out = 1'b0; assign s15_out = 1'b0;
`else
  assign b_out = (bsel == 2'd0) ? b1 : (bsel == 2'd1) ? S[15] : (bsel == 2'd2) ? cr : g;
  assign cb_out = S[15];
  assign s15_out = S[15];
`endif
  assign flag = F;
  assign s_out = outs ? S : p_out;
endmodule
