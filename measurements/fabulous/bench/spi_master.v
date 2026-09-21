`default_nettype none
// SPI master, mode 0, 8-bit transfers, divisor 4. io_in[0]=rst, io_in[1]=start, io_in[2]=miso.
// io_out[0]=sclk, io_out[1]=mosi, io_out[2]=cs_n, io_out[3]=done, io_out[4]=received parity.
module spi_master (
    input  wire        clk,
    input  wire [27:0] io_in,
    output wire [27:0] io_out,
    output wire [27:0] io_oeb
);
    wire rst = io_in[0], start = io_in[1], miso = io_in[2];
    reg [7:0] tx, rx; reg [3:0] bitn; reg [1:0] div; reg sclk, active, done;
    always @(posedge clk) begin
        if (rst) begin tx <= 8'hA5; rx <= 0; bitn <= 0; div <= 0; sclk <= 0; active <= 0; done <= 0; end
        else if (!active) begin
            done <= 0;
            if (start) begin active <= 1; bitn <= 0; div <= 0; sclk <= 0; end
        end else begin
            div <= div + 2'd1;
            if (div == 2'd3) begin
                sclk <= ~sclk;
                if (!sclk) rx <= {rx[6:0], miso};              // rising edge: sample
                else begin tx <= {tx[6:0], 1'b0}; bitn <= bitn + 4'd1; // falling edge: shift out
                    if (bitn == 4'd7) begin active <= 0; done <= 1; tx <= rx ^ 8'h5A; end
                end
            end
        end
    end
    assign io_out = {23'b0, ^rx, done, ~active, tx[7], sclk};
    assign io_oeb = 28'b0;
endmodule
`resetall
