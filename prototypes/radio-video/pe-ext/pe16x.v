// pe16x: the semiring-ring cell narrowed to 16 bits (../../pe-synth ring_cell16: add/sub/max/min
// with saturation, x from the state or one of four neighbours, y from a neighbour or the constant
// k), plus the smallest set of generic extensions the radio and video demos need:
//
//   W  wrap: modular add/sub instead of saturating (NCO phase accumulators, CIC integrators and
//      combs, timers, checksums)
//   P  pipe: a register holding the previous x operand (en-gated); x or y may select it, so
//      x[n] - x[n-1] (combs, differentiators, frame and line differences) is one PE
//   H  arithmetic right shift of the y operand by 0..15 (CORDIC, scaling after CIC, shift-add
//      constant multiplication, averages)
//   E  EMA mode: s <- s + ((x - s) >>> h)  (one-pole low-pass: de-emphasis, loudness and envelope
//      followers, DC and black-level tracking, AGC, loop filters)
//   L  flag LUT: a 4-input LUT with two outputs (negate y, enable the update) over four bits chosen
//      from the neighbours' top bits, the own state's top bits, three sideband bits (e.g. pin
//      samples) and the previous values of the first two inputs (sign-select arithmetic: 1-bit
//      mixing, CORDIC directions, abs; 3-level LOs; quadrature/rotary decoding; edge counting)
//
// Configuration: a byte-wide chain of 10 bytes, shifted in with cfg_strobe (first byte in ends
// last, as in pe16):
//   b0: [1:0] op (0 add, 1 sub, 2 max, 3 min)  [2] wrap  [3] ema  [6:4] xsel  [7] lut_en
//   b1: [2:0] ysel  [6:3] shift  [7] unused
//   b2,b3: k (b2 high byte)
//   b4,b5: four 4-bit LUT input selects (b4[3:0] in0, b4[7:4] in1, b5[3:0] in2, b5[7:4] in3)
//   b6,b7: LUT output 0 (negate y), b6 high byte;  b8,b9: LUT output 1 (enable), b8 high byte
// xsel: 0 s, 1..4 nb1..nb4, 5 pipe, 6 zero, 7 zero.  ysel: 0..3 nb1..nb4, 4 k, 5 s, 6 pipe, 7 zero.
// LUT input sources: 0..3 nb1..nb4 bit 15; 4 nb1 bit 14; 5 nb1 bit 13; 6 nb1 bit 12; 7 s bit 15;
//   8 s bit 14; 9..11 ext[0..2]; 12 previous in0; 13 previous in1; 14 zero; 15 one.
// With lut_en = 0 the PE is the plain cell: never negate, always update.
module pe16x (
    input  wire               clk,
    input  wire               rst,
    input  wire               cfg_strobe,
    input  wire        [7:0]  cfg_in,
    output wire        [7:0]  cfg_out,
    input  wire               en,
    input  wire signed [15:0] nb1, nb2, nb3, nb4,
    input  wire        [2:0]  ext,
    output wire signed [15:0] s_out
);
  reg [7:0] cfg [0:9];
  integer i;
  always @(posedge clk) if (cfg_strobe) begin
    cfg[9] <= cfg_in;
    for (i = 0; i < 9; i = i + 1) cfg[i] <= cfg[i + 1];
  end
  assign cfg_out = cfg[0];

  wire [1:0]  op    = cfg[0][1:0];
  wire        wrap  = cfg[0][2];
  wire        ema   = cfg[0][3];
  wire [2:0]  xsel  = cfg[0][6:4];
  wire        lut_en = cfg[0][7];
  wire [2:0]  ysel  = cfg[1][2:0];
  wire [3:0]  sh    = cfg[1][6:3];
  wire signed [15:0] k = {cfg[2], cfg[3]};
  wire [15:0] lut_neg = {cfg[6], cfg[7]};
  wire [15:0] lut_upd = {cfg[8], cfg[9]};

  reg signed [15:0] s, pipe;
  reg [1:0] hist;

  reg signed [15:0] x, y0;
  always @* begin
    case (xsel)
      3'd0: x = s;   3'd1: x = nb1; 3'd2: x = nb2; 3'd3: x = nb3; 3'd4: x = nb4;
      3'd5: x = pipe; default: x = 16'sd0;
    endcase
    case (ysel)
      3'd0: y0 = nb1; 3'd1: y0 = nb2; 3'd2: y0 = nb3; 3'd3: y0 = nb4;
      3'd4: y0 = k;   3'd5: y0 = s;   3'd6: y0 = pipe; default: y0 = 16'sd0;
    endcase
  end

  wire [15:0] src = {1'b1, 1'b0, hist[1], hist[0], ext, s[14], s[15], nb1[12], nb1[13], nb1[14],
                     nb4[15], nb3[15], nb2[15], nb1[15]};
  wire [3:0] lin = {src[cfg[5][7:4]], src[cfg[5][3:0]], src[cfg[4][7:4]], src[cfg[4][3:0]]};
`ifdef NO_LUT
  wire neg = 1'b0;
  wire upd = 1'b1;
`else
  wire neg = lut_en & lut_neg[lin];
  wire upd = ~lut_en | lut_upd[lin];
`endif

  // E mode shifts (x - s); otherwise the shifter acts on y
  wire signed [16:0] d   = {x[15], x} - {s[15], s};
`ifdef NO_EMA
  wire signed [16:0] shin = {y0[15], y0};
`else
  wire signed [16:0] shin = ema ? d : {y0[15], y0};
`endif
`ifdef NO_SHIFT
  wire signed [16:0] shv = shin;
`else
  wire signed [16:0] shv = shin >>> sh;
`endif
  wire signed [16:0] yv  = neg ? -shv : shv;
`ifdef NO_EMA
  wire ema_on = 1'b0;
`else
  wire ema_on = ema;
`endif
  wire signed [17:0] sum = ema_on ? ({{2{s[15]}}, s} + {shv[16], shv})
                         : (op == 2'd1) ? ({{2{x[15]}}, x} - {yv[16], yv})
                         : ({{2{x[15]}}, x} + {yv[16], yv});
  wire signed [15:0] satv = (sum > 18'sd32767) ? 16'sd32767 : (sum < -18'sd32768) ? -16'sd32768 : sum[15:0];
  wire signed [15:0] arith = wrap ? sum[15:0] : satv;
  wire lt = ($signed({x[15], x}) < yv);
  wire signed [15:0] ysat = (yv > 17'sd32767) ? 16'sd32767 : yv[15:0];
  wire signed [15:0] nxt = ema_on ? arith : (op == 2'd2) ? (lt ? ysat : x) : (op == 2'd3) ? (lt ? x : ysat) : arith;

  always @(posedge clk) begin
    if (rst) begin
      s <= 16'sd0; pipe <= 16'sd0; hist <= 2'b0;
    end else if (en) begin
      if (upd) s <= nxt;
      pipe <= x;
      hist <= lin[1:0];
    end
  end
  assign s_out = s;
endmodule
