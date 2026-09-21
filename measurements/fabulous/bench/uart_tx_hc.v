module uart_tx_hc (
    clk,
    io_in,
    io_out,
    io_oeb
);

    input clk;
    input [27:0] io_in;
    output [27:0] io_out;
    output [27:0] io_oeb;

    wire [27:0] _9;
    wire [9:0] _46;
    wire [9:0] _55;
    wire gnd;
    wire [7:0] _20;
    wire [7:0] _27;
    wire [7:0] _23;
    wire [7:0] _24;
    wire [7:0] _25;
    wire [7:0] _26;
    wire [7:0] _28;
    wire [7:0] _2;
    reg [7:0] _21;
    wire [9:0] _52;
    wire [9:0] _53;
    wire [8:0] _48;
    wire [9:0] _49;
    wire [9:0] _50;
    wire [9:0] _54;
    wire [9:0] _56;
    wire [9:0] _3;
    reg [9:0] _47;
    wire _75;
    wire [3:0] _15;
    wire [3:0] _69;
    wire [3:0] _70;
    wire [3:0] _66;
    wire [3:0] _67;
    wire [11:0] _42;
    wire [11:0] _40;
    wire [11:0] _39;
    wire [11:0] _38;
    wire [11:0] _37;
    wire [11:0] _36;
    wire [11:0] _35;
    wire [11:0] _34;
    wire [11:0] _33;
    wire [2:0] _32;
    reg [11:0] _41;
    wire [11:0] _43;
    wire vdd;
    wire [11:0] _30;
    wire _22;
    wire [11:0] _62;
    wire [11:0] _58;
    wire [11:0] _60;
    wire [11:0] _63;
    wire [11:0] _65;
    wire [11:0] _5;
    reg [11:0] _31;
    wire _44;
    wire [3:0] _68;
    wire _18;
    wire [3:0] _71;
    wire _10;
    wire [3:0] _73;
    wire [3:0] _7;
    reg [3:0] _14;
    wire _16;
    wire _17;
    wire [25:0] _74;
    wire [27:0] _76;
    assign _9 = 28'b0000000000000000000000000000;
    assign _46 = 10'b0000000000;
    assign _55 = 10'b1111111111;
    assign gnd = 1'b0;
    assign _20 = 8'b00000000;
    assign _27 = 8'b01000001;
    assign _23 = 8'b00000001;
    assign _24 = _21 + _23;
    assign _25 = _22 ? _24 : _21;
    assign _26 = _18 ? _25 : _21;
    assign _28 = _10 ? _27 : _26;
    assign _2 = _28;
    always @(posedge clk) begin
        _21 <= _2;
    end
    assign _52 = { vdd,
                   _21,
                   gnd };
    assign _53 = _22 ? _52 : _47;
    assign _48 = _47[9:1];
    assign _49 = { vdd,
                   _48 };
    assign _50 = _44 ? _49 : _47;
    assign _54 = _18 ? _53 : _50;
    assign _56 = _10 ? _55 : _54;
    assign _3 = _56;
    always @(posedge clk) begin
        _47 <= _3;
    end
    assign _75 = _47[0:0];
    assign _15 = 4'b0000;
    assign _69 = 4'b1010;
    assign _70 = _22 ? _69 : _14;
    assign _66 = 4'b0001;
    assign _67 = _14 - _66;
    assign _42 = 12'b000000000001;
    assign _40 = 12'b100000000000;
    assign _39 = 12'b010000000000;
    assign _38 = 12'b001000000000;
    assign _37 = 12'b000100000000;
    assign _36 = 12'b000010000000;
    assign _35 = 12'b000001000000;
    assign _34 = 12'b000000100000;
    assign _33 = 12'b000000010000;
    assign _32 = io_in[4:2];
    always @* begin
        case (_32)
        0:
            _41 <= _33;
        1:
            _41 <= _34;
        2:
            _41 <= _35;
        3:
            _41 <= _36;
        4:
            _41 <= _37;
        5:
            _41 <= _38;
        6:
            _41 <= _39;
        default:
            _41 <= _40;
        endcase
    end
    assign _43 = _41 - _42;
    assign vdd = 1'b1;
    assign _30 = 12'b000000000000;
    assign _22 = io_in[1:1];
    assign _62 = _22 ? _30 : _31;
    assign _58 = _31 + _42;
    assign _60 = _44 ? _30 : _58;
    assign _63 = _18 ? _62 : _60;
    assign _65 = _10 ? _30 : _63;
    assign _5 = _65;
    always @(posedge clk) begin
        _31 <= _5;
    end
    assign _44 = _31 == _43;
    assign _68 = _44 ? _67 : _14;
    assign _18 = ~ _17;
    assign _71 = _18 ? _70 : _68;
    assign _10 = io_in[0:0];
    assign _73 = _10 ? _15 : _71;
    assign _7 = _73;
    always @(posedge clk) begin
        _14 <= _7;
    end
    assign _16 = _14 == _15;
    assign _17 = ~ _16;
    assign _74 = 26'b00000000000000000000000000;
    assign _76 = { _74,
                   _17,
                   _75 };
    assign io_out = _76;
    assign io_oeb = _9;

endmodule
