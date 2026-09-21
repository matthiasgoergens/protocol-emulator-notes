// Hardened 32-bit PIO-style input shift register (fixed 1-or-8 shift) as a FABulous BEL:
// wide-interface example, ports modelled on fpga_pio's isr.v.
(* FABulous, BelMap, MODE0=0, MODE1=1 *)
module PIO32_bel #(
    parameter integer NoConfigBits = 2
) (
    input  wire [31:0] DIN,
    input  wire        SHIFT8,
    input  wire        DIR,
    input  wire        SET,
    input  wire        DO_SHIFT,
    input  wire [5:0]  BIT_COUNT,
    output wire [31:0] DOUT,
    output wire [5:0]  SHIFT_COUNT,
    (* FABulous, EXTERNAL, SHARED_PORT *) input wire UserCLK,
    (* FABulous, GLOBAL *) input wire [NoConfigBits-1:0] ConfigBits
);
    reg [31:0] shift_reg; reg [5:0] count;
    wire [5:0] shift_val = SHIFT8 ? 6'd8 : 6'd1;
    wire [63:0] new_shift = DIR ? {DIN, shift_reg} >> shift_val
                                : {shift_reg, DIN << (32 - shift_val)} << shift_val;
    always @(posedge UserCLK) begin
        if (ConfigBits[0]) begin shift_reg <= 0; count <= 0; end
        else if (SET) begin shift_reg <= DIN; count <= BIT_COUNT; end
        else if (DO_SHIFT) begin
            shift_reg <= DIR ? new_shift[31:0] : new_shift[63:32];
            count <= count + shift_val > 32 ? 6'd32 : count + shift_val;
        end
    end
    assign DOUT = ConfigBits[1] ? ~shift_reg : shift_reg;
    assign SHIFT_COUNT = count;
endmodule
