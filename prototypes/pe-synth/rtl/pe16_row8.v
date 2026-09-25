module pe16_row8 (
    en,
    clear,
    nbr_in,
    cfg_strobe,
    clock,
    cfg_in,
    out0,
    out1,
    out2,
    out3,
    out4,
    out5,
    out6,
    out7,
    pipe_out,
    cfg_out
);

    input [7:0] en;
    input clear;
    input [15:0] nbr_in;
    input cfg_strobe;
    input clock;
    input [7:0] cfg_in;
    output [15:0] out0;
    output [15:0] out1;
    output [15:0] out2;
    output [15:0] out3;
    output [15:0] out4;
    output [15:0] out5;
    output [15:0] out6;
    output [15:0] out7;
    output [15:0] pipe_out;
    output [7:0] cfg_out;

    wire _165;
    wire [15:0] _164;
    wire [15:0] _161;
    wire _159;
    wire [15:0] _160;
    wire [15:0] _156;
    wire [15:0] _155;
    wire _154;
    wire [15:0] _157;
    wire [15:0] _153;
    wire _151;
    wire _150;
    wire _152;
    wire [15:0] _158;
    wire _145;
    wire [15:0] _148;
    wire [15:0] _144;
    wire _142;
    wire _138;
    wire [16:0] _139;
    wire [15:0] _130;
    wire _129;
    wire [15:0] _131;
    wire _132;
    wire [16:0] _133;
    wire [16:0] _134;
    wire [1:0] _127;
    wire _128;
    wire [16:0] _135;
    wire _123;
    wire [15:0] _124;
    wire _125;
    wire [16:0] _126;
    wire [16:0] _136;
    wire [16:0] _140;
    wire _141;
    wire _143;
    wire [15:0] _149;
    wire [1:0] _122;
    reg [15:0] _162;
    reg [15:0] _166;
    wire [15:0] _3;
    reg [15:0] _121;
    wire [7:0] _95;
    reg [7:0] _90;
    reg [7:0] _93;
    reg [7:0] _96;
    wire _167;
    wire [15:0] _168;
    wire _212;
    wire [15:0] _208;
    wire _206;
    wire [15:0] _207;
    wire _201;
    wire [15:0] _204;
    wire [15:0] _200;
    wire _198;
    wire _197;
    wire _199;
    wire [15:0] _205;
    wire _192;
    wire [15:0] _195;
    wire [15:0] _191;
    wire _189;
    wire _185;
    wire [16:0] _186;
    wire [15:0] _177;
    wire _176;
    wire [15:0] _178;
    wire _179;
    wire [16:0] _180;
    wire [16:0] _181;
    wire _175;
    wire [16:0] _182;
    wire _170;
    wire [15:0] _171;
    wire _172;
    wire [16:0] _173;
    wire [16:0] _183;
    wire [16:0] _187;
    wire _188;
    wire _190;
    wire [15:0] _196;
    wire [1:0] _169;
    reg [15:0] _209;
    reg [15:0] _213;
    wire [15:0] _5;
    reg [15:0] _118;
    reg [7:0] _81;
    reg [7:0] _84;
    reg [7:0] _87;
    wire _214;
    wire [15:0] _215;
    wire _259;
    wire [15:0] _255;
    wire _253;
    wire [15:0] _254;
    wire _248;
    wire [15:0] _251;
    wire [15:0] _247;
    wire _245;
    wire _244;
    wire _246;
    wire [15:0] _252;
    wire _239;
    wire [15:0] _242;
    wire [15:0] _238;
    wire _236;
    wire _232;
    wire [16:0] _233;
    wire [15:0] _224;
    wire _223;
    wire [15:0] _225;
    wire _226;
    wire [16:0] _227;
    wire [16:0] _228;
    wire _222;
    wire [16:0] _229;
    wire _217;
    wire [15:0] _218;
    wire _219;
    wire [16:0] _220;
    wire [16:0] _230;
    wire [16:0] _234;
    wire _235;
    wire _237;
    wire [15:0] _243;
    wire [1:0] _216;
    reg [15:0] _256;
    reg [15:0] _260;
    wire [15:0] _7;
    reg [15:0] _115;
    reg [7:0] _72;
    reg [7:0] _75;
    reg [7:0] _78;
    wire _261;
    wire [15:0] _262;
    wire _306;
    wire [15:0] _302;
    wire _300;
    wire [15:0] _301;
    wire _295;
    wire [15:0] _298;
    wire [15:0] _294;
    wire _292;
    wire _291;
    wire _293;
    wire [15:0] _299;
    wire _286;
    wire [15:0] _289;
    wire [15:0] _285;
    wire _283;
    wire _279;
    wire [16:0] _280;
    wire [15:0] _271;
    wire _270;
    wire [15:0] _272;
    wire _273;
    wire [16:0] _274;
    wire [16:0] _275;
    wire _269;
    wire [16:0] _276;
    wire _264;
    wire [15:0] _265;
    wire _266;
    wire [16:0] _267;
    wire [16:0] _277;
    wire [16:0] _281;
    wire _282;
    wire _284;
    wire [15:0] _290;
    wire [1:0] _263;
    reg [15:0] _303;
    reg [15:0] _307;
    wire [15:0] _9;
    reg [15:0] _112;
    reg [7:0] _63;
    reg [7:0] _66;
    reg [7:0] _69;
    wire _308;
    wire [15:0] _309;
    wire _353;
    wire [15:0] _349;
    wire _347;
    wire [15:0] _348;
    wire _342;
    wire [15:0] _345;
    wire [15:0] _341;
    wire _339;
    wire _338;
    wire _340;
    wire [15:0] _346;
    wire _333;
    wire [15:0] _336;
    wire [15:0] _332;
    wire _330;
    wire _326;
    wire [16:0] _327;
    wire [15:0] _318;
    wire _317;
    wire [15:0] _319;
    wire _320;
    wire [16:0] _321;
    wire [16:0] _322;
    wire _316;
    wire [16:0] _323;
    wire _311;
    wire [15:0] _312;
    wire _313;
    wire [16:0] _314;
    wire [16:0] _324;
    wire [16:0] _328;
    wire _329;
    wire _331;
    wire [15:0] _337;
    wire [1:0] _310;
    reg [15:0] _350;
    reg [15:0] _354;
    wire [15:0] _11;
    reg [15:0] _109;
    reg [7:0] _54;
    reg [7:0] _57;
    reg [7:0] _60;
    wire _355;
    wire [15:0] _356;
    wire _400;
    wire [15:0] _396;
    wire _394;
    wire [15:0] _395;
    wire _389;
    wire [15:0] _392;
    wire [15:0] _388;
    wire _386;
    wire _385;
    wire _387;
    wire [15:0] _393;
    wire _380;
    wire [15:0] _383;
    wire [15:0] _379;
    wire _377;
    wire _373;
    wire [16:0] _374;
    wire [15:0] _365;
    wire _364;
    wire [15:0] _366;
    wire _367;
    wire [16:0] _368;
    wire [16:0] _369;
    wire _363;
    wire [16:0] _370;
    wire _358;
    wire [15:0] _359;
    wire _360;
    wire [16:0] _361;
    wire [16:0] _371;
    wire [16:0] _375;
    wire _376;
    wire _378;
    wire [15:0] _384;
    wire [1:0] _357;
    reg [15:0] _397;
    reg [15:0] _401;
    wire [15:0] _13;
    reg [15:0] _106;
    reg [7:0] _45;
    reg [7:0] _48;
    reg [7:0] _51;
    wire _402;
    wire [15:0] _403;
    wire _447;
    wire [15:0] _443;
    wire _441;
    wire [15:0] _442;
    wire _436;
    wire [15:0] _439;
    wire [15:0] _435;
    wire _433;
    wire _432;
    wire _434;
    wire [15:0] _440;
    wire _427;
    wire [15:0] _430;
    wire [15:0] _426;
    wire _424;
    wire _420;
    wire [16:0] _421;
    wire [15:0] _412;
    wire _411;
    wire [15:0] _413;
    wire _414;
    wire [16:0] _415;
    wire [16:0] _416;
    wire _410;
    wire [16:0] _417;
    wire _405;
    wire [15:0] _406;
    wire _407;
    wire [16:0] _408;
    wire [16:0] _418;
    wire [16:0] _422;
    wire _423;
    wire _425;
    wire [15:0] _431;
    wire [1:0] _404;
    reg [15:0] _444;
    reg [15:0] _448;
    wire [15:0] _15;
    reg [15:0] _103;
    reg [7:0] _36;
    reg [7:0] _39;
    reg [7:0] _42;
    wire _449;
    wire [15:0] _450;
    wire _494;
    wire [15:0] _490;
    wire _488;
    wire [15:0] _489;
    wire _483;
    wire [15:0] _486;
    wire [15:0] _482;
    wire _480;
    wire _479;
    wire _481;
    wire [15:0] _487;
    wire _474;
    wire [15:0] _477;
    wire [15:0] _473;
    wire _471;
    wire _467;
    wire [16:0] _468;
    wire [15:0] _459;
    wire _458;
    wire [15:0] _460;
    wire _461;
    wire [16:0] _462;
    wire [16:0] _463;
    wire _457;
    wire [16:0] _464;
    wire _452;
    wire [15:0] _453;
    wire _454;
    wire [16:0] _455;
    wire [16:0] _465;
    wire [16:0] _469;
    wire _470;
    wire _472;
    wire [15:0] _478;
    wire [1:0] _451;
    reg [15:0] _491;
    reg [15:0] _495;
    wire [15:0] _18;
    wire vdd;
    reg [15:0] _100;
    reg [7:0] _27;
    reg [7:0] _30;
    reg [7:0] _33;
    wire _496;
    wire [15:0] _497;
    assign _165 = en[7:7];
    assign _164 = 16'b0000000000000000;
    assign _161 = _159 ? _124 : _131;
    assign _159 = _140[16:16];
    assign _160 = _159 ? _131 : _124;
    assign _156 = 16'b1000000000000000;
    assign _155 = 16'b0111111111111111;
    assign _154 = _140[16:16];
    assign _157 = _154 ? _156 : _155;
    assign _153 = _140[15:0];
    assign _151 = _140[15:15];
    assign _150 = _140[16:16];
    assign _152 = _150 ^ _151;
    assign _158 = _152 ? _157 : _153;
    assign _145 = _140[16:16];
    assign _148 = _145 ? _156 : _155;
    assign _144 = _140[15:0];
    assign _142 = _140[15:15];
    assign _138 = ~ _128;
    assign _139 = { _164,
                    _138 };
    assign _130 = { _93,
                    _90 };
    assign _129 = _96[2:2];
    assign _131 = _129 ? _130 : _3;
    assign _132 = _131[15:15];
    assign _133 = { _132,
                    _131 };
    assign _134 = ~ _133;
    assign _127 = 2'b00;
    assign _128 = _122 == _127;
    assign _135 = _128 ? _133 : _134;
    assign _123 = _96[3:3];
    assign _124 = _123 ? _3 : _118;
    assign _125 = _124[15:15];
    assign _126 = { _125,
                    _124 };
    assign _136 = _126 + _135;
    assign _140 = _136 + _139;
    assign _141 = _140[16:16];
    assign _143 = _141 ^ _142;
    assign _149 = _143 ? _148 : _144;
    assign _122 = _96[1:0];
    always @* begin
        case (_122)
        0:
            _162 <= _149;
        1:
            _162 <= _158;
        2:
            _162 <= _160;
        default:
            _162 <= _161;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _166 <= _164;
        else
            if (_165)
                _166 <= _162;
    end
    assign _3 = _166;
    always @(posedge clock) begin
        if (clear)
            _121 <= _164;
        else
            _121 <= _118;
    end
    assign _95 = 8'b00000000;
    always @(posedge clock) begin
        if (cfg_strobe)
            _90 <= _87;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _93 <= _90;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _96 <= _93;
    end
    assign _167 = _96[4:4];
    assign _168 = _167 ? _3 : _121;
    assign _212 = en[6:6];
    assign _208 = _206 ? _171 : _178;
    assign _206 = _187[16:16];
    assign _207 = _206 ? _178 : _171;
    assign _201 = _187[16:16];
    assign _204 = _201 ? _156 : _155;
    assign _200 = _187[15:0];
    assign _198 = _187[15:15];
    assign _197 = _187[16:16];
    assign _199 = _197 ^ _198;
    assign _205 = _199 ? _204 : _200;
    assign _192 = _187[16:16];
    assign _195 = _192 ? _156 : _155;
    assign _191 = _187[15:0];
    assign _189 = _187[15:15];
    assign _185 = ~ _175;
    assign _186 = { _164,
                    _185 };
    assign _177 = { _84,
                    _81 };
    assign _176 = _87[2:2];
    assign _178 = _176 ? _177 : _5;
    assign _179 = _178[15:15];
    assign _180 = { _179,
                    _178 };
    assign _181 = ~ _180;
    assign _175 = _169 == _127;
    assign _182 = _175 ? _180 : _181;
    assign _170 = _87[3:3];
    assign _171 = _170 ? _5 : _115;
    assign _172 = _171[15:15];
    assign _173 = { _172,
                    _171 };
    assign _183 = _173 + _182;
    assign _187 = _183 + _186;
    assign _188 = _187[16:16];
    assign _190 = _188 ^ _189;
    assign _196 = _190 ? _195 : _191;
    assign _169 = _87[1:0];
    always @* begin
        case (_169)
        0:
            _209 <= _196;
        1:
            _209 <= _205;
        2:
            _209 <= _207;
        default:
            _209 <= _208;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _213 <= _164;
        else
            if (_212)
                _213 <= _209;
    end
    assign _5 = _213;
    always @(posedge clock) begin
        if (clear)
            _118 <= _164;
        else
            _118 <= _115;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _81 <= _78;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _84 <= _81;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _87 <= _84;
    end
    assign _214 = _87[4:4];
    assign _215 = _214 ? _5 : _118;
    assign _259 = en[5:5];
    assign _255 = _253 ? _218 : _225;
    assign _253 = _234[16:16];
    assign _254 = _253 ? _225 : _218;
    assign _248 = _234[16:16];
    assign _251 = _248 ? _156 : _155;
    assign _247 = _234[15:0];
    assign _245 = _234[15:15];
    assign _244 = _234[16:16];
    assign _246 = _244 ^ _245;
    assign _252 = _246 ? _251 : _247;
    assign _239 = _234[16:16];
    assign _242 = _239 ? _156 : _155;
    assign _238 = _234[15:0];
    assign _236 = _234[15:15];
    assign _232 = ~ _222;
    assign _233 = { _164,
                    _232 };
    assign _224 = { _75,
                    _72 };
    assign _223 = _78[2:2];
    assign _225 = _223 ? _224 : _7;
    assign _226 = _225[15:15];
    assign _227 = { _226,
                    _225 };
    assign _228 = ~ _227;
    assign _222 = _216 == _127;
    assign _229 = _222 ? _227 : _228;
    assign _217 = _78[3:3];
    assign _218 = _217 ? _7 : _112;
    assign _219 = _218[15:15];
    assign _220 = { _219,
                    _218 };
    assign _230 = _220 + _229;
    assign _234 = _230 + _233;
    assign _235 = _234[16:16];
    assign _237 = _235 ^ _236;
    assign _243 = _237 ? _242 : _238;
    assign _216 = _78[1:0];
    always @* begin
        case (_216)
        0:
            _256 <= _243;
        1:
            _256 <= _252;
        2:
            _256 <= _254;
        default:
            _256 <= _255;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _260 <= _164;
        else
            if (_259)
                _260 <= _256;
    end
    assign _7 = _260;
    always @(posedge clock) begin
        if (clear)
            _115 <= _164;
        else
            _115 <= _112;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _72 <= _69;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _75 <= _72;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _78 <= _75;
    end
    assign _261 = _78[4:4];
    assign _262 = _261 ? _7 : _115;
    assign _306 = en[4:4];
    assign _302 = _300 ? _265 : _272;
    assign _300 = _281[16:16];
    assign _301 = _300 ? _272 : _265;
    assign _295 = _281[16:16];
    assign _298 = _295 ? _156 : _155;
    assign _294 = _281[15:0];
    assign _292 = _281[15:15];
    assign _291 = _281[16:16];
    assign _293 = _291 ^ _292;
    assign _299 = _293 ? _298 : _294;
    assign _286 = _281[16:16];
    assign _289 = _286 ? _156 : _155;
    assign _285 = _281[15:0];
    assign _283 = _281[15:15];
    assign _279 = ~ _269;
    assign _280 = { _164,
                    _279 };
    assign _271 = { _66,
                    _63 };
    assign _270 = _69[2:2];
    assign _272 = _270 ? _271 : _9;
    assign _273 = _272[15:15];
    assign _274 = { _273,
                    _272 };
    assign _275 = ~ _274;
    assign _269 = _263 == _127;
    assign _276 = _269 ? _274 : _275;
    assign _264 = _69[3:3];
    assign _265 = _264 ? _9 : _109;
    assign _266 = _265[15:15];
    assign _267 = { _266,
                    _265 };
    assign _277 = _267 + _276;
    assign _281 = _277 + _280;
    assign _282 = _281[16:16];
    assign _284 = _282 ^ _283;
    assign _290 = _284 ? _289 : _285;
    assign _263 = _69[1:0];
    always @* begin
        case (_263)
        0:
            _303 <= _290;
        1:
            _303 <= _299;
        2:
            _303 <= _301;
        default:
            _303 <= _302;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _307 <= _164;
        else
            if (_306)
                _307 <= _303;
    end
    assign _9 = _307;
    always @(posedge clock) begin
        if (clear)
            _112 <= _164;
        else
            _112 <= _109;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _63 <= _60;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _66 <= _63;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _69 <= _66;
    end
    assign _308 = _69[4:4];
    assign _309 = _308 ? _9 : _112;
    assign _353 = en[3:3];
    assign _349 = _347 ? _312 : _319;
    assign _347 = _328[16:16];
    assign _348 = _347 ? _319 : _312;
    assign _342 = _328[16:16];
    assign _345 = _342 ? _156 : _155;
    assign _341 = _328[15:0];
    assign _339 = _328[15:15];
    assign _338 = _328[16:16];
    assign _340 = _338 ^ _339;
    assign _346 = _340 ? _345 : _341;
    assign _333 = _328[16:16];
    assign _336 = _333 ? _156 : _155;
    assign _332 = _328[15:0];
    assign _330 = _328[15:15];
    assign _326 = ~ _316;
    assign _327 = { _164,
                    _326 };
    assign _318 = { _57,
                    _54 };
    assign _317 = _60[2:2];
    assign _319 = _317 ? _318 : _11;
    assign _320 = _319[15:15];
    assign _321 = { _320,
                    _319 };
    assign _322 = ~ _321;
    assign _316 = _310 == _127;
    assign _323 = _316 ? _321 : _322;
    assign _311 = _60[3:3];
    assign _312 = _311 ? _11 : _106;
    assign _313 = _312[15:15];
    assign _314 = { _313,
                    _312 };
    assign _324 = _314 + _323;
    assign _328 = _324 + _327;
    assign _329 = _328[16:16];
    assign _331 = _329 ^ _330;
    assign _337 = _331 ? _336 : _332;
    assign _310 = _60[1:0];
    always @* begin
        case (_310)
        0:
            _350 <= _337;
        1:
            _350 <= _346;
        2:
            _350 <= _348;
        default:
            _350 <= _349;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _354 <= _164;
        else
            if (_353)
                _354 <= _350;
    end
    assign _11 = _354;
    always @(posedge clock) begin
        if (clear)
            _109 <= _164;
        else
            _109 <= _106;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _54 <= _51;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _57 <= _54;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _60 <= _57;
    end
    assign _355 = _60[4:4];
    assign _356 = _355 ? _11 : _109;
    assign _400 = en[2:2];
    assign _396 = _394 ? _359 : _366;
    assign _394 = _375[16:16];
    assign _395 = _394 ? _366 : _359;
    assign _389 = _375[16:16];
    assign _392 = _389 ? _156 : _155;
    assign _388 = _375[15:0];
    assign _386 = _375[15:15];
    assign _385 = _375[16:16];
    assign _387 = _385 ^ _386;
    assign _393 = _387 ? _392 : _388;
    assign _380 = _375[16:16];
    assign _383 = _380 ? _156 : _155;
    assign _379 = _375[15:0];
    assign _377 = _375[15:15];
    assign _373 = ~ _363;
    assign _374 = { _164,
                    _373 };
    assign _365 = { _48,
                    _45 };
    assign _364 = _51[2:2];
    assign _366 = _364 ? _365 : _13;
    assign _367 = _366[15:15];
    assign _368 = { _367,
                    _366 };
    assign _369 = ~ _368;
    assign _363 = _357 == _127;
    assign _370 = _363 ? _368 : _369;
    assign _358 = _51[3:3];
    assign _359 = _358 ? _13 : _103;
    assign _360 = _359[15:15];
    assign _361 = { _360,
                    _359 };
    assign _371 = _361 + _370;
    assign _375 = _371 + _374;
    assign _376 = _375[16:16];
    assign _378 = _376 ^ _377;
    assign _384 = _378 ? _383 : _379;
    assign _357 = _51[1:0];
    always @* begin
        case (_357)
        0:
            _397 <= _384;
        1:
            _397 <= _393;
        2:
            _397 <= _395;
        default:
            _397 <= _396;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _401 <= _164;
        else
            if (_400)
                _401 <= _397;
    end
    assign _13 = _401;
    always @(posedge clock) begin
        if (clear)
            _106 <= _164;
        else
            _106 <= _103;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _45 <= _42;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _48 <= _45;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _51 <= _48;
    end
    assign _402 = _51[4:4];
    assign _403 = _402 ? _13 : _106;
    assign _447 = en[1:1];
    assign _443 = _441 ? _406 : _413;
    assign _441 = _422[16:16];
    assign _442 = _441 ? _413 : _406;
    assign _436 = _422[16:16];
    assign _439 = _436 ? _156 : _155;
    assign _435 = _422[15:0];
    assign _433 = _422[15:15];
    assign _432 = _422[16:16];
    assign _434 = _432 ^ _433;
    assign _440 = _434 ? _439 : _435;
    assign _427 = _422[16:16];
    assign _430 = _427 ? _156 : _155;
    assign _426 = _422[15:0];
    assign _424 = _422[15:15];
    assign _420 = ~ _410;
    assign _421 = { _164,
                    _420 };
    assign _412 = { _39,
                    _36 };
    assign _411 = _42[2:2];
    assign _413 = _411 ? _412 : _15;
    assign _414 = _413[15:15];
    assign _415 = { _414,
                    _413 };
    assign _416 = ~ _415;
    assign _410 = _404 == _127;
    assign _417 = _410 ? _415 : _416;
    assign _405 = _42[3:3];
    assign _406 = _405 ? _15 : _100;
    assign _407 = _406[15:15];
    assign _408 = { _407,
                    _406 };
    assign _418 = _408 + _417;
    assign _422 = _418 + _421;
    assign _423 = _422[16:16];
    assign _425 = _423 ^ _424;
    assign _431 = _425 ? _430 : _426;
    assign _404 = _42[1:0];
    always @* begin
        case (_404)
        0:
            _444 <= _431;
        1:
            _444 <= _440;
        2:
            _444 <= _442;
        default:
            _444 <= _443;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _448 <= _164;
        else
            if (_447)
                _448 <= _444;
    end
    assign _15 = _448;
    always @(posedge clock) begin
        if (clear)
            _103 <= _164;
        else
            _103 <= _100;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _36 <= _33;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _39 <= _36;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _42 <= _39;
    end
    assign _449 = _42[4:4];
    assign _450 = _449 ? _15 : _103;
    assign _494 = en[0:0];
    assign _490 = _488 ? _453 : _460;
    assign _488 = _469[16:16];
    assign _489 = _488 ? _460 : _453;
    assign _483 = _469[16:16];
    assign _486 = _483 ? _156 : _155;
    assign _482 = _469[15:0];
    assign _480 = _469[15:15];
    assign _479 = _469[16:16];
    assign _481 = _479 ^ _480;
    assign _487 = _481 ? _486 : _482;
    assign _474 = _469[16:16];
    assign _477 = _474 ? _156 : _155;
    assign _473 = _469[15:0];
    assign _471 = _469[15:15];
    assign _467 = ~ _457;
    assign _468 = { _164,
                    _467 };
    assign _459 = { _30,
                    _27 };
    assign _458 = _33[2:2];
    assign _460 = _458 ? _459 : _18;
    assign _461 = _460[15:15];
    assign _462 = { _461,
                    _460 };
    assign _463 = ~ _462;
    assign _457 = _451 == _127;
    assign _464 = _457 ? _462 : _463;
    assign _452 = _33[3:3];
    assign _453 = _452 ? _18 : nbr_in;
    assign _454 = _453[15:15];
    assign _455 = { _454,
                    _453 };
    assign _465 = _455 + _464;
    assign _469 = _465 + _468;
    assign _470 = _469[16:16];
    assign _472 = _470 ^ _471;
    assign _478 = _472 ? _477 : _473;
    assign _451 = _33[1:0];
    always @* begin
        case (_451)
        0:
            _491 <= _478;
        1:
            _491 <= _487;
        2:
            _491 <= _489;
        default:
            _491 <= _490;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _495 <= _164;
        else
            if (_494)
                _495 <= _491;
    end
    assign _18 = _495;
    assign vdd = 1'b1;
    always @(posedge clock) begin
        if (clear)
            _100 <= _164;
        else
            _100 <= nbr_in;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _27 <= cfg_in;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _30 <= _27;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _33 <= _30;
    end
    assign _496 = _33[4:4];
    assign _497 = _496 ? _18 : _100;
    assign out0 = _497;
    assign out1 = _450;
    assign out2 = _403;
    assign out3 = _356;
    assign out4 = _309;
    assign out5 = _262;
    assign out6 = _215;
    assign out7 = _168;
    assign pipe_out = _121;
    assign cfg_out = _96;

endmodule
