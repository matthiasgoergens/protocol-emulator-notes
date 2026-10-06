// Behavioural model of the hard macro GC_ARRAY_32x38 (simulation only): 32 rows x 38 columns
// of thick-oxide 3T gain cells, as seen from its pins. It lets the bank's own RTL
// (gc_bank.v), with the PDK's standard-cell models, be simulated end to end.
//
// Electrical facts it encodes (../README.md, sections 1 and 2):
//   - a write needs WWL high for at least TWRITE_MIN_NS; a shorter pulse leaves the row X;
//   - the row stores the WBL values present when WWL falls;
//   - a stored 1 lasts RETENTION_NS after its write; after that it reads X. A stored 0 does not
//     decay in the circuit (it stays below 0.03 V), but the model makes the whole row X: a
//     scheduling bug must not pass just because the word held few 1s;
//   - a read needs RWL high for TEVAL_MIN_NS before RBL is a valid level: before that, a column
//     whose selected cell stores 1 reads X (RBL is falling);
//   - a selected 1 pulls RBL to 0 (strong); otherwise the cell does not drive RBL, and the
//     model holds the line's charge with a weak 1 (the bank precharges RBL whenever it is not
//     reading, so between reads RBL is high);
//   - a row never written reads X.
// Every read of an expired or never-written row prints a line starting "GC_ARRAY EXPIRED" and
// counts in expired_reads, so a testbench can check its planted controls.
`timescale 1ns/1ps
module GC_ARRAY_32x38 #(
    parameter real RETENTION_NS = 3.0e6,
    parameter real TWRITE_MIN_NS = 20.0,
    parameter real TEVAL_MIN_NS = 20.0
) (
`ifdef USE_POWER_PINS
    inout  wire        GND,
`endif
    input  wire [31:0] WWL,
    input  wire [31:0] RWL,
    input  wire [37:0] WBL,
    inout  wire [37:0] RBL
);
    reg  [37:0] mem [0:31];
    real t_write [0:31];      // time of the last complete write; < 0: never written
    real t_wwl_up [0:31];
    reg  [31:0] sensed;       // RWL[r] has been high for TEVAL_MIN_NS
    reg  [31:0] expired;      // the row was expired (or never written) when its read sensed
    integer expired_reads = 0;
    integer r;

    initial begin
        for (r = 0; r < 32; r = r + 1) begin
            mem[r] = {38{1'bx}};
            t_write[r] = -1.0;
        end
        sensed = 32'd0;
        expired = 32'd0;
    end

    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : row
            // only a 1 -> 0 transition of WWL completes a write (x -> 0 at reset does not)
            reg wwl_was = 1'b0;
            always @(WWL[g]) begin
                if (WWL[g] === 1'b1 && wwl_was !== 1'b1)
                    t_wwl_up[g] = $realtime;
                else if (wwl_was === 1'b1 && WWL[g] === 1'b0) begin
                    t_write[g] = $realtime;
                    if ($realtime - t_wwl_up[g] >= TWRITE_MIN_NS)
                        mem[g] = WBL;
                    else begin
                        mem[g] = {38{1'bx}};
                        $display("%t GC_ARRAY SHORT WRITE row %0d: WWL high %0.3f ns < %0.1f ns",
                                 $realtime, g, $realtime - t_wwl_up[g], TWRITE_MIN_NS);
                    end
                end else if (wwl_was === 1'b1 && WWL[g] !== 1'b1) begin
                    mem[g] = {38{1'bx}};      // the word line went unknown during a write
                    t_write[g] = $realtime;
                end
                wwl_was = WWL[g];
            end
            always @(posedge RWL[g]) begin : eval
                sensed[g] = 1'b0;
                #(TEVAL_MIN_NS);
                if (RWL[g] === 1'b1) begin
                    expired[g] = (t_write[g] < 0.0) || ($realtime - t_write[g] > RETENTION_NS);
                    if (expired[g]) begin
                        expired_reads = expired_reads + 1;
                        if (t_write[g] < 0.0)
                            $display("%t GC_ARRAY EXPIRED read of row %0d: never written", $realtime, g);
                        else
                            $display("%t GC_ARRAY EXPIRED read of row %0d: %0.0f ns after its write, bound %0.0f ns",
                                     $realtime, g, $realtime - t_write[g], RETENTION_NS);
                    end
                    sensed[g] = 1'b1;
                end
            end
            always @(negedge RWL[g]) sensed[g] = 1'b0;
        end
    endgenerate

    // per column: pull down (0), unknown (x) or leave the precharged charge (weak 1)
    reg [37:0] pull_x, pull_0;
    integer rr, b;
    always @* begin
        pull_x = 38'd0;
        pull_0 = 38'd0;
        for (rr = 0; rr < 32; rr = rr + 1)
            if (RWL[rr] !== 1'b0)
                for (b = 0; b < 38; b = b + 1) begin
                    if (RWL[rr] !== 1'b1 || (sensed[rr] && expired[rr]))
                        pull_x[b] = 1'b1;                     // unknown word line, or expired row
                    else if (mem[rr][b] === 1'b0)
                        ;                                     // a 0 never pulls
                    else if (!sensed[rr] || mem[rr][b] !== 1'b1)
                        pull_x[b] = 1'b1;                     // RBL still falling, or unknown bit
                    else
                        pull_0[b] = 1'b1;
                end
    end
    genvar c;
    generate
        for (c = 0; c < 38; c = c + 1) begin : col
            assign (strong0, weak1) RBL[c] = pull_x[c] ? 1'bx : (pull_0[c] ? 1'b0 : 1'b1);
        end
    endgenerate
endmodule
