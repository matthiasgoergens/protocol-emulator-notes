module feeder (
    hw_en,
    rdata,
    clear,
    clock,
    line_go_n,
    raddr,
    waddr,
    tag,
    data
);

    input hw_en;
    input [18:0] rdata;
    input clear;
    input clock;
    input line_go_n;
    output [8:0] raddr;
    output [8:0] waddr;
    output [2:0] tag;
    output [15:0] data;

    wire [15:0] _67;
    wire [14:0] _61;
    wire [8:0] _59;
    wire _60;
    wire [15:0] _62;
    wire _49;
    wire [15:0] _51;
    wire [15:0] _52;
    wire [15:0] _53;
    wire [15:0] _54;
    wire [15:0] _1;
    reg [15:0] _46;
    wire [15:0] _63;
    wire [15:0] _57;
    wire [15:0] _58;
    wire [15:0] _64;
    wire [15:0] _65;
    wire [15:0] _2;
    reg [15:0] _68;
    wire [2:0] _76;
    wire [2:0] _72;
    wire [2:0] _70;
    wire [2:0] _71;
    wire [2:0] _73;
    wire [2:0] _74;
    wire [2:0] _4;
    reg [2:0] _77;
    wire [7:0] _79;
    wire [7:0] _81;
    wire [7:0] _82;
    wire [7:0] _83;
    wire [7:0] _85;
    wire [7:0] _7;
    reg [7:0] _80;
    wire _89;
    wire [8:0] _90;
    wire [7:0] _138;
    wire [7:0] _134;
    wire [6:0] _130;
    wire [15:0] _131;
    wire [15:0] _50;
    wire _132;
    wire [7:0] _135;
    wire [7:0] _128;
    wire _126;
    wire [7:0] _129;
    wire _125;
    wire [7:0] _136;
    wire _56;
    wire [7:0] _139;
    wire [7:0] _140;
    wire [8:0] _38;
    wire [8:0] _36;
    wire [8:0] _91;
    wire [8:0] _92;
    wire [8:0] _93;
    wire [8:0] _95;
    wire [8:0] _9;
    reg [8:0] _37;
    wire _39;
    wire _32;
    wire _106;
    wire _107;
    wire gnd;
    wire [2:0] _98;
    wire _99;
    wire _101;
    wire [2:0] _96;
    wire [2:0] _47;
    wire _97;
    wire _102;
    wire _103;
    wire _104;
    wire _105;
    wire _11;
    reg _43;
    wire _108;
    wire _109;
    wire _110;
    wire _12;
    reg _33;
    wire [11:0] _29;
    wire [11:0] _119;
    wire [11:0] _117;
    wire [11:0] _114;
    wire [11:0] _115;
    wire _112;
    wire _113;
    wire [11:0] _116;
    wire [11:0] _118;
    wire [11:0] _120;
    wire [11:0] _13;
    reg [11:0] _28;
    wire _30;
    wire _34;
    wire _40;
    wire [7:0] _141;
    wire [7:0] _143;
    wire [7:0] _14;
    reg [7:0] _123;
    wire _144;
    wire _24;
    wire vdd;
    reg _23;
    wire _25;
    wire _145;
    wire _18;
    reg _88;
    wire [8:0] _146;
    assign _67 = 16'b0000000000000000;
    assign _61 = 15'b000000000000000;
    assign _59 = 9'b011111111;
    assign _60 = _37 == _59;
    assign _62 = { _60,
                   _61 };
    assign _49 = _47 == _72;
    assign _51 = _49 ? _50 : _46;
    assign _52 = _43 ? _51 : _46;
    assign _53 = _40 ? _46 : _52;
    assign _54 = _25 ? _46 : _53;
    assign _1 = _54;
    always @(posedge clock) begin
        if (clear)
            _46 <= _67;
        else
            _46 <= _1;
    end
    assign _63 = _46 | _62;
    assign _57 = _56 ? _50 : _67;
    assign _58 = _43 ? _57 : _67;
    assign _64 = _40 ? _63 : _58;
    assign _65 = _25 ? _67 : _64;
    assign _2 = _65;
    always @(posedge clock) begin
        if (clear)
            _68 <= _67;
        else
            _68 <= _2;
    end
    assign _76 = 3'b000;
    assign _72 = 3'b001;
    assign _70 = _56 ? _47 : _76;
    assign _71 = _43 ? _70 : _76;
    assign _73 = _40 ? _72 : _71;
    assign _74 = _25 ? _76 : _73;
    assign _4 = _74;
    always @(posedge clock) begin
        if (clear)
            _77 <= _76;
        else
            _77 <= _4;
    end
    assign _79 = 8'b00000000;
    assign _81 = 8'b00000001;
    assign _82 = _80 + _81;
    assign _83 = hw_en ? _82 : _80;
    assign _85 = _25 ? _79 : _83;
    assign _7 = _85;
    always @(posedge clock) begin
        if (clear)
            _80 <= _79;
        else
            _80 <= _7;
    end
    assign _89 = ~ _88;
    assign _90 = { _89,
                   _80 };
    assign _138 = _123 + _81;
    assign _134 = _123 + _81;
    assign _130 = 7'b0000000;
    assign _131 = { _130,
                    _37 };
    assign _50 = rdata[15:0];
    assign _132 = _50 < _131;
    assign _135 = _132 ? _134 : _123;
    assign _128 = _123 + _81;
    assign _126 = _47 == _72;
    assign _129 = _126 ? _128 : _123;
    assign _125 = _47 == _76;
    assign _136 = _125 ? _135 : _129;
    assign _56 = _47[1:1];
    assign _139 = _56 ? _138 : _136;
    assign _140 = _43 ? _139 : _123;
    assign _38 = 9'b100000000;
    assign _36 = 9'b000000000;
    assign _91 = 9'b000000001;
    assign _92 = _37 + _91;
    assign _93 = _40 ? _92 : _37;
    assign _95 = _25 ? _36 : _93;
    assign _9 = _95;
    always @(posedge clock) begin
        if (clear)
            _37 <= _36;
        else
            _37 <= _9;
    end
    assign _39 = _37 < _38;
    assign _32 = 1'b0;
    assign _106 = _47 == _72;
    assign _107 = _106 ? vdd : _33;
    assign gnd = 1'b0;
    assign _98 = 3'b101;
    assign _99 = _47 == _98;
    assign _101 = _99 ? gnd : _43;
    assign _96 = 3'b100;
    assign _47 = rdata[18:16];
    assign _97 = _47 == _96;
    assign _102 = _97 ? gnd : _101;
    assign _103 = _43 ? _102 : _43;
    assign _104 = _40 ? _43 : _103;
    assign _105 = _25 ? vdd : _104;
    assign _11 = _105;
    always @(posedge clock) begin
        if (clear)
            _43 <= _32;
        else
            _43 <= _11;
    end
    assign _108 = _43 ? _107 : _33;
    assign _109 = _40 ? _33 : _108;
    assign _110 = _25 ? gnd : _109;
    assign _12 = _110;
    always @(posedge clock) begin
        if (clear)
            _33 <= _32;
        else
            _33 <= _12;
    end
    assign _29 = 12'b000000000000;
    assign _119 = 12'b001010000001;
    assign _117 = 12'b000000001001;
    assign _114 = 12'b000000000001;
    assign _115 = _28 - _114;
    assign _112 = _28 == _29;
    assign _113 = ~ _112;
    assign _116 = _113 ? _115 : _28;
    assign _118 = _40 ? _117 : _116;
    assign _120 = _25 ? _119 : _118;
    assign _13 = _120;
    always @(posedge clock) begin
        if (clear)
            _28 <= _29;
        else
            _28 <= _13;
    end
    assign _30 = _28 == _29;
    assign _34 = _30 & _33;
    assign _40 = _34 & _39;
    assign _141 = _40 ? _123 : _140;
    assign _143 = _25 ? _79 : _141;
    assign _14 = _143;
    always @(posedge clock) begin
        if (clear)
            _123 <= _79;
        else
            _123 <= _14;
    end
    assign _144 = ~ _88;
    assign _24 = ~ line_go_n;
    assign vdd = 1'b1;
    always @(posedge clock) begin
        if (clear)
            _23 <= _32;
        else
            _23 <= line_go_n;
    end
    assign _25 = _23 & _24;
    assign _145 = _25 ? _144 : _88;
    assign _18 = _145;
    always @(posedge clock) begin
        if (clear)
            _88 <= _32;
        else
            _88 <= _18;
    end
    assign _146 = { _88,
                    _123 };
    assign raddr = _146;
    assign waddr = _90;
    assign tag = _77;
    assign data = _68;

endmodule
