module crc_usb16 (
    value,
    clear,
    clock,
    frame,
    stb,
    en,
    ok
);

    input value;
    input clear;
    input clock;
    input frame;
    input stb;
    input en;
    output ok;

    wire [15:0] _48;
    wire [15:0] _46;
    wire [15:0] _40;
    wire _37;
    wire _38;
    wire [15:0] _41;
    wire [14:0] _35;
    wire _34;
    wire [15:0] _36;
    wire [15:0] _42;
    wire [4:0] _31;
    wire [4:0] _22;
    wire [4:0] _23;
    wire _19;
    wire _20;
    wire _21;
    wire [4:0] _24;
    wire [4:0] _25;
    reg [4:0] _28;
    wire [4:0] _2;
    wire _32;
    wire vdd;
    reg _15;
    wire _16;
    wire _11;
    wire _17;
    wire _30;
    wire _33;
    wire [15:0] _43;
    wire [15:0] _29;
    wire [15:0] _44;
    reg [15:0] _47;
    wire [15:0] _8;
    wire _49;
    assign _48 = 16'b1011000000000001;
    assign _46 = 16'b0000000000000000;
    assign _40 = 16'b1010000000000001;
    assign _37 = _8[0:0];
    assign _38 = _37 ^ value;
    assign _41 = _38 ? _40 : _46;
    assign _35 = _8[15:1];
    assign _34 = 1'b0;
    assign _36 = { _34,
                   _35 };
    assign _42 = _36 ^ _41;
    assign _31 = 5'b00000;
    assign _22 = 5'b00001;
    assign _23 = _2 - _22;
    assign _19 = _2 == _31;
    assign _20 = ~ _19;
    assign _21 = _17 & _20;
    assign _24 = _21 ? _23 : _2;
    assign _25 = en ? _24 : _31;
    always @(posedge clock) begin
        if (clear)
            _28 <= _31;
        else
            _28 <= _25;
    end
    assign _2 = _28;
    assign _32 = _2 == _31;
    assign vdd = 1'b1;
    always @(posedge clock) begin
        if (clear)
            _15 <= _34;
        else
            _15 <= _11;
    end
    assign _16 = ~ _15;
    assign _11 = stb & frame;
    assign _17 = _11 & _16;
    assign _30 = en & _17;
    assign _33 = _30 & _32;
    assign _43 = _33 ? _42 : _8;
    assign _29 = 16'b1111111111111111;
    assign _44 = en ? _43 : _29;
    always @(posedge clock) begin
        if (clear)
            _47 <= _46;
        else
            _47 <= _44;
    end
    assign _8 = _47;
    assign _49 = _8 == _48;
    assign ok = _49;

endmodule
