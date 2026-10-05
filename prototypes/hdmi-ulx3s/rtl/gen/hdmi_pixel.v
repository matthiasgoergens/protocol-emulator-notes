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

    wire _30;
    wire [23:0] _15;
    wire [23:0] _26;
    wire [23:0] _21;
    wire [23:0] _22;
    wire [23:0] _24;
    reg [23:0] _27;
    wire [23:0] _1;
    wire _16;
    reg _20;
    wire _28;
    reg _31;
    wire _2;
    wire _32;
    reg _35;
    wire _4;
    wire [9:0] _303;
    wire [7:0] _297;
    wire [7:0] _298;
    wire _296;
    wire [9:0] _299;
    wire [7:0] _293;
    wire [9:0] _294;
    wire [9:0] _292;
    wire [9:0] _295;
    wire [3:0] _244;
    wire _245;
    wire [4:0] _50;
    wire [4:0] _284;
    wire [4:0] _283;
    wire [4:0] _285;
    wire [3:0] _275;
    wire [4:0] _276;
    wire [3:0] _277;
    wire [4:0] _279;
    wire [4:0] _280;
    wire [4:0] _281;
    wire [4:0] _272;
    wire [4:0] _268;
    wire [3:0] _269;
    wire [4:0] _271;
    wire [4:0] _273;
    wire _260;
    wire _261;
    wire [4:0] _262;
    wire [3:0] _263;
    wire [4:0] _265;
    wire [4:0] _266;
    wire [4:0] _274;
    wire _256;
    wire _254;
    wire _257;
    wire _239;
    wire [2:0] _238;
    wire [3:0] _240;
    wire _236;
    wire [3:0] _237;
    wire [3:0] _241;
    wire _232;
    wire [3:0] _233;
    wire _229;
    wire [3:0] _230;
    wire [3:0] _234;
    wire [3:0] _242;
    wire _224;
    wire [3:0] _225;
    wire _221;
    wire [3:0] _222;
    wire [3:0] _226;
    wire _217;
    wire [3:0] _218;
    wire _211;
    wire _209;
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
    wire _208;
    wire _210;
    wire _180;
    wire _181;
    wire _179;
    wire _182;
    wire _172;
    wire [3:0] _173;
    wire _169;
    wire [3:0] _170;
    wire [3:0] _174;
    wire _165;
    wire [3:0] _166;
    wire _162;
    wire [3:0] _163;
    wire [3:0] _167;
    wire [3:0] _175;
    wire _157;
    wire [3:0] _158;
    wire _154;
    wire [3:0] _155;
    wire [3:0] _159;
    wire _150;
    wire [3:0] _151;
    wire [7:0] _145;
    wire [2:0] _138;
    wire _139;
    wire [2:0] _135;
    wire _136;
    wire [2:0] _132;
    wire _133;
    wire _131;
    wire _134;
    wire _137;
    wire _140;
    wire [7:0] _141;
    wire [7:0] _87;
    wire [9:0] _70;
    wire _71;
    wire [7:0] _86;
    wire _69;
    wire [7:0] _88;
    wire [9:0] _66;
    wire _67;
    wire [7:0] _142;
    wire [7:0] _143;
    reg [7:0] _146;
    wire _147;
    wire [3:0] _148;
    wire [3:0] _152;
    wire [3:0] _160;
    wire [3:0] _176;
    wire _177;
    wire _183;
    wire _212;
    wire [7:0] _213;
    wire _214;
    wire [3:0] _215;
    wire [3:0] _219;
    wire [3:0] _227;
    wire [3:0] _243;
    wire _252;
    wire _249;
    wire _247;
    wire _248;
    wire _250;
    wire _253;
    wire _258;
    wire [4:0] _282;
    wire [4:0] _286;
    wire [4:0] _287;
    reg [4:0] _290;
    wire [4:0] _6;
    wire _51;
    wire _246;
    wire [9:0] _300;
    wire [9:0] _291;
    wire [9:0] _301;
    reg [9:0] _304;
    wire [7:0] _477;
    wire [7:0] _478;
    wire _476;
    wire [9:0] _479;
    wire [7:0] _473;
    wire [9:0] _474;
    wire [9:0] _472;
    wire [9:0] _475;
    wire _426;
    wire [4:0] _464;
    wire [4:0] _463;
    wire [4:0] _465;
    wire [4:0] _456;
    wire [3:0] _457;
    wire [4:0] _459;
    wire [4:0] _460;
    wire [4:0] _461;
    wire [4:0] _448;
    wire [3:0] _449;
    wire [4:0] _451;
    wire [4:0] _453;
    wire _441;
    wire _442;
    wire [4:0] _443;
    wire [3:0] _444;
    wire [4:0] _446;
    wire [4:0] _447;
    wire [4:0] _454;
    wire _437;
    wire _435;
    wire _438;
    wire _420;
    wire [3:0] _421;
    wire _417;
    wire [3:0] _418;
    wire [3:0] _422;
    wire _413;
    wire [3:0] _414;
    wire _410;
    wire [3:0] _411;
    wire [3:0] _415;
    wire [3:0] _423;
    wire _405;
    wire [3:0] _406;
    wire _402;
    wire [3:0] _403;
    wire [3:0] _407;
    wire _398;
    wire [3:0] _399;
    wire _392;
    wire _390;
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
    wire _389;
    wire _391;
    wire _361;
    wire _362;
    wire _360;
    wire _363;
    wire _353;
    wire [3:0] _354;
    wire _350;
    wire [3:0] _351;
    wire [3:0] _355;
    wire _346;
    wire [3:0] _347;
    wire _343;
    wire [3:0] _344;
    wire [3:0] _348;
    wire [3:0] _356;
    wire _338;
    wire [3:0] _339;
    wire _335;
    wire [3:0] _336;
    wire [3:0] _340;
    wire _331;
    wire [3:0] _332;
    wire _321;
    wire [7:0] _322;
    wire [7:0] _318;
    wire _316;
    wire [7:0] _317;
    wire _314;
    wire [7:0] _319;
    wire _312;
    wire [7:0] _323;
    wire [7:0] _324;
    reg [7:0] _327;
    wire _328;
    wire [3:0] _329;
    wire [3:0] _333;
    wire [3:0] _341;
    wire [3:0] _357;
    wire _358;
    wire _364;
    wire _393;
    wire [7:0] _394;
    wire _395;
    wire [3:0] _396;
    wire [3:0] _400;
    wire [3:0] _408;
    wire [3:0] _424;
    wire _433;
    wire _430;
    wire _428;
    wire _429;
    wire _431;
    wire _434;
    wire _439;
    wire [4:0] _462;
    wire [4:0] _466;
    wire [4:0] _467;
    reg [4:0] _470;
    wire [4:0] _8;
    wire _307;
    wire _427;
    wire [9:0] _480;
    wire [9:0] _481;
    reg [9:0] _484;
    wire [7:0] _708;
    wire [7:0] _709;
    wire _707;
    wire [9:0] _710;
    wire [7:0] _704;
    wire [9:0] _705;
    wire [9:0] _703;
    wire [9:0] _706;
    wire _616;
    wire [4:0] _654;
    wire [4:0] _653;
    wire [4:0] _655;
    wire [4:0] _646;
    wire [3:0] _647;
    wire [4:0] _649;
    wire [4:0] _650;
    wire [4:0] _651;
    wire gnd;
    wire [4:0] _638;
    wire [3:0] _639;
    wire [4:0] _641;
    wire [4:0] _643;
    wire _631;
    wire _632;
    wire [4:0] _633;
    wire [3:0] _634;
    wire [4:0] _636;
    wire [4:0] _637;
    wire [4:0] _644;
    wire _627;
    wire _625;
    wire _628;
    wire _610;
    wire [3:0] _611;
    wire _607;
    wire [3:0] _608;
    wire [3:0] _612;
    wire _603;
    wire [3:0] _604;
    wire _600;
    wire [3:0] _601;
    wire [3:0] _605;
    wire [3:0] _613;
    wire _595;
    wire [3:0] _596;
    wire _592;
    wire [3:0] _593;
    wire [3:0] _597;
    wire _588;
    wire [3:0] _589;
    wire _582;
    wire _580;
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
    wire _579;
    wire _581;
    wire _551;
    wire _552;
    wire _550;
    wire _553;
    wire _543;
    wire [3:0] _544;
    wire _540;
    wire [3:0] _541;
    wire [3:0] _545;
    wire _536;
    wire [3:0] _537;
    wire _533;
    wire [3:0] _534;
    wire [3:0] _538;
    wire [3:0] _546;
    wire _528;
    wire [3:0] _529;
    wire _525;
    wire [3:0] _526;
    wire [3:0] _530;
    wire _521;
    wire [3:0] _522;
    wire [2:0] _509;
    wire _510;
    wire _507;
    wire [2:0] _503;
    wire _504;
    wire [9:0] _125;
    wire _126;
    wire _127;
    wire [1:0] _124;
    wire [2:0] _128;
    wire [9:0] _119;
    wire _120;
    wire _121;
    wire [2:0] _122;
    wire [9:0] _113;
    wire _114;
    wire _115;
    wire [2:0] _116;
    wire _108;
    wire _109;
    wire [2:0] _110;
    wire [9:0] _101;
    wire _102;
    wire _103;
    wire [2:0] _104;
    wire _96;
    wire _97;
    wire [2:0] _98;
    wire [9:0] _90;
    wire _91;
    wire _92;
    wire [2:0] _93;
    wire [2:0] _99;
    wire [2:0] _105;
    wire [2:0] _111;
    wire [2:0] _117;
    wire [2:0] _123;
    wire [2:0] _129;
    wire _502;
    wire _505;
    wire _508;
    wire _511;
    wire [7:0] _512;
    wire [9:0] _498;
    wire [7:0] _499;
    wire [7:0] _84;
    wire _80;
    wire _79;
    wire _81;
    wire _82;
    wire [7:0] _85;
    wire [7:0] _76;
    wire [9:0] _74;
    wire [5:0] _72;
    wire [15:0] _75;
    wire [23:0] _77;
    wire [7:0] _78;
    wire _496;
    wire [7:0] _497;
    wire _494;
    wire [7:0] _500;
    wire _492;
    wire [7:0] _513;
    wire [9:0] _63;
    wire _64;
    wire [9:0] _60;
    wire _61;
    wire _58;
    wire _56;
    wire _59;
    wire _62;
    wire _65;
    wire [7:0] _514;
    reg [7:0] _517;
    wire _518;
    wire [3:0] _519;
    wire [3:0] _523;
    wire [3:0] _531;
    wire [3:0] _547;
    wire _548;
    wire _554;
    wire _583;
    wire [7:0] _584;
    wire _585;
    wire [3:0] _586;
    wire [3:0] _590;
    wire [3:0] _598;
    wire [3:0] _614;
    wire _623;
    wire _620;
    wire _618;
    wire _619;
    wire _621;
    wire _624;
    wire _629;
    wire [4:0] _652;
    wire [4:0] _656;
    wire [4:0] _657;
    reg [4:0] _660;
    wire [4:0] _10;
    wire _487;
    wire _617;
    wire [9:0] _711;
    wire [9:0] _701;
    wire [9:0] _700;
    wire [9:0] _699;
    wire [9:0] _690;
    wire _691;
    wire [9:0] _687;
    wire _688;
    wire _689;
    wire _692;
    wire _693;
    reg _696;
    wire [9:0] _680;
    wire _681;
    wire [9:0] _677;
    wire _678;
    wire _679;
    wire _682;
    wire _683;
    reg _686;
    wire [1:0] _697;
    reg [9:0] _702;
    wire [9:0] _42;
    wire _44;
    wire [9:0] _40;
    wire vdd;
    wire [19:0] _37;
    wire [9:0] _672;
    wire [9:0] _673;
    wire [9:0] _675;
    wire [9:0] _668;
    wire [9:0] _665;
    wire _666;
    wire [9:0] _670;
    wire [9:0] _664;
    wire [9:0] _662;
    wire [9:0] _661;
    wire _663;
    wire [9:0] _671;
    wire [19:0] _676;
    wire [19:0] _13;
    reg [19:0] _38;
    wire [9:0] _39;
    wire _41;
    wire _45;
    reg _48;
    wire [9:0] _712;
    reg [9:0] _715;
    assign _30 = 1'b0;
    assign _15 = 24'b101111101011110000011110;
    assign _26 = 24'b000000000000000000000000;
    assign _21 = 24'b000000000000000000000001;
    assign _22 = _1 + _21;
    assign _24 = _20 ? _26 : _22;
    always @(posedge clock) begin
        if (clear)
            _27 <= _26;
        else
            _27 <= _24;
    end
    assign _1 = _27;
    assign _16 = _1 == _15;
    always @(posedge clock) begin
        if (clear)
            _20 <= _30;
        else
            _20 <= _16;
    end
    assign _28 = _2 ^ _20;
    always @(posedge clock) begin
        if (clear)
            _31 <= _30;
        else
            _31 <= _28;
    end
    assign _2 = _31;
    assign _32 = ~ _4;
    always @(posedge clock) begin
        if (clear)
            _35 <= _30;
        else
            _35 <= _32;
    end
    assign _4 = _35;
    assign _303 = 10'b0000000000;
    assign _297 = ~ _213;
    assign _298 = _260 ? _213 : _297;
    assign _296 = ~ _260;
    assign _299 = { _296,
                    _260,
                    _298 };
    assign _293 = ~ _213;
    assign _294 = { vdd,
                    _260,
                    _293 };
    assign _292 = { gnd,
                    _260,
                    _213 };
    assign _295 = _258 ? _294 : _292;
    assign _244 = 4'b0100;
    assign _245 = _243 == _244;
    assign _50 = 5'b00000;
    assign _284 = _6 + _273;
    assign _283 = _6 - _273;
    assign _285 = _260 ? _284 : _283;
    assign _275 = 4'b0000;
    assign _276 = { _275,
                    _260 };
    assign _277 = _276[3:0];
    assign _279 = { _277,
                    _30 };
    assign _280 = _6 + _279;
    assign _281 = _280 - _273;
    assign _272 = 5'b01000;
    assign _268 = { gnd,
                    _243 };
    assign _269 = _268[3:0];
    assign _271 = { _269,
                    _30 };
    assign _273 = _271 - _272;
    assign _260 = ~ _183;
    assign _261 = ~ _260;
    assign _262 = { _275,
                    _261 };
    assign _263 = _262[3:0];
    assign _265 = { _263,
                    _30 };
    assign _266 = _6 - _265;
    assign _274 = _266 + _273;
    assign _256 = _243 < _244;
    assign _254 = _6[4:4];
    assign _257 = _254 & _256;
    assign _239 = _213[7:7];
    assign _238 = 3'b000;
    assign _240 = { _238,
                    _239 };
    assign _236 = _213[6:6];
    assign _237 = { _238,
                    _236 };
    assign _241 = _237 + _240;
    assign _232 = _213[5:5];
    assign _233 = { _238,
                    _232 };
    assign _229 = _213[4:4];
    assign _230 = { _238,
                    _229 };
    assign _234 = _230 + _233;
    assign _242 = _234 + _241;
    assign _224 = _213[3:3];
    assign _225 = { _238,
                    _224 };
    assign _221 = _213[2:2];
    assign _222 = { _238,
                    _221 };
    assign _226 = _222 + _225;
    assign _217 = _213[1:1];
    assign _218 = { _238,
                    _217 };
    assign _211 = ~ _210;
    assign _209 = _146[7:7];
    assign _207 = ~ _206;
    assign _205 = _146[6:6];
    assign _203 = ~ _202;
    assign _201 = _146[5:5];
    assign _199 = ~ _198;
    assign _197 = _146[4:4];
    assign _195 = ~ _194;
    assign _193 = _146[3:3];
    assign _191 = ~ _190;
    assign _189 = _146[2:2];
    assign _187 = ~ _186;
    assign _185 = _146[1:1];
    assign _184 = _146[0:0];
    assign _186 = _184 ^ _185;
    assign _188 = _183 ? _187 : _186;
    assign _190 = _188 ^ _189;
    assign _192 = _183 ? _191 : _190;
    assign _194 = _192 ^ _193;
    assign _196 = _183 ? _195 : _194;
    assign _198 = _196 ^ _197;
    assign _200 = _183 ? _199 : _198;
    assign _202 = _200 ^ _201;
    assign _204 = _183 ? _203 : _202;
    assign _206 = _204 ^ _205;
    assign _208 = _183 ? _207 : _206;
    assign _210 = _208 ^ _209;
    assign _180 = _146[0:0];
    assign _181 = ~ _180;
    assign _179 = _176 == _244;
    assign _182 = _179 & _181;
    assign _172 = _146[7:7];
    assign _173 = { _238,
                    _172 };
    assign _169 = _146[6:6];
    assign _170 = { _238,
                    _169 };
    assign _174 = _170 + _173;
    assign _165 = _146[5:5];
    assign _166 = { _238,
                    _165 };
    assign _162 = _146[4:4];
    assign _163 = { _238,
                    _162 };
    assign _167 = _163 + _166;
    assign _175 = _167 + _174;
    assign _157 = _146[3:3];
    assign _158 = { _238,
                    _157 };
    assign _154 = _146[2:2];
    assign _155 = { _238,
                    _154 };
    assign _159 = _155 + _158;
    assign _150 = _146[1:1];
    assign _151 = { _238,
                    _150 };
    assign _145 = 8'b00000000;
    assign _138 = 3'b101;
    assign _139 = _129 == _138;
    assign _135 = 3'b100;
    assign _136 = _129 == _135;
    assign _132 = 3'b001;
    assign _133 = _129 == _132;
    assign _131 = _129 == _238;
    assign _134 = _131 | _133;
    assign _137 = _134 | _136;
    assign _140 = _137 | _139;
    assign _141 = _140 ? _84 : _145;
    assign _87 = _39[7:0];
    assign _70 = 10'b0101000000;
    assign _71 = _39 < _70;
    assign _86 = _71 ? _85 : _78;
    assign _69 = _42 < _70;
    assign _88 = _69 ? _87 : _86;
    assign _66 = 10'b0010100000;
    assign _67 = _42 < _66;
    assign _142 = _67 ? _141 : _88;
    assign _143 = _65 ? _84 : _142;
    always @(posedge clock) begin
        if (clear)
            _146 <= _145;
        else
            _146 <= _143;
    end
    assign _147 = _146[0:0];
    assign _148 = { _238,
                    _147 };
    assign _152 = _148 + _151;
    assign _160 = _152 + _159;
    assign _176 = _160 + _175;
    assign _177 = _244 < _176;
    assign _183 = _177 | _182;
    assign _212 = _183 ? _211 : _210;
    assign _213 = { _212,
                    _208,
                    _204,
                    _200,
                    _196,
                    _192,
                    _188,
                    _184 };
    assign _214 = _213[0:0];
    assign _215 = { _238,
                    _214 };
    assign _219 = _215 + _218;
    assign _227 = _219 + _226;
    assign _243 = _227 + _242;
    assign _252 = _244 < _243;
    assign _249 = ~ _51;
    assign _247 = _6[4:4];
    assign _248 = ~ _247;
    assign _250 = _248 & _249;
    assign _253 = _250 & _252;
    assign _258 = _253 | _257;
    assign _282 = _258 ? _281 : _274;
    assign _286 = _246 ? _285 : _282;
    assign _287 = _48 ? _286 : _50;
    always @(posedge clock) begin
        if (clear)
            _290 <= _50;
        else
            _290 <= _287;
    end
    assign _6 = _290;
    assign _51 = _6 == _50;
    assign _246 = _51 | _245;
    assign _300 = _246 ? _299 : _295;
    assign _291 = 10'b1101010100;
    assign _301 = _48 ? _300 : _291;
    always @(posedge clock) begin
        if (clear)
            _304 <= _303;
        else
            _304 <= _301;
    end
    assign _477 = ~ _394;
    assign _478 = _441 ? _394 : _477;
    assign _476 = ~ _441;
    assign _479 = { _476,
                    _441,
                    _478 };
    assign _473 = ~ _394;
    assign _474 = { vdd,
                    _441,
                    _473 };
    assign _472 = { gnd,
                    _441,
                    _394 };
    assign _475 = _439 ? _474 : _472;
    assign _426 = _424 == _244;
    assign _464 = _8 + _453;
    assign _463 = _8 - _453;
    assign _465 = _441 ? _464 : _463;
    assign _456 = { _275,
                    _441 };
    assign _457 = _456[3:0];
    assign _459 = { _457,
                    _30 };
    assign _460 = _8 + _459;
    assign _461 = _460 - _453;
    assign _448 = { gnd,
                    _424 };
    assign _449 = _448[3:0];
    assign _451 = { _449,
                    _30 };
    assign _453 = _451 - _272;
    assign _441 = ~ _364;
    assign _442 = ~ _441;
    assign _443 = { _275,
                    _442 };
    assign _444 = _443[3:0];
    assign _446 = { _444,
                    _30 };
    assign _447 = _8 - _446;
    assign _454 = _447 + _453;
    assign _437 = _424 < _244;
    assign _435 = _8[4:4];
    assign _438 = _435 & _437;
    assign _420 = _394[7:7];
    assign _421 = { _238,
                    _420 };
    assign _417 = _394[6:6];
    assign _418 = { _238,
                    _417 };
    assign _422 = _418 + _421;
    assign _413 = _394[5:5];
    assign _414 = { _238,
                    _413 };
    assign _410 = _394[4:4];
    assign _411 = { _238,
                    _410 };
    assign _415 = _411 + _414;
    assign _423 = _415 + _422;
    assign _405 = _394[3:3];
    assign _406 = { _238,
                    _405 };
    assign _402 = _394[2:2];
    assign _403 = { _238,
                    _402 };
    assign _407 = _403 + _406;
    assign _398 = _394[1:1];
    assign _399 = { _238,
                    _398 };
    assign _392 = ~ _391;
    assign _390 = _327[7:7];
    assign _388 = ~ _387;
    assign _386 = _327[6:6];
    assign _384 = ~ _383;
    assign _382 = _327[5:5];
    assign _380 = ~ _379;
    assign _378 = _327[4:4];
    assign _376 = ~ _375;
    assign _374 = _327[3:3];
    assign _372 = ~ _371;
    assign _370 = _327[2:2];
    assign _368 = ~ _367;
    assign _366 = _327[1:1];
    assign _365 = _327[0:0];
    assign _367 = _365 ^ _366;
    assign _369 = _364 ? _368 : _367;
    assign _371 = _369 ^ _370;
    assign _373 = _364 ? _372 : _371;
    assign _375 = _373 ^ _374;
    assign _377 = _364 ? _376 : _375;
    assign _379 = _377 ^ _378;
    assign _381 = _364 ? _380 : _379;
    assign _383 = _381 ^ _382;
    assign _385 = _364 ? _384 : _383;
    assign _387 = _385 ^ _386;
    assign _389 = _364 ? _388 : _387;
    assign _391 = _389 ^ _390;
    assign _361 = _327[0:0];
    assign _362 = ~ _361;
    assign _360 = _357 == _244;
    assign _363 = _360 & _362;
    assign _353 = _327[7:7];
    assign _354 = { _238,
                    _353 };
    assign _350 = _327[6:6];
    assign _351 = { _238,
                    _350 };
    assign _355 = _351 + _354;
    assign _346 = _327[5:5];
    assign _347 = { _238,
                    _346 };
    assign _343 = _327[4:4];
    assign _344 = { _238,
                    _343 };
    assign _348 = _344 + _347;
    assign _356 = _348 + _355;
    assign _338 = _327[3:3];
    assign _339 = { _238,
                    _338 };
    assign _335 = _327[2:2];
    assign _336 = { _238,
                    _335 };
    assign _340 = _336 + _339;
    assign _331 = _327[1:1];
    assign _332 = { _238,
                    _331 };
    assign _321 = _129 < _135;
    assign _322 = _321 ? _84 : _145;
    assign _318 = _42[7:0];
    assign _316 = _39 < _70;
    assign _317 = _316 ? _85 : _78;
    assign _314 = _42 < _70;
    assign _319 = _314 ? _318 : _317;
    assign _312 = _42 < _66;
    assign _323 = _312 ? _322 : _319;
    assign _324 = _65 ? _84 : _323;
    always @(posedge clock) begin
        if (clear)
            _327 <= _145;
        else
            _327 <= _324;
    end
    assign _328 = _327[0:0];
    assign _329 = { _238,
                    _328 };
    assign _333 = _329 + _332;
    assign _341 = _333 + _340;
    assign _357 = _341 + _356;
    assign _358 = _244 < _357;
    assign _364 = _358 | _363;
    assign _393 = _364 ? _392 : _391;
    assign _394 = { _393,
                    _389,
                    _385,
                    _381,
                    _377,
                    _373,
                    _369,
                    _365 };
    assign _395 = _394[0:0];
    assign _396 = { _238,
                    _395 };
    assign _400 = _396 + _399;
    assign _408 = _400 + _407;
    assign _424 = _408 + _423;
    assign _433 = _244 < _424;
    assign _430 = ~ _307;
    assign _428 = _8[4:4];
    assign _429 = ~ _428;
    assign _431 = _429 & _430;
    assign _434 = _431 & _433;
    assign _439 = _434 | _438;
    assign _462 = _439 ? _461 : _454;
    assign _466 = _427 ? _465 : _462;
    assign _467 = _48 ? _466 : _50;
    always @(posedge clock) begin
        if (clear)
            _470 <= _50;
        else
            _470 <= _467;
    end
    assign _8 = _470;
    assign _307 = _8 == _50;
    assign _427 = _307 | _426;
    assign _480 = _427 ? _479 : _475;
    assign _481 = _48 ? _480 : _291;
    always @(posedge clock) begin
        if (clear)
            _484 <= _303;
        else
            _484 <= _481;
    end
    assign _708 = ~ _584;
    assign _709 = _631 ? _584 : _708;
    assign _707 = ~ _631;
    assign _710 = { _707,
                    _631,
                    _709 };
    assign _704 = ~ _584;
    assign _705 = { vdd,
                    _631,
                    _704 };
    assign _703 = { gnd,
                    _631,
                    _584 };
    assign _706 = _629 ? _705 : _703;
    assign _616 = _614 == _244;
    assign _654 = _10 + _643;
    assign _653 = _10 - _643;
    assign _655 = _631 ? _654 : _653;
    assign _646 = { _275,
                    _631 };
    assign _647 = _646[3:0];
    assign _649 = { _647,
                    _30 };
    assign _650 = _10 + _649;
    assign _651 = _650 - _643;
    assign gnd = 1'b0;
    assign _638 = { gnd,
                    _614 };
    assign _639 = _638[3:0];
    assign _641 = { _639,
                    _30 };
    assign _643 = _641 - _272;
    assign _631 = ~ _554;
    assign _632 = ~ _631;
    assign _633 = { _275,
                    _632 };
    assign _634 = _633[3:0];
    assign _636 = { _634,
                    _30 };
    assign _637 = _10 - _636;
    assign _644 = _637 + _643;
    assign _627 = _614 < _244;
    assign _625 = _10[4:4];
    assign _628 = _625 & _627;
    assign _610 = _584[7:7];
    assign _611 = { _238,
                    _610 };
    assign _607 = _584[6:6];
    assign _608 = { _238,
                    _607 };
    assign _612 = _608 + _611;
    assign _603 = _584[5:5];
    assign _604 = { _238,
                    _603 };
    assign _600 = _584[4:4];
    assign _601 = { _238,
                    _600 };
    assign _605 = _601 + _604;
    assign _613 = _605 + _612;
    assign _595 = _584[3:3];
    assign _596 = { _238,
                    _595 };
    assign _592 = _584[2:2];
    assign _593 = { _238,
                    _592 };
    assign _597 = _593 + _596;
    assign _588 = _584[1:1];
    assign _589 = { _238,
                    _588 };
    assign _582 = ~ _581;
    assign _580 = _517[7:7];
    assign _578 = ~ _577;
    assign _576 = _517[6:6];
    assign _574 = ~ _573;
    assign _572 = _517[5:5];
    assign _570 = ~ _569;
    assign _568 = _517[4:4];
    assign _566 = ~ _565;
    assign _564 = _517[3:3];
    assign _562 = ~ _561;
    assign _560 = _517[2:2];
    assign _558 = ~ _557;
    assign _556 = _517[1:1];
    assign _555 = _517[0:0];
    assign _557 = _555 ^ _556;
    assign _559 = _554 ? _558 : _557;
    assign _561 = _559 ^ _560;
    assign _563 = _554 ? _562 : _561;
    assign _565 = _563 ^ _564;
    assign _567 = _554 ? _566 : _565;
    assign _569 = _567 ^ _568;
    assign _571 = _554 ? _570 : _569;
    assign _573 = _571 ^ _572;
    assign _575 = _554 ? _574 : _573;
    assign _577 = _575 ^ _576;
    assign _579 = _554 ? _578 : _577;
    assign _581 = _579 ^ _580;
    assign _551 = _517[0:0];
    assign _552 = ~ _551;
    assign _550 = _547 == _244;
    assign _553 = _550 & _552;
    assign _543 = _517[7:7];
    assign _544 = { _238,
                    _543 };
    assign _540 = _517[6:6];
    assign _541 = { _238,
                    _540 };
    assign _545 = _541 + _544;
    assign _536 = _517[5:5];
    assign _537 = { _238,
                    _536 };
    assign _533 = _517[4:4];
    assign _534 = { _238,
                    _533 };
    assign _538 = _534 + _537;
    assign _546 = _538 + _545;
    assign _528 = _517[3:3];
    assign _529 = { _238,
                    _528 };
    assign _525 = _517[2:2];
    assign _526 = { _238,
                    _525 };
    assign _530 = _526 + _529;
    assign _521 = _517[1:1];
    assign _522 = { _238,
                    _521 };
    assign _509 = 3'b110;
    assign _510 = _129 == _509;
    assign _507 = _129 == _135;
    assign _503 = 3'b010;
    assign _504 = _129 == _503;
    assign _125 = 10'b1000110000;
    assign _126 = _39 < _125;
    assign _127 = ~ _126;
    assign _124 = 2'b00;
    assign _128 = { _124,
                    _127 };
    assign _119 = 10'b0111100000;
    assign _120 = _39 < _119;
    assign _121 = ~ _120;
    assign _122 = { _124,
                    _121 };
    assign _113 = 10'b0110010000;
    assign _114 = _39 < _113;
    assign _115 = ~ _114;
    assign _116 = { _124,
                    _115 };
    assign _108 = _39 < _70;
    assign _109 = ~ _108;
    assign _110 = { _124,
                    _109 };
    assign _101 = 10'b0011110000;
    assign _102 = _39 < _101;
    assign _103 = ~ _102;
    assign _104 = { _124,
                    _103 };
    assign _96 = _39 < _66;
    assign _97 = ~ _96;
    assign _98 = { _124,
                   _97 };
    assign _90 = 10'b0001010000;
    assign _91 = _39 < _90;
    assign _92 = ~ _91;
    assign _93 = { _124,
                   _92 };
    assign _99 = _93 + _98;
    assign _105 = _99 + _104;
    assign _111 = _105 + _110;
    assign _117 = _111 + _116;
    assign _123 = _117 + _122;
    assign _129 = _123 + _128;
    assign _502 = _129 == _238;
    assign _505 = _502 | _504;
    assign _508 = _505 | _507;
    assign _511 = _508 | _510;
    assign _512 = _511 ? _84 : _145;
    assign _498 = _39 ^ _42;
    assign _499 = _498[7:0];
    assign _84 = 8'b11111111;
    assign _80 = _42[0:0];
    assign _79 = _39[0:0];
    assign _81 = _79 ^ _80;
    assign _82 = ~ _81;
    assign _85 = _82 ? _84 : _145;
    assign _76 = 8'b11001101;
    assign _74 = _39 - _70;
    assign _72 = 6'b000000;
    assign _75 = { _72,
                   _74 };
    assign _77 = _75 * _76;
    assign _78 = _77[15:8];
    assign _496 = _39 < _70;
    assign _497 = _496 ? _85 : _78;
    assign _494 = _42 < _70;
    assign _500 = _494 ? _499 : _497;
    assign _492 = _42 < _66;
    assign _513 = _492 ? _512 : _500;
    assign _63 = 10'b0111011111;
    assign _64 = _42 == _63;
    assign _60 = 10'b1001111111;
    assign _61 = _39 == _60;
    assign _58 = _42 == _303;
    assign _56 = _39 == _303;
    assign _59 = _56 | _58;
    assign _62 = _59 | _61;
    assign _65 = _62 | _64;
    assign _514 = _65 ? _84 : _513;
    always @(posedge clock) begin
        if (clear)
            _517 <= _145;
        else
            _517 <= _514;
    end
    assign _518 = _517[0:0];
    assign _519 = { _238,
                    _518 };
    assign _523 = _519 + _522;
    assign _531 = _523 + _530;
    assign _547 = _531 + _546;
    assign _548 = _244 < _547;
    assign _554 = _548 | _553;
    assign _583 = _554 ? _582 : _581;
    assign _584 = { _583,
                    _579,
                    _575,
                    _571,
                    _567,
                    _563,
                    _559,
                    _555 };
    assign _585 = _584[0:0];
    assign _586 = { _238,
                    _585 };
    assign _590 = _586 + _589;
    assign _598 = _590 + _597;
    assign _614 = _598 + _613;
    assign _623 = _244 < _614;
    assign _620 = ~ _487;
    assign _618 = _10[4:4];
    assign _619 = ~ _618;
    assign _621 = _619 & _620;
    assign _624 = _621 & _623;
    assign _629 = _624 | _628;
    assign _652 = _629 ? _651 : _644;
    assign _656 = _617 ? _655 : _652;
    assign _657 = _48 ? _656 : _50;
    always @(posedge clock) begin
        if (clear)
            _660 <= _50;
        else
            _660 <= _657;
    end
    assign _10 = _660;
    assign _487 = _10 == _50;
    assign _617 = _487 | _616;
    assign _711 = _617 ? _710 : _706;
    assign _701 = 10'b1010101011;
    assign _700 = 10'b0101010100;
    assign _699 = 10'b0010101011;
    assign _690 = 10'b1011110000;
    assign _691 = _39 < _690;
    assign _687 = 10'b1010010000;
    assign _688 = _39 < _687;
    assign _689 = ~ _688;
    assign _692 = _689 & _691;
    assign _693 = ~ _692;
    always @(posedge clock) begin
        if (clear)
            _696 <= _30;
        else
            _696 <= _693;
    end
    assign _680 = 10'b0111101100;
    assign _681 = _42 < _680;
    assign _677 = 10'b0111101010;
    assign _678 = _42 < _677;
    assign _679 = ~ _678;
    assign _682 = _679 & _681;
    assign _683 = ~ _682;
    always @(posedge clock) begin
        if (clear)
            _686 <= _30;
        else
            _686 <= _683;
    end
    assign _697 = { _686,
                    _696 };
    always @* begin
        case (_697)
        0:
            _702 <= _291;
        1:
            _702 <= _699;
        2:
            _702 <= _700;
        default:
            _702 <= _701;
        endcase
    end
    assign _42 = _38[19:10];
    assign _44 = _42 < _119;
    assign _40 = 10'b1010000000;
    assign vdd = 1'b1;
    assign _37 = 20'b00000000000000000000;
    assign _672 = 10'b0000000001;
    assign _673 = _661 + _672;
    assign _675 = _663 ? _303 : _673;
    assign _668 = _664 + _672;
    assign _665 = 10'b1000001100;
    assign _666 = _664 == _665;
    assign _670 = _666 ? _303 : _668;
    assign _664 = _38[19:10];
    assign _662 = 10'b1100011111;
    assign _661 = _38[9:0];
    assign _663 = _661 == _662;
    assign _671 = _663 ? _670 : _664;
    assign _676 = { _671,
                    _675 };
    assign _13 = _676;
    always @(posedge clock) begin
        if (clear)
            _38 <= _37;
        else
            _38 <= _13;
    end
    assign _39 = _38[9:0];
    assign _41 = _39 < _40;
    assign _45 = _41 & _44;
    always @(posedge clock) begin
        if (clear)
            _48 <= _30;
        else
            _48 <= _45;
    end
    assign _712 = _48 ? _711 : _702;
    always @(posedge clock) begin
        if (clear)
            _715 <= _303;
        else
            _715 <= _712;
    end
    assign word_b = _715;
    assign word_g = _484;
    assign word_r = _304;
    assign toggle = _4;
    assign led_1hz = _2;

endmodule
