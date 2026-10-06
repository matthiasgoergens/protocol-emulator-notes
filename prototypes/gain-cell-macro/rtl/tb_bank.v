// Testbench for gc_bank_32x32. Compiled twice (sim.sh):
//   RTL: gc_bank.v with gc_array_beh.v and the PDK's standard-cell Verilog models;
//   BEH: gc_bank_beh.v, the model a design placing the macro would simulate with.
// Both write the same trace of every rvalid cycle (trace_*.txt) for sim.sh to compare.
// Checks, each reported as PASS or FAIL:
//   1. every row written with random data and read back, rerr = 0;
//   2. 2000 random operations against a reference memory (within the retention bound);
//   3. planted control: a read after the retention bound returns X in rdata and rerr, and the
//      model counts it (RETENTION_NS is lowered to 5 us for this);
//   4. planted control: a read of a row never written returns X;
//   5. a read just inside the bound returns the data;
//   6. (RTL only) planted decay: one stored 1 of a live row forced to 0 inside the array model;
//      the Berger check must raise rerr;
//   7. (RTL only, with PERIOD below 10 ns) a write pulse shorter than 20 ns is reported by the
//      array model; sim.sh runs this as its own case and expects the SHORT WRITE line.
`timescale 1ns/1ps
module tb_bank;
`ifndef PERIOD
    `define PERIOD 16.667
`endif
    localparam real RET = 5000.0;
    reg clk = 0, rst_n = 0, req = 0, we = 0;
    reg [4:0] addr = 0;
    reg [31:0] wdata = 0;
    wire busy, rvalid, rerr;
    wire [31:0] rdata;
    always #(`PERIOD / 2.0) clk = ~clk;

`ifdef BEH
    gc_bank_32x32 #(.RETENTION_NS(RET)) dut (.clk(clk), .rst_n(rst_n), .req(req), .we(we),
        .addr(addr), .wdata(wdata), .busy(busy), .rvalid(rvalid), .rdata(rdata), .rerr(rerr));
    `define EXPIRED dut.expired_reads
`else
    gc_bank_32x32 dut (.clk(clk), .rst_n(rst_n), .req(req), .we(we),
        .addr(addr), .wdata(wdata), .busy(busy), .rvalid(rvalid), .rdata(rdata), .rerr(rerr));
    defparam dut.array_i.RETENTION_NS = RET;
    `define EXPIRED dut.array_i.expired_reads
`endif

    integer fails = 0, f, i, seed = 7;
    reg [31:0] ref_mem [0:31];
    reg [31:0] got;
    reg got_err;

    task check(input cond, input [8*64-1:0] what);
        if (!cond) begin fails = fails + 1; $display("FAIL %0s at %t", what, $realtime); end
    endtask

    // one operation, waiting until the bank accepts it
    task op(input w, input [4:0] a, input [31:0] d);
        begin
            @(negedge clk);
            while (busy) @(negedge clk);
            req = 1; we = w; addr = a; wdata = d;
            @(negedge clk);
            req = 0; we = 0; addr = 5'bx; wdata = 32'bx;
            if (!w) begin
                while (!rvalid) @(negedge clk);
                got = rdata; got_err = rerr;
            end
        end
    endtask

    always @(posedge clk) if (rvalid) $fdisplay(f, "%0d %h %b", $rtoi($realtime * 1000), rdata, rerr);

    integer k, n_ok;
    reg [4:0] a;
    reg [31:0] d;
    initial begin
`ifndef TRACE
    `define TRACE "trace.txt"
`endif
        f = $fopen(`TRACE);
        #(3 * `PERIOD) rst_n = 1;
        // 4: a row never written reads X
        op(0, 5'd9, 0);
        check(got === 32'bx && got_err === 1'bx, "never-written row did not read X");
        check(`EXPIRED == 1, "never-written read not counted");
        // 1: write and read every row
        for (i = 0; i < 32; i = i + 1) begin
            ref_mem[i] = $random(seed);
            op(1, i[4:0], ref_mem[i]);
        end
        n_ok = 0;
        for (i = 0; i < 32; i = i + 1) begin
            op(0, i[4:0], 0);
            if (got === ref_mem[i] && got_err === 1'b0) n_ok = n_ok + 1;
        end
        check(n_ok == 32, "write/read of all rows");
        $display("check 1: %0d of 32 rows read back", n_ok);
        // 2: random operations; rewrite every row often enough to stay inside the bound
        n_ok = 0;
        for (k = 0; k < 2000; k = k + 1) begin
            a = $random(seed);
            d = $random(seed);
            if (k % 16 == 0)
                for (i = 0; i < 32; i = i + 1) op(1, i[4:0], ref_mem[i]);   // refresh pass
            if ($random(seed) & 1) begin
                ref_mem[a] = d;
                op(1, a, d);
            end else begin
                op(0, a, 0);
                if (got === ref_mem[a] && got_err === 1'b0) n_ok = n_ok + 1;
                else $display("random read row %0d: got %h err %b, want %h", a, got, got_err, ref_mem[a]);
            end
        end
        check(`EXPIRED == 1, "a random read expired");
        $display("check 2: %0d random reads correct, expired reads so far %0d", n_ok, `EXPIRED);
        // 5: just inside the bound (written, read 4 us later with a 5 us bound)
        op(1, 5'd3, 32'hDEAD_BEEF);
        #4000;
        op(0, 5'd3, 0);
        check(got === 32'hDEAD_BEEF && got_err === 1'b0, "read inside the bound");
        // 3: planted control, a read after the bound
        op(1, 5'd4, 32'hFFFF_0000);
        #(RET + 1000);
        op(0, 5'd4, 0);
        check(got === 32'bx && got_err === 1'bx, "read after the bound did not return X");
        check(`EXPIRED == 2, "read after the bound not counted");
        $display("check 3: late read returned %h err %b, expired reads %0d", got, got_err, `EXPIRED);
`ifndef BEH
        // 6: planted decay of one stored 1 in a live row
        op(1, 5'd5, 32'h0000_0001);
        @(negedge clk); while (busy) @(negedge clk);           // let the write complete
        dut.array_i.mem[5] = {6'd31, 32'h0000_0000};     // the data's 1 has decayed to 0
        op(0, 5'd5, 0);
        check(got_err === 1'b1, "Berger check missed a decayed 1");
        $display("check 6: decayed word read %h err %b", got, got_err);
`endif
        $fclose(f);
        if (fails == 0) $display("PASS (%0d expired reads flagged)", `EXPIRED);
        else $display("FAIL: %0d checks failed", fails);
        $finish;
    end
endmodule
