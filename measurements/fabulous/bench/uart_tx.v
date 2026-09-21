`default_nettype none
// UART transmitter, 8N1, programmable divisor. io_in[0]=rst, io_in[1]=load, io_in[2..]: data bits come
// from a small internal pattern generator to save fabric IO; io_out[0]=tx, io_out[1]=busy.
module uart_tx (
    input  wire        clk,
    input  wire [27:0] io_in,
    output wire [27:0] io_out,
    output wire [27:0] io_oeb
);
    wire rst  = io_in[0];
    wire load = io_in[1];
    wire [3:0] div_sel = io_in[5:2];          // baud divisor select
    reg  [7:0] data;
    reg  [9:0] shifter;                        // start, 8 data, stop
    reg  [3:0] bits;
    reg  [11:0] cnt;
    wire [11:0] div = 12'd16 << div_sel[2:0];
    wire busy = (bits != 0);
    always @(posedge clk) begin
        if (rst) begin shifter <= 10'h3FF; bits <= 0; cnt <= 0; data <= 8'h41; end
        else if (!busy) begin
            if (load) begin shifter <= {1'b1, data, 1'b0}; bits <= 4'd10; cnt <= 0; data <= data + 8'd1; end
        end else if (cnt == div - 1) begin
            cnt <= 0; shifter <= {1'b1, shifter[9:1]}; bits <= bits - 4'd1;
        end else cnt <= cnt + 12'd1;
    end
    assign io_out = {26'b0, busy, shifter[0]};
    assign io_oeb = 28'b0;
endmodule
`resetall
