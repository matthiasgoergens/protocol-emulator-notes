// gc_bank_32x32: a 32-word x 32-bit gain-cell memory bank for sg13cmos5l.
//
// The storage is the hard macro GC_ARRAY_32x38 (thick-oxide 3T cells, ../gc_array.py): 32 rows
// of 38 columns, 32 data bits and a 6-bit Berger check (the count of 0s in the data word). The
// periphery is standard cells: one flop per word line, so no decoder glitch reaches a word line;
// a flop per write bit line; per read bit line a tristate buffer for the precharge and an
// inverter for the sense, instantiated by hand so that synthesis and the resizer leave the
// analogue node RBL alone.
//
// A stored 1 leaks away; a stored 0 does not (../../gain-cell/README.md, findings 6). Every
// decay therefore turns a 1 into a 0. The Berger check catches any number of such errors: decay
// can only raise the number of 0s in the data and only lower the stored count. rerr flags a
// word that fails the check. A read does not refresh; a write does.
//
// Protocol (all on the rising edge of clk; inputs are sampled only when accepted):
//   accept: req & ~busy. we = 1 writes wdata to row addr, we = 0 reads row addr.
//   write: edge A accepts and drives the write bit lines; WWL[addr] is high from A+1 to A+3
//          (2 cycles; >= 20 ns needs a clock period >= 10 ns); the bit lines hold until the next
//          accepted write, at A+4 at the earliest. busy is high from A to A+3.
//   read:  edge A accepts, turns the precharge off and raises RWL[addr]; at A+2 (2 cycles of
//          evaluation) the sense outputs are captured into rdata, RWL falls and the precharge
//          turns on again; rvalid and rerr are valid in the cycle after A+2; the next accept can
//          be at A+3, so every evaluation is preceded by at least one cycle of precharge.
//          busy is high from A to A+2.
// The cycle counts are parameters; the electrical requirements (2 cycles of write and of
// evaluation at 60 MHz) are argued in ../README.md, section 2.
module gc_bank_32x32 #(
    parameter WCYC = 2,       // cycles with WWL high
    parameter RCYC = 2        // cycles of read evaluation (RWL high, precharge off)
) (
`ifdef USE_POWER_PINS
    inout  wire        VPWR,
    inout  wire        VGND,
`endif
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        we,
    input  wire [4:0]  addr,
    input  wire [31:0] wdata,
    output wire        busy,
    output reg         rvalid,
    output wire [31:0] rdata,
    output wire        rerr
);
    localparam ROWS = 32, COLS = 38;

    // count of 0s in a 32-bit word, 0..32
    function [5:0] zeros(input [31:0] d);
        integer i;
        begin
            zeros = 6'd0;
            for (i = 0; i < 32; i = i + 1)
                zeros = zeros + {5'd0, ~d[i]};
        end
    endfunction

    localparam [2:0] IDLE = 3'd0, WSET = 3'd1, WON = 3'd2, WHOLD = 3'd3, REVAL = 3'd4, RPRE = 3'd5;
    reg [2:0] state;
    reg [1:0] cnt;
    reg [ROWS-1:0] wwl_q, rwl_q;
    reg [COLS-1:0] wbl_q;
    reg [4:0] row_q;
    reg pre_b_q;              // 0: precharge on
    reg [COLS-1:0] raw_q;     // captured sense outputs
    wire [COLS-1:0] rbl, sense_q;

    assign busy = (state == WSET) || (state == WON) || (state == REVAL);
    wire accept = req && !busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; cnt <= 2'd0; wwl_q <= {ROWS{1'b0}}; rwl_q <= {ROWS{1'b0}};
            wbl_q <= {COLS{1'b0}}; row_q <= 5'd0; pre_b_q <= 1'b0; raw_q <= {COLS{1'b0}};
            rvalid <= 1'b0;
        end else begin
            rvalid <= 1'b0;
            case (state)
                WSET: begin
                    wwl_q <= {{(ROWS-1){1'b0}}, 1'b1} << row_q;
                    cnt <= WCYC - 1;
                    state <= WON;
                end
                WON: begin
                    if (cnt == 2'd0) begin
                        wwl_q <= {ROWS{1'b0}};
                        state <= WHOLD;
                    end else
                        cnt <= cnt - 2'd1;
                end
                REVAL: begin
                    if (cnt == 2'd0) begin
                        raw_q <= sense_q;
                        rwl_q <= {ROWS{1'b0}};
                        pre_b_q <= 1'b0;
                        rvalid <= 1'b1;
                        state <= RPRE;
                    end else
                        cnt <= cnt - 2'd1;
                end
                default: ;     // IDLE, WHOLD, RPRE: wait for an accept
            endcase
            if (accept) begin
                if (we) begin
                    wbl_q <= {zeros(wdata), wdata};
                    row_q <= addr;
                    state <= WSET;
                end else begin
                    rwl_q <= {{(ROWS-1){1'b0}}, 1'b1} << addr;
                    pre_b_q <= 1'b1;
                    cnt <= RCYC - 1;
                    state <= REVAL;
                end
            end else if (state == WHOLD || state == RPRE)
                state <= IDLE;
        end
    end

    assign rdata = raw_q[31:0];
    assign rerr = zeros(raw_q[31:0]) != raw_q[37:32];

    // the array and the column circuits
    GC_ARRAY_32x38 array_i (
`ifdef USE_POWER_PINS
        .GND(VGND),
`endif
        .WWL(wwl_q), .RWL(rwl_q), .WBL(wbl_q), .RBL(rbl)
    );
    genvar c;
    generate
        for (c = 0; c < COLS; c = c + 1) begin : col
            // precharge: drives RBL to VDD while pre_b_q is low, floats it while a read evaluates
            (* keep *) sg13cmos5l_ebufn_2 pre_i (
                .A(1'b1), .TE_B(pre_b_q), .Z(rbl[c]));
            // sense: a stored 1 discharges RBL, so the gate's output reads the bit directly. A
            // NAND4 with all inputs on RBL (four series NMOS against four parallel PMOS) switches
            // well above VDD / 2, so a smaller discharge reads as 1 than with an inverter
            // (../README.md, section 2: it lowers the readable level by 9-26 mV)
            (* keep *) sg13cmos5l_nand4_1 sense_i (
                .A(rbl[c]), .B(rbl[c]), .C(rbl[c]), .D(rbl[c]), .Y(sense_q[c]));
        end
    endgenerate
endmodule
