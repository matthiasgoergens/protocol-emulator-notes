module upe_v1 (
    s15_in,
    init_in,
    g_in,
    cb_in,
    bcast,
    alane,
    lstep_in,
    av,
    run,
    init_wr,
    a,
    cfg_wr,
    clock,
    cfg_in,
    p,
    pv,
    l,
    g,
    step,
    s15,
    cfg_out,
    init_out,
    tap,
    f
);

    input s15_in;
    input [7:0] init_in;
    input g_in;
    input cb_in;
    input bcast;
    input alane;
    input lstep_in;
    input av;
    input run;
    input init_wr;
    input [15:0] a;
    input cfg_wr;
    input clock;
    input [7:0] cfg_in;
    output [15:0] p;
    output pv;
    output l;
    output g;
    output step;
    output s15;
    output [7:0] cfg_out;
    output [7:0] init_out;
    output [15:0] tap;
    output f;

    wire _56;
    wire [15:0] _57;
    wire [7:0] _58;
    wire _59;
    wire _184;
    wire _181;
    wire _150;
    wire [1:0] _137;
    reg _182;
    reg _185;
    wire _8;
    wire _186;
    wire _187;
    wire _188;
    wire _189;
    wire _190;
    reg _193;
    wire _10;
    wire [15:0] _258;
    wire [7:0] _253;
    wire [7:0] _252;
    wire [15:0] _254;
    wire [15:0] _255;
    wire [15:0] _250;
    wire [15:0] _249;
    reg [15:0] _251;
    wire [15:0] _246;
    wire [15:0] _245;
    wire [15:0] _244;
    wire [14:0] _239;
    wire _237;
    wire _238;
    wire [15:0] _240;
    wire [14:0] _235;
    wire _233;
    wire _234;
    wire [15:0] _236;
    wire _241;
    wire _242;
    wire [15:0] _243;
    wire [14:0] _228;
    wire _226;
    wire _227;
    wire [15:0] _229;
    wire [14:0] _224;
    wire _222;
    wire _223;
    wire [15:0] _225;
    wire _230;
    wire _231;
    wire [15:0] _232;
    wire [15:0] _219;
    wire [15:0] _218;
    wire _217;
    wire [15:0] _220;
    wire _214;
    wire _177;
    wire _178;
    wire [16:0] _179;
    wire [16:0] _174;
    wire gnd;
    wire [16:0] _152;
    wire [16:0] _175;
    wire [16:0] _180;
    wire [15:0] _212;
    wire _213;
    wire _215;
    wire [1:0] _165;
    wire _166;
    wire _167;
    wire [1:0] _163;
    wire _164;
    wire _168;
    wire [1:0] _169;
    wire [3:0] _170;
    wire [7:0] _171;
    wire [15:0] _172;
    wire [15:0] _159;
    wire [1:0] _158;
    reg [15:0] _160;
    wire _156;
    wire [1:0] _154;
    wire [1:0] _153;
    wire _155;
    wire _157;
    wire [15:0] _162;
    wire [15:0] _173;
    wire _210;
    wire [14:0] _145;
    wire [15:0] _146;
    wire _142;
    wire [1:0] _141;
    reg _143;
    wire [14:0] _140;
    wire [15:0] _144;
    wire [7:0] _202;
    wire [15:0] _203;
    wire _133;
    wire _132;
    wire _131;
    wire _130;
    wire _129;
    wire _128;
    wire _127;
    wire _126;
    wire _125;
    wire _124;
    wire _123;
    wire _122;
    wire _121;
    wire _120;
    wire _119;
    wire _116;
    wire _115;
    wire _114;
    wire _113;
    wire _112;
    wire _111;
    wire _110;
    wire _109;
    wire _108;
    wire _107;
    wire _106;
    wire _105;
    wire _104;
    wire _103;
    wire _102;
    wire _101;
    wire [15:0] _117;
    wire _118;
    wire [3:0] _100;
    reg _134;
    wire [3:0] _98;
    wire [15:0] _94;
    wire [7:0] _95;
    wire [7:0] _93;
    wire [7:0] _96;
    wire [3:0] _97;
    wire _99;
    wire _135;
    wire _196;
    wire [1:0] _194;
    reg _197;
    reg _200;
    wire _15;
    wire _91;
    wire _89;
    wire _90;
    wire _92;
    wire _87;
    wire _88;
    wire _85;
    wire _86;
    wire _83;
    wire _82;
    wire _81;
    wire _80;
    wire _79;
    wire _78;
    wire _77;
    wire _76;
    wire _75;
    wire _74;
    wire _73;
    wire _72;
    wire _71;
    wire _70;
    wire _69;
    wire _68;
    wire [3:0] _67;
    reg _84;
    wire [2:0] _66;
    reg _136;
    wire [15:0] _148;
    wire [1:0] _138;
    reg [15:0] _149;
    wire vdd;
    wire _61;
    wire _63;
    wire _60;
    wire _64;
    wire _65;
    wire [15:0] _201;
    wire [15:0] _204;
    reg [15:0] _207;
    wire [15:0] _23;
    wire [1:0] _139;
    reg [15:0] _147;
    wire _209;
    wire _211;
    wire _216;
    wire [15:0] _221;
    wire [2:0] _208;
    reg [15:0] _247;
    wire [15:0] _24;
    wire [7:0] _53;
    reg [7:0] _33;
    reg [7:0] _36;
    reg [7:0] _39;
    reg [7:0] _42;
    reg [7:0] _45;
    reg [7:0] _48;
    reg [7:0] _51;
    reg [7:0] _54;
    wire [63:0] _55;
    wire [1:0] _248;
    reg [15:0] _256;
    reg [15:0] _259;
    wire [15:0] _29;
    assign _56 = _55[47:47];
    assign _57 = _56 ? _29 : _23;
    assign _58 = _23[15:8];
    assign _59 = _23[15:15];
    assign _184 = 1'b0;
    assign _181 = _180[16:16];
    assign _150 = _149[15:15];
    assign _137 = _55[43:42];
    always @* begin
        case (_137)
        0:
            _182 <= _86;
        1:
            _182 <= _150;
        2:
            _182 <= _181;
        default:
            _182 <= _136;
        endcase
    end
    always @(posedge clock) begin
        if (_65)
            _185 <= _182;
    end
    assign _8 = _185;
    assign _186 = _55[45:45];
    assign _187 = _186 & _136;
    assign _188 = ~ _187;
    assign _189 = av & _188;
    assign _190 = run ? _189 : _10;
    always @(posedge clock) begin
        _193 <= _190;
    end
    assign _10 = _193;
    assign _258 = 16'b0000000000000000;
    assign _253 = _94[7:0];
    assign _252 = a[15:8];
    assign _254 = { _252,
                    _253 };
    assign _255 = _136 ? _254 : a;
    assign _250 = _242 ? _173 : _147;
    assign _249 = _231 ? _173 : _147;
    always @* begin
        case (_208)
        0:
            _251 <= _147;
        1:
            _251 <= _147;
        2:
            _251 <= _249;
        3:
            _251 <= _250;
        4:
            _251 <= _147;
        5:
            _251 <= _147;
        6:
            _251 <= _147;
        default:
            _251 <= _147;
        endcase
    end
    assign _246 = _147 | _173;
    assign _245 = _147 & _173;
    assign _244 = _147 ^ _173;
    assign _239 = _147[14:0];
    assign _237 = _147[15:15];
    assign _238 = ~ _237;
    assign _240 = { _238,
                    _239 };
    assign _235 = _173[14:0];
    assign _233 = _173[15:15];
    assign _234 = ~ _233;
    assign _236 = { _234,
                    _235 };
    assign _241 = _236 < _240;
    assign _242 = ~ _241;
    assign _243 = _242 ? _147 : _173;
    assign _228 = _173[14:0];
    assign _226 = _173[15:15];
    assign _227 = ~ _226;
    assign _229 = { _227,
                    _228 };
    assign _224 = _147[14:0];
    assign _222 = _147[15:15];
    assign _223 = ~ _222;
    assign _225 = { _223,
                    _224 };
    assign _230 = _225 < _229;
    assign _231 = ~ _230;
    assign _232 = _231 ? _147 : _173;
    assign _219 = 16'b1000000000000000;
    assign _218 = 16'b0111111111111111;
    assign _217 = _147[15:15];
    assign _220 = _217 ? _219 : _218;
    assign _214 = _147[15:15];
    assign _177 = _55[35:35];
    assign _178 = _177 ? _86 : _168;
    assign _179 = { _258,
                    _178 };
    assign _174 = { gnd,
                    _173 };
    assign gnd = 1'b0;
    assign _152 = { gnd,
                    _147 };
    assign _175 = _152 + _174;
    assign _180 = _175 + _179;
    assign _212 = _180[15:0];
    assign _213 = _212[15:15];
    assign _215 = _213 ^ _214;
    assign _165 = 2'b10;
    assign _166 = _153 == _165;
    assign _167 = _166 & _136;
    assign _163 = 2'b11;
    assign _164 = _153 == _163;
    assign _168 = _164 | _167;
    assign _169 = { _168,
                    _168 };
    assign _170 = { _169,
                    _169 };
    assign _171 = { _170,
                    _170 };
    assign _172 = { _171,
                    _171 };
    assign _159 = 16'b0000000000000001;
    assign _158 = _55[21:20];
    always @* begin
        case (_158)
        0:
            _160 <= _94;
        1:
            _160 <= a;
        2:
            _160 <= _23;
        default:
            _160 <= _159;
        endcase
    end
    assign _156 = ~ _136;
    assign _154 = 2'b01;
    assign _153 = _55[23:22];
    assign _155 = _153 == _154;
    assign _157 = _155 & _156;
    assign _162 = _157 ? _258 : _160;
    assign _173 = _162 ^ _172;
    assign _210 = _173[15:15];
    assign _145 = _23[15:1];
    assign _146 = { _143,
                    _145 };
    assign _142 = a[0:0];
    assign _141 = _55[19:18];
    always @* begin
        case (_141)
        0:
            _143 <= _136;
        1:
            _143 <= _86;
        2:
            _143 <= s15_in;
        default:
            _143 <= _142;
        endcase
    end
    assign _140 = _23[14:0];
    assign _144 = { _140,
                    _143 };
    assign _202 = _23[7:0];
    assign _203 = { _202,
                    init_in };
    assign _133 = _117[15:15];
    assign _132 = _117[14:14];
    assign _131 = _117[13:13];
    assign _130 = _117[12:12];
    assign _129 = _117[11:11];
    assign _128 = _117[10:10];
    assign _127 = _117[9:9];
    assign _126 = _117[8:8];
    assign _125 = _117[7:7];
    assign _124 = _117[6:6];
    assign _123 = _117[5:5];
    assign _122 = _117[4:4];
    assign _121 = _117[3:3];
    assign _120 = _117[2:2];
    assign _119 = _117[1:1];
    assign _116 = _23[15:15];
    assign _115 = _23[14:14];
    assign _114 = _23[13:13];
    assign _113 = _23[12:12];
    assign _112 = _23[11:11];
    assign _111 = _23[10:10];
    assign _110 = _23[9:9];
    assign _109 = _23[8:8];
    assign _108 = _23[7:7];
    assign _107 = _23[6:6];
    assign _106 = _23[5:5];
    assign _105 = _23[4:4];
    assign _104 = _23[3:3];
    assign _103 = _23[2:2];
    assign _102 = _23[1:1];
    assign _101 = _23[0:0];
    assign _117 = { _101,
                    _102,
                    _103,
                    _104,
                    _105,
                    _106,
                    _107,
                    _108,
                    _109,
                    _110,
                    _111,
                    _112,
                    _113,
                    _114,
                    _115,
                    _116 };
    assign _118 = _117[0:0];
    assign _100 = _96[3:0];
    always @* begin
        case (_100)
        0:
            _134 <= _118;
        1:
            _134 <= _119;
        2:
            _134 <= _120;
        3:
            _134 <= _121;
        4:
            _134 <= _122;
        5:
            _134 <= _123;
        6:
            _134 <= _124;
        7:
            _134 <= _125;
        8:
            _134 <= _126;
        9:
            _134 <= _127;
        10:
            _134 <= _128;
        11:
            _134 <= _129;
        12:
            _134 <= _130;
        13:
            _134 <= _131;
        14:
            _134 <= _132;
        default:
            _134 <= _133;
        endcase
    end
    assign _98 = 4'b0000;
    assign _94 = _55[15:0];
    assign _95 = _94[15:8];
    assign _93 = a[15:8];
    assign _96 = _93 - _95;
    assign _97 = _96[7:4];
    assign _99 = _97 == _98;
    assign _135 = _99 & _134;
    assign _196 = _24 == _258;
    assign _194 = _55[41:40];
    always @* begin
        case (_194)
        0:
            _197 <= _15;
        1:
            _197 <= _136;
        2:
            _197 <= _196;
        default:
            _197 <= _15;
        endcase
    end
    always @(posedge clock) begin
        if (_65)
            _200 <= _197;
    end
    assign _15 = _200;
    assign _91 = a[0:0];
    assign _89 = _55[31:31];
    assign _90 = _89 ? cb_in : _87;
    assign _92 = _90 ^ _91;
    assign _87 = _23[15:15];
    assign _88 = _87 ^ _86;
    assign _85 = _55[44:44];
    assign _86 = _85 ? bcast : alane;
    assign _83 = a[15:15];
    assign _82 = a[14:14];
    assign _81 = a[13:13];
    assign _80 = a[12:12];
    assign _79 = a[11:11];
    assign _78 = a[10:10];
    assign _77 = a[9:9];
    assign _76 = a[8:8];
    assign _75 = a[7:7];
    assign _74 = a[6:6];
    assign _73 = a[5:5];
    assign _72 = a[4:4];
    assign _71 = a[3:3];
    assign _70 = a[2:2];
    assign _69 = a[1:1];
    assign _68 = a[0:0];
    assign _67 = _55[30:27];
    always @* begin
        case (_67)
        0:
            _84 <= _68;
        1:
            _84 <= _69;
        2:
            _84 <= _70;
        3:
            _84 <= _71;
        4:
            _84 <= _72;
        5:
            _84 <= _73;
        6:
            _84 <= _74;
        7:
            _84 <= _75;
        8:
            _84 <= _76;
        9:
            _84 <= _77;
        10:
            _84 <= _78;
        11:
            _84 <= _79;
        12:
            _84 <= _80;
        13:
            _84 <= _81;
        14:
            _84 <= _82;
        default:
            _84 <= _83;
        endcase
    end
    assign _66 = _55[26:24];
    always @* begin
        case (_66)
        0:
            _136 <= vdd;
        1:
            _136 <= _84;
        2:
            _136 <= _86;
        3:
            _136 <= _88;
        4:
            _136 <= _92;
        5:
            _136 <= _15;
        6:
            _136 <= _135;
        default:
            _136 <= g_in;
        endcase
    end
    assign _148 = _136 ? _24 : _23;
    assign _138 = _55[37:36];
    always @* begin
        case (_138)
        0:
            _149 <= _23;
        1:
            _149 <= _24;
        2:
            _149 <= _147;
        default:
            _149 <= _148;
        endcase
    end
    assign vdd = 1'b1;
    assign _61 = _55[46:46];
    assign _63 = _61 ? av : vdd;
    assign _60 = _55[48:48];
    assign _64 = _60 ? lstep_in : _63;
    assign _65 = run & _64;
    assign _201 = _65 ? _149 : _23;
    assign _204 = init_wr ? _203 : _201;
    always @(posedge clock) begin
        _207 <= _204;
    end
    assign _23 = _207;
    assign _139 = _55[17:16];
    always @* begin
        case (_139)
        0:
            _147 <= _23;
        1:
            _147 <= a;
        2:
            _147 <= _144;
        default:
            _147 <= _146;
        endcase
    end
    assign _209 = _147[15:15];
    assign _211 = _209 == _210;
    assign _216 = _211 & _215;
    assign _221 = _216 ? _220 : _212;
    assign _208 = _55[34:32];
    always @* begin
        case (_208)
        0:
            _247 <= _221;
        1:
            _247 <= _212;
        2:
            _247 <= _232;
        3:
            _247 <= _243;
        4:
            _247 <= _244;
        5:
            _247 <= _245;
        6:
            _247 <= _246;
        default:
            _247 <= _173;
        endcase
    end
    assign _24 = _247;
    assign _53 = 8'b00000000;
    always @(posedge clock) begin
        if (cfg_wr)
            _33 <= cfg_in;
    end
    always @(posedge clock) begin
        if (cfg_wr)
            _36 <= _33;
    end
    always @(posedge clock) begin
        if (cfg_wr)
            _39 <= _36;
    end
    always @(posedge clock) begin
        if (cfg_wr)
            _42 <= _39;
    end
    always @(posedge clock) begin
        if (cfg_wr)
            _45 <= _42;
    end
    always @(posedge clock) begin
        if (cfg_wr)
            _48 <= _45;
    end
    always @(posedge clock) begin
        if (cfg_wr)
            _51 <= _48;
    end
    always @(posedge clock) begin
        if (cfg_wr)
            _54 <= _51;
    end
    assign _55 = { _54,
                   _51,
                   _48,
                   _45,
                   _42,
                   _39,
                   _36,
                   _33 };
    assign _248 = _55[39:38];
    always @* begin
        case (_248)
        0:
            _256 <= a;
        1:
            _256 <= _24;
        2:
            _256 <= _251;
        default:
            _256 <= _255;
        endcase
    end
    always @(posedge clock) begin
        if (_65)
            _259 <= _256;
    end
    assign _29 = _259;
    assign p = _29;
    assign pv = _10;
    assign l = _8;
    assign g = _136;
    assign step = _65;
    assign s15 = _59;
    assign cfg_out = _54;
    assign init_out = _58;
    assign tap = _57;
    assign f = _15;

endmodule
