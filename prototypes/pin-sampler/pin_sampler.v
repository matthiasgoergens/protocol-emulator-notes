module pin_sampler (
    width,
    offset,
    period,
    trig_val,
    pins,
    trig_pin,
    clear,
    clock,
    frame_len,
    clocked,
    pop,
    data,
    count,
    valid,
    overflows
);

    input [2:0] width;
    input [11:0] offset;
    input [11:0] period;
    input trig_val;
    input [3:0] pins;
    input [1:0] trig_pin;
    input clear;
    input clock;
    input [7:0] frame_len;
    input clocked;
    input pop;
    output [15:0] data;
    output [3:0] count;
    output valid;
    output [7:0] overflows;

    wire [7:0] _88;
    wire [7:0] _90;
    wire [7:0] _91;
    wire _85;
    wire _86;
    wire [7:0] _92;
    wire [7:0] _1;
    reg [7:0] _89;
    wire [3:0] _174;
    wire [1:0] _169;
    wire _170;
    wire _171;
    wire [19:0] _168;
    wire [19:0] _166;
    reg [19:0] _172;
    wire [1:0] _162;
    wire _163;
    wire _164;
    wire [19:0] _159;
    reg [19:0] _165;
    wire [1:0] _155;
    wire _156;
    wire _157;
    wire [19:0] _152;
    reg [19:0] _158;
    wire [1:0] _148;
    wire [1:0] _176;
    wire [1:0] _177;
    reg [1:0] _180;
    wire [1:0] _5;
    wire _149;
    wire _150;
    wire [7:0] _140;
    wire [15:0] _142;
    wire [3:0] _137;
    wire [11:0] _136;
    wire [15:0] _138;
    wire [13:0] _132;
    wire [15:0] _134;
    wire _129;
    wire [14:0] _128;
    wire [15:0] _130;
    wire [15:0] _125;
    wire [15:0] _123;
    wire [15:0] _122;
    wire [2:0] _120;
    wire _121;
    wire [15:0] _124;
    wire [2:0] _118;
    wire _119;
    wire [15:0] _126;
    wire [11:0] _116;
    wire [15:0] _117;
    wire [15:0] _127;
    wire _115;
    wire [15:0] _131;
    wire _114;
    wire [15:0] _135;
    wire _113;
    wire [15:0] _139;
    wire [14:0] _106;
    wire [15:0] _108;
    wire [10:0] _101;
    wire [15:0] _102;
    wire [13:0] _103;
    wire [15:0] _105;
    wire _100;
    wire [15:0] _109;
    wire _98;
    wire [15:0] _110;
    wire [3:0] _111;
    wire _112;
    wire [15:0] _143;
    wire [15:0] _185;
    wire [15:0] _181;
    wire [15:0] _183;
    reg [15:0] _186;
    wire [15:0] _6;
    wire [15:0] _144;
    wire [3:0] _94;
    wire _93;
    wire [3:0] _96;
    wire [19:0] _145;
    reg [19:0] _151;
    wire [1:0] _232;
    wire [2:0] _79;
    wire [2:0] _226;
    wire [2:0] _76;
    wire _77;
    wire _78;
    wire _83;
    wire [4:0] _62;
    wire [4:0] _60;
    wire [4:0] _59;
    wire _58;
    wire [4:0] _61;
    wire _56;
    wire [4:0] _63;
    wire [4:0] _53;
    wire [4:0] _191;
    wire [4:0] _187;
    wire [4:0] _189;
    reg [4:0] _192;
    wire [4:0] _8;
    wire [4:0] _54;
    wire _64;
    wire _74;
    wire [11:0] _201;
    wire [11:0] _202;
    wire [11:0] _200;
    wire _198;
    wire [11:0] _203;
    wire [11:0] _204;
    wire _196;
    wire [11:0] _205;
    reg [11:0] _208;
    wire [11:0] _11;
    wire _28;
    wire gnd;
    wire _47;
    wire _46;
    wire _45;
    reg [3:0] _43;
    wire _44;
    reg _48;
    wire _49;
    wire _50;
    wire _37;
    wire _36;
    wire _35;
    wire _34;
    reg _38;
    wire _39;
    reg _33;
    wire _40;
    wire _51;
    wire _194;
    wire _193;
    wire _195;
    wire _215;
    wire _216;
    wire vdd;
    wire [7:0] _209;
    wire [7:0] _211;
    reg [7:0] _214;
    wire [7:0] _17;
    wire [7:0] _70;
    wire _71;
    wire _72;
    wire _66;
    wire _67;
    wire _68;
    wire _73;
    wire _218;
    reg _221;
    wire _19;
    wire _25;
    wire _26;
    wire _29;
    wire _52;
    wire _75;
    wire _84;
    wire [2:0] _223;
    wire [2:0] _224;
    wire [2:0] _227;
    reg [2:0] _230;
    wire [2:0] _21;
    wire _80;
    wire _81;
    wire _82;
    wire [1:0] _233;
    reg [1:0] _236;
    wire [1:0] _23;
    reg [19:0] _173;
    wire [15:0] _237;
    assign _88 = 8'b00000000;
    assign _90 = 8'b00000001;
    assign _91 = _89 + _90;
    assign _85 = ~ _84;
    assign _86 = _75 & _85;
    assign _92 = _86 ? _91 : _89;
    assign _1 = _92;
    always @(posedge clock) begin
        if (clear)
            _89 <= _88;
        else
            _89 <= _1;
    end
    assign _174 = _173[19:16];
    assign _169 = 2'b11;
    assign _170 = _5 == _169;
    assign _171 = _84 & _170;
    assign _168 = 20'b00000000000000000000;
    assign _166 = { _96,
                    _144 };
    always @(posedge clock) begin
        if (clear)
            _172 <= _168;
        else
            if (_171)
                _172 <= _166;
    end
    assign _162 = 2'b10;
    assign _163 = _5 == _162;
    assign _164 = _84 & _163;
    assign _159 = { _96,
                    _144 };
    always @(posedge clock) begin
        if (clear)
            _165 <= _168;
        else
            if (_164)
                _165 <= _159;
    end
    assign _155 = 2'b01;
    assign _156 = _5 == _155;
    assign _157 = _84 & _156;
    assign _152 = { _96,
                    _144 };
    always @(posedge clock) begin
        if (clear)
            _158 <= _168;
        else
            if (_157)
                _158 <= _152;
    end
    assign _148 = 2'b00;
    assign _176 = _5 + _155;
    assign _177 = _84 ? _176 : _5;
    always @(posedge clock) begin
        if (clear)
            _180 <= _148;
        else
            _180 <= _177;
    end
    assign _5 = _180;
    assign _149 = _5 == _148;
    assign _150 = _84 & _149;
    assign _140 = _139[7:0];
    assign _142 = { _140,
                    _88 };
    assign _137 = 4'b0000;
    assign _136 = _135[11:0];
    assign _138 = { _136,
                    _137 };
    assign _132 = _131[13:0];
    assign _134 = { _132,
                    _148 };
    assign _129 = 1'b0;
    assign _128 = _127[14:0];
    assign _130 = { _128,
                    _129 };
    assign _125 = 16'b0000000000000001;
    assign _123 = 16'b0000000000000011;
    assign _122 = 16'b0000000000001111;
    assign _120 = 3'b010;
    assign _121 = width == _120;
    assign _124 = _121 ? _123 : _122;
    assign _118 = 3'b001;
    assign _119 = width == _118;
    assign _126 = _119 ? _125 : _124;
    assign _116 = 12'b000000000000;
    assign _117 = { _116,
                    pins };
    assign _127 = _117 & _126;
    assign _115 = _111[0:0];
    assign _131 = _115 ? _130 : _127;
    assign _114 = _111[1:1];
    assign _135 = _114 ? _134 : _131;
    assign _113 = _111[2:2];
    assign _139 = _113 ? _138 : _135;
    assign _106 = _102[14:0];
    assign _108 = { _106,
                    _129 };
    assign _101 = 11'b00000000000;
    assign _102 = { _101,
                    _8 };
    assign _103 = _102[13:0];
    assign _105 = { _103,
                    _148 };
    assign _100 = width == _120;
    assign _109 = _100 ? _108 : _105;
    assign _98 = width == _118;
    assign _110 = _98 ? _102 : _109;
    assign _111 = _110[3:0];
    assign _112 = _111[3:3];
    assign _143 = _112 ? _142 : _139;
    assign _185 = 16'b0000000000000000;
    assign _181 = _52 ? _144 : _6;
    assign _183 = _75 ? _185 : _181;
    always @(posedge clock) begin
        if (clear)
            _186 <= _185;
        else
            _186 <= _183;
    end
    assign _6 = _186;
    assign _144 = _6 | _143;
    assign _94 = _54[3:0];
    assign _93 = _54 == _63;
    assign _96 = _93 ? _137 : _94;
    assign _145 = { _96,
                    _144 };
    always @(posedge clock) begin
        if (clear)
            _151 <= _168;
        else
            if (_150)
                _151 <= _145;
    end
    assign _232 = _23 + _155;
    assign _79 = 3'b000;
    assign _226 = { _148,
                    _82 };
    assign _76 = 3'b100;
    assign _77 = _21 == _76;
    assign _78 = ~ _77;
    assign _83 = _78 | _82;
    assign _62 = 5'b10000;
    assign _60 = 5'b01000;
    assign _59 = 5'b00100;
    assign _58 = width == _120;
    assign _61 = _58 ? _60 : _59;
    assign _56 = width == _118;
    assign _63 = _56 ? _62 : _61;
    assign _53 = 5'b00001;
    assign _191 = 5'b00000;
    assign _187 = _52 ? _54 : _8;
    assign _189 = _75 ? _191 : _187;
    always @(posedge clock) begin
        if (clear)
            _192 <= _191;
        else
            _192 <= _189;
    end
    assign _8 = _192;
    assign _54 = _8 + _53;
    assign _64 = _54 == _63;
    assign _74 = _64 | _73;
    assign _201 = 12'b000000000001;
    assign _202 = period - _201;
    assign _200 = _11 - _201;
    assign _198 = _11 == _116;
    assign _203 = _198 ? _202 : _200;
    assign _204 = _26 ? _203 : _11;
    assign _196 = _195 & _51;
    assign _205 = _196 ? offset : _204;
    always @(posedge clock) begin
        if (clear)
            _208 <= _116;
        else
            _208 <= _205;
    end
    assign _11 = _208;
    assign _28 = _11 == _116;
    assign gnd = 1'b0;
    assign _47 = _43[3:3];
    assign _46 = _43[2:2];
    assign _45 = _43[1:1];
    always @(posedge clock) begin
        if (clear)
            _43 <= _137;
        else
            _43 <= pins;
    end
    assign _44 = _43[0:0];
    always @* begin
        case (trig_pin)
        0:
            _48 <= _44;
        1:
            _48 <= _45;
        2:
            _48 <= _46;
        default:
            _48 <= _47;
        endcase
    end
    assign _49 = _48 == trig_val;
    assign _50 = ~ _49;
    assign _37 = pins[3:3];
    assign _36 = pins[2:2];
    assign _35 = pins[1:1];
    assign _34 = pins[0:0];
    always @* begin
        case (trig_pin)
        0:
            _38 <= _34;
        1:
            _38 <= _35;
        2:
            _38 <= _36;
        default:
            _38 <= _37;
        endcase
    end
    assign _39 = _38 == trig_val;
    always @(posedge clock) begin
        if (clear)
            _33 <= _129;
        else
            _33 <= vdd;
    end
    assign _40 = _33 & _39;
    assign _51 = _40 & _50;
    assign _194 = ~ _19;
    assign _193 = ~ clocked;
    assign _195 = _193 & _194;
    assign _215 = _195 & _51;
    assign _216 = _215 ? vdd : _19;
    assign vdd = 1'b1;
    assign _209 = _52 ? _70 : _17;
    assign _211 = _73 ? _88 : _209;
    always @(posedge clock) begin
        if (clear)
            _214 <= _88;
        else
            _214 <= _211;
    end
    assign _17 = _214;
    assign _70 = _17 + _90;
    assign _71 = _70 < frame_len;
    assign _72 = ~ _71;
    assign _66 = frame_len == _88;
    assign _67 = ~ _66;
    assign _68 = _52 & _67;
    assign _73 = _68 & _72;
    assign _218 = _73 ? gnd : _216;
    always @(posedge clock) begin
        if (clear)
            _221 <= _129;
        else
            _221 <= _218;
    end
    assign _19 = _221;
    assign _25 = ~ clocked;
    assign _26 = _25 & _19;
    assign _29 = _26 & _28;
    assign _52 = clocked ? _51 : _29;
    assign _75 = _52 & _74;
    assign _84 = _75 & _83;
    assign _223 = { _148,
                    _84 };
    assign _224 = _21 + _223;
    assign _227 = _224 - _226;
    always @(posedge clock) begin
        if (clear)
            _230 <= _79;
        else
            _230 <= _227;
    end
    assign _21 = _230;
    assign _80 = _21 == _79;
    assign _81 = ~ _80;
    assign _82 = pop & _81;
    assign _233 = _82 ? _232 : _23;
    always @(posedge clock) begin
        if (clear)
            _236 <= _148;
        else
            _236 <= _233;
    end
    assign _23 = _236;
    always @* begin
        case (_23)
        0:
            _173 <= _151;
        1:
            _173 <= _158;
        2:
            _173 <= _165;
        default:
            _173 <= _172;
        endcase
    end
    assign _237 = _173[15:0];
    assign data = _237;
    assign count = _174;
    assign valid = _81;
    assign overflows = _89;

endmodule
