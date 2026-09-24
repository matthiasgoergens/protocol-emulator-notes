module pin_streamer (
    idle_oe,
    od_mask,
    idle_out,
    width,
    host_data,
    host_count,
    host_push,
    clear,
    clock,
    period,
    pin_out,
    pin_oe,
    full
);

    input [3:0] idle_oe;
    input [3:0] od_mask;
    input [3:0] idle_out;
    input [2:0] width;
    input [15:0] host_data;
    input [3:0] host_count;
    input host_push;
    input clear;
    input clock;
    input [11:0] period;
    output [3:0] pin_out;
    output [3:0] pin_oe;
    output full;

    wire [3:0] _108;
    wire [3:0] _103;
    wire [3:0] _104;
    wire [3:0] _97;
    wire [3:0] _98;
    wire [3:0] _105;
    wire [3:0] _106;
    reg [3:0] _110;
    wire [3:0] _2;
    wire [3:0] _111;
    wire [3:0] _96;
    wire [3:0] _131;
    wire [3:0] _94;
    wire [3:0] _92;
    wire [3:0] _91;
    wire [2:0] _89;
    wire _90;
    wire [3:0] _93;
    wire [2:0] _87;
    wire _88;
    wire [3:0] _95;
    wire [15:0] _99;
    wire [15:0] _129;
    wire [14:0] _124;
    wire _123;
    wire [15:0] _125;
    wire [13:0] _120;
    wire [1:0] _119;
    wire [15:0] _121;
    wire [11:0] _117;
    wire [15:0] _118;
    wire _115;
    wire [15:0] _122;
    wire _113;
    wire [15:0] _126;
    wire [15:0] _127;
    reg [15:0] _130;
    wire [15:0] _6;
    wire [15:0] _100;
    wire [3:0] _101;
    wire [3:0] _102;
    wire [3:0] _132;
    wire [3:0] _133;
    reg [3:0] _136;
    wire [3:0] _7;
    wire _173;
    wire _174;
    wire [4:0] _83;
    wire gnd;
    wire [4:0] _78;
    wire [4:0] _75;
    wire [4:0] _73;
    wire [4:0] _72;
    wire _71;
    wire [4:0] _74;
    wire _69;
    wire [4:0] _76;
    wire _79;
    wire [1:0] _60;
    wire _61;
    wire _62;
    wire [19:0] _59;
    wire [19:0] _57;
    reg [19:0] _63;
    wire [1:0] _53;
    wire _54;
    wire _55;
    wire [19:0] _50;
    reg [19:0] _56;
    wire [1:0] _46;
    wire _47;
    wire _48;
    wire [19:0] _43;
    reg [19:0] _49;
    wire [1:0] _138;
    wire [1:0] _139;
    reg [1:0] _142;
    wire [1:0] _10;
    wire _40;
    wire _41;
    wire [19:0] _34;
    reg [19:0] _42;
    wire [1:0] _144;
    wire [1:0] _145;
    reg [1:0] _148;
    wire [1:0] _13;
    reg [19:0] _64;
    wire [3:0] _65;
    wire _67;
    wire _80;
    wire [4:0] _81;
    wire [2:0] _30;
    wire [2:0] _153;
    wire [2:0] _23;
    wire _24;
    wire _37;
    wire _38;
    wire [2:0] _150;
    wire [2:0] _151;
    wire [2:0] _154;
    reg [2:0] _157;
    wire [2:0] _15;
    wire _31;
    wire _32;
    wire [4:0] _158;
    wire [4:0] _159;
    wire [4:0] _160;
    reg [4:0] _163;
    wire [4:0] _16;
    wire _28;
    wire _29;
    wire _33;
    wire [4:0] _82;
    wire _84;
    wire _85;
    wire [11:0] _25;
    wire vdd;
    wire [11:0] _167;
    wire [11:0] _168;
    wire [11:0] _165;
    wire [11:0] _166;
    wire [11:0] _169;
    reg [11:0] _172;
    wire [11:0] _20;
    wire _26;
    wire _86;
    wire _175;
    reg _178;
    wire _21;
    wire [3:0] _179;
    assign _108 = 4'b0000;
    assign _103 = ~ _102;
    assign _104 = _96 & _103;
    assign _97 = ~ _96;
    assign _98 = _95 & _97;
    assign _105 = _98 | _104;
    assign _106 = _86 ? _105 : _2;
    always @(posedge clock) begin
        if (clear)
            _110 <= _108;
        else
            _110 <= _106;
    end
    assign _2 = _110;
    assign _111 = _21 ? _2 : idle_oe;
    assign _96 = od_mask & _95;
    assign _131 = ~ _96;
    assign _94 = 4'b0001;
    assign _92 = 4'b0011;
    assign _91 = 4'b1111;
    assign _89 = 3'b010;
    assign _90 = width == _89;
    assign _93 = _90 ? _92 : _91;
    assign _87 = 3'b001;
    assign _88 = width == _87;
    assign _95 = _88 ? _94 : _93;
    assign _99 = _64[15:0];
    assign _129 = 16'b0000000000000000;
    assign _124 = _100[15:1];
    assign _123 = 1'b0;
    assign _125 = { _123,
                    _124 };
    assign _120 = _100[15:2];
    assign _119 = 2'b00;
    assign _121 = { _119,
                    _120 };
    assign _117 = _100[15:4];
    assign _118 = { _108,
                    _117 };
    assign _115 = width == _89;
    assign _122 = _115 ? _121 : _118;
    assign _113 = width == _87;
    assign _126 = _113 ? _125 : _122;
    assign _127 = _86 ? _126 : _6;
    always @(posedge clock) begin
        if (clear)
            _130 <= _129;
        else
            _130 <= _127;
    end
    assign _6 = _130;
    assign _100 = _33 ? _99 : _6;
    assign _101 = _100[3:0];
    assign _102 = _101 & _95;
    assign _132 = _102 & _131;
    assign _133 = _86 ? _132 : _7;
    always @(posedge clock) begin
        if (clear)
            _136 <= _108;
        else
            _136 <= _133;
    end
    assign _7 = _136;
    assign _173 = _29 & _31;
    assign _174 = _173 ? gnd : _21;
    assign _83 = 5'b00000;
    assign gnd = 1'b0;
    assign _78 = { gnd,
                   _65 };
    assign _75 = 5'b10000;
    assign _73 = 5'b01000;
    assign _72 = 5'b00100;
    assign _71 = width == _89;
    assign _74 = _71 ? _73 : _72;
    assign _69 = width == _87;
    assign _76 = _69 ? _75 : _74;
    assign _79 = _76 < _78;
    assign _60 = 2'b11;
    assign _61 = _10 == _60;
    assign _62 = _38 & _61;
    assign _59 = 20'b00000000000000000000;
    assign _57 = { host_count,
                   host_data };
    always @(posedge clock) begin
        if (clear)
            _63 <= _59;
        else
            if (_62)
                _63 <= _57;
    end
    assign _53 = 2'b10;
    assign _54 = _10 == _53;
    assign _55 = _38 & _54;
    assign _50 = { host_count,
                   host_data };
    always @(posedge clock) begin
        if (clear)
            _56 <= _59;
        else
            if (_55)
                _56 <= _50;
    end
    assign _46 = 2'b01;
    assign _47 = _10 == _46;
    assign _48 = _38 & _47;
    assign _43 = { host_count,
                   host_data };
    always @(posedge clock) begin
        if (clear)
            _49 <= _59;
        else
            if (_48)
                _49 <= _43;
    end
    assign _138 = _10 + _46;
    assign _139 = _38 ? _138 : _10;
    always @(posedge clock) begin
        if (clear)
            _142 <= _119;
        else
            _142 <= _139;
    end
    assign _10 = _142;
    assign _40 = _10 == _119;
    assign _41 = _38 & _40;
    assign _34 = { host_count,
                   host_data };
    always @(posedge clock) begin
        if (clear)
            _42 <= _59;
        else
            if (_41)
                _42 <= _34;
    end
    assign _144 = _13 + _46;
    assign _145 = _33 ? _144 : _13;
    always @(posedge clock) begin
        if (clear)
            _148 <= _119;
        else
            _148 <= _145;
    end
    assign _13 = _148;
    always @* begin
        case (_13)
        0:
            _64 <= _42;
        1:
            _64 <= _49;
        2:
            _64 <= _56;
        default:
            _64 <= _63;
        endcase
    end
    assign _65 = _64[19:16];
    assign _67 = _65 == _108;
    assign _80 = _67 | _79;
    assign _81 = _80 ? _76 : _78;
    assign _30 = 3'b000;
    assign _153 = { _119,
                    _33 };
    assign _23 = 3'b100;
    assign _24 = _15 == _23;
    assign _37 = ~ _24;
    assign _38 = host_push & _37;
    assign _150 = { _119,
                    _38 };
    assign _151 = _15 + _150;
    assign _154 = _151 - _153;
    always @(posedge clock) begin
        if (clear)
            _157 <= _30;
        else
            _157 <= _154;
    end
    assign _15 = _157;
    assign _31 = _15 == _30;
    assign _32 = ~ _31;
    assign _158 = 5'b00001;
    assign _159 = _82 - _158;
    assign _160 = _86 ? _159 : _16;
    always @(posedge clock) begin
        if (clear)
            _163 <= _83;
        else
            _163 <= _160;
    end
    assign _16 = _163;
    assign _28 = _16 == _83;
    assign _29 = _26 & _28;
    assign _33 = _29 & _32;
    assign _82 = _33 ? _81 : _16;
    assign _84 = _82 == _83;
    assign _85 = ~ _84;
    assign _25 = 12'b000000000000;
    assign vdd = 1'b1;
    assign _167 = 12'b000000000001;
    assign _168 = period - _167;
    assign _165 = _20 - _167;
    assign _166 = _26 ? _20 : _165;
    assign _169 = _86 ? _168 : _166;
    always @(posedge clock) begin
        if (clear)
            _172 <= _25;
        else
            _172 <= _169;
    end
    assign _20 = _172;
    assign _26 = _20 == _25;
    assign _86 = _26 & _85;
    assign _175 = _86 ? vdd : _174;
    always @(posedge clock) begin
        if (clear)
            _178 <= _123;
        else
            _178 <= _175;
    end
    assign _21 = _178;
    assign _179 = _21 ? _7 : idle_out;
    assign pin_out = _179;
    assign pin_oe = _111;
    assign full = _24;

endmodule
