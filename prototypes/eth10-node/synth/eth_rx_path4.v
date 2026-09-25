module eth_rx_path (
    cfg_shift,
    cfg_in,
    clear,
    clock,
    samples,
    active,
    rx_byte,
    byte_valid,
    frame_end,
    frame_ok,
    length,
    overrun,
    carrier
);

    input cfg_shift;
    input cfg_in;
    input clear;
    input clock;
    input [3:0] samples;
    input active;
    output [7:0] rx_byte;
    output byte_valid;
    output frame_end;
    output frame_ok;
    output [11:0] length;
    output overrun;
    output carrier;

    wire [1:0] _45;
    wire _46;
    wire _47;
    wire _41;
    wire _48;
    wire _144;
    wire _141;
    wire _116;
    wire _92;
    wire _117;
    wire _142;
    reg _145;
    wire [11:0] _156;
    wire [11:0] _520;
    wire [11:0] _163;
    wire [11:0] _164;
    wire [11:0] _165;
    wire [11:0] _166;
    wire [11:0] _521;
    wire [11:0] _3;
    reg [11:0] _157;
    wire _608;
    wire [31:0] _605;
    wire [31:0] _527;
    wire [31:0] _593;
    wire [31:0] _589;
    wire _532;
    wire _587;
    wire [31:0] _590;
    wire [30:0] _530;
    wire [31:0] _531;
    wire [31:0] _591;
    wire _522;
    wire _523;
    wire _5;
    wire [31:0] _592;
    wire _524;
    wire _525;
    wire _6;
    wire [31:0] _594;
    wire [31:0] _7;
    reg [31:0] _528;
    wire _606;
    wire _599;
    wire _598;
    wire _600;
    wire _601;
    wire _8;
    reg _597;
    wire _607;
    wire _609;
    wire _9;
    reg _604;
    wire _612;
    wire _613;
    wire _10;
    wire _614;
    wire _615;
    wire _12;
    wire [2:0] _161;
    wire [2:0] _159;
    wire [2:0] _620;
    wire [2:0] _616;
    wire [2:0] _617;
    wire [2:0] _618;
    wire [2:0] _621;
    wire [2:0] _14;
    reg [2:0] _160;
    wire _162;
    wire _622;
    wire _623;
    wire _624;
    wire _15;
    wire [7:0] _640;
    wire [7:0] _644;
    wire _517;
    reg _497;
    reg _500;
    reg _503;
    reg _506;
    reg _509;
    wire [4:0] _510;
    wire [4:0] _493;
    reg _487;
    reg _481;
    reg _484;
    wire _488;
    reg _478;
    wire _489;
    wire [3:0] _475;
    wire [4:0] _490;
    reg _467;
    reg _461;
    reg _464;
    wire _468;
    reg _458;
    wire _469;
    wire [4:0] _470;
    reg _447;
    reg _441;
    reg _444;
    wire _448;
    reg _438;
    wire _449;
    wire [4:0] _450;
    reg _427;
    reg _421;
    reg _424;
    wire _428;
    reg _418;
    wire _429;
    wire [4:0] _430;
    reg _407;
    reg _401;
    reg _404;
    wire _408;
    reg _398;
    wire _409;
    wire [4:0] _410;
    reg _387;
    reg _381;
    reg _384;
    wire _388;
    reg _378;
    wire _389;
    wire [4:0] _390;
    reg _367;
    reg _361;
    reg _364;
    wire _368;
    reg _358;
    wire _369;
    wire [4:0] _370;
    reg _347;
    reg _341;
    reg _344;
    wire _348;
    reg _338;
    wire _349;
    wire [4:0] _350;
    reg _327;
    reg _321;
    reg _324;
    wire _328;
    reg _318;
    wire _329;
    wire [4:0] _330;
    reg _307;
    reg _301;
    reg _304;
    wire _308;
    reg _298;
    wire _309;
    wire [4:0] _310;
    reg _287;
    reg _281;
    reg _284;
    wire _288;
    reg _278;
    wire _289;
    wire [4:0] _290;
    reg _267;
    reg _261;
    reg _264;
    wire _268;
    reg _258;
    wire _269;
    wire [4:0] _270;
    reg _247;
    reg _241;
    reg _244;
    wire _248;
    reg _238;
    wire _249;
    wire [4:0] _250;
    reg _227;
    reg _221;
    reg _224;
    wire _228;
    reg _218;
    wire _229;
    wire [4:0] _230;
    reg _207;
    reg _201;
    reg _204;
    wire _208;
    reg _198;
    wire _209;
    wire [4:0] _210;
    reg _188;
    reg _185;
    wire _189;
    reg _170;
    wire _190;
    wire [4:0] _191;
    reg [4:0] _194;
    wire [4:0] _211;
    reg [4:0] _214;
    wire [4:0] _231;
    reg [4:0] _234;
    wire [4:0] _251;
    reg [4:0] _254;
    wire [4:0] _271;
    reg [4:0] _274;
    wire [4:0] _291;
    reg [4:0] _294;
    wire [4:0] _311;
    reg [4:0] _314;
    wire [4:0] _331;
    reg [4:0] _334;
    wire [4:0] _351;
    reg [4:0] _354;
    wire [4:0] _371;
    reg [4:0] _374;
    wire [4:0] _391;
    reg [4:0] _394;
    wire [4:0] _411;
    reg [4:0] _414;
    wire [4:0] _431;
    reg [4:0] _434;
    wire [4:0] _451;
    reg [4:0] _454;
    wire [4:0] _471;
    reg [4:0] _474;
    wire [4:0] _491;
    reg [4:0] _494;
    wire _511;
    wire _512;
    reg _515;
    wire _516;
    wire _518;
    wire _637;
    wire [1:0] _610;
    wire [1:0] _629;
    wire [5:0] _627;
    wire _628;
    wire [1:0] _630;
    wire [1:0] _631;
    wire _626;
    wire [1:0] _633;
    wire [1:0] _635;
    wire [1:0] _19;
    reg [1:0] _44;
    wire _611;
    wire _636;
    wire _638;
    wire _20;
    reg _148;
    wire _149;
    wire [7:0] _645;
    wire [7:0] _21;
    reg [7:0] _641;
    wire [6:0] _642;
    wire [5:0] _38;
    wire [5:0] _662;
    wire [5:0] _659;
    wire _654;
    wire _649;
    wire _647;
    wire _646;
    wire _648;
    wire _650;
    wire _655;
    reg _658;
    wire [5:0] _660;
    wire [5:0] _663;
    wire [5:0] _22;
    reg [5:0] _37;
    wire _39;
    wire _40;
    wire _154;
    wire _175;
    wire _174;
    wire _176;
    wire _173;
    wire _177;
    wire gnd;
    wire _172;
    wire _178;
    reg _181;
    wire _139;
    wire _114;
    wire _90;
    wire _653;
    wire _668;
    wire _120;
    wire _121;
    wire _95;
    wire _96;
    wire [9:0] _69;
    wire [9:0] _62;
    wire [9:0] _63;
    wire [9:0] _60;
    wire [9:0] _134;
    wire _132;
    wire [9:0] _135;
    wire _136;
    wire _137;
    wire _138;
    wire [9:0] _652;
    wire [9:0] _109;
    wire _107;
    wire [9:0] _110;
    wire _111;
    wire _112;
    wire _113;
    wire [9:0] _119;
    wire [9:0] _65;
    wire [9:0] _85;
    wire _83;
    wire [9:0] _86;
    wire _87;
    wire _88;
    wire _89;
    wire [9:0] _94;
    wire [9:0] _80;
    wire [9:0] _81;
    wire _76;
    wire _77;
    wire _78;
    wire [9:0] _104;
    wire [9:0] _105;
    wire _100;
    wire _101;
    wire _102;
    wire [9:0] _129;
    wire [9:0] _130;
    wire _125;
    wire _126;
    wire _127;
    wire [9:0] _665;
    wire [9:0] _666;
    wire [9:0] _23;
    reg [9:0] _59;
    wire _61;
    wire [9:0] _64;
    wire _66;
    wire _67;
    wire _68;
    wire [9:0] _70;
    wire [9:0] _56;
    wire _71;
    wire _72;
    wire vdd;
    wire _123;
    wire _98;
    wire _74;
    wire _75;
    wire _99;
    wire _124;
    wire _667;
    wire _26;
    reg _52;
    wire _49;
    wire _53;
    wire _54;
    wire _55;
    wire _73;
    wire _97;
    wire _122;
    wire _669;
    wire _29;
    reg _34;
    wire _91;
    wire _115;
    wire _140;
    wire _150;
    reg _153;
    wire _182;
    reg _535;
    reg _538;
    reg _541;
    reg _544;
    reg _547;
    reg _550;
    reg _553;
    reg _556;
    reg _559;
    reg _562;
    reg _565;
    reg _568;
    reg _571;
    reg _574;
    reg _577;
    reg _580;
    reg _583;
    reg _586;
    wire [7:0] _643;
    assign _45 = 2'b00;
    assign _46 = _44 == _45;
    assign _47 = ~ _46;
    assign _41 = _34 | _40;
    assign _48 = _41 | _47;
    assign _144 = 1'b0;
    assign _141 = _139 & _140;
    assign _116 = _114 & _115;
    assign _92 = _90 & _91;
    assign _117 = _92 | _116;
    assign _142 = _117 | _141;
    always @(posedge clock) begin
        if (clear)
            _145 <= _144;
        else
            _145 <= _142;
    end
    assign _156 = 12'b000000000000;
    assign _520 = _518 ? _156 : _157;
    assign _163 = 12'b000000000001;
    assign _164 = _157 + _163;
    assign _165 = _162 ? _164 : _157;
    assign _166 = _154 ? _165 : _157;
    assign _521 = _149 ? _520 : _166;
    assign _3 = _521;
    always @(posedge clock) begin
        if (clear)
            _157 <= _156;
        else
            _157 <= _3;
    end
    assign _608 = _518 ? gnd : _607;
    assign _605 = 32'b11011110101110110010000011100011;
    assign _527 = 32'b00000000000000000000000000000000;
    assign _593 = 32'b11111111111111111111111111111111;
    assign _589 = 32'b11101101101110001000001100100000;
    assign _532 = _528[0:0];
    assign _587 = _532 ^ _586;
    assign _590 = _587 ? _589 : _527;
    assign _530 = _528[31:1];
    assign _531 = { _144,
                    _530 };
    assign _591 = _531 ^ _590;
    assign _522 = _154 ? vdd : gnd;
    assign _523 = _149 ? gnd : _522;
    assign _5 = _523;
    assign _592 = _5 ? _591 : _528;
    assign _524 = _518 ? vdd : gnd;
    assign _525 = _149 ? _524 : gnd;
    assign _6 = _525;
    assign _594 = _6 ? _593 : _592;
    assign _7 = _594;
    always @(posedge clock) begin
        if (clear)
            _528 <= _527;
        else
            _528 <= _7;
    end
    assign _606 = _528 == _605;
    assign _599 = _162 ? vdd : _598;
    assign _598 = _597 ? gnd : _597;
    assign _600 = _154 ? _599 : _598;
    assign _601 = _149 ? _598 : _600;
    assign _8 = _601;
    always @(posedge clock) begin
        if (clear)
            _597 <= _144;
        else
            _597 <= _8;
    end
    assign _607 = _597 ? _606 : _604;
    assign _609 = _149 ? _608 : _607;
    assign _9 = _609;
    always @(posedge clock) begin
        if (clear)
            _604 <= _144;
        else
            _604 <= _9;
    end
    assign _612 = _148 ? _604 : gnd;
    assign _613 = _611 ? _612 : gnd;
    assign _10 = _613;
    assign _614 = _148 ? vdd : gnd;
    assign _615 = _611 ? _614 : gnd;
    assign _12 = _615;
    assign _161 = 3'b111;
    assign _159 = 3'b000;
    assign _620 = _518 ? _159 : _160;
    assign _616 = 3'b001;
    assign _617 = _160 + _616;
    assign _618 = _154 ? _617 : _160;
    assign _621 = _149 ? _620 : _618;
    assign _14 = _621;
    always @(posedge clock) begin
        if (clear)
            _160 <= _159;
        else
            _160 <= _14;
    end
    assign _162 = _160 == _161;
    assign _622 = _162 ? vdd : gnd;
    assign _623 = _154 ? _622 : gnd;
    assign _624 = _149 ? gnd : _623;
    assign _15 = _624;
    assign _640 = 8'b00000000;
    assign _644 = _154 ? _643 : _641;
    assign _517 = ~ _40;
    always @(posedge clock) begin
        if (cfg_shift)
            _497 <= _487;
    end
    always @(posedge clock) begin
        if (cfg_shift)
            _500 <= _497;
    end
    always @(posedge clock) begin
        if (cfg_shift)
            _503 <= _500;
    end
    always @(posedge clock) begin
        if (cfg_shift)
            _506 <= _503;
    end
    always @(posedge clock) begin
        if (cfg_shift)
            _509 <= _506;
    end
    assign _510 = { _509,
                    _506,
                    _503,
                    _500,
                    _497 };
    assign _493 = 5'b00000;
    always @(posedge clock) begin
        if (cfg_shift)
            _487 <= _478;
    end
    always @(posedge clock) begin
        if (clear)
            _481 <= _144;
        else
            if (_154)
                _481 <= _464;
    end
    always @(posedge clock) begin
        if (clear)
            _484 <= _144;
        else
            if (_154)
                _484 <= _481;
    end
    assign _488 = _484 == _487;
    always @(posedge clock) begin
        if (cfg_shift)
            _478 <= _467;
    end
    assign _489 = _478 & _488;
    assign _475 = 4'b0000;
    assign _490 = { _475,
                    _489 };
    always @(posedge clock) begin
        if (cfg_shift)
            _467 <= _458;
    end
    always @(posedge clock) begin
        if (clear)
            _461 <= _144;
        else
            if (_154)
                _461 <= _444;
    end
    always @(posedge clock) begin
        if (clear)
            _464 <= _144;
        else
            if (_154)
                _464 <= _461;
    end
    assign _468 = _464 == _467;
    always @(posedge clock) begin
        if (cfg_shift)
            _458 <= _447;
    end
    assign _469 = _458 & _468;
    assign _470 = { _475,
                    _469 };
    always @(posedge clock) begin
        if (cfg_shift)
            _447 <= _438;
    end
    always @(posedge clock) begin
        if (clear)
            _441 <= _144;
        else
            if (_154)
                _441 <= _424;
    end
    always @(posedge clock) begin
        if (clear)
            _444 <= _144;
        else
            if (_154)
                _444 <= _441;
    end
    assign _448 = _444 == _447;
    always @(posedge clock) begin
        if (cfg_shift)
            _438 <= _427;
    end
    assign _449 = _438 & _448;
    assign _450 = { _475,
                    _449 };
    always @(posedge clock) begin
        if (cfg_shift)
            _427 <= _418;
    end
    always @(posedge clock) begin
        if (clear)
            _421 <= _144;
        else
            if (_154)
                _421 <= _404;
    end
    always @(posedge clock) begin
        if (clear)
            _424 <= _144;
        else
            if (_154)
                _424 <= _421;
    end
    assign _428 = _424 == _427;
    always @(posedge clock) begin
        if (cfg_shift)
            _418 <= _407;
    end
    assign _429 = _418 & _428;
    assign _430 = { _475,
                    _429 };
    always @(posedge clock) begin
        if (cfg_shift)
            _407 <= _398;
    end
    always @(posedge clock) begin
        if (clear)
            _401 <= _144;
        else
            if (_154)
                _401 <= _384;
    end
    always @(posedge clock) begin
        if (clear)
            _404 <= _144;
        else
            if (_154)
                _404 <= _401;
    end
    assign _408 = _404 == _407;
    always @(posedge clock) begin
        if (cfg_shift)
            _398 <= _387;
    end
    assign _409 = _398 & _408;
    assign _410 = { _475,
                    _409 };
    always @(posedge clock) begin
        if (cfg_shift)
            _387 <= _378;
    end
    always @(posedge clock) begin
        if (clear)
            _381 <= _144;
        else
            if (_154)
                _381 <= _364;
    end
    always @(posedge clock) begin
        if (clear)
            _384 <= _144;
        else
            if (_154)
                _384 <= _381;
    end
    assign _388 = _384 == _387;
    always @(posedge clock) begin
        if (cfg_shift)
            _378 <= _367;
    end
    assign _389 = _378 & _388;
    assign _390 = { _475,
                    _389 };
    always @(posedge clock) begin
        if (cfg_shift)
            _367 <= _358;
    end
    always @(posedge clock) begin
        if (clear)
            _361 <= _144;
        else
            if (_154)
                _361 <= _344;
    end
    always @(posedge clock) begin
        if (clear)
            _364 <= _144;
        else
            if (_154)
                _364 <= _361;
    end
    assign _368 = _364 == _367;
    always @(posedge clock) begin
        if (cfg_shift)
            _358 <= _347;
    end
    assign _369 = _358 & _368;
    assign _370 = { _475,
                    _369 };
    always @(posedge clock) begin
        if (cfg_shift)
            _347 <= _338;
    end
    always @(posedge clock) begin
        if (clear)
            _341 <= _144;
        else
            if (_154)
                _341 <= _324;
    end
    always @(posedge clock) begin
        if (clear)
            _344 <= _144;
        else
            if (_154)
                _344 <= _341;
    end
    assign _348 = _344 == _347;
    always @(posedge clock) begin
        if (cfg_shift)
            _338 <= _327;
    end
    assign _349 = _338 & _348;
    assign _350 = { _475,
                    _349 };
    always @(posedge clock) begin
        if (cfg_shift)
            _327 <= _318;
    end
    always @(posedge clock) begin
        if (clear)
            _321 <= _144;
        else
            if (_154)
                _321 <= _304;
    end
    always @(posedge clock) begin
        if (clear)
            _324 <= _144;
        else
            if (_154)
                _324 <= _321;
    end
    assign _328 = _324 == _327;
    always @(posedge clock) begin
        if (cfg_shift)
            _318 <= _307;
    end
    assign _329 = _318 & _328;
    assign _330 = { _475,
                    _329 };
    always @(posedge clock) begin
        if (cfg_shift)
            _307 <= _298;
    end
    always @(posedge clock) begin
        if (clear)
            _301 <= _144;
        else
            if (_154)
                _301 <= _284;
    end
    always @(posedge clock) begin
        if (clear)
            _304 <= _144;
        else
            if (_154)
                _304 <= _301;
    end
    assign _308 = _304 == _307;
    always @(posedge clock) begin
        if (cfg_shift)
            _298 <= _287;
    end
    assign _309 = _298 & _308;
    assign _310 = { _475,
                    _309 };
    always @(posedge clock) begin
        if (cfg_shift)
            _287 <= _278;
    end
    always @(posedge clock) begin
        if (clear)
            _281 <= _144;
        else
            if (_154)
                _281 <= _264;
    end
    always @(posedge clock) begin
        if (clear)
            _284 <= _144;
        else
            if (_154)
                _284 <= _281;
    end
    assign _288 = _284 == _287;
    always @(posedge clock) begin
        if (cfg_shift)
            _278 <= _267;
    end
    assign _289 = _278 & _288;
    assign _290 = { _475,
                    _289 };
    always @(posedge clock) begin
        if (cfg_shift)
            _267 <= _258;
    end
    always @(posedge clock) begin
        if (clear)
            _261 <= _144;
        else
            if (_154)
                _261 <= _244;
    end
    always @(posedge clock) begin
        if (clear)
            _264 <= _144;
        else
            if (_154)
                _264 <= _261;
    end
    assign _268 = _264 == _267;
    always @(posedge clock) begin
        if (cfg_shift)
            _258 <= _247;
    end
    assign _269 = _258 & _268;
    assign _270 = { _475,
                    _269 };
    always @(posedge clock) begin
        if (cfg_shift)
            _247 <= _238;
    end
    always @(posedge clock) begin
        if (clear)
            _241 <= _144;
        else
            if (_154)
                _241 <= _224;
    end
    always @(posedge clock) begin
        if (clear)
            _244 <= _144;
        else
            if (_154)
                _244 <= _241;
    end
    assign _248 = _244 == _247;
    always @(posedge clock) begin
        if (cfg_shift)
            _238 <= _227;
    end
    assign _249 = _238 & _248;
    assign _250 = { _475,
                    _249 };
    always @(posedge clock) begin
        if (cfg_shift)
            _227 <= _218;
    end
    always @(posedge clock) begin
        if (clear)
            _221 <= _144;
        else
            if (_154)
                _221 <= _204;
    end
    always @(posedge clock) begin
        if (clear)
            _224 <= _144;
        else
            if (_154)
                _224 <= _221;
    end
    assign _228 = _224 == _227;
    always @(posedge clock) begin
        if (cfg_shift)
            _218 <= _207;
    end
    assign _229 = _218 & _228;
    assign _230 = { _475,
                    _229 };
    always @(posedge clock) begin
        if (cfg_shift)
            _207 <= _198;
    end
    always @(posedge clock) begin
        if (clear)
            _201 <= _144;
        else
            if (_154)
                _201 <= _185;
    end
    always @(posedge clock) begin
        if (clear)
            _204 <= _144;
        else
            if (_154)
                _204 <= _201;
    end
    assign _208 = _204 == _207;
    always @(posedge clock) begin
        if (cfg_shift)
            _198 <= _188;
    end
    assign _209 = _198 & _208;
    assign _210 = { _475,
                    _209 };
    always @(posedge clock) begin
        if (cfg_shift)
            _188 <= _170;
    end
    always @(posedge clock) begin
        if (clear)
            _185 <= _144;
        else
            if (_154)
                _185 <= _182;
    end
    assign _189 = _185 == _188;
    always @(posedge clock) begin
        if (cfg_shift)
            _170 <= cfg_in;
    end
    assign _190 = _170 & _189;
    assign _191 = { _475,
                    _190 };
    always @(posedge clock) begin
        if (clear)
            _194 <= _493;
        else
            if (_154)
                _194 <= _191;
    end
    assign _211 = _194 + _210;
    always @(posedge clock) begin
        if (clear)
            _214 <= _493;
        else
            if (_154)
                _214 <= _211;
    end
    assign _231 = _214 + _230;
    always @(posedge clock) begin
        if (clear)
            _234 <= _493;
        else
            if (_154)
                _234 <= _231;
    end
    assign _251 = _234 + _250;
    always @(posedge clock) begin
        if (clear)
            _254 <= _493;
        else
            if (_154)
                _254 <= _251;
    end
    assign _271 = _254 + _270;
    always @(posedge clock) begin
        if (clear)
            _274 <= _493;
        else
            if (_154)
                _274 <= _271;
    end
    assign _291 = _274 + _290;
    always @(posedge clock) begin
        if (clear)
            _294 <= _493;
        else
            if (_154)
                _294 <= _291;
    end
    assign _311 = _294 + _310;
    always @(posedge clock) begin
        if (clear)
            _314 <= _493;
        else
            if (_154)
                _314 <= _311;
    end
    assign _331 = _314 + _330;
    always @(posedge clock) begin
        if (clear)
            _334 <= _493;
        else
            if (_154)
                _334 <= _331;
    end
    assign _351 = _334 + _350;
    always @(posedge clock) begin
        if (clear)
            _354 <= _493;
        else
            if (_154)
                _354 <= _351;
    end
    assign _371 = _354 + _370;
    always @(posedge clock) begin
        if (clear)
            _374 <= _493;
        else
            if (_154)
                _374 <= _371;
    end
    assign _391 = _374 + _390;
    always @(posedge clock) begin
        if (clear)
            _394 <= _493;
        else
            if (_154)
                _394 <= _391;
    end
    assign _411 = _394 + _410;
    always @(posedge clock) begin
        if (clear)
            _414 <= _493;
        else
            if (_154)
                _414 <= _411;
    end
    assign _431 = _414 + _430;
    always @(posedge clock) begin
        if (clear)
            _434 <= _493;
        else
            if (_154)
                _434 <= _431;
    end
    assign _451 = _434 + _450;
    always @(posedge clock) begin
        if (clear)
            _454 <= _493;
        else
            if (_154)
                _454 <= _451;
    end
    assign _471 = _454 + _470;
    always @(posedge clock) begin
        if (clear)
            _474 <= _493;
        else
            if (_154)
                _474 <= _471;
    end
    assign _491 = _474 + _490;
    always @(posedge clock) begin
        if (clear)
            _494 <= _493;
        else
            if (_154)
                _494 <= _491;
    end
    assign _511 = _494 < _510;
    assign _512 = ~ _511;
    always @(posedge clock) begin
        if (clear)
            _515 <= _144;
        else
            if (_154)
                _515 <= _512;
    end
    assign _516 = _154 & _515;
    assign _518 = _516 & _517;
    assign _637 = _518 ? vdd : _636;
    assign _610 = 2'b01;
    assign _629 = 2'b10;
    assign _627 = 6'b000001;
    assign _628 = _37 == _627;
    assign _630 = _628 ? _629 : _44;
    assign _631 = _40 ? _630 : _44;
    assign _626 = _44 == _629;
    assign _633 = _626 ? _610 : _631;
    assign _635 = _611 ? _45 : _633;
    assign _19 = _635;
    always @(posedge clock) begin
        if (clear)
            _44 <= _45;
        else
            _44 <= _19;
    end
    assign _611 = _44 == _610;
    assign _636 = _611 ? gnd : _148;
    assign _638 = _149 ? _637 : _636;
    assign _20 = _638;
    always @(posedge clock) begin
        if (clear)
            _148 <= _144;
        else
            _148 <= _20;
    end
    assign _149 = ~ _148;
    assign _645 = _149 ? _641 : _644;
    assign _21 = _645;
    always @(posedge clock) begin
        if (clear)
            _641 <= _640;
        else
            _641 <= _21;
    end
    assign _642 = _641[7:1];
    assign _38 = 6'b000000;
    assign _662 = _37 - _627;
    assign _659 = 6'b010011;
    assign _654 = _122 & _653;
    assign _649 = _97 & _120;
    assign _647 = _73 & _95;
    assign _646 = _34 & _71;
    assign _648 = _646 | _647;
    assign _650 = _648 | _649;
    assign _655 = _650 | _654;
    always @(posedge clock) begin
        if (clear)
            _658 <= _144;
        else
            _658 <= _655;
    end
    assign _660 = _658 ? _659 : _37;
    assign _663 = _40 ? _662 : _660;
    assign _22 = _663;
    always @(posedge clock) begin
        if (clear)
            _37 <= _38;
        else
            _37 <= _22;
    end
    assign _39 = _37 == _38;
    assign _40 = ~ _39;
    assign _154 = _153 | _40;
    assign _175 = _49 ^ gnd;
    assign _174 = _74 ^ gnd;
    assign _176 = _91 ? _175 : _174;
    assign _173 = _98 ^ gnd;
    assign _177 = _115 ? _176 : _173;
    assign gnd = 1'b0;
    assign _172 = _123 ^ gnd;
    assign _178 = _140 ? _177 : _172;
    always @(posedge clock) begin
        if (clear)
            _181 <= _144;
        else
            _181 <= _178;
    end
    assign _139 = _122 & _138;
    assign _114 = _97 & _113;
    assign _90 = _73 & _89;
    assign _653 = _56 < _652;
    assign _668 = ~ _653;
    assign _120 = _56 < _119;
    assign _121 = ~ _120;
    assign _95 = _56 < _94;
    assign _96 = ~ _95;
    assign _69 = 10'b0000000000;
    assign _62 = 10'b0000000001;
    assign _63 = _59 + _62;
    assign _60 = 10'b1111111111;
    assign _134 = _130 + _62;
    assign _132 = _130 == _60;
    assign _135 = _132 ? _130 : _134;
    assign _136 = _135 < _65;
    assign _137 = ~ _136;
    assign _138 = _127 & _137;
    assign _652 = _138 ? _69 : _135;
    assign _109 = _105 + _62;
    assign _107 = _105 == _60;
    assign _110 = _107 ? _105 : _109;
    assign _111 = _110 < _65;
    assign _112 = ~ _111;
    assign _113 = _102 & _112;
    assign _119 = _113 ? _69 : _110;
    assign _65 = 10'b0000010010;
    assign _85 = _81 + _62;
    assign _83 = _81 == _60;
    assign _86 = _83 ? _81 : _85;
    assign _87 = _86 < _65;
    assign _88 = ~ _87;
    assign _89 = _78 & _88;
    assign _94 = _89 ? _69 : _86;
    assign _80 = _55 ? _69 : _59;
    assign _81 = _34 ? _70 : _80;
    assign _76 = _74 == _75;
    assign _77 = ~ _76;
    assign _78 = active & _77;
    assign _104 = _78 ? _69 : _81;
    assign _105 = _73 ? _94 : _104;
    assign _100 = _98 == _99;
    assign _101 = ~ _100;
    assign _102 = active & _101;
    assign _129 = _102 ? _69 : _105;
    assign _130 = _97 ? _119 : _129;
    assign _125 = _123 == _124;
    assign _126 = ~ _125;
    assign _127 = active & _126;
    assign _665 = _127 ? _69 : _130;
    assign _666 = _122 ? _652 : _665;
    assign _23 = _666;
    always @(posedge clock) begin
        if (clear)
            _59 <= _69;
        else
            _59 <= _23;
    end
    assign _61 = _59 == _60;
    assign _64 = _61 ? _59 : _63;
    assign _66 = _64 < _65;
    assign _67 = ~ _66;
    assign _68 = _55 & _67;
    assign _70 = _68 ? _69 : _64;
    assign _56 = 10'b0000110000;
    assign _71 = _56 < _70;
    assign _72 = ~ _71;
    assign vdd = 1'b1;
    assign _123 = samples[3:3];
    assign _98 = samples[2:2];
    assign _74 = samples[1:1];
    assign _75 = active ? _49 : _52;
    assign _99 = active ? _74 : _75;
    assign _124 = active ? _98 : _99;
    assign _667 = active ? _123 : _124;
    assign _26 = _667;
    always @(posedge clock) begin
        if (clear)
            _52 <= _144;
        else
            _52 <= _26;
    end
    assign _49 = samples[0:0];
    assign _53 = _49 == _52;
    assign _54 = ~ _53;
    assign _55 = active & _54;
    assign _73 = _34 ? _72 : _55;
    assign _97 = _73 ? _96 : _78;
    assign _122 = _97 ? _121 : _102;
    assign _669 = _122 ? _668 : _127;
    assign _29 = _669;
    always @(posedge clock) begin
        if (clear)
            _34 <= _144;
        else
            _34 <= _29;
    end
    assign _91 = _34 & _68;
    assign _115 = _91 | _90;
    assign _140 = _115 | _114;
    assign _150 = _140 | _139;
    always @(posedge clock) begin
        if (clear)
            _153 <= _144;
        else
            _153 <= _150;
    end
    assign _182 = _153 & _181;
    always @(posedge clock) begin
        if (clear)
            _535 <= _144;
        else
            if (_154)
                _535 <= _182;
    end
    always @(posedge clock) begin
        if (clear)
            _538 <= _144;
        else
            if (_154)
                _538 <= _535;
    end
    always @(posedge clock) begin
        if (clear)
            _541 <= _144;
        else
            if (_154)
                _541 <= _538;
    end
    always @(posedge clock) begin
        if (clear)
            _544 <= _144;
        else
            if (_154)
                _544 <= _541;
    end
    always @(posedge clock) begin
        if (clear)
            _547 <= _144;
        else
            if (_154)
                _547 <= _544;
    end
    always @(posedge clock) begin
        if (clear)
            _550 <= _144;
        else
            if (_154)
                _550 <= _547;
    end
    always @(posedge clock) begin
        if (clear)
            _553 <= _144;
        else
            if (_154)
                _553 <= _550;
    end
    always @(posedge clock) begin
        if (clear)
            _556 <= _144;
        else
            if (_154)
                _556 <= _553;
    end
    always @(posedge clock) begin
        if (clear)
            _559 <= _144;
        else
            if (_154)
                _559 <= _556;
    end
    always @(posedge clock) begin
        if (clear)
            _562 <= _144;
        else
            if (_154)
                _562 <= _559;
    end
    always @(posedge clock) begin
        if (clear)
            _565 <= _144;
        else
            if (_154)
                _565 <= _562;
    end
    always @(posedge clock) begin
        if (clear)
            _568 <= _144;
        else
            if (_154)
                _568 <= _565;
    end
    always @(posedge clock) begin
        if (clear)
            _571 <= _144;
        else
            if (_154)
                _571 <= _568;
    end
    always @(posedge clock) begin
        if (clear)
            _574 <= _144;
        else
            if (_154)
                _574 <= _571;
    end
    always @(posedge clock) begin
        if (clear)
            _577 <= _144;
        else
            if (_154)
                _577 <= _574;
    end
    always @(posedge clock) begin
        if (clear)
            _580 <= _144;
        else
            if (_154)
                _580 <= _577;
    end
    always @(posedge clock) begin
        if (clear)
            _583 <= _144;
        else
            if (_154)
                _583 <= _580;
    end
    always @(posedge clock) begin
        if (clear)
            _586 <= _144;
        else
            if (_154)
                _586 <= _583;
    end
    assign _643 = { _586,
                    _642 };
    assign rx_byte = _643;
    assign byte_valid = _15;
    assign frame_end = _12;
    assign frame_ok = _10;
    assign length = _157;
    assign overrun = _145;
    assign carrier = _48;

endmodule
