// blackbox of the hard macro GC_ARRAY_32x38 (see gc_array.py)
(* blackbox *)
module GC_ARRAY_32x38 (
`ifdef USE_POWER_PINS
    inout  wire GND,
`endif
    input  wire [31:0] WWL,
    input  wire [31:0] RWL,
    input  wire [37:0] WBL,
    inout  wire [37:0] RBL
);
endmodule
