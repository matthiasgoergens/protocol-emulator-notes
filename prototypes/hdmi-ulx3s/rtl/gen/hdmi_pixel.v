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

    wire _28;
    wire [23:0] _16;
    wire [23:0] _23;
    wire [23:0] _18;
    wire [23:0] _19;
    wire [23:0] _21;
    reg [23:0] _25;
    wire [23:0] _1;
    wire _17;
    wire _26;
    reg _29;
    wire _2;
    wire _30;
    reg _33;
    wire _4;
    wire [9:0] _296;
    wire [7:0] _290;
    wire [7:0] _291;
    wire _289;
    wire [9:0] _292;
    wire [7:0] _286;
    wire [9:0] _287;
    wire [9:0] _285;
    wire [9:0] _288;
    wire [3:0] _237;
    wire _238;
    wire [4:0] _43;
    wire [4:0] _277;
    wire [4:0] _276;
    wire [4:0] _278;
    wire [3:0] _268;
    wire [4:0] _269;
    wire [3:0] _270;
    wire [4:0] _272;
    wire [4:0] _273;
    wire [4:0] _274;
    wire [4:0] _265;
    wire [4:0] _261;
    wire [3:0] _262;
    wire [4:0] _264;
    wire [4:0] _266;
    wire _253;
    wire _254;
    wire [4:0] _255;
    wire [3:0] _256;
    wire [4:0] _258;
    wire [4:0] _259;
    wire [4:0] _267;
    wire _249;
    wire _247;
    wire _250;
    wire _232;
    wire [2:0] _231;
    wire [3:0] _233;
    wire _229;
    wire [3:0] _230;
    wire [3:0] _234;
    wire _225;
    wire [3:0] _226;
    wire _222;
    wire [3:0] _223;
    wire [3:0] _227;
    wire [3:0] _235;
    wire _217;
    wire [3:0] _218;
    wire _214;
    wire [3:0] _215;
    wire [3:0] _219;
    wire _210;
    wire [3:0] _211;
    wire _204;
    wire _202;
    wire _200;
    wire _198;
    wire _196;
    wire _194;
    wire _192;
    wire _190;
    wire _188;
    wire _186;
    wire _184;
    wire _182;
    wire _180;
    wire _178;
    wire _177;
    wire _179;
    wire _181;
    wire _183;
    wire _185;
    wire _187;
    wire _189;
    wire _191;
    wire _193;
    wire _195;
    wire _197;
    wire _199;
    wire _201;
    wire _203;
    wire _173;
    wire _174;
    wire _172;
    wire _175;
    wire _165;
    wire [3:0] _166;
    wire _162;
    wire [3:0] _163;
    wire [3:0] _167;
    wire _158;
    wire [3:0] _159;
    wire _155;
    wire [3:0] _156;
    wire [3:0] _160;
    wire [3:0] _168;
    wire _150;
    wire [3:0] _151;
    wire _147;
    wire [3:0] _148;
    wire [3:0] _152;
    wire _143;
    wire [3:0] _144;
    wire [7:0] _138;
    wire [2:0] _131;
    wire _132;
    wire [2:0] _128;
    wire _129;
    wire [2:0] _125;
    wire _126;
    wire _124;
    wire _127;
    wire _130;
    wire _133;
    wire [7:0] _134;
    wire [7:0] _80;
    wire [9:0] _63;
    wire _64;
    wire [7:0] _79;
    wire _62;
    wire [7:0] _81;
    wire [9:0] _59;
    wire _60;
    wire [7:0] _135;
    wire [7:0] _136;
    reg [7:0] _139;
    wire _140;
    wire [3:0] _141;
    wire [3:0] _145;
    wire [3:0] _153;
    wire [3:0] _169;
    wire _170;
    wire _176;
    wire _205;
    wire [7:0] _206;
    wire _207;
    wire [3:0] _208;
    wire [3:0] _212;
    wire [3:0] _220;
    wire [3:0] _236;
    wire _245;
    wire _242;
    wire _240;
    wire _241;
    wire _243;
    wire _246;
    wire _251;
    wire [4:0] _275;
    wire [4:0] _279;
    wire [4:0] _280;
    reg [4:0] _283;
    wire [4:0] _6;
    wire _44;
    wire _239;
    wire [9:0] _293;
    wire [9:0] _284;
    wire [9:0] _294;
    reg [9:0] _297;
    wire [7:0] _470;
    wire [7:0] _471;
    wire _469;
    wire [9:0] _472;
    wire [7:0] _466;
    wire [9:0] _467;
    wire [9:0] _465;
    wire [9:0] _468;
    wire _419;
    wire [4:0] _457;
    wire [4:0] _456;
    wire [4:0] _458;
    wire [4:0] _449;
    wire [3:0] _450;
    wire [4:0] _452;
    wire [4:0] _453;
    wire [4:0] _454;
    wire [4:0] _441;
    wire [3:0] _442;
    wire [4:0] _444;
    wire [4:0] _446;
    wire _434;
    wire _435;
    wire [4:0] _436;
    wire [3:0] _437;
    wire [4:0] _439;
    wire [4:0] _440;
    wire [4:0] _447;
    wire _430;
    wire _428;
    wire _431;
    wire _413;
    wire [3:0] _414;
    wire _410;
    wire [3:0] _411;
    wire [3:0] _415;
    wire _406;
    wire [3:0] _407;
    wire _403;
    wire [3:0] _404;
    wire [3:0] _408;
    wire [3:0] _416;
    wire _398;
    wire [3:0] _399;
    wire _395;
    wire [3:0] _396;
    wire [3:0] _400;
    wire _391;
    wire [3:0] _392;
    wire _385;
    wire _383;
    wire _381;
    wire _379;
    wire _377;
    wire _375;
    wire _373;
    wire _371;
    wire _369;
    wire _367;
    wire _365;
    wire _363;
    wire _361;
    wire _359;
    wire _358;
    wire _360;
    wire _362;
    wire _364;
    wire _366;
    wire _368;
    wire _370;
    wire _372;
    wire _374;
    wire _376;
    wire _378;
    wire _380;
    wire _382;
    wire _384;
    wire _354;
    wire _355;
    wire _353;
    wire _356;
    wire _346;
    wire [3:0] _347;
    wire _343;
    wire [3:0] _344;
    wire [3:0] _348;
    wire _339;
    wire [3:0] _340;
    wire _336;
    wire [3:0] _337;
    wire [3:0] _341;
    wire [3:0] _349;
    wire _331;
    wire [3:0] _332;
    wire _328;
    wire [3:0] _329;
    wire [3:0] _333;
    wire _324;
    wire [3:0] _325;
    wire _314;
    wire [7:0] _315;
    wire [7:0] _311;
    wire _309;
    wire [7:0] _310;
    wire _307;
    wire [7:0] _312;
    wire _305;
    wire [7:0] _316;
    wire [7:0] _317;
    reg [7:0] _320;
    wire _321;
    wire [3:0] _322;
    wire [3:0] _326;
    wire [3:0] _334;
    wire [3:0] _350;
    wire _351;
    wire _357;
    wire _386;
    wire [7:0] _387;
    wire _388;
    wire [3:0] _389;
    wire [3:0] _393;
    wire [3:0] _401;
    wire [3:0] _417;
    wire _426;
    wire _423;
    wire _421;
    wire _422;
    wire _424;
    wire _427;
    wire _432;
    wire [4:0] _455;
    wire [4:0] _459;
    wire [4:0] _460;
    reg [4:0] _463;
    wire [4:0] _8;
    wire _300;
    wire _420;
    wire [9:0] _473;
    wire [9:0] _474;
    reg [9:0] _477;
    wire [7:0] _704;
    wire [7:0] _705;
    wire _703;
    wire [9:0] _706;
    wire [7:0] _700;
    wire [9:0] _701;
    wire [9:0] _699;
    wire [9:0] _702;
    wire _609;
    wire [4:0] _647;
    wire [4:0] _646;
    wire [4:0] _648;
    wire [4:0] _639;
    wire [3:0] _640;
    wire [4:0] _642;
    wire [4:0] _643;
    wire [4:0] _644;
    wire gnd;
    wire [4:0] _631;
    wire [3:0] _632;
    wire [4:0] _634;
    wire [4:0] _636;
    wire _624;
    wire _625;
    wire [4:0] _626;
    wire [3:0] _627;
    wire [4:0] _629;
    wire [4:0] _630;
    wire [4:0] _637;
    wire _620;
    wire _618;
    wire _621;
    wire _603;
    wire [3:0] _604;
    wire _600;
    wire [3:0] _601;
    wire [3:0] _605;
    wire _596;
    wire [3:0] _597;
    wire _593;
    wire [3:0] _594;
    wire [3:0] _598;
    wire [3:0] _606;
    wire _588;
    wire [3:0] _589;
    wire _585;
    wire [3:0] _586;
    wire [3:0] _590;
    wire _581;
    wire [3:0] _582;
    wire _575;
    wire _573;
    wire _571;
    wire _569;
    wire _567;
    wire _565;
    wire _563;
    wire _561;
    wire _559;
    wire _557;
    wire _555;
    wire _553;
    wire _551;
    wire _549;
    wire _548;
    wire _550;
    wire _552;
    wire _554;
    wire _556;
    wire _558;
    wire _560;
    wire _562;
    wire _564;
    wire _566;
    wire _568;
    wire _570;
    wire _572;
    wire _574;
    wire _544;
    wire _545;
    wire _543;
    wire _546;
    wire _536;
    wire [3:0] _537;
    wire _533;
    wire [3:0] _534;
    wire [3:0] _538;
    wire _529;
    wire [3:0] _530;
    wire _526;
    wire [3:0] _527;
    wire [3:0] _531;
    wire [3:0] _539;
    wire _521;
    wire [3:0] _522;
    wire _518;
    wire [3:0] _519;
    wire [3:0] _523;
    wire _514;
    wire [3:0] _515;
    wire [2:0] _502;
    wire _503;
    wire _500;
    wire [2:0] _496;
    wire _497;
    wire [9:0] _118;
    wire _119;
    wire _120;
    wire [1:0] _117;
    wire [2:0] _121;
    wire [9:0] _112;
    wire _113;
    wire _114;
    wire [2:0] _115;
    wire [9:0] _106;
    wire _107;
    wire _108;
    wire [2:0] _109;
    wire _101;
    wire _102;
    wire [2:0] _103;
    wire [9:0] _94;
    wire _95;
    wire _96;
    wire [2:0] _97;
    wire _89;
    wire _90;
    wire [2:0] _91;
    wire [9:0] _83;
    wire _84;
    wire _85;
    wire [2:0] _86;
    wire [2:0] _92;
    wire [2:0] _98;
    wire [2:0] _104;
    wire [2:0] _110;
    wire [2:0] _116;
    wire [2:0] _122;
    wire _495;
    wire _498;
    wire _501;
    wire _504;
    wire [7:0] _505;
    wire [9:0] _491;
    wire [7:0] _492;
    wire [7:0] _77;
    wire _73;
    wire _72;
    wire _74;
    wire _75;
    wire [7:0] _78;
    wire [7:0] _69;
    wire [9:0] _67;
    wire [5:0] _65;
    wire [15:0] _68;
    wire [23:0] _70;
    wire [7:0] _71;
    wire _489;
    wire [7:0] _490;
    wire _487;
    wire [7:0] _493;
    wire _485;
    wire [7:0] _506;
    wire [9:0] _56;
    wire _57;
    wire [9:0] _53;
    wire _54;
    wire _51;
    wire _49;
    wire _52;
    wire _55;
    wire _58;
    wire [7:0] _507;
    reg [7:0] _510;
    wire _511;
    wire [3:0] _512;
    wire [3:0] _516;
    wire [3:0] _524;
    wire [3:0] _540;
    wire _541;
    wire _547;
    wire _576;
    wire [7:0] _577;
    wire _578;
    wire [3:0] _579;
    wire [3:0] _583;
    wire [3:0] _591;
    wire [3:0] _607;
    wire _616;
    wire _613;
    wire _611;
    wire _612;
    wire _614;
    wire _617;
    wire _622;
    wire [4:0] _645;
    wire [4:0] _649;
    wire [4:0] _650;
    reg [4:0] _653;
    wire [4:0] _10;
    wire _480;
    wire _610;
    wire [9:0] _707;
    wire [9:0] _697;
    wire [9:0] _696;
    wire [9:0] _695;
    wire [9:0] _686;
    wire _687;
    wire [9:0] _683;
    wire _684;
    wire _685;
    wire _688;
    wire _689;
    reg _692;
    wire [9:0] _676;
    wire _677;
    wire [9:0] _673;
    wire _674;
    wire _675;
    wire _678;
    wire _679;
    reg _682;
    wire [1:0] _693;
    reg [9:0] _698;
    wire [9:0] _658;
    wire [9:0] _659;
    wire [9:0] _656;
    wire _657;
    wire [9:0] _661;
    wire [9:0] _662;
    reg [9:0] _665;
    wire [9:0] _11;
    wire _37;
    wire [9:0] _34;
    wire vdd;
    wire [9:0] _667;
    wire [9:0] _654;
    wire _655;
    wire [9:0] _669;
    reg [9:0] _672;
    wire [9:0] _14;
    wire _35;
    wire _38;
    reg _41;
    wire [9:0] _708;
    reg [9:0] _711;
    assign _28 = 1'b0;
    assign _16 = 24'b101111101011110000011111;
    assign _23 = 24'b000000000000000000000000;
    assign _18 = 24'b000000000000000000000001;
    assign _19 = _1 + _18;
    assign _21 = _17 ? _23 : _19;
    always @(posedge clock) begin
        if (clear)
            _25 <= _23;
        else
            _25 <= _21;
    end
    assign _1 = _25;
    assign _17 = _1 == _16;
    assign _26 = _2 ^ _17;
    always @(posedge clock) begin
        if (clear)
            _29 <= _28;
        else
            _29 <= _26;
    end
    assign _2 = _29;
    assign _30 = ~ _4;
    always @(posedge clock) begin
        if (clear)
            _33 <= _28;
        else
            _33 <= _30;
    end
    assign _4 = _33;
    assign _296 = 10'b0000000000;
    assign _290 = ~ _206;
    assign _291 = _253 ? _206 : _290;
    assign _289 = ~ _253;
    assign _292 = { _289,
                    _253,
                    _291 };
    assign _286 = ~ _206;
    assign _287 = { vdd,
                    _253,
                    _286 };
    assign _285 = { gnd,
                    _253,
                    _206 };
    assign _288 = _251 ? _287 : _285;
    assign _237 = 4'b0100;
    assign _238 = _236 == _237;
    assign _43 = 5'b00000;
    assign _277 = _6 + _266;
    assign _276 = _6 - _266;
    assign _278 = _253 ? _277 : _276;
    assign _268 = 4'b0000;
    assign _269 = { _268,
                    _253 };
    assign _270 = _269[3:0];
    assign _272 = { _270,
                    _28 };
    assign _273 = _6 + _272;
    assign _274 = _273 - _266;
    assign _265 = 5'b01000;
    assign _261 = { gnd,
                    _236 };
    assign _262 = _261[3:0];
    assign _264 = { _262,
                    _28 };
    assign _266 = _264 - _265;
    assign _253 = ~ _176;
    assign _254 = ~ _253;
    assign _255 = { _268,
                    _254 };
    assign _256 = _255[3:0];
    assign _258 = { _256,
                    _28 };
    assign _259 = _6 - _258;
    assign _267 = _259 + _266;
    assign _249 = _236 < _237;
    assign _247 = _6[4:4];
    assign _250 = _247 & _249;
    assign _232 = _206[7:7];
    assign _231 = 3'b000;
    assign _233 = { _231,
                    _232 };
    assign _229 = _206[6:6];
    assign _230 = { _231,
                    _229 };
    assign _234 = _230 + _233;
    assign _225 = _206[5:5];
    assign _226 = { _231,
                    _225 };
    assign _222 = _206[4:4];
    assign _223 = { _231,
                    _222 };
    assign _227 = _223 + _226;
    assign _235 = _227 + _234;
    assign _217 = _206[3:3];
    assign _218 = { _231,
                    _217 };
    assign _214 = _206[2:2];
    assign _215 = { _231,
                    _214 };
    assign _219 = _215 + _218;
    assign _210 = _206[1:1];
    assign _211 = { _231,
                    _210 };
    assign _204 = ~ _203;
    assign _202 = _139[7:7];
    assign _200 = ~ _199;
    assign _198 = _139[6:6];
    assign _196 = ~ _195;
    assign _194 = _139[5:5];
    assign _192 = ~ _191;
    assign _190 = _139[4:4];
    assign _188 = ~ _187;
    assign _186 = _139[3:3];
    assign _184 = ~ _183;
    assign _182 = _139[2:2];
    assign _180 = ~ _179;
    assign _178 = _139[1:1];
    assign _177 = _139[0:0];
    assign _179 = _177 ^ _178;
    assign _181 = _176 ? _180 : _179;
    assign _183 = _181 ^ _182;
    assign _185 = _176 ? _184 : _183;
    assign _187 = _185 ^ _186;
    assign _189 = _176 ? _188 : _187;
    assign _191 = _189 ^ _190;
    assign _193 = _176 ? _192 : _191;
    assign _195 = _193 ^ _194;
    assign _197 = _176 ? _196 : _195;
    assign _199 = _197 ^ _198;
    assign _201 = _176 ? _200 : _199;
    assign _203 = _201 ^ _202;
    assign _173 = _139[0:0];
    assign _174 = ~ _173;
    assign _172 = _169 == _237;
    assign _175 = _172 & _174;
    assign _165 = _139[7:7];
    assign _166 = { _231,
                    _165 };
    assign _162 = _139[6:6];
    assign _163 = { _231,
                    _162 };
    assign _167 = _163 + _166;
    assign _158 = _139[5:5];
    assign _159 = { _231,
                    _158 };
    assign _155 = _139[4:4];
    assign _156 = { _231,
                    _155 };
    assign _160 = _156 + _159;
    assign _168 = _160 + _167;
    assign _150 = _139[3:3];
    assign _151 = { _231,
                    _150 };
    assign _147 = _139[2:2];
    assign _148 = { _231,
                    _147 };
    assign _152 = _148 + _151;
    assign _143 = _139[1:1];
    assign _144 = { _231,
                    _143 };
    assign _138 = 8'b00000000;
    assign _131 = 3'b101;
    assign _132 = _122 == _131;
    assign _128 = 3'b100;
    assign _129 = _122 == _128;
    assign _125 = 3'b001;
    assign _126 = _122 == _125;
    assign _124 = _122 == _231;
    assign _127 = _124 | _126;
    assign _130 = _127 | _129;
    assign _133 = _130 | _132;
    assign _134 = _133 ? _77 : _138;
    assign _80 = _14[7:0];
    assign _63 = 10'b0101000000;
    assign _64 = _14 < _63;
    assign _79 = _64 ? _78 : _71;
    assign _62 = _11 < _63;
    assign _81 = _62 ? _80 : _79;
    assign _59 = 10'b0010100000;
    assign _60 = _11 < _59;
    assign _135 = _60 ? _134 : _81;
    assign _136 = _58 ? _77 : _135;
    always @(posedge clock) begin
        if (clear)
            _139 <= _138;
        else
            _139 <= _136;
    end
    assign _140 = _139[0:0];
    assign _141 = { _231,
                    _140 };
    assign _145 = _141 + _144;
    assign _153 = _145 + _152;
    assign _169 = _153 + _168;
    assign _170 = _237 < _169;
    assign _176 = _170 | _175;
    assign _205 = _176 ? _204 : _203;
    assign _206 = { _205,
                    _201,
                    _197,
                    _193,
                    _189,
                    _185,
                    _181,
                    _177 };
    assign _207 = _206[0:0];
    assign _208 = { _231,
                    _207 };
    assign _212 = _208 + _211;
    assign _220 = _212 + _219;
    assign _236 = _220 + _235;
    assign _245 = _237 < _236;
    assign _242 = ~ _44;
    assign _240 = _6[4:4];
    assign _241 = ~ _240;
    assign _243 = _241 & _242;
    assign _246 = _243 & _245;
    assign _251 = _246 | _250;
    assign _275 = _251 ? _274 : _267;
    assign _279 = _239 ? _278 : _275;
    assign _280 = _41 ? _279 : _43;
    always @(posedge clock) begin
        if (clear)
            _283 <= _43;
        else
            _283 <= _280;
    end
    assign _6 = _283;
    assign _44 = _6 == _43;
    assign _239 = _44 | _238;
    assign _293 = _239 ? _292 : _288;
    assign _284 = 10'b1101010100;
    assign _294 = _41 ? _293 : _284;
    always @(posedge clock) begin
        if (clear)
            _297 <= _296;
        else
            _297 <= _294;
    end
    assign _470 = ~ _387;
    assign _471 = _434 ? _387 : _470;
    assign _469 = ~ _434;
    assign _472 = { _469,
                    _434,
                    _471 };
    assign _466 = ~ _387;
    assign _467 = { vdd,
                    _434,
                    _466 };
    assign _465 = { gnd,
                    _434,
                    _387 };
    assign _468 = _432 ? _467 : _465;
    assign _419 = _417 == _237;
    assign _457 = _8 + _446;
    assign _456 = _8 - _446;
    assign _458 = _434 ? _457 : _456;
    assign _449 = { _268,
                    _434 };
    assign _450 = _449[3:0];
    assign _452 = { _450,
                    _28 };
    assign _453 = _8 + _452;
    assign _454 = _453 - _446;
    assign _441 = { gnd,
                    _417 };
    assign _442 = _441[3:0];
    assign _444 = { _442,
                    _28 };
    assign _446 = _444 - _265;
    assign _434 = ~ _357;
    assign _435 = ~ _434;
    assign _436 = { _268,
                    _435 };
    assign _437 = _436[3:0];
    assign _439 = { _437,
                    _28 };
    assign _440 = _8 - _439;
    assign _447 = _440 + _446;
    assign _430 = _417 < _237;
    assign _428 = _8[4:4];
    assign _431 = _428 & _430;
    assign _413 = _387[7:7];
    assign _414 = { _231,
                    _413 };
    assign _410 = _387[6:6];
    assign _411 = { _231,
                    _410 };
    assign _415 = _411 + _414;
    assign _406 = _387[5:5];
    assign _407 = { _231,
                    _406 };
    assign _403 = _387[4:4];
    assign _404 = { _231,
                    _403 };
    assign _408 = _404 + _407;
    assign _416 = _408 + _415;
    assign _398 = _387[3:3];
    assign _399 = { _231,
                    _398 };
    assign _395 = _387[2:2];
    assign _396 = { _231,
                    _395 };
    assign _400 = _396 + _399;
    assign _391 = _387[1:1];
    assign _392 = { _231,
                    _391 };
    assign _385 = ~ _384;
    assign _383 = _320[7:7];
    assign _381 = ~ _380;
    assign _379 = _320[6:6];
    assign _377 = ~ _376;
    assign _375 = _320[5:5];
    assign _373 = ~ _372;
    assign _371 = _320[4:4];
    assign _369 = ~ _368;
    assign _367 = _320[3:3];
    assign _365 = ~ _364;
    assign _363 = _320[2:2];
    assign _361 = ~ _360;
    assign _359 = _320[1:1];
    assign _358 = _320[0:0];
    assign _360 = _358 ^ _359;
    assign _362 = _357 ? _361 : _360;
    assign _364 = _362 ^ _363;
    assign _366 = _357 ? _365 : _364;
    assign _368 = _366 ^ _367;
    assign _370 = _357 ? _369 : _368;
    assign _372 = _370 ^ _371;
    assign _374 = _357 ? _373 : _372;
    assign _376 = _374 ^ _375;
    assign _378 = _357 ? _377 : _376;
    assign _380 = _378 ^ _379;
    assign _382 = _357 ? _381 : _380;
    assign _384 = _382 ^ _383;
    assign _354 = _320[0:0];
    assign _355 = ~ _354;
    assign _353 = _350 == _237;
    assign _356 = _353 & _355;
    assign _346 = _320[7:7];
    assign _347 = { _231,
                    _346 };
    assign _343 = _320[6:6];
    assign _344 = { _231,
                    _343 };
    assign _348 = _344 + _347;
    assign _339 = _320[5:5];
    assign _340 = { _231,
                    _339 };
    assign _336 = _320[4:4];
    assign _337 = { _231,
                    _336 };
    assign _341 = _337 + _340;
    assign _349 = _341 + _348;
    assign _331 = _320[3:3];
    assign _332 = { _231,
                    _331 };
    assign _328 = _320[2:2];
    assign _329 = { _231,
                    _328 };
    assign _333 = _329 + _332;
    assign _324 = _320[1:1];
    assign _325 = { _231,
                    _324 };
    assign _314 = _122 < _128;
    assign _315 = _314 ? _77 : _138;
    assign _311 = _11[7:0];
    assign _309 = _14 < _63;
    assign _310 = _309 ? _78 : _71;
    assign _307 = _11 < _63;
    assign _312 = _307 ? _311 : _310;
    assign _305 = _11 < _59;
    assign _316 = _305 ? _315 : _312;
    assign _317 = _58 ? _77 : _316;
    always @(posedge clock) begin
        if (clear)
            _320 <= _138;
        else
            _320 <= _317;
    end
    assign _321 = _320[0:0];
    assign _322 = { _231,
                    _321 };
    assign _326 = _322 + _325;
    assign _334 = _326 + _333;
    assign _350 = _334 + _349;
    assign _351 = _237 < _350;
    assign _357 = _351 | _356;
    assign _386 = _357 ? _385 : _384;
    assign _387 = { _386,
                    _382,
                    _378,
                    _374,
                    _370,
                    _366,
                    _362,
                    _358 };
    assign _388 = _387[0:0];
    assign _389 = { _231,
                    _388 };
    assign _393 = _389 + _392;
    assign _401 = _393 + _400;
    assign _417 = _401 + _416;
    assign _426 = _237 < _417;
    assign _423 = ~ _300;
    assign _421 = _8[4:4];
    assign _422 = ~ _421;
    assign _424 = _422 & _423;
    assign _427 = _424 & _426;
    assign _432 = _427 | _431;
    assign _455 = _432 ? _454 : _447;
    assign _459 = _420 ? _458 : _455;
    assign _460 = _41 ? _459 : _43;
    always @(posedge clock) begin
        if (clear)
            _463 <= _43;
        else
            _463 <= _460;
    end
    assign _8 = _463;
    assign _300 = _8 == _43;
    assign _420 = _300 | _419;
    assign _473 = _420 ? _472 : _468;
    assign _474 = _41 ? _473 : _284;
    always @(posedge clock) begin
        if (clear)
            _477 <= _296;
        else
            _477 <= _474;
    end
    assign _704 = ~ _577;
    assign _705 = _624 ? _577 : _704;
    assign _703 = ~ _624;
    assign _706 = { _703,
                    _624,
                    _705 };
    assign _700 = ~ _577;
    assign _701 = { vdd,
                    _624,
                    _700 };
    assign _699 = { gnd,
                    _624,
                    _577 };
    assign _702 = _622 ? _701 : _699;
    assign _609 = _607 == _237;
    assign _647 = _10 + _636;
    assign _646 = _10 - _636;
    assign _648 = _624 ? _647 : _646;
    assign _639 = { _268,
                    _624 };
    assign _640 = _639[3:0];
    assign _642 = { _640,
                    _28 };
    assign _643 = _10 + _642;
    assign _644 = _643 - _636;
    assign gnd = 1'b0;
    assign _631 = { gnd,
                    _607 };
    assign _632 = _631[3:0];
    assign _634 = { _632,
                    _28 };
    assign _636 = _634 - _265;
    assign _624 = ~ _547;
    assign _625 = ~ _624;
    assign _626 = { _268,
                    _625 };
    assign _627 = _626[3:0];
    assign _629 = { _627,
                    _28 };
    assign _630 = _10 - _629;
    assign _637 = _630 + _636;
    assign _620 = _607 < _237;
    assign _618 = _10[4:4];
    assign _621 = _618 & _620;
    assign _603 = _577[7:7];
    assign _604 = { _231,
                    _603 };
    assign _600 = _577[6:6];
    assign _601 = { _231,
                    _600 };
    assign _605 = _601 + _604;
    assign _596 = _577[5:5];
    assign _597 = { _231,
                    _596 };
    assign _593 = _577[4:4];
    assign _594 = { _231,
                    _593 };
    assign _598 = _594 + _597;
    assign _606 = _598 + _605;
    assign _588 = _577[3:3];
    assign _589 = { _231,
                    _588 };
    assign _585 = _577[2:2];
    assign _586 = { _231,
                    _585 };
    assign _590 = _586 + _589;
    assign _581 = _577[1:1];
    assign _582 = { _231,
                    _581 };
    assign _575 = ~ _574;
    assign _573 = _510[7:7];
    assign _571 = ~ _570;
    assign _569 = _510[6:6];
    assign _567 = ~ _566;
    assign _565 = _510[5:5];
    assign _563 = ~ _562;
    assign _561 = _510[4:4];
    assign _559 = ~ _558;
    assign _557 = _510[3:3];
    assign _555 = ~ _554;
    assign _553 = _510[2:2];
    assign _551 = ~ _550;
    assign _549 = _510[1:1];
    assign _548 = _510[0:0];
    assign _550 = _548 ^ _549;
    assign _552 = _547 ? _551 : _550;
    assign _554 = _552 ^ _553;
    assign _556 = _547 ? _555 : _554;
    assign _558 = _556 ^ _557;
    assign _560 = _547 ? _559 : _558;
    assign _562 = _560 ^ _561;
    assign _564 = _547 ? _563 : _562;
    assign _566 = _564 ^ _565;
    assign _568 = _547 ? _567 : _566;
    assign _570 = _568 ^ _569;
    assign _572 = _547 ? _571 : _570;
    assign _574 = _572 ^ _573;
    assign _544 = _510[0:0];
    assign _545 = ~ _544;
    assign _543 = _540 == _237;
    assign _546 = _543 & _545;
    assign _536 = _510[7:7];
    assign _537 = { _231,
                    _536 };
    assign _533 = _510[6:6];
    assign _534 = { _231,
                    _533 };
    assign _538 = _534 + _537;
    assign _529 = _510[5:5];
    assign _530 = { _231,
                    _529 };
    assign _526 = _510[4:4];
    assign _527 = { _231,
                    _526 };
    assign _531 = _527 + _530;
    assign _539 = _531 + _538;
    assign _521 = _510[3:3];
    assign _522 = { _231,
                    _521 };
    assign _518 = _510[2:2];
    assign _519 = { _231,
                    _518 };
    assign _523 = _519 + _522;
    assign _514 = _510[1:1];
    assign _515 = { _231,
                    _514 };
    assign _502 = 3'b110;
    assign _503 = _122 == _502;
    assign _500 = _122 == _128;
    assign _496 = 3'b010;
    assign _497 = _122 == _496;
    assign _118 = 10'b1000110000;
    assign _119 = _14 < _118;
    assign _120 = ~ _119;
    assign _117 = 2'b00;
    assign _121 = { _117,
                    _120 };
    assign _112 = 10'b0111100000;
    assign _113 = _14 < _112;
    assign _114 = ~ _113;
    assign _115 = { _117,
                    _114 };
    assign _106 = 10'b0110010000;
    assign _107 = _14 < _106;
    assign _108 = ~ _107;
    assign _109 = { _117,
                    _108 };
    assign _101 = _14 < _63;
    assign _102 = ~ _101;
    assign _103 = { _117,
                    _102 };
    assign _94 = 10'b0011110000;
    assign _95 = _14 < _94;
    assign _96 = ~ _95;
    assign _97 = { _117,
                   _96 };
    assign _89 = _14 < _59;
    assign _90 = ~ _89;
    assign _91 = { _117,
                   _90 };
    assign _83 = 10'b0001010000;
    assign _84 = _14 < _83;
    assign _85 = ~ _84;
    assign _86 = { _117,
                   _85 };
    assign _92 = _86 + _91;
    assign _98 = _92 + _97;
    assign _104 = _98 + _103;
    assign _110 = _104 + _109;
    assign _116 = _110 + _115;
    assign _122 = _116 + _121;
    assign _495 = _122 == _231;
    assign _498 = _495 | _497;
    assign _501 = _498 | _500;
    assign _504 = _501 | _503;
    assign _505 = _504 ? _77 : _138;
    assign _491 = _14 ^ _11;
    assign _492 = _491[7:0];
    assign _77 = 8'b11111111;
    assign _73 = _11[0:0];
    assign _72 = _14[0:0];
    assign _74 = _72 ^ _73;
    assign _75 = ~ _74;
    assign _78 = _75 ? _77 : _138;
    assign _69 = 8'b11001101;
    assign _67 = _14 - _63;
    assign _65 = 6'b000000;
    assign _68 = { _65,
                   _67 };
    assign _70 = _68 * _69;
    assign _71 = _70[15:8];
    assign _489 = _14 < _63;
    assign _490 = _489 ? _78 : _71;
    assign _487 = _11 < _63;
    assign _493 = _487 ? _492 : _490;
    assign _485 = _11 < _59;
    assign _506 = _485 ? _505 : _493;
    assign _56 = 10'b0111011111;
    assign _57 = _11 == _56;
    assign _53 = 10'b1001111111;
    assign _54 = _14 == _53;
    assign _51 = _11 == _296;
    assign _49 = _14 == _296;
    assign _52 = _49 | _51;
    assign _55 = _52 | _54;
    assign _58 = _55 | _57;
    assign _507 = _58 ? _77 : _506;
    always @(posedge clock) begin
        if (clear)
            _510 <= _138;
        else
            _510 <= _507;
    end
    assign _511 = _510[0:0];
    assign _512 = { _231,
                    _511 };
    assign _516 = _512 + _515;
    assign _524 = _516 + _523;
    assign _540 = _524 + _539;
    assign _541 = _237 < _540;
    assign _547 = _541 | _546;
    assign _576 = _547 ? _575 : _574;
    assign _577 = { _576,
                    _572,
                    _568,
                    _564,
                    _560,
                    _556,
                    _552,
                    _548 };
    assign _578 = _577[0:0];
    assign _579 = { _231,
                    _578 };
    assign _583 = _579 + _582;
    assign _591 = _583 + _590;
    assign _607 = _591 + _606;
    assign _616 = _237 < _607;
    assign _613 = ~ _480;
    assign _611 = _10[4:4];
    assign _612 = ~ _611;
    assign _614 = _612 & _613;
    assign _617 = _614 & _616;
    assign _622 = _617 | _621;
    assign _645 = _622 ? _644 : _637;
    assign _649 = _610 ? _648 : _645;
    assign _650 = _41 ? _649 : _43;
    always @(posedge clock) begin
        if (clear)
            _653 <= _43;
        else
            _653 <= _650;
    end
    assign _10 = _653;
    assign _480 = _10 == _43;
    assign _610 = _480 | _609;
    assign _707 = _610 ? _706 : _702;
    assign _697 = 10'b1010101011;
    assign _696 = 10'b0101010100;
    assign _695 = 10'b0010101011;
    assign _686 = 10'b1011110000;
    assign _687 = _14 < _686;
    assign _683 = 10'b1010010000;
    assign _684 = _14 < _683;
    assign _685 = ~ _684;
    assign _688 = _685 & _687;
    assign _689 = ~ _688;
    always @(posedge clock) begin
        if (clear)
            _692 <= _28;
        else
            _692 <= _689;
    end
    assign _676 = 10'b0111101100;
    assign _677 = _11 < _676;
    assign _673 = 10'b0111101010;
    assign _674 = _11 < _673;
    assign _675 = ~ _674;
    assign _678 = _675 & _677;
    assign _679 = ~ _678;
    always @(posedge clock) begin
        if (clear)
            _682 <= _28;
        else
            _682 <= _679;
    end
    assign _693 = { _682,
                    _692 };
    always @* begin
        case (_693)
        0:
            _698 <= _284;
        1:
            _698 <= _695;
        2:
            _698 <= _696;
        default:
            _698 <= _697;
        endcase
    end
    assign _658 = 10'b0000000001;
    assign _659 = _11 + _658;
    assign _656 = 10'b1000001100;
    assign _657 = _11 == _656;
    assign _661 = _657 ? _296 : _659;
    assign _662 = _655 ? _661 : _11;
    always @(posedge clock) begin
        if (clear)
            _665 <= _296;
        else
            _665 <= _662;
    end
    assign _11 = _665;
    assign _37 = _11 < _112;
    assign _34 = 10'b1010000000;
    assign vdd = 1'b1;
    assign _667 = _14 + _658;
    assign _654 = 10'b1100011111;
    assign _655 = _14 == _654;
    assign _669 = _655 ? _296 : _667;
    always @(posedge clock) begin
        if (clear)
            _672 <= _296;
        else
            _672 <= _669;
    end
    assign _14 = _672;
    assign _35 = _14 < _34;
    assign _38 = _35 & _37;
    always @(posedge clock) begin
        if (clear)
            _41 <= _28;
        else
            _41 <= _38;
    end
    assign _708 = _41 ? _707 : _698;
    always @(posedge clock) begin
        if (clear)
            _711 <= _296;
        else
            _711 <= _708;
    end
    assign word_b = _711;
    assign word_g = _477;
    assign word_r = _297;
    assign toggle = _4;
    assign led_1hz = _2;

endmodule
