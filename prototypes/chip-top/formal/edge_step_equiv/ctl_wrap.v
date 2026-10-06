// Control for run.sh: the plain step with its holdoff input increased by one, the "holdoff + 1"
// fault the block's own control uses. Same ports as edge_step_new.
module edge_step_ctlw (input [1:0] mode, input [9:0] holdoff, input [9:0] timeout, input [7:0] offset,
  input [7:0] period, input invert, input prev, input in_burst, input [9:0] since, input unq,
  input [7:0] until, input active, input s,
  output n_prev, output n_in_burst, output [9:0] n_since, output n_unq, output [7:0] n_until,
  output emit, output bit, output ended);
  edge_step_plain p (.mode(mode), .holdoff(holdoff + 10'd1), .timeout(timeout), .offset(offset),
    .period(period), .invert(invert), .prev(prev), .in_burst(in_burst), .since(since), .unq(unq),
    .until(until), .active(active), .s(s), .n_prev(n_prev), .n_in_burst(n_in_burst),
    .n_since(n_since), .n_unq(n_unq), .n_until(n_until), .emit(emit), .bit(bit), .ended(ended));
endmodule
