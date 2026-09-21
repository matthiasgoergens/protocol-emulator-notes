// Blackbox primitives for Yosys synth_fabulous (Yosys 0.69 no longer ships the FABulous
// primitive library, so the fabric's I/O BELs and the global clock are declared here).
(* blackbox, keep *)
module IO_1_bidirectional_frame_config_pass (
    input  wire I,
    input  wire T,
    output wire O,
    output wire Q,
    output wire I_top,
    output wire T_top,
    input  wire O_top,
    input  wire UserCLK
);
endmodule
(* blackbox, keep *)
module Config_access (
    output wire [3:0] C_bit,
    input  wire [3:0] ConfigBits
);
endmodule
(* blackbox, keep *)
module Global_Clock (
    output wire CLK
);
endmodule
