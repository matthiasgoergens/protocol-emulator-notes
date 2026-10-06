// Testbench for gc_test_top with the bank's behavioural model (RETENTION_NS lowered to 20 us):
//   a pass with a 2^8-cycle wait (4.3 us) must report 0 bad and 0 Berger-failed words;
//   a pass with a 2^11-cycle wait (34 us, past the bound) must report all 32 words bad and failed:
//   the planted control that a read after expiry is flagged.
// Compile with GL=1 to run the gate-level netlist of the hardened top (the bank stays behavioural).
`timescale 1ns/1ps
module tb_top;
    reg clk = 0, rst_n = 0, start = 0;
    reg [4:0] wait_log2 = 0;
    wire done;
    wire [5:0] bad_words, err_words;
    always #8.3335 clk = ~clk;
    gc_test_top dut (.clk(clk), .rst_n(rst_n), .start(start), .wait_log2(wait_log2), .done(done),
                     .bad_words(bad_words), .err_words(err_words));
    defparam dut.bank_i.RETENTION_NS = 20000.0;
    integer fails = 0;
    task pass(input [4:0] w, input [5:0] want_bad, input [5:0] want_err);
        begin
            wait_log2 = w;
            @(negedge clk) start = 1;
            @(negedge clk) start = 0;
            @(negedge clk);
            wait (done === 1'b1);
            $display("wait 2^%0d cycles: bad_words %0d err_words %0d (want %0d, %0d)", w, bad_words,
                     err_words, want_bad, want_err);
            if (bad_words !== want_bad || err_words !== want_err) fails = fails + 1;
        end
    endtask
    initial begin
        #50 rst_n = 1;
        pass(5'd8, 6'd0, 6'd0);
        pass(5'd11, 6'd32, 6'd32);
        pass(5'd4, 6'd0, 6'd0);
        if (fails == 0) $display("PASS (expired reads flagged by the model: %0d)", dut.bank_i.expired_reads);
        else $display("FAIL: %0d passes wrong", fails);
        $finish;
    end
endmodule
