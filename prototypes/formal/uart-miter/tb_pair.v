// Simulation of uart_pair, 4 bytes (0x4f, 0xa5, 0x3c, 0x81): prints each transmitter's line edges
// and the clock at which each has taken each byte. LOCKED is given on the command line (-DLOCKED=1).
module tb;
  reg clock = 0, clear = 1;
  wire lo, lj; wire [3:0] to, tj;
  uart_pair #(.LOCKED(`LOCKED), .N_BYTES(4)) p(.clock(clock), .clear(clear), .bytes(32'h81_3c_a5_4f), .bytes_js(32'h81_3c_a5_4f),
    .line_ours(lo), .txd_js(lj), .taken_ours(to), .taken_js(tj));
  integer t; reg plo, plj; reg [3:0] pto, ptj;
  initial begin
    plo = 1; plj = 1; pto = 0; ptj = 0;
    for (t = 0; t < 900; t = t + 1) begin
      #1;
      if (t > 0 && lo !== plo) $display("clock %0d ours %0d", t, lo);
      if (t > 0 && lj !== plj) $display("clock %0d js   %0d", t, lj);
      if (to !== pto) $display("clock %0d ours took byte %0d", t, to);
      if (tj !== ptj) $display("clock %0d js   took byte %0d", t, tj);
      plo = lo; plj = lj; pto = to; ptj = tj;
      #4 clock = 1; #5 clock = 0; clear = 0;
    end
    $finish;
  end
endmodule
