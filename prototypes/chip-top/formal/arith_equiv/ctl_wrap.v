// Control for run.sh: the plain operators with the adder's carry-in tied to 0.
module arith_ctl (input [15:0] x, input [15:0] y, input c, input [7:0] a, input [7:0] k,
  output [16:0] sum, output ge, output le, output [7:0] d);
  arith_plain p (.x(x), .y(y), .c(1'b0), .a(a), .k(k), .sum(sum), .ge(ge), .le(le), .d(d));
endmodule
