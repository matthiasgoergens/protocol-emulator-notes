module hdmi_pixel (
    clear,
    clock,
    word_b,
    word_g,
    word_r,
    toggle,
    led_1hz
);

    input clear;
    input clock;
    output [9:0] word_b;
    output [9:0] word_g;
    output [9:0] word_r;
    output toggle;
    output led_1hz;

    wire _31;
    wire [23:0] _16;
    wire [23:0] _27;
    wire [23:0] _22;
    wire [23:0] _23;
    wire [23:0] _25;
    reg [23:0] _28;
    wire [23:0] _1;
    wire _17;
    reg _21;
    wire _29;
    reg _32;
    wire _2;
    wire _33;
    reg _36;
    wire _4;
    wire [9:0] _299;
    wire [7:0] _293;
    wire [7:0] _294;
    wire _292;
    wire [9:0] _295;
    wire [7:0] _289;
    wire [9:0] _290;
    wire [9:0] _288;
    wire [9:0] _291;
    wire [3:0] _240;
    wire _241;
    wire [4:0] _46;
    wire [4:0] _280;
    wire [4:0] _279;
    wire [4:0] _281;
    wire [3:0] _271;
    wire [4:0] _272;
    wire [3:0] _273;
    wire [4:0] _275;
    wire [4:0] _276;
    wire [4:0] _277;
    wire [4:0] _268;
    wire [4:0] _264;
    wire [3:0] _265;
    wire [4:0] _267;
    wire [4:0] _269;
    wire _256;
    wire _257;
    wire [4:0] _258;
    wire [3:0] _259;
    wire [4:0] _261;
    wire [4:0] _262;
    wire [4:0] _270;
    wire _252;
    wire _250;
    wire _253;
    wire _235;
    wire [2:0] _234;
    wire [3:0] _236;
    wire _232;
    wire [3:0] _233;
    wire [3:0] _237;
    wire _228;
    wire [3:0] _229;
    wire _225;
    wire [3:0] _226;
    wire [3:0] _230;
    wire [3:0] _238;
    wire _220;
    wire [3:0] _221;
    wire _217;
    wire [3:0] _218;
    wire [3:0] _222;
    wire _213;
    wire [3:0] _214;
    wire _207;
    wire _205;
    wire _203;
    wire _201;
    wire _199;
    wire _197;
    wire _195;
    wire _193;
    wire _191;
    wire _189;
    wire _187;
    wire _185;
    wire _183;
    wire _181;
    wire _180;
    wire _182;
    wire _184;
    wire _186;
    wire _188;
    wire _190;
    wire _192;
    wire _194;
    wire _196;
    wire _198;
    wire _200;
    wire _202;
    wire _204;
    wire _206;
    wire _176;
    wire _177;
    wire _175;
    wire _178;
    wire _168;
    wire [3:0] _169;
    wire _165;
    wire [3:0] _166;
    wire [3:0] _170;
    wire _161;
    wire [3:0] _162;
    wire _158;
    wire [3:0] _159;
    wire [3:0] _163;
    wire [3:0] _171;
    wire _153;
    wire [3:0] _154;
    wire _150;
    wire [3:0] _151;
    wire [3:0] _155;
    wire _146;
    wire [3:0] _147;
    wire [7:0] _141;
    wire [2:0] _134;
    wire _135;
    wire [2:0] _131;
    wire _132;
    wire [2:0] _128;
    wire _129;
    wire _127;
    wire _130;
    wire _133;
    wire _136;
    wire [7:0] _137;
    wire [7:0] _83;
    wire [9:0] _66;
    wire _67;
    wire [7:0] _82;
    wire _65;
    wire [7:0] _84;
    wire [9:0] _62;
    wire _63;
    wire [7:0] _138;
    wire [7:0] _139;
    reg [7:0] _142;
    wire _143;
    wire [3:0] _144;
    wire [3:0] _148;
    wire [3:0] _156;
    wire [3:0] _172;
    wire _173;
    wire _179;
    wire _208;
    wire [7:0] _209;
    wire _210;
    wire [3:0] _211;
    wire [3:0] _215;
    wire [3:0] _223;
    wire [3:0] _239;
    wire _248;
    wire _245;
    wire _243;
    wire _244;
    wire _246;
    wire _249;
    wire _254;
    wire [4:0] _278;
    wire [4:0] _282;
    wire [4:0] _283;
    reg [4:0] _286;
    wire [4:0] _6;
    wire _47;
    wire _242;
    wire [9:0] _296;
    wire [9:0] _287;
    wire [9:0] _297;
    reg [9:0] _300;
    wire [7:0] _473;
    wire [7:0] _474;
    wire _472;
    wire [9:0] _475;
    wire [7:0] _469;
    wire [9:0] _470;
    wire [9:0] _468;
    wire [9:0] _471;
    wire _422;
    wire [4:0] _460;
    wire [4:0] _459;
    wire [4:0] _461;
    wire [4:0] _452;
    wire [3:0] _453;
    wire [4:0] _455;
    wire [4:0] _456;
    wire [4:0] _457;
    wire [4:0] _444;
    wire [3:0] _445;
    wire [4:0] _447;
    wire [4:0] _449;
    wire _437;
    wire _438;
    wire [4:0] _439;
    wire [3:0] _440;
    wire [4:0] _442;
    wire [4:0] _443;
    wire [4:0] _450;
    wire _433;
    wire _431;
    wire _434;
    wire _416;
    wire [3:0] _417;
    wire _413;
    wire [3:0] _414;
    wire [3:0] _418;
    wire _409;
    wire [3:0] _410;
    wire _406;
    wire [3:0] _407;
    wire [3:0] _411;
    wire [3:0] _419;
    wire _401;
    wire [3:0] _402;
    wire _398;
    wire [3:0] _399;
    wire [3:0] _403;
    wire _394;
    wire [3:0] _395;
    wire _388;
    wire _386;
    wire _384;
    wire _382;
    wire _380;
    wire _378;
    wire _376;
    wire _374;
    wire _372;
    wire _370;
    wire _368;
    wire _366;
    wire _364;
    wire _362;
    wire _361;
    wire _363;
    wire _365;
    wire _367;
    wire _369;
    wire _371;
    wire _373;
    wire _375;
    wire _377;
    wire _379;
    wire _381;
    wire _383;
    wire _385;
    wire _387;
    wire _357;
    wire _358;
    wire _356;
    wire _359;
    wire _349;
    wire [3:0] _350;
    wire _346;
    wire [3:0] _347;
    wire [3:0] _351;
    wire _342;
    wire [3:0] _343;
    wire _339;
    wire [3:0] _340;
    wire [3:0] _344;
    wire [3:0] _352;
    wire _334;
    wire [3:0] _335;
    wire _331;
    wire [3:0] _332;
    wire [3:0] _336;
    wire _327;
    wire [3:0] _328;
    wire _317;
    wire [7:0] _318;
    wire [7:0] _314;
    wire _312;
    wire [7:0] _313;
    wire _310;
    wire [7:0] _315;
    wire _308;
    wire [7:0] _319;
    wire [7:0] _320;
    reg [7:0] _323;
    wire _324;
    wire [3:0] _325;
    wire [3:0] _329;
    wire [3:0] _337;
    wire [3:0] _353;
    wire _354;
    wire _360;
    wire _389;
    wire [7:0] _390;
    wire _391;
    wire [3:0] _392;
    wire [3:0] _396;
    wire [3:0] _404;
    wire [3:0] _420;
    wire _429;
    wire _426;
    wire _424;
    wire _425;
    wire _427;
    wire _430;
    wire _435;
    wire [4:0] _458;
    wire [4:0] _462;
    wire [4:0] _463;
    reg [4:0] _466;
    wire [4:0] _8;
    wire _303;
    wire _423;
    wire [9:0] _476;
    wire [9:0] _477;
    reg [9:0] _480;
    wire [7:0] _707;
    wire [7:0] _708;
    wire _706;
    wire [9:0] _709;
    wire [7:0] _703;
    wire [9:0] _704;
    wire [9:0] _702;
    wire [9:0] _705;
    wire _612;
    wire [4:0] _650;
    wire [4:0] _649;
    wire [4:0] _651;
    wire [4:0] _642;
    wire [3:0] _643;
    wire [4:0] _645;
    wire [4:0] _646;
    wire [4:0] _647;
    wire gnd;
    wire [4:0] _634;
    wire [3:0] _635;
    wire [4:0] _637;
    wire [4:0] _639;
    wire _627;
    wire _628;
    wire [4:0] _629;
    wire [3:0] _630;
    wire [4:0] _632;
    wire [4:0] _633;
    wire [4:0] _640;
    wire _623;
    wire _621;
    wire _624;
    wire _606;
    wire [3:0] _607;
    wire _603;
    wire [3:0] _604;
    wire [3:0] _608;
    wire _599;
    wire [3:0] _600;
    wire _596;
    wire [3:0] _597;
    wire [3:0] _601;
    wire [3:0] _609;
    wire _591;
    wire [3:0] _592;
    wire _588;
    wire [3:0] _589;
    wire [3:0] _593;
    wire _584;
    wire [3:0] _585;
    wire _578;
    wire _576;
    wire _574;
    wire _572;
    wire _570;
    wire _568;
    wire _566;
    wire _564;
    wire _562;
    wire _560;
    wire _558;
    wire _556;
    wire _554;
    wire _552;
    wire _551;
    wire _553;
    wire _555;
    wire _557;
    wire _559;
    wire _561;
    wire _563;
    wire _565;
    wire _567;
    wire _569;
    wire _571;
    wire _573;
    wire _575;
    wire _577;
    wire _547;
    wire _548;
    wire _546;
    wire _549;
    wire _539;
    wire [3:0] _540;
    wire _536;
    wire [3:0] _537;
    wire [3:0] _541;
    wire _532;
    wire [3:0] _533;
    wire _529;
    wire [3:0] _530;
    wire [3:0] _534;
    wire [3:0] _542;
    wire _524;
    wire [3:0] _525;
    wire _521;
    wire [3:0] _522;
    wire [3:0] _526;
    wire _517;
    wire [3:0] _518;
    wire [2:0] _505;
    wire _506;
    wire _503;
    wire [2:0] _499;
    wire _500;
    wire [9:0] _121;
    wire _122;
    wire _123;
    wire [1:0] _120;
    wire [2:0] _124;
    wire [9:0] _115;
    wire _116;
    wire _117;
    wire [2:0] _118;
    wire [9:0] _109;
    wire _110;
    wire _111;
    wire [2:0] _112;
    wire _104;
    wire _105;
    wire [2:0] _106;
    wire [9:0] _97;
    wire _98;
    wire _99;
    wire [2:0] _100;
    wire _92;
    wire _93;
    wire [2:0] _94;
    wire [9:0] _86;
    wire _87;
    wire _88;
    wire [2:0] _89;
    wire [2:0] _95;
    wire [2:0] _101;
    wire [2:0] _107;
    wire [2:0] _113;
    wire [2:0] _119;
    wire [2:0] _125;
    wire _498;
    wire _501;
    wire _504;
    wire _507;
    wire [7:0] _508;
    wire [9:0] _494;
    wire [7:0] _495;
    wire [7:0] _80;
    wire _76;
    wire _75;
    wire _77;
    wire _78;
    wire [7:0] _81;
    wire [7:0] _72;
    wire [9:0] _70;
    wire [5:0] _68;
    wire [15:0] _71;
    wire [23:0] _73;
    wire [7:0] _74;
    wire _492;
    wire [7:0] _493;
    wire _490;
    wire [7:0] _496;
    wire _488;
    wire [7:0] _509;
    wire [9:0] _59;
    wire _60;
    wire [9:0] _56;
    wire _57;
    wire _54;
    wire _52;
    wire _55;
    wire _58;
    wire _61;
    wire [7:0] _510;
    reg [7:0] _513;
    wire _514;
    wire [3:0] _515;
    wire [3:0] _519;
    wire [3:0] _527;
    wire [3:0] _543;
    wire _544;
    wire _550;
    wire _579;
    wire [7:0] _580;
    wire _581;
    wire [3:0] _582;
    wire [3:0] _586;
    wire [3:0] _594;
    wire [3:0] _610;
    wire _619;
    wire _616;
    wire _614;
    wire _615;
    wire _617;
    wire _620;
    wire _625;
    wire [4:0] _648;
    wire [4:0] _652;
    wire [4:0] _653;
    reg [4:0] _656;
    wire [4:0] _10;
    wire _483;
    wire _613;
    wire [9:0] _710;
    wire [9:0] _700;
    wire [9:0] _699;
    wire [9:0] _698;
    wire [9:0] _689;
    wire _690;
    wire [9:0] _686;
    wire _687;
    wire _688;
    wire _691;
    wire _692;
    reg _695;
    wire [9:0] _679;
    wire _680;
    wire [9:0] _676;
    wire _677;
    wire _678;
    wire _681;
    wire _682;
    reg _685;
    wire [1:0] _696;
    reg [9:0] _701;
    wire [9:0] _661;
    wire [9:0] _662;
    wire [9:0] _659;
    wire _660;
    wire [9:0] _664;
    wire [9:0] _665;
    reg [9:0] _668;
    wire [9:0] _11;
    wire _40;
    wire [9:0] _37;
    wire vdd;
    wire [9:0] _670;
    wire [9:0] _657;
    wire _658;
    wire [9:0] _672;
    reg [9:0] _675;
    wire [9:0] _14;
    wire _38;
    wire _41;
    reg _44;
    wire [9:0] _711;
    reg [9:0] _714;
    assign _31 = 1'b0;
    assign _16 = 24'b101111101011110000011110;
    assign _27 = 24'b000000000000000000000000;
    assign _22 = 24'b000000000000000000000001;
    assign _23 = _1 + _22;
    assign _25 = _21 ? _27 : _23;
    always @(posedge clock) begin
        if (clear)
            _28 <= _27;
        else
            _28 <= _25;
    end
    assign _1 = _28;
    assign _17 = _1 == _16;
    always @(posedge clock) begin
        if (clear)
            _21 <= _31;
        else
            _21 <= _17;
    end
    assign _29 = _2 ^ _21;
    always @(posedge clock) begin
        if (clear)
            _32 <= _31;
        else
            _32 <= _29;
    end
    assign _2 = _32;
    assign _33 = ~ _4;
    always @(posedge clock) begin
        if (clear)
            _36 <= _31;
        else
            _36 <= _33;
    end
    assign _4 = _36;
    assign _299 = 10'b0000000000;
    assign _293 = ~ _209;
    assign _294 = _256 ? _209 : _293;
    assign _292 = ~ _256;
    assign _295 = { _292,
                    _256,
                    _294 };
    assign _289 = ~ _209;
    assign _290 = { vdd,
                    _256,
                    _289 };
    assign _288 = { gnd,
                    _256,
                    _209 };
    assign _291 = _254 ? _290 : _288;
    assign _240 = 4'b0100;
    assign _241 = _239 == _240;
    assign _46 = 5'b00000;
    assign _280 = _6 + _269;
    assign _279 = _6 - _269;
    assign _281 = _256 ? _280 : _279;
    assign _271 = 4'b0000;
    assign _272 = { _271,
                    _256 };
    assign _273 = _272[3:0];
    assign _275 = { _273,
                    _31 };
    assign _276 = _6 + _275;
    assign _277 = _276 - _269;
    assign _268 = 5'b01000;
    assign _264 = { gnd,
                    _239 };
    assign _265 = _264[3:0];
    assign _267 = { _265,
                    _31 };
    assign _269 = _267 - _268;
    assign _256 = ~ _179;
    assign _257 = ~ _256;
    assign _258 = { _271,
                    _257 };
    assign _259 = _258[3:0];
    assign _261 = { _259,
                    _31 };
    assign _262 = _6 - _261;
    assign _270 = _262 + _269;
    assign _252 = _239 < _240;
    assign _250 = _6[4:4];
    assign _253 = _250 & _252;
    assign _235 = _209[7:7];
    assign _234 = 3'b000;
    assign _236 = { _234,
                    _235 };
    assign _232 = _209[6:6];
    assign _233 = { _234,
                    _232 };
    assign _237 = _233 + _236;
    assign _228 = _209[5:5];
    assign _229 = { _234,
                    _228 };
    assign _225 = _209[4:4];
    assign _226 = { _234,
                    _225 };
    assign _230 = _226 + _229;
    assign _238 = _230 + _237;
    assign _220 = _209[3:3];
    assign _221 = { _234,
                    _220 };
    assign _217 = _209[2:2];
    assign _218 = { _234,
                    _217 };
    assign _222 = _218 + _221;
    assign _213 = _209[1:1];
    assign _214 = { _234,
                    _213 };
    assign _207 = ~ _206;
    assign _205 = _142[7:7];
    assign _203 = ~ _202;
    assign _201 = _142[6:6];
    assign _199 = ~ _198;
    assign _197 = _142[5:5];
    assign _195 = ~ _194;
    assign _193 = _142[4:4];
    assign _191 = ~ _190;
    assign _189 = _142[3:3];
    assign _187 = ~ _186;
    assign _185 = _142[2:2];
    assign _183 = ~ _182;
    assign _181 = _142[1:1];
    assign _180 = _142[0:0];
    assign _182 = _180 ^ _181;
    assign _184 = _179 ? _183 : _182;
    assign _186 = _184 ^ _185;
    assign _188 = _179 ? _187 : _186;
    assign _190 = _188 ^ _189;
    assign _192 = _179 ? _191 : _190;
    assign _194 = _192 ^ _193;
    assign _196 = _179 ? _195 : _194;
    assign _198 = _196 ^ _197;
    assign _200 = _179 ? _199 : _198;
    assign _202 = _200 ^ _201;
    assign _204 = _179 ? _203 : _202;
    assign _206 = _204 ^ _205;
    assign _176 = _142[0:0];
    assign _177 = ~ _176;
    assign _175 = _172 == _240;
    assign _178 = _175 & _177;
    assign _168 = _142[7:7];
    assign _169 = { _234,
                    _168 };
    assign _165 = _142[6:6];
    assign _166 = { _234,
                    _165 };
    assign _170 = _166 + _169;
    assign _161 = _142[5:5];
    assign _162 = { _234,
                    _161 };
    assign _158 = _142[4:4];
    assign _159 = { _234,
                    _158 };
    assign _163 = _159 + _162;
    assign _171 = _163 + _170;
    assign _153 = _142[3:3];
    assign _154 = { _234,
                    _153 };
    assign _150 = _142[2:2];
    assign _151 = { _234,
                    _150 };
    assign _155 = _151 + _154;
    assign _146 = _142[1:1];
    assign _147 = { _234,
                    _146 };
    assign _141 = 8'b00000000;
    assign _134 = 3'b101;
    assign _135 = _125 == _134;
    assign _131 = 3'b100;
    assign _132 = _125 == _131;
    assign _128 = 3'b001;
    assign _129 = _125 == _128;
    assign _127 = _125 == _234;
    assign _130 = _127 | _129;
    assign _133 = _130 | _132;
    assign _136 = _133 | _135;
    assign _137 = _136 ? _80 : _141;
    assign _83 = _14[7:0];
    assign _66 = 10'b0101000000;
    assign _67 = _14 < _66;
    assign _82 = _67 ? _81 : _74;
    assign _65 = _11 < _66;
    assign _84 = _65 ? _83 : _82;
    assign _62 = 10'b0010100000;
    assign _63 = _11 < _62;
    assign _138 = _63 ? _137 : _84;
    assign _139 = _61 ? _80 : _138;
    always @(posedge clock) begin
        if (clear)
            _142 <= _141;
        else
            _142 <= _139;
    end
    assign _143 = _142[0:0];
    assign _144 = { _234,
                    _143 };
    assign _148 = _144 + _147;
    assign _156 = _148 + _155;
    assign _172 = _156 + _171;
    assign _173 = _240 < _172;
    assign _179 = _173 | _178;
    assign _208 = _179 ? _207 : _206;
    assign _209 = { _208,
                    _204,
                    _200,
                    _196,
                    _192,
                    _188,
                    _184,
                    _180 };
    assign _210 = _209[0:0];
    assign _211 = { _234,
                    _210 };
    assign _215 = _211 + _214;
    assign _223 = _215 + _222;
    assign _239 = _223 + _238;
    assign _248 = _240 < _239;
    assign _245 = ~ _47;
    assign _243 = _6[4:4];
    assign _244 = ~ _243;
    assign _246 = _244 & _245;
    assign _249 = _246 & _248;
    assign _254 = _249 | _253;
    assign _278 = _254 ? _277 : _270;
    assign _282 = _242 ? _281 : _278;
    assign _283 = _44 ? _282 : _46;
    always @(posedge clock) begin
        if (clear)
            _286 <= _46;
        else
            _286 <= _283;
    end
    assign _6 = _286;
    assign _47 = _6 == _46;
    assign _242 = _47 | _241;
    assign _296 = _242 ? _295 : _291;
    assign _287 = 10'b1101010100;
    assign _297 = _44 ? _296 : _287;
    always @(posedge clock) begin
        if (clear)
            _300 <= _299;
        else
            _300 <= _297;
    end
    assign _473 = ~ _390;
    assign _474 = _437 ? _390 : _473;
    assign _472 = ~ _437;
    assign _475 = { _472,
                    _437,
                    _474 };
    assign _469 = ~ _390;
    assign _470 = { vdd,
                    _437,
                    _469 };
    assign _468 = { gnd,
                    _437,
                    _390 };
    assign _471 = _435 ? _470 : _468;
    assign _422 = _420 == _240;
    assign _460 = _8 + _449;
    assign _459 = _8 - _449;
    assign _461 = _437 ? _460 : _459;
    assign _452 = { _271,
                    _437 };
    assign _453 = _452[3:0];
    assign _455 = { _453,
                    _31 };
    assign _456 = _8 + _455;
    assign _457 = _456 - _449;
    assign _444 = { gnd,
                    _420 };
    assign _445 = _444[3:0];
    assign _447 = { _445,
                    _31 };
    assign _449 = _447 - _268;
    assign _437 = ~ _360;
    assign _438 = ~ _437;
    assign _439 = { _271,
                    _438 };
    assign _440 = _439[3:0];
    assign _442 = { _440,
                    _31 };
    assign _443 = _8 - _442;
    assign _450 = _443 + _449;
    assign _433 = _420 < _240;
    assign _431 = _8[4:4];
    assign _434 = _431 & _433;
    assign _416 = _390[7:7];
    assign _417 = { _234,
                    _416 };
    assign _413 = _390[6:6];
    assign _414 = { _234,
                    _413 };
    assign _418 = _414 + _417;
    assign _409 = _390[5:5];
    assign _410 = { _234,
                    _409 };
    assign _406 = _390[4:4];
    assign _407 = { _234,
                    _406 };
    assign _411 = _407 + _410;
    assign _419 = _411 + _418;
    assign _401 = _390[3:3];
    assign _402 = { _234,
                    _401 };
    assign _398 = _390[2:2];
    assign _399 = { _234,
                    _398 };
    assign _403 = _399 + _402;
    assign _394 = _390[1:1];
    assign _395 = { _234,
                    _394 };
    assign _388 = ~ _387;
    assign _386 = _323[7:7];
    assign _384 = ~ _383;
    assign _382 = _323[6:6];
    assign _380 = ~ _379;
    assign _378 = _323[5:5];
    assign _376 = ~ _375;
    assign _374 = _323[4:4];
    assign _372 = ~ _371;
    assign _370 = _323[3:3];
    assign _368 = ~ _367;
    assign _366 = _323[2:2];
    assign _364 = ~ _363;
    assign _362 = _323[1:1];
    assign _361 = _323[0:0];
    assign _363 = _361 ^ _362;
    assign _365 = _360 ? _364 : _363;
    assign _367 = _365 ^ _366;
    assign _369 = _360 ? _368 : _367;
    assign _371 = _369 ^ _370;
    assign _373 = _360 ? _372 : _371;
    assign _375 = _373 ^ _374;
    assign _377 = _360 ? _376 : _375;
    assign _379 = _377 ^ _378;
    assign _381 = _360 ? _380 : _379;
    assign _383 = _381 ^ _382;
    assign _385 = _360 ? _384 : _383;
    assign _387 = _385 ^ _386;
    assign _357 = _323[0:0];
    assign _358 = ~ _357;
    assign _356 = _353 == _240;
    assign _359 = _356 & _358;
    assign _349 = _323[7:7];
    assign _350 = { _234,
                    _349 };
    assign _346 = _323[6:6];
    assign _347 = { _234,
                    _346 };
    assign _351 = _347 + _350;
    assign _342 = _323[5:5];
    assign _343 = { _234,
                    _342 };
    assign _339 = _323[4:4];
    assign _340 = { _234,
                    _339 };
    assign _344 = _340 + _343;
    assign _352 = _344 + _351;
    assign _334 = _323[3:3];
    assign _335 = { _234,
                    _334 };
    assign _331 = _323[2:2];
    assign _332 = { _234,
                    _331 };
    assign _336 = _332 + _335;
    assign _327 = _323[1:1];
    assign _328 = { _234,
                    _327 };
    assign _317 = _125 < _131;
    assign _318 = _317 ? _80 : _141;
    assign _314 = _11[7:0];
    assign _312 = _14 < _66;
    assign _313 = _312 ? _81 : _74;
    assign _310 = _11 < _66;
    assign _315 = _310 ? _314 : _313;
    assign _308 = _11 < _62;
    assign _319 = _308 ? _318 : _315;
    assign _320 = _61 ? _80 : _319;
    always @(posedge clock) begin
        if (clear)
            _323 <= _141;
        else
            _323 <= _320;
    end
    assign _324 = _323[0:0];
    assign _325 = { _234,
                    _324 };
    assign _329 = _325 + _328;
    assign _337 = _329 + _336;
    assign _353 = _337 + _352;
    assign _354 = _240 < _353;
    assign _360 = _354 | _359;
    assign _389 = _360 ? _388 : _387;
    assign _390 = { _389,
                    _385,
                    _381,
                    _377,
                    _373,
                    _369,
                    _365,
                    _361 };
    assign _391 = _390[0:0];
    assign _392 = { _234,
                    _391 };
    assign _396 = _392 + _395;
    assign _404 = _396 + _403;
    assign _420 = _404 + _419;
    assign _429 = _240 < _420;
    assign _426 = ~ _303;
    assign _424 = _8[4:4];
    assign _425 = ~ _424;
    assign _427 = _425 & _426;
    assign _430 = _427 & _429;
    assign _435 = _430 | _434;
    assign _458 = _435 ? _457 : _450;
    assign _462 = _423 ? _461 : _458;
    assign _463 = _44 ? _462 : _46;
    always @(posedge clock) begin
        if (clear)
            _466 <= _46;
        else
            _466 <= _463;
    end
    assign _8 = _466;
    assign _303 = _8 == _46;
    assign _423 = _303 | _422;
    assign _476 = _423 ? _475 : _471;
    assign _477 = _44 ? _476 : _287;
    always @(posedge clock) begin
        if (clear)
            _480 <= _299;
        else
            _480 <= _477;
    end
    assign _707 = ~ _580;
    assign _708 = _627 ? _580 : _707;
    assign _706 = ~ _627;
    assign _709 = { _706,
                    _627,
                    _708 };
    assign _703 = ~ _580;
    assign _704 = { vdd,
                    _627,
                    _703 };
    assign _702 = { gnd,
                    _627,
                    _580 };
    assign _705 = _625 ? _704 : _702;
    assign _612 = _610 == _240;
    assign _650 = _10 + _639;
    assign _649 = _10 - _639;
    assign _651 = _627 ? _650 : _649;
    assign _642 = { _271,
                    _627 };
    assign _643 = _642[3:0];
    assign _645 = { _643,
                    _31 };
    assign _646 = _10 + _645;
    assign _647 = _646 - _639;
    assign gnd = 1'b0;
    assign _634 = { gnd,
                    _610 };
    assign _635 = _634[3:0];
    assign _637 = { _635,
                    _31 };
    assign _639 = _637 - _268;
    assign _627 = ~ _550;
    assign _628 = ~ _627;
    assign _629 = { _271,
                    _628 };
    assign _630 = _629[3:0];
    assign _632 = { _630,
                    _31 };
    assign _633 = _10 - _632;
    assign _640 = _633 + _639;
    assign _623 = _610 < _240;
    assign _621 = _10[4:4];
    assign _624 = _621 & _623;
    assign _606 = _580[7:7];
    assign _607 = { _234,
                    _606 };
    assign _603 = _580[6:6];
    assign _604 = { _234,
                    _603 };
    assign _608 = _604 + _607;
    assign _599 = _580[5:5];
    assign _600 = { _234,
                    _599 };
    assign _596 = _580[4:4];
    assign _597 = { _234,
                    _596 };
    assign _601 = _597 + _600;
    assign _609 = _601 + _608;
    assign _591 = _580[3:3];
    assign _592 = { _234,
                    _591 };
    assign _588 = _580[2:2];
    assign _589 = { _234,
                    _588 };
    assign _593 = _589 + _592;
    assign _584 = _580[1:1];
    assign _585 = { _234,
                    _584 };
    assign _578 = ~ _577;
    assign _576 = _513[7:7];
    assign _574 = ~ _573;
    assign _572 = _513[6:6];
    assign _570 = ~ _569;
    assign _568 = _513[5:5];
    assign _566 = ~ _565;
    assign _564 = _513[4:4];
    assign _562 = ~ _561;
    assign _560 = _513[3:3];
    assign _558 = ~ _557;
    assign _556 = _513[2:2];
    assign _554 = ~ _553;
    assign _552 = _513[1:1];
    assign _551 = _513[0:0];
    assign _553 = _551 ^ _552;
    assign _555 = _550 ? _554 : _553;
    assign _557 = _555 ^ _556;
    assign _559 = _550 ? _558 : _557;
    assign _561 = _559 ^ _560;
    assign _563 = _550 ? _562 : _561;
    assign _565 = _563 ^ _564;
    assign _567 = _550 ? _566 : _565;
    assign _569 = _567 ^ _568;
    assign _571 = _550 ? _570 : _569;
    assign _573 = _571 ^ _572;
    assign _575 = _550 ? _574 : _573;
    assign _577 = _575 ^ _576;
    assign _547 = _513[0:0];
    assign _548 = ~ _547;
    assign _546 = _543 == _240;
    assign _549 = _546 & _548;
    assign _539 = _513[7:7];
    assign _540 = { _234,
                    _539 };
    assign _536 = _513[6:6];
    assign _537 = { _234,
                    _536 };
    assign _541 = _537 + _540;
    assign _532 = _513[5:5];
    assign _533 = { _234,
                    _532 };
    assign _529 = _513[4:4];
    assign _530 = { _234,
                    _529 };
    assign _534 = _530 + _533;
    assign _542 = _534 + _541;
    assign _524 = _513[3:3];
    assign _525 = { _234,
                    _524 };
    assign _521 = _513[2:2];
    assign _522 = { _234,
                    _521 };
    assign _526 = _522 + _525;
    assign _517 = _513[1:1];
    assign _518 = { _234,
                    _517 };
    assign _505 = 3'b110;
    assign _506 = _125 == _505;
    assign _503 = _125 == _131;
    assign _499 = 3'b010;
    assign _500 = _125 == _499;
    assign _121 = 10'b1000110000;
    assign _122 = _14 < _121;
    assign _123 = ~ _122;
    assign _120 = 2'b00;
    assign _124 = { _120,
                    _123 };
    assign _115 = 10'b0111100000;
    assign _116 = _14 < _115;
    assign _117 = ~ _116;
    assign _118 = { _120,
                    _117 };
    assign _109 = 10'b0110010000;
    assign _110 = _14 < _109;
    assign _111 = ~ _110;
    assign _112 = { _120,
                    _111 };
    assign _104 = _14 < _66;
    assign _105 = ~ _104;
    assign _106 = { _120,
                    _105 };
    assign _97 = 10'b0011110000;
    assign _98 = _14 < _97;
    assign _99 = ~ _98;
    assign _100 = { _120,
                    _99 };
    assign _92 = _14 < _62;
    assign _93 = ~ _92;
    assign _94 = { _120,
                   _93 };
    assign _86 = 10'b0001010000;
    assign _87 = _14 < _86;
    assign _88 = ~ _87;
    assign _89 = { _120,
                   _88 };
    assign _95 = _89 + _94;
    assign _101 = _95 + _100;
    assign _107 = _101 + _106;
    assign _113 = _107 + _112;
    assign _119 = _113 + _118;
    assign _125 = _119 + _124;
    assign _498 = _125 == _234;
    assign _501 = _498 | _500;
    assign _504 = _501 | _503;
    assign _507 = _504 | _506;
    assign _508 = _507 ? _80 : _141;
    assign _494 = _14 ^ _11;
    assign _495 = _494[7:0];
    assign _80 = 8'b11111111;
    assign _76 = _11[0:0];
    assign _75 = _14[0:0];
    assign _77 = _75 ^ _76;
    assign _78 = ~ _77;
    assign _81 = _78 ? _80 : _141;
    assign _72 = 8'b11001101;
    assign _70 = _14 - _66;
    assign _68 = 6'b000000;
    assign _71 = { _68,
                   _70 };
    assign _73 = _71 * _72;
    assign _74 = _73[15:8];
    assign _492 = _14 < _66;
    assign _493 = _492 ? _81 : _74;
    assign _490 = _11 < _66;
    assign _496 = _490 ? _495 : _493;
    assign _488 = _11 < _62;
    assign _509 = _488 ? _508 : _496;
    assign _59 = 10'b0111011111;
    assign _60 = _11 == _59;
    assign _56 = 10'b1001111111;
    assign _57 = _14 == _56;
    assign _54 = _11 == _299;
    assign _52 = _14 == _299;
    assign _55 = _52 | _54;
    assign _58 = _55 | _57;
    assign _61 = _58 | _60;
    assign _510 = _61 ? _80 : _509;
    always @(posedge clock) begin
        if (clear)
            _513 <= _141;
        else
            _513 <= _510;
    end
    assign _514 = _513[0:0];
    assign _515 = { _234,
                    _514 };
    assign _519 = _515 + _518;
    assign _527 = _519 + _526;
    assign _543 = _527 + _542;
    assign _544 = _240 < _543;
    assign _550 = _544 | _549;
    assign _579 = _550 ? _578 : _577;
    assign _580 = { _579,
                    _575,
                    _571,
                    _567,
                    _563,
                    _559,
                    _555,
                    _551 };
    assign _581 = _580[0:0];
    assign _582 = { _234,
                    _581 };
    assign _586 = _582 + _585;
    assign _594 = _586 + _593;
    assign _610 = _594 + _609;
    assign _619 = _240 < _610;
    assign _616 = ~ _483;
    assign _614 = _10[4:4];
    assign _615 = ~ _614;
    assign _617 = _615 & _616;
    assign _620 = _617 & _619;
    assign _625 = _620 | _624;
    assign _648 = _625 ? _647 : _640;
    assign _652 = _613 ? _651 : _648;
    assign _653 = _44 ? _652 : _46;
    always @(posedge clock) begin
        if (clear)
            _656 <= _46;
        else
            _656 <= _653;
    end
    assign _10 = _656;
    assign _483 = _10 == _46;
    assign _613 = _483 | _612;
    assign _710 = _613 ? _709 : _705;
    assign _700 = 10'b1010101011;
    assign _699 = 10'b0101010100;
    assign _698 = 10'b0010101011;
    assign _689 = 10'b1011110000;
    assign _690 = _14 < _689;
    assign _686 = 10'b1010010000;
    assign _687 = _14 < _686;
    assign _688 = ~ _687;
    assign _691 = _688 & _690;
    assign _692 = ~ _691;
    always @(posedge clock) begin
        if (clear)
            _695 <= _31;
        else
            _695 <= _692;
    end
    assign _679 = 10'b0111101100;
    assign _680 = _11 < _679;
    assign _676 = 10'b0111101010;
    assign _677 = _11 < _676;
    assign _678 = ~ _677;
    assign _681 = _678 & _680;
    assign _682 = ~ _681;
    always @(posedge clock) begin
        if (clear)
            _685 <= _31;
        else
            _685 <= _682;
    end
    assign _696 = { _685,
                    _695 };
    always @* begin
        case (_696)
        0:
            _701 <= _287;
        1:
            _701 <= _698;
        2:
            _701 <= _699;
        default:
            _701 <= _700;
        endcase
    end
    assign _661 = 10'b0000000001;
    assign _662 = _11 + _661;
    assign _659 = 10'b1000001100;
    assign _660 = _11 == _659;
    assign _664 = _660 ? _299 : _662;
    assign _665 = _658 ? _664 : _11;
    always @(posedge clock) begin
        if (clear)
            _668 <= _299;
        else
            _668 <= _665;
    end
    assign _11 = _668;
    assign _40 = _11 < _115;
    assign _37 = 10'b1010000000;
    assign vdd = 1'b1;
    assign _670 = _14 + _661;
    assign _657 = 10'b1100011111;
    assign _658 = _14 == _657;
    assign _672 = _658 ? _299 : _670;
    always @(posedge clock) begin
        if (clear)
            _675 <= _299;
        else
            _675 <= _672;
    end
    assign _14 = _675;
    assign _38 = _14 < _37;
    assign _41 = _38 & _40;
    always @(posedge clock) begin
        if (clear)
            _44 <= _31;
        else
            _44 <= _41;
    end
    assign _711 = _44 ? _710 : _701;
    always @(posedge clock) begin
        if (clear)
            _714 <= _299;
        else
            _714 <= _711;
    end
    assign word_b = _714;
    assign word_g = _480;
    assign word_r = _300;
    assign toggle = _4;
    assign led_1hz = _2;

endmodule
