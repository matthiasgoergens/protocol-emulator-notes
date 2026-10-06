// Behavioural model of the hardened bank macro gc_bank_32x32 (simulation only), for designs that
// place the macro: the same ports and the same cycle-level protocol as gc_bank.v, without the
// array, the column circuits or the Berger logic.
//
// Expiry: every row remembers the time its last write completed (the clock edge at which its
// WWL fell). A read whose capture edge comes more than RETENTION_NS after that, or that reads a
// row never written, returns rdata = X and rerr = X, prints a line starting
// "GC_BANK EXPIRED", and counts in expired_reads. The whole word goes X even though, in the
// circuit, only its 1s decay: a scheduling bug must not pass because a word held few 1s. Within
// the bound the read returns the written word and rerr = 0.
//
// RETENTION_NS is the guaranteed retention (../README.md, "What the model's bound is"); a
// testbench may lower it to exercise expiry in a short simulation.
`timescale 1ns/1ps
module gc_bank_32x32 #(
    parameter WCYC = 2,
    parameter RCYC = 2,
    parameter real RETENTION_NS = 3.0e6
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
    output reg  [31:0] rdata,
    output reg         rerr
);
    localparam [2:0] IDLE = 3'd0, WSET = 3'd1, WON = 3'd2, WHOLD = 3'd3, REVAL = 3'd4, RPRE = 3'd5;
    reg [2:0] state;
    reg [1:0] cnt;
    reg [4:0] row_q;
    reg [31:0] data_q;
    reg [31:0] mem [0:31];
    real t_write [0:31];
    integer expired_reads = 0;
    integer i;
    initial for (i = 0; i < 32; i = i + 1) t_write[i] = -1.0;

    assign busy = (state == WSET) || (state == WON) || (state == REVAL);
    wire accept = req && !busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; cnt <= 2'd0; row_q <= 5'd0; data_q <= 32'd0;
            rvalid <= 1'b0; rdata <= 32'd0; rerr <= 1'b0;
        end else begin
            rvalid <= 1'b0;
            case (state)
                WSET: begin cnt <= WCYC - 1; state <= WON; end
                WON:
                    if (cnt == 2'd0) begin
                        mem[row_q] = data_q;            // the write completes as WWL falls
                        t_write[row_q] = $realtime;
                        state <= WHOLD;
                    end else
                        cnt <= cnt - 2'd1;
                REVAL:
                    if (cnt == 2'd0) begin
                        rvalid <= 1'b1;
                        state <= RPRE;
                        if (t_write[row_q] < 0.0 || $realtime - t_write[row_q] > RETENTION_NS) begin
                            rdata <= 32'bx;
                            rerr <= 1'bx;
                            expired_reads = expired_reads + 1;
                            if (t_write[row_q] < 0.0)
                                $display("%t GC_BANK EXPIRED read of row %0d: never written", $realtime, row_q);
                            else
                                $display("%t GC_BANK EXPIRED read of row %0d: %0.0f ns after its write, bound %0.0f ns",
                                         $realtime, row_q, $realtime - t_write[row_q], RETENTION_NS);
                        end else begin
                            rdata <= mem[row_q];
                            rerr <= 1'b0;
                        end
                    end else
                        cnt <= cnt - 2'd1;
                default: ;
            endcase
            if (accept) begin
                row_q <= addr;
                if (we) begin
                    data_q <= wdata;
                    state <= WSET;
                end else begin
                    cnt <= RCYC - 1;
                    state <= REVAL;
                end
            end else if (state == WHOLD || state == RPRE)
                state <= IDLE;
        end
    end
endmodule
