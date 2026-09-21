`default_nettype none
// I2C master bit engine: START, 8 address bits, ACK sample, STOP; open-drain via oeb.
// io_in[0]=rst, io_in[1]=go, io_in[2]=sda_in, io_in[3]=scl_in (clock stretching).
// io_out[4]=sda drive (0), io_oeb[4]=sda release, io_out[5]=scl drive, io_oeb[5]=scl release, io_out[6]=ack, io_out[7]=done.
module i2c_engine (
    input  wire        clk,
    input  wire [27:0] io_in,
    output wire [27:0] io_out,
    output wire [27:0] io_oeb
);
    wire rst = io_in[0], go = io_in[1], sda_in = io_in[2], scl_in = io_in[3];
    reg [2:0] state; reg [3:0] bitn; reg [3:0] phase; reg [7:0] addr; reg sda_oe, scl_oe, ack, done;
    localparam IDLE=0, START=1, BIT=2, ACK=3, STOP=4;
    always @(posedge clk) begin
        if (rst) begin state <= IDLE; bitn <= 0; phase <= 0; addr <= 8'hA0; sda_oe <= 0; scl_oe <= 0; ack <= 0; done <= 0; end
        else begin
            phase <= phase + 4'd1;
            case (state)
              IDLE: begin done <= 0; if (go) begin state <= START; phase <= 0; end end
              START: if (phase == 4'd7) begin sda_oe <= 1; end
                     else if (phase == 4'd15) begin scl_oe <= 1; state <= BIT; bitn <= 0; end
              BIT: begin
                     if (phase == 4'd3) sda_oe <= ~addr[7];
                     if (phase == 4'd7) scl_oe <= 0;                   // release SCL
                     if (phase == 4'd11 && scl_in) begin end            // wait for stretch
                     if (phase == 4'd15 && scl_in) begin scl_oe <= 1; addr <= {addr[6:0], 1'b0}; bitn <= bitn + 4'd1;
                        if (bitn == 4'd7) state <= ACK; end
                     else if (phase == 4'd15) phase <= 4'd15;          // hold while stretched
                   end
              ACK: begin
                     if (phase == 4'd3) sda_oe <= 0;
                     if (phase == 4'd7) scl_oe <= 0;
                     if (phase == 4'd11) ack <= ~sda_in;
                     if (phase == 4'd15) begin scl_oe <= 1; state <= STOP; end
                   end
              STOP: begin
                     if (phase == 4'd3) sda_oe <= 1;
                     if (phase == 4'd7) scl_oe <= 0;
                     if (phase == 4'd15) begin sda_oe <= 0; state <= IDLE; done <= 1; end
                   end
              default: state <= IDLE;
            endcase
        end
    end
    assign io_out = {20'b0, done, ack, 1'b0, 1'b0, 4'b0};
    assign io_oeb = {22'b0, ~scl_oe, ~sda_oe, 4'b0};
endmodule
`resetall
