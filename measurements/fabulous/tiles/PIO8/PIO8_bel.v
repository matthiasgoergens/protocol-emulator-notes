// Hardened 8-bit protocol shifter as a FABulous BEL: narrow-interface example.
(* FABulous, BelMap, MODE0=0, MODE1=1 *)
module PIO8_bel #(
    parameter integer NoConfigBits = 2
) (
    input  wire [7:0] D,        // parallel data in
    input  wire       LOAD,     // load D into the shift register
    input  wire       SHIFT,    // shift one bit
    input  wire       DIR,      // 0: lsb first, 1: msb first
    output wire       SO,       // serial out
    output wire       EMPTY,    // all bits shifted
    (* FABulous, EXTERNAL, SHARED_PORT *) input wire UserCLK,
    (* FABulous, GLOBAL *) input wire [NoConfigBits-1:0] ConfigBits
);
    reg [7:0] sr; reg [3:0] cnt;
    always @(posedge UserCLK) begin
        if (LOAD) begin sr <= ConfigBits[0] ? ~D : D; cnt <= 4'd8; end
        else if (SHIFT && cnt != 0) begin
            sr <= DIR ? {sr[6:0], ConfigBits[1]} : {ConfigBits[1], sr[7:1]};
            cnt <= cnt - 4'd1;
        end
    end
    assign SO = DIR ? sr[7] : sr[0];
    assign EMPTY = (cnt == 0);
endmodule
