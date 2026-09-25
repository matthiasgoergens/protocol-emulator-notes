module crc_unit (
    residue,
    xorout,
    clear,
    clock,
    init,
    poly,
    bit,
    mask,
    refl,
    valid,
    start,
    raw,
    value,
    check
);

    input [31:0] residue;
    input [31:0] xorout;
    input clear;
    input clock;
    input [31:0] init;
    input [31:0] poly;
    input bit;
    input [31:0] mask;
    input refl;
    input valid;
    input start;
    output [31:0] raw;
    output [31:0] value;
    output check;

    wire _20;
    wire [31:0] _21;
    wire vdd;
    wire [31:0] _17;
    wire _41;
    wire _42;
    wire [31:0] _44;
    wire [30:0] _39;
    wire _38;
    wire [31:0] _40;
    wire [31:0] _45;
    wire [30:0] _27;
    wire [31:0] _28;
    wire [31:0] _29;
    wire [31:0] _30;
    wire _32;
    wire _33;
    wire _34;
    wire [31:0] _36;
    wire [30:0] _22;
    wire [31:0] _24;
    wire [31:0] _25;
    wire [31:0] _37;
    wire [31:0] _46;
    wire [31:0] _47;
    wire [31:0] _48;
    wire [31:0] _14;
    reg [31:0] _19;
    assign _20 = _19 == residue;
    assign _21 = _19 ^ xorout;
    assign vdd = 1'b1;
    assign _17 = 32'b00000000000000000000000000000000;
    assign _41 = _19[0:0];
    assign _42 = _41 ^ bit;
    assign _44 = _42 ? poly : _17;
    assign _39 = _19[31:1];
    assign _38 = 1'b0;
    assign _40 = { _38,
                   _39 };
    assign _45 = _40 ^ _44;
    assign _27 = mask[31:1];
    assign _28 = { _38,
                   _27 };
    assign _29 = mask ^ _28;
    assign _30 = _19 & _29;
    assign _32 = _30 == _17;
    assign _33 = ~ _32;
    assign _34 = _33 ^ bit;
    assign _36 = _34 ? poly : _17;
    assign _22 = _19[30:0];
    assign _24 = { _22,
                   _38 };
    assign _25 = _24 & mask;
    assign _37 = _25 ^ _36;
    assign _46 = refl ? _45 : _37;
    assign _47 = valid ? _46 : _19;
    assign _48 = start ? init : _47;
    assign _14 = _48;
    always @(posedge clock) begin
        if (clear)
            _19 <= _17;
        else
            _19 <= _14;
    end
    assign raw = _19;
    assign value = _21;
    assign check = _20;

endmodule
