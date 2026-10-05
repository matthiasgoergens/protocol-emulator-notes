// Two pixel-domain modules side by side, the same clock and clear: OLD (the Verilog generated
// before the Delayed rewrite, module renamed with an _old suffix) and NEW (generated now).
// Counts the cycles on which any output differs (!==, so X against X counts as equal), and
// separately the cycles on which NEW's words hold an X, so that a run comparing only X is visible,
// and the cycles on which NEW's blue word changes in the second half of the run, so that a run
// comparing two constant outputs is visible too.  (The X count is 0 in practice even before the
// demo's frame buffer is written: Hardcaml emits [mux] as a case statement whose default arm
// catches an X select.)
`timescale 1ns/1ps
`default_nettype none
module tb_compare;
  reg clock = 0, clear = 1;
  always #20 clock = ~clock;
  wire [9:0] ob, og, or_, nb, ng, nr;
  wire ot, ol, nt, nl;
  `OLD u_old (.clock(clock), .clear(clear), .word_b(ob), .word_g(og), .word_r(or_), .toggle(ot), .led_1hz(ol));
  `NEW u_new (.clock(clock), .clear(clear), .word_b(nb), .word_g(ng), .word_r(nr), .toggle(nt), .led_1hz(nl));
  integer t = 0, differ = 0, xs = 0, first = -1, changes = 0;
  reg [9:0] prev_b = 0;
  always @(posedge clock) if (!clear) begin
    #1;
    if ({ob, og, or_, ot, ol} !== {nb, ng, nr, nt, nl}) begin
      differ = differ + 1;
      if (first < 0) first = t;
    end
    if (^{nb, ng, nr} === 1'bx) xs = xs + 1;
    if (t >= `CYCLES / 2 && nb !== prev_b) changes = changes + 1;
    prev_b = nb;
    t = t + 1;
    if (t == `CYCLES) begin
      $display("%0d cycles compared, %0d differ (first at %0d), %0d with an X in NEW's words, %0d changes of NEW's word_b in the second half",
               t, differ, first, xs, changes);
      $finish;
    end
  end
  initial begin
    @(posedge clock); @(posedge clock); #1 clear = 0;
  end
endmodule
