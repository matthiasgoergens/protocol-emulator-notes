// Map Yosys generic positive-enable latches onto the IHP sg13g2 plain latch.
module \$_DLATCH_P_ (input E, input D, output Q);
  sg13g2_dlhq_1 _TECHMAP_REPLACE_ (.D(D), .GATE(E), .Q(Q));
endmodule
