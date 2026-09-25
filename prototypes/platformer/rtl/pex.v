module pex (
    clear,
    data_in,
    cfg_strobe,
    clock,
    cfg_in,
    tag_in,
    tag_out,
    data_out,
    s,
    cfg_out
);

    input clear;
    input [15:0] data_in;
    input cfg_strobe;
    input clock;
    input [7:0] cfg_in;
    input [2:0] tag_in;
    output [2:0] tag_out;
    output [15:0] data_out;
    output [15:0] s;
    output [7:0] cfg_out;

    wire [15:0] _235;
    wire [7:0] _230;
    wire [7:0] _231;
    wire [2:0] _58;
    wire _59;
    wire [15:0] _60;
    wire [15:0] _61;
    wire [15:0] _3;
    reg [15:0] _54;
    wire [7:0] _228;
    wire [7:0] _229;
    wire [15:0] _232;
    wire [7:0] _223;
    wire [7:0] _221;
    wire [7:0] _220;
    wire [7:0] _222;
    wire _224;
    wire _225;
    wire _226;
    wire [7:0] _212;
    wire [7:0] _211;
    wire [7:0] _210;
    wire [7:0] _209;
    reg [7:0] _213;
    wire [7:0] _208;
    wire [7:0] _214;
    wire [7:0] _206;
    wire [3:0] _204;
    wire [3:0] _203;
    wire [7:0] _205;
    wire [1:0] _201;
    wire [5:0] _200;
    wire [7:0] _202;
    wire [31:0] _65;
    wire [15:0] _184;
    wire [31:0] _185;
    wire [15:0] _181;
    wire [31:0] _182;
    wire [2:0] _179;
    wire _180;
    wire [31:0] _183;
    wire [2:0] _177;
    wire _178;
    wire [31:0] _186;
    wire [23:0] _170;
    wire [7:0] _169;
    wire [31:0] _171;
    wire [23:0] _167;
    wire [31:0] _168;
    wire [31:0] _172;
    wire [27:0] _163;
    wire [3:0] _162;
    wire [31:0] _164;
    wire [27:0] _160;
    wire [31:0] _161;
    wire [31:0] _165;
    wire [29:0] _156;
    wire [1:0] _155;
    wire [31:0] _157;
    wire [29:0] _153;
    wire [1:0] _152;
    wire [31:0] _154;
    wire [31:0] _158;
    wire [30:0] _149;
    wire _148;
    wire [31:0] _150;
    wire [30:0] _146;
    wire _145;
    wire [31:0] _147;
    wire [31:0] _151;
    reg [31:0] _173;
    wire [7:0] _141;
    wire [23:0] _140;
    wire [31:0] _142;
    wire [23:0] _137;
    wire [31:0] _139;
    wire [31:0] _143;
    wire [3:0] _134;
    wire [27:0] _133;
    wire [31:0] _135;
    wire [27:0] _130;
    wire [31:0] _132;
    wire [31:0] _136;
    wire [1:0] _127;
    wire [29:0] _126;
    wire [31:0] _128;
    wire [29:0] _123;
    wire [31:0] _125;
    wire [31:0] _129;
    wire _120;
    wire [30:0] _119;
    wire [31:0] _121;
    wire [30:0] _116;
    wire [31:0] _118;
    wire _115;
    wire [31:0] _122;
    reg [31:0] _144;
    wire [31:0] _174;
    wire _109;
    wire [31:0] _175;
    wire [31:0] _176;
    wire [31:0] _187;
    wire [31:0] _4;
    reg [31:0] _66;
    wire _198;
    wire [6:0] _197;
    wire [7:0] _199;
    wire [1:0] _114;
    reg [7:0] _207;
    wire [8:0] _111;
    wire [8:0] _190;
    wire [2:0] _188;
    wire _189;
    wire [8:0] _191;
    wire [8:0] _192;
    wire [8:0] _5;
    reg [8:0] _112;
    wire _113;
    wire [7:0] _215;
    wire _217;
    wire _218;
    wire _193;
    wire _194;
    wire _195;
    wire _196;
    wire _219;
    wire _227;
    wire [15:0] _233;
    wire [15:0] _6;
    reg [15:0] _236;
    wire _313;
    wire _307;
    wire gnd;
    wire [15:0] _104;
    wire [15:0] _103;
    wire [15:0] _102;
    wire [15:0] _101;
    wire [15:0] _100;
    wire [15:0] _99;
    wire [15:0] _98;
    wire [15:0] _97;
    wire [15:0] _96;
    wire [15:0] _95;
    wire [15:0] _94;
    wire [15:0] _93;
    wire [15:0] _92;
    wire [15:0] _91;
    wire [15:0] _90;
    wire [3:0] _88;
    reg [15:0] _105;
    wire [7:0] _85;
    wire [15:0] _86;
    wire [11:0] _81;
    wire [15:0] _82;
    wire [13:0] _77;
    wire [15:0] _78;
    wire [14:0] _73;
    wire [15:0] _74;
    wire [2:0] _292;
    wire vdd;
    wire [2:0] _243;
    wire [2:0] _239;
    wire _240;
    wire _241;
    wire [2:0] _244;
    wire [1:0] _237;
    wire _238;
    wire [2:0] _246;
    wire [2:0] _247;
    wire [2:0] _9;
    reg [2:0] _57;
    wire _293;
    wire [15:0] _294;
    wire [15:0] _288;
    wire _286;
    wire [15:0] _287;
    wire [15:0] _283;
    wire _281;
    wire [15:0] _284;
    wire [15:0] _280;
    wire _278;
    wire _277;
    wire _279;
    wire [15:0] _285;
    wire _272;
    wire [15:0] _275;
    wire [15:0] _271;
    wire _269;
    wire _265;
    wire [16:0] _266;
    wire [15:0] _257;
    wire _256;
    wire [15:0] _258;
    wire _259;
    wire [16:0] _260;
    wire [16:0] _261;
    wire _255;
    wire [16:0] _262;
    wire _250;
    wire [15:0] _251;
    wire _252;
    wire [16:0] _253;
    wire [16:0] _263;
    wire [16:0] _267;
    wire _268;
    wire _270;
    wire [15:0] _276;
    wire [1:0] _249;
    reg [15:0] _289;
    wire _248;
    wire [15:0] _290;
    wire [15:0] _291;
    wire [15:0] _295;
    wire [15:0] _10;
    reg [15:0] _38;
    wire _71;
    wire [15:0] _75;
    wire _70;
    wire [15:0] _79;
    wire _69;
    wire [15:0] _83;
    wire [3:0] _67;
    wire _68;
    wire [15:0] _87;
    wire [15:0] _106;
    wire _108;
    wire _301;
    wire _302;
    wire _11;
    reg _298;
    wire _305;
    wire _306;
    wire _308;
    wire _299;
    wire _303;
    wire _304;
    wire _309;
    wire _310;
    wire _311;
    wire [1:0] _62;
    wire _63;
    wire _312;
    wire _314;
    wire _13;
    reg _49;
    wire _50;
    wire _45;
    reg [7:0] _22;
    reg [7:0] _25;
    reg [7:0] _28;
    reg [7:0] _31;
    reg [7:0] _34;
    wire _42;
    wire _41;
    wire _43;
    wire [1:0] _39;
    wire _40;
    wire _44;
    wire _46;
    wire _51;
    wire [2:0] _316;
    wire [2:0] _18;
    reg [2:0] _319;
    assign _235 = 16'b0000000000000000;
    assign _230 = _54[7:0];
    assign _231 = _230 | _215;
    assign _58 = 3'b000;
    assign _59 = _57 == _58;
    assign _60 = _59 ? data_in : _54;
    assign _61 = _51 ? _60 : _54;
    assign _3 = _61;
    always @(posedge clock) begin
        if (clear)
            _54 <= _235;
        else
            _54 <= _3;
    end
    assign _228 = _54[15:8];
    assign _229 = _220 | _228;
    assign _232 = { _229,
                    _231 };
    assign _223 = 8'b00000000;
    assign _221 = _112[7:0];
    assign _220 = data_in[15:8];
    assign _222 = _220 & _221;
    assign _224 = _222 == _223;
    assign _225 = ~ _224;
    assign _226 = ~ _225;
    assign _212 = 8'b11111111;
    assign _211 = 8'b00001111;
    assign _210 = 8'b00000011;
    assign _209 = 8'b00000001;
    always @* begin
        case (_114)
        0:
            _213 <= _209;
        1:
            _213 <= _210;
        2:
            _213 <= _211;
        default:
            _213 <= _212;
        endcase
    end
    assign _208 = _66[7:0];
    assign _214 = _208 & _213;
    assign _206 = _66[31:24];
    assign _204 = _66[31:28];
    assign _203 = 4'b0000;
    assign _205 = { _203,
                    _204 };
    assign _201 = _66[31:30];
    assign _200 = 6'b000000;
    assign _202 = { _200,
                    _201 };
    assign _65 = 32'b00000000000000000000000000000000;
    assign _184 = _66[15:0];
    assign _185 = { data_in,
                    _184 };
    assign _181 = _66[31:16];
    assign _182 = { _181,
                    data_in };
    assign _179 = 3'b010;
    assign _180 = _57 == _179;
    assign _183 = _180 ? _182 : _176;
    assign _177 = 3'b001;
    assign _178 = _57 == _177;
    assign _186 = _178 ? _185 : _183;
    assign _170 = _66[31:8];
    assign _169 = _66[7:0];
    assign _171 = { _169,
                    _170 };
    assign _167 = _66[31:8];
    assign _168 = { _223,
                    _167 };
    assign _172 = _115 ? _171 : _168;
    assign _163 = _66[31:4];
    assign _162 = _66[3:0];
    assign _164 = { _162,
                    _163 };
    assign _160 = _66[31:4];
    assign _161 = { _203,
                    _160 };
    assign _165 = _115 ? _164 : _161;
    assign _156 = _66[31:2];
    assign _155 = _66[1:0];
    assign _157 = { _155,
                    _156 };
    assign _153 = _66[31:2];
    assign _152 = 2'b00;
    assign _154 = { _152,
                    _153 };
    assign _158 = _115 ? _157 : _154;
    assign _149 = _66[31:1];
    assign _148 = _66[0:0];
    assign _150 = { _148,
                    _149 };
    assign _146 = _66[31:1];
    assign _145 = 1'b0;
    assign _147 = { _145,
                    _146 };
    assign _151 = _115 ? _150 : _147;
    always @* begin
        case (_114)
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
    assign _141 = _66[31:24];
    assign _140 = _66[23:0];
    assign _142 = { _140,
                    _141 };
    assign _137 = _66[23:0];
    assign _139 = { _137,
                    _223 };
    assign _143 = _115 ? _142 : _139;
    assign _134 = _66[31:28];
    assign _133 = _66[27:0];
    assign _135 = { _133,
                    _134 };
    assign _130 = _66[27:0];
    assign _132 = { _130,
                    _203 };
    assign _136 = _115 ? _135 : _132;
    assign _127 = _66[31:30];
    assign _126 = _66[29:0];
    assign _128 = { _126,
                    _127 };
    assign _123 = _66[29:0];
    assign _125 = { _123,
                    _152 };
    assign _129 = _115 ? _128 : _125;
    assign _120 = _66[31:31];
    assign _119 = _66[30:0];
    assign _121 = { _119,
                    _120 };
    assign _116 = _66[30:0];
    assign _118 = { _116,
                    _145 };
    assign _115 = _34[7:7];
    assign _122 = _115 ? _121 : _118;
    always @* begin
        case (_114)
        0:
            _144 <= _122;
        1:
            _144 <= _129;
        2:
            _144 <= _136;
        default:
            _144 <= _143;
        endcase
    end
    assign _174 = _113 ? _173 : _144;
    assign _109 = _49 & _108;
    assign _175 = _109 ? _174 : _66;
    assign _176 = _63 ? _175 : _66;
    assign _187 = _51 ? _186 : _176;
    assign _4 = _187;
    always @(posedge clock) begin
        if (clear)
            _66 <= _65;
        else
            _66 <= _4;
    end
    assign _198 = _66[31:31];
    assign _197 = 7'b0000000;
    assign _199 = { _197,
                    _198 };
    assign _114 = _25[1:0];
    always @* begin
        case (_114)
        0:
            _207 <= _199;
        1:
            _207 <= _202;
        2:
            _207 <= _205;
        default:
            _207 <= _206;
        endcase
    end
    assign _111 = 9'b000000000;
    assign _190 = data_in[8:0];
    assign _188 = 3'b100;
    assign _189 = _57 == _188;
    assign _191 = _189 ? _190 : _112;
    assign _192 = _51 ? _191 : _112;
    assign _5 = _192;
    always @(posedge clock) begin
        if (clear)
            _112 <= _111;
        else
            _112 <= _5;
    end
    assign _113 = _112[8:8];
    assign _215 = _113 ? _214 : _207;
    assign _217 = _215 == _223;
    assign _218 = ~ _217;
    assign _193 = _22[4:4];
    assign _194 = _63 & _193;
    assign _195 = _194 & _49;
    assign _196 = _195 & _108;
    assign _219 = _196 & _218;
    assign _227 = _219 & _226;
    assign _233 = _227 ? _232 : data_in;
    assign _6 = _233;
    always @(posedge clock) begin
        if (clear)
            _236 <= _235;
        else
            _236 <= _6;
    end
    assign _313 = _238 ? vdd : _312;
    assign _307 = ~ _108;
    assign gnd = 1'b0;
    assign _104 = 16'b0111111111111111;
    assign _103 = 16'b0011111111111111;
    assign _102 = 16'b0001111111111111;
    assign _101 = 16'b0000111111111111;
    assign _100 = 16'b0000011111111111;
    assign _99 = 16'b0000001111111111;
    assign _98 = 16'b0000000111111111;
    assign _97 = 16'b0000000011111111;
    assign _96 = 16'b0000000001111111;
    assign _95 = 16'b0000000000111111;
    assign _94 = 16'b0000000000011111;
    assign _93 = 16'b0000000000001111;
    assign _92 = 16'b0000000000000111;
    assign _91 = 16'b0000000000000011;
    assign _90 = 16'b0000000000000001;
    assign _88 = _22[3:0];
    always @* begin
        case (_88)
        0:
            _105 <= _235;
        1:
            _105 <= _90;
        2:
            _105 <= _91;
        3:
            _105 <= _92;
        4:
            _105 <= _93;
        5:
            _105 <= _94;
        6:
            _105 <= _95;
        7:
            _105 <= _96;
        8:
            _105 <= _97;
        9:
            _105 <= _98;
        10:
            _105 <= _99;
        11:
            _105 <= _100;
        12:
            _105 <= _101;
        13:
            _105 <= _102;
        14:
            _105 <= _103;
        default:
            _105 <= _104;
        endcase
    end
    assign _85 = _83[15:8];
    assign _86 = { _223,
                   _85 };
    assign _81 = _79[15:4];
    assign _82 = { _203,
                   _81 };
    assign _77 = _75[15:2];
    assign _78 = { _152,
                   _77 };
    assign _73 = _38[15:1];
    assign _74 = { _145,
                   _73 };
    assign _292 = 3'b011;
    assign vdd = 1'b1;
    assign _243 = _57 + _177;
    assign _239 = 3'b111;
    assign _240 = _57 == _239;
    assign _241 = ~ _240;
    assign _244 = _241 ? _243 : _57;
    assign _237 = 2'b11;
    assign _238 = _39 == _237;
    assign _246 = _238 ? _58 : _244;
    assign _247 = _51 ? _246 : _57;
    assign _9 = _247;
    always @(posedge clock) begin
        if (clear)
            _57 <= _58;
        else
            _57 <= _9;
    end
    assign _293 = _57 == _292;
    assign _294 = _293 ? data_in : _291;
    assign _288 = _286 ? _251 : _258;
    assign _286 = _267[16:16];
    assign _287 = _286 ? _258 : _251;
    assign _283 = 16'b1000000000000000;
    assign _281 = _267[16:16];
    assign _284 = _281 ? _283 : _104;
    assign _280 = _267[15:0];
    assign _278 = _267[15:15];
    assign _277 = _267[16:16];
    assign _279 = _277 ^ _278;
    assign _285 = _279 ? _284 : _280;
    assign _272 = _267[16:16];
    assign _275 = _272 ? _283 : _104;
    assign _271 = _267[15:0];
    assign _269 = _267[15:15];
    assign _265 = ~ _255;
    assign _266 = { _235,
                    _265 };
    assign _257 = { _31,
                    _28 };
    assign _256 = _34[2:2];
    assign _258 = _256 ? _257 : _38;
    assign _259 = _258[15:15];
    assign _260 = { _259,
                    _258 };
    assign _261 = ~ _260;
    assign _255 = _249 == _152;
    assign _262 = _255 ? _260 : _261;
    assign _250 = _34[3:3];
    assign _251 = _250 ? _38 : data_in;
    assign _252 = _251[15:15];
    assign _253 = { _252,
                    _251 };
    assign _263 = _253 + _262;
    assign _267 = _263 + _266;
    assign _268 = _267[16:16];
    assign _270 = _268 ^ _269;
    assign _276 = _270 ? _275 : _271;
    assign _249 = _34[1:0];
    always @* begin
        case (_249)
        0:
            _289 <= _276;
        1:
            _289 <= _285;
        2:
            _289 <= _287;
        default:
            _289 <= _288;
        endcase
    end
    assign _248 = _34[4:4];
    assign _290 = _248 ? _289 : _38;
    assign _291 = _63 ? _290 : _38;
    assign _295 = _51 ? _294 : _291;
    assign _10 = _295;
    always @(posedge clock) begin
        if (clear)
            _38 <= _235;
        else
            _38 <= _10;
    end
    assign _71 = _67[0:0];
    assign _75 = _71 ? _74 : _38;
    assign _70 = _67[1:1];
    assign _79 = _70 ? _78 : _75;
    assign _69 = _67[2:2];
    assign _83 = _69 ? _82 : _79;
    assign _67 = _25[5:2];
    assign _68 = _67[3:3];
    assign _87 = _68 ? _86 : _83;
    assign _106 = _87 & _105;
    assign _108 = _106 == _235;
    assign _301 = _299 ? gnd : _108;
    assign _302 = _63 ? _301 : _298;
    assign _11 = _302;
    always @(posedge clock) begin
        if (clear)
            _298 <= _145;
        else
            _298 <= _11;
    end
    assign _305 = _25[6:6];
    assign _306 = _305 & _298;
    assign _308 = _306 & _307;
    assign _299 = data_in[15:15];
    assign _303 = _25[7:7];
    assign _304 = _303 & _299;
    assign _309 = _304 | _308;
    assign _310 = _49 & _309;
    assign _311 = _310 ? gnd : _49;
    assign _62 = 2'b01;
    assign _63 = _39 == _62;
    assign _312 = _63 ? _311 : _49;
    assign _314 = _51 ? _313 : _312;
    assign _13 = _314;
    always @(posedge clock) begin
        if (clear)
            _49 <= _145;
        else
            _49 <= _13;
    end
    assign _50 = ~ _49;
    assign _45 = _34[5:5];
    always @(posedge clock) begin
        if (cfg_strobe)
            _22 <= cfg_in;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _25 <= _22;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _28 <= _25;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _31 <= _28;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _34 <= _31;
    end
    assign _42 = _34[6:6];
    assign _41 = tag_in[2:2];
    assign _43 = _41 == _42;
    assign _39 = tag_in[1:0];
    assign _40 = _39[1:1];
    assign _44 = _40 & _43;
    assign _46 = _44 & _45;
    assign _51 = _46 & _50;
    assign _316 = _51 ? _58 : tag_in;
    assign _18 = _316;
    always @(posedge clock) begin
        if (clear)
            _319 <= _58;
        else
            _319 <= _18;
    end
    assign tag_out = _319;
    assign data_out = _236;
    assign s = _38;
    assign cfg_out = _34;

endmodule
