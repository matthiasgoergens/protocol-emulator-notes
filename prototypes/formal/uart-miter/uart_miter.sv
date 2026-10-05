// The miter of our UART programme against Jane Street's Uart.Tx (README.md, section 7). After
// MarcosAsh/protocol-emulator's fsm_miter (Apache-2.0), idea only.
//
// Both transmitters send the same N_BYTES (4) bytes, every byte value free (anyconst); the Tx is
// offered byte i on the clock after our core takes it (uart_pair, LOCKED = 1). Measured first in
// simulation (sim-locked1.txt): the Tx's frame k starts OFFSET_1 - (k - 1) clocks before ours,
// because a back-to-back frame takes the Tx 10 * clocks_per_bit + 1 clocks and our programme
// 10 * clocks_per_bit (5 slots of 4 clocks per bit, the next byte's IN inside the stop bit).
//
// Property "line": from reset on, every clock t, our line at t equals the Tx's line at t - d,
// where d = OFFSET_1 - (k - 1) and k is the frame our core is sending (the number of bytes it has
// taken; d = OFFSET_1 before the first): 3, 2, 1, 0 for the four frames. With CONSTANT = 1, d is
// OFFSET_1 throughout: the claim "equivalent up to a constant offset", which must fail at the
// second frame. A fifth back-to-back frame would put the Tx behind ours (d = -1), so N_BYTES = 4
// is as far as this monitor's delay line reaches.
// FLIP, a control: the Tx is given each byte XOR FLIP; with FLIP != 0 the proof must fail.
module uart_miter #(parameter N_BYTES = 4, parameter OFFSET_1 = 3, parameter CONSTANT = 0, parameter FLIP = 0,
                    parameter ANTE_AS_ASSERT = 0) (
    input clock
);
  (* anyconst *) reg [8 * N_BYTES - 1:0] bytes;
  reg started = 1'b0;
  always @(posedge clock) started <= 1'b1;
  wire clear = !started;

  wire line_ours, txd_js;
  wire [3:0] taken_ours, taken_js;
  uart_pair #(.LOCKED(1), .N_BYTES(N_BYTES)) p (.clock(clock), .clear(clear), .bytes(bytes),
    .bytes_js(bytes ^ {N_BYTES{FLIP[7:0]}}),
    .line_ours(line_ours), .txd_js(txd_js), .taken_ours(taken_ours), .taken_js(taken_js));

  // the Tx's line delayed by 0..7 clocks (bit i: i + 1 clocks ago), idle (high) until the reset
  // has taken effect: during the reset clock its register still holds its power-up value
  reg [7:0] js_past = 8'hff;
  always @(posedge clock) js_past <= {js_past[6:0], clear ? 1'b1 : txd_js};
  wire [3:0] frame = taken_ours == 4'd0 ? 4'd1 : taken_ours;
  wire [3:0] d = CONSTANT ? OFFSET_1 : OFFSET_1 - (frame - 4'd1);
  wire js_then = d == 4'd0 ? txd_js : js_past[d - 4'd1];

  always @(*) if (started) begin
    if (!ANTE_AS_ASSERT) line: assert (line_ours == js_then);
  end

  // the antecedent of "line": both transmitters have taken every byte, and our last frame has
  // had time to finish (its start bit begins 4 clocks after our core takes the byte, and a frame
  // is 10 bits of 20 clocks), so every frame has been compared
  reg [9:0] since_last = 10'd0;
  always @(posedge clock)
    if (started && taken_ours == N_BYTES && since_last != 10'h3ff) since_last <= since_last + 10'd1;
  wire ante = taken_ours == N_BYTES && taken_js == N_BYTES && since_last >= 10'd204;
  // ANTE_AS_ASSERT: the antecedent as the negated assertion line_ante_reach, so that a bit-level
  // BMC (abc bmc3) decides its reachability: FAIL at step n means reachable at step n. smtbmc's
  // cover needed over 20 minutes for the first 82 of the 440 steps.
  generate if (ANTE_AS_ASSERT) begin : reach
    always @(*) if (started) line_ante_reach: assert (!ante);
  end else begin : cov
    always @(*) if (started) line_ante: cover (ante);
  end endgenerate
endmodule
