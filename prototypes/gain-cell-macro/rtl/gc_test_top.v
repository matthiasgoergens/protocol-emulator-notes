// gc_test_top: a small standard-cell design that places the bank macro gc_bank_32x32 and drives
// it, to show the macro hardens next to standard cells. It is also a retention tester for
// silicon: it writes all 32 rows with a pseudo-random pattern, waits a programmable time, reads
// every row back and counts words that differ from the pattern and words whose Berger check
// fails.
//
//   wait_log2: the wait is 2^wait_log2 clock cycles (0 .. 2^31; at 60 MHz, 2^17 is 2.2 ms and
//              2^20 is 17 ms), so one design sweeps retention across the bound;
//   start:     a rising edge starts a pass (write all, wait, read all);
//   done:      high when the pass has finished; bad_words and err_words then hold its counts.
// A pass with a short wait must give bad_words = 0 and err_words = 0. A pass with a wait past
// the retention of the 1s must give err_words > 0 for every word that lost a 1: the Berger check
// is how silicon reports expiry.
module gc_test_top (
`ifdef USE_POWER_PINS
    inout  wire       VPWR,
    inout  wire       VGND,
`endif
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [4:0] wait_log2,
    output reg        done,
    output reg  [5:0] bad_words,
    output reg  [5:0] err_words
);
    localparam [2:0] IDLE = 3'd0, WRITE = 3'd1, WAIT = 3'd2, READ = 3'd3, CHECK = 3'd4, DONE = 3'd5;
    reg [2:0] state;
    reg [4:0] row;
    reg [31:0] lfsr, wait_cnt;
    reg start_q, issued;
    wire busy, rvalid, rerr;
    wire [31:0] rdata;

    // Galois LFSR, x^32 + x^22 + x^2 + x + 1; the same seed regenerates the pattern on read
    function [31:0] step(input [31:0] s);
        step = s[0] ? (s >> 1) ^ 32'h8020_0003 : s >> 1;
    endfunction
    localparam [31:0] SEED = 32'hACE1_2468;

    wire req = (state == WRITE || state == READ) && !issued && !busy;
    gc_bank_32x32 bank_i (
`ifdef USE_POWER_PINS
        .VPWR(VPWR), .VGND(VGND),
`endif
        .clk(clk), .rst_n(rst_n), .req(req), .we(state == WRITE), .addr(row), .wdata(lfsr),
        .busy(busy), .rvalid(rvalid), .rdata(rdata), .rerr(rerr));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; row <= 5'd0; lfsr <= SEED; wait_cnt <= 32'd0; start_q <= 1'b0;
            issued <= 1'b0; done <= 1'b0; bad_words <= 6'd0; err_words <= 6'd0;
        end else begin
            start_q <= start;
            case (state)
                IDLE, DONE:
                    if (start && !start_q) begin
                        state <= WRITE; row <= 5'd0; lfsr <= SEED; issued <= 1'b0; done <= 1'b0;
                        bad_words <= 6'd0; err_words <= 6'd0;
                    end
                WRITE:
                    if (req) begin
                        lfsr <= step(lfsr);
                        row <= row + 5'd1;
                        if (row == 5'd31) begin
                            state <= WAIT;
                            wait_cnt <= 32'd1 << wait_log2;
                        end
                    end
                WAIT:
                    if (wait_cnt == 32'd0) begin
                        state <= READ; row <= 5'd0; lfsr <= SEED; issued <= 1'b0;
                    end else
                        wait_cnt <= wait_cnt - 32'd1;
                READ:
                    if (req)
                        issued <= 1'b1;
                    else if (rvalid) begin
                        issued <= 1'b0;
                        if (rdata !== lfsr) bad_words <= bad_words + 6'd1;
                        if (rerr !== 1'b0) err_words <= err_words + 6'd1;
                        lfsr <= step(lfsr);
                        row <= row + 5'd1;
                        if (row == 5'd31) begin
                            state <= DONE;
                            done <= 1'b1;
                        end
                    end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
