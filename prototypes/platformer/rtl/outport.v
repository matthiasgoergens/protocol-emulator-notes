module outport (
    data,
    lut_rdata,
    seq_pins,
    clear,
    clock,
    tag,
    pins,
    lut_raddr,
    lut_waddr,
    lut_we,
    lut_wdata
);

    input [15:0] data;
    input [13:0] lut_rdata;
    input [7:0] seq_pins;
    input clear;
    input clock;
    input [2:0] tag;
    output [6:0] pins;
    output [5:0] lut_raddr;
    output [5:0] lut_waddr;
    output lut_we;
    output [13:0] lut_wdata;

    wire [13:0] _17;
    wire _26;
    wire [5:0] _35;
    wire [5:0] _38;
    wire [5:0] _39;
    wire [5:0] _37;
    wire _23;
    wire gnd;
    wire _31;
    wire [1:0] _27;
    wire _28;
    wire _29;
    wire _32;
    wire _33;
    wire _3;
    reg _25;
    wire [5:0] _40;
    wire _20;
    wire _19;
    wire _21;
    wire [5:0] _41;
    wire [5:0] _4;
    reg [5:0] _36;
    wire [5:0] _50;
    wire [5:0] _47;
    wire [5:0] _48;
    wire [5:0] _7;
    reg [5:0] _46;
    wire [5:0] _51;
    wire [6:0] _93;
    wire [3:0] _89;
    wire [3:0] _88;
    wire [3:0] _90;
    wire [23:0] _83;
    wire [7:0] _80;
    wire [7:0] _81;
    wire [7:0] _79;
    wire _78;
    wire [7:0] _82;
    wire [31:0] _84;
    wire [31:0] _76;
    wire [31:0] _53;
    wire [31:0] _55;
    wire [31:0] _56;
    wire [31:0] _9;
    reg [31:0] _54;
    wire [31:0] _77;
    wire [31:0] _85;
    wire _86;
    wire _87;
    wire _74;
    wire _75;
    wire _72;
    wire _49;
    wire [3:0] _68;
    wire vdd;
    wire [3:0] _66;
    wire [3:0] _63;
    wire [3:0] _64;
    wire _61;
    wire _62;
    wire [3:0] _65;
    wire [1:0] _42;
    wire [1:0] _18;
    wire _43;
    wire [3:0] _67;
    wire [3:0] _15;
    reg [3:0] _59;
    wire _69;
    wire _70;
    wire _71;
    wire _73;
    wire [6:0] _91;
    reg [6:0] _94;
    assign _17 = data[13:0];
    assign _26 = _21 & _25;
    assign _35 = 6'b000000;
    assign _38 = 6'b000001;
    assign _39 = _36 + _38;
    assign _37 = data[5:0];
    assign _23 = 1'b0;
    assign gnd = 1'b0;
    assign _31 = _28 ? gnd : _25;
    assign _27 = 2'b11;
    assign _28 = _18 == _27;
    assign _29 = ~ _28;
    assign _32 = _25 ? _31 : _29;
    assign _33 = _21 ? _32 : _25;
    assign _3 = _33;
    always @(posedge clock) begin
        if (clear)
            _25 <= _23;
        else
            _25 <= _3;
    end
    assign _40 = _25 ? _39 : _37;
    assign _20 = tag[2:2];
    assign _19 = _18[1:1];
    assign _21 = _19 & _20;
    assign _41 = _21 ? _40 : _36;
    assign _4 = _41;
    always @(posedge clock) begin
        if (clear)
            _36 <= _35;
        else
            _36 <= _4;
    end
    assign _50 = 6'b111111;
    assign _47 = data[5:0];
    assign _48 = _43 ? _47 : _46;
    assign _7 = _48;
    always @(posedge clock) begin
        if (clear)
            _46 <= _35;
        else
            _46 <= _7;
    end
    assign _51 = _49 ? _50 : _46;
    assign _93 = 7'b0000000;
    assign _89 = lut_rdata[3:0];
    assign _88 = seq_pins[3:0];
    assign _90 = _70 ? _89 : _88;
    assign _83 = 24'b000000000000000000000000;
    assign _80 = 8'b11101011;
    assign _81 = _80 - _79;
    assign _79 = lut_rdata[11:4];
    assign _78 = seq_pins[6:6];
    assign _82 = _78 ? _81 : _79;
    assign _84 = { _82,
                   _83 };
    assign _76 = 32'b00001010101010101010101010101011;
    assign _53 = 32'b00000000000000000000000000000000;
    assign _55 = 32'b00010101010101010101010101010101;
    assign _56 = _54 + _55;
    assign _9 = _56;
    always @(posedge clock) begin
        if (clear)
            _54 <= _53;
        else
            _54 <= _9;
    end
    assign _77 = _54 + _76;
    assign _85 = _77 + _84;
    assign _86 = _85[31:31];
    assign _87 = ~ _86;
    assign _74 = lut_rdata[12:12];
    assign _75 = _71 & _74;
    assign _72 = lut_rdata[13:13];
    assign _49 = seq_pins[7:7];
    assign _68 = 4'b0000;
    assign vdd = 1'b1;
    assign _66 = 4'b1010;
    assign _63 = 4'b0001;
    assign _64 = _59 - _63;
    assign _61 = _59 == _68;
    assign _62 = ~ _61;
    assign _65 = _62 ? _64 : _59;
    assign _42 = 2'b01;
    assign _18 = tag[1:0];
    assign _43 = _18 == _42;
    assign _67 = _43 ? _66 : _65;
    assign _15 = _67;
    always @(posedge clock) begin
        if (clear)
            _59 <= _68;
        else
            _59 <= _15;
    end
    assign _69 = _59 == _68;
    assign _70 = ~ _69;
    assign _71 = _70 | _49;
    assign _73 = _71 & _72;
    assign _91 = { _73,
                   _75,
                   _87,
                   _90 };
    always @(posedge clock) begin
        if (clear)
            _94 <= _93;
        else
            _94 <= _91;
    end
    assign pins = _94;
    assign lut_raddr = _51;
    assign lut_waddr = _36;
    assign lut_we = _26;
    assign lut_wdata = _17;

endmodule
