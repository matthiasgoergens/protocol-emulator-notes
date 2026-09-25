module deadline_sequencer (
    pin_in4,
    host_in,
    pin_in,
    host_in_valid,
    imem_data,
    clear,
    clock,
    imem_addr,
    pin_out,
    pin_oe,
    host_out,
    host_out_valid,
    host_in_ready,
    pcs,
    pin_sub
);

    input [31:0] pin_in4;
    input [7:0] host_in;
    input [7:0] pin_in;
    input host_in_valid;
    input [15:0] imem_data;
    input clear;
    input clock;
    output [7:0] imem_addr;
    output [7:0] pin_out;
    output [7:0] pin_oe;
    output [7:0] host_out;
    output host_out_valid;
    output host_in_ready;
    output [23:0] pcs;
    output [31:0] pin_sub;

    wire _220;
    wire _219;
    wire [1:0] _217;
    wire _218;
    wire _221;
    wire _215;
    wire _214;
    wire [1:0] _212;
    wire _213;
    wire _216;
    wire _210;
    wire _209;
    wire [1:0] _207;
    wire _208;
    wire _211;
    wire _205;
    wire _204;
    wire [1:0] _202;
    wire _203;
    wire _206;
    wire _200;
    wire _199;
    wire _198;
    wire _201;
    wire _195;
    wire _194;
    wire _193;
    wire _196;
    wire _190;
    wire _189;
    wire _188;
    wire _191;
    wire _185;
    wire _184;
    wire _183;
    wire _186;
    wire _180;
    wire _179;
    wire _178;
    wire _181;
    wire _175;
    wire _174;
    wire _173;
    wire _176;
    wire _170;
    wire _169;
    wire _168;
    wire _171;
    wire _165;
    wire _164;
    wire _163;
    wire _166;
    wire _160;
    wire _159;
    wire _158;
    wire _161;
    wire _155;
    wire _154;
    wire _153;
    wire _156;
    wire _150;
    wire _149;
    wire _148;
    wire _151;
    wire _145;
    wire _144;
    wire _143;
    wire _146;
    wire _140;
    wire _139;
    wire _138;
    wire _141;
    wire _135;
    wire _134;
    wire _133;
    wire _136;
    wire _130;
    wire _129;
    wire _128;
    wire _131;
    wire _125;
    wire _124;
    wire _123;
    wire _126;
    wire _120;
    wire _119;
    wire _118;
    wire _121;
    wire _115;
    wire _114;
    wire _113;
    wire _116;
    wire _110;
    wire _109;
    wire _108;
    wire _111;
    wire _105;
    wire _104;
    wire _103;
    wire _106;
    wire _100;
    wire _99;
    wire _98;
    wire _101;
    wire _95;
    wire _94;
    wire _93;
    wire _96;
    wire _90;
    wire _89;
    wire _88;
    wire _91;
    wire _85;
    wire _84;
    wire _83;
    wire _86;
    wire _80;
    wire _79;
    wire _78;
    wire _81;
    wire _75;
    wire _74;
    wire _73;
    wire _76;
    wire _70;
    wire _69;
    wire _68;
    wire _71;
    wire [7:0] _63;
    wire [7:0] _1;
    reg [7:0] _64;
    wire _65;
    wire _61;
    wire [1:0] _54;
    wire _52;
    wire [1:0] _55;
    wire [1:0] _2;
    wire [1:0] _3;
    reg [1:0] _59;
    wire _60;
    wire _66;
    wire [31:0] _222;
    wire [23:0] _235;
    wire _239;
    wire _237;
    wire _240;
    wire _6;
    wire _245;
    wire _242;
    wire _243;
    wire _8;
    reg _246;
    wire [3:0] _241;
    wire _247;
    wire [7:0] _267;
    wire [7:0] _10;
    reg [7:0] _250;
    wire _319;
    wire [1:0] _320;
    wire [3:0] _321;
    wire [7:0] _322;
    wire [7:0] _323;
    wire [7:0] _317;
    wire [7:0] _318;
    wire [7:0] _324;
    wire _311;
    wire [2:0] _309;
    wire _310;
    wire _312;
    wire _307;
    wire [2:0] _305;
    wire _306;
    wire _308;
    wire _303;
    wire [2:0] _301;
    wire _302;
    wire _304;
    wire _299;
    wire [2:0] _297;
    wire _298;
    wire _300;
    wire _295;
    wire [2:0] _293;
    wire _294;
    wire _296;
    wire _291;
    wire [2:0] _289;
    wire _290;
    wire _292;
    wire _287;
    wire [2:0] _285;
    wire _286;
    wire _288;
    wire _283;
    wire _278;
    wire [2:0] _276;
    wire _277;
    wire _284;
    wire [7:0] _313;
    wire [7:0] _314;
    wire _270;
    wire [7:0] _315;
    wire _268;
    wire [7:0] _325;
    wire [7:0] _12;
    reg [7:0] _273;
    wire _464;
    wire [1:0] _465;
    wire [3:0] _466;
    wire [7:0] _467;
    wire [7:0] _468;
    wire [7:0] _316;
    wire [7:0] _462;
    wire [7:0] _463;
    wire [7:0] _469;
    wire _457;
    wire _456;
    wire _458;
    wire _453;
    wire _452;
    wire _454;
    wire _449;
    wire _448;
    wire _450;
    wire _445;
    wire _444;
    wire _446;
    wire _441;
    wire _440;
    wire _442;
    wire _437;
    wire _436;
    wire _438;
    wire _433;
    wire _432;
    wire _434;
    wire gnd;
    wire _429;
    wire _428;
    wire _430;
    wire [7:0] _459;
    wire _424;
    wire _423;
    wire _425;
    wire _420;
    wire _419;
    wire _421;
    wire _416;
    wire _415;
    wire _417;
    wire _412;
    wire _411;
    wire _413;
    wire _408;
    wire _407;
    wire _409;
    wire _404;
    wire _403;
    wire _405;
    wire _400;
    wire _399;
    wire _401;
    wire _281;
    wire [7:0] _328;
    wire [7:0] _14;
    reg [7:0] _265;
    wire [7:0] _331;
    wire [7:0] _15;
    reg [7:0] _262;
    wire [7:0] _334;
    wire [7:0] _16;
    reg [7:0] _259;
    wire [7:0] _387;
    wire [6:0] _382;
    wire [7:0] _384;
    wire [6:0] _380;
    wire [7:0] _381;
    wire [7:0] _385;
    wire _373;
    wire _372;
    wire _371;
    wire _370;
    wire [3:0] _374;
    wire [3:0] _369;
    wire [7:0] _375;
    wire [3:0] _367;
    wire [3:0] _365;
    wire [3:0] _364;
    wire [3:0] _363;
    wire [3:0] _362;
    wire [3:0] _361;
    wire [3:0] _360;
    wire [3:0] _359;
    wire [3:0] _358;
    reg [3:0] _366;
    wire [7:0] _368;
    wire [7:0] _376;
    wire [6:0] _355;
    wire [7:0] _356;
    wire [6:0] _353;
    wire [7:0] _354;
    wire [7:0] _357;
    wire _343;
    wire [7:0] _377;
    wire [7:0] _341;
    wire _340;
    wire [7:0] _342;
    wire _339;
    wire [7:0] _378;
    wire _337;
    wire [7:0] _386;
    wire [3:0] _335;
    wire _336;
    wire [7:0] _388;
    wire [7:0] _19;
    wire [7:0] _391;
    wire [7:0] _20;
    reg [7:0] _256;
    reg [7:0] _266;
    wire _280;
    wire _282;
    wire _396;
    wire _395;
    wire _397;
    wire [7:0] _426;
    wire _274;
    wire [7:0] _460;
    wire _393;
    wire [7:0] _461;
    wire [3:0] _51;
    wire _392;
    wire [7:0] _470;
    wire [7:0] _21;
    wire [7:0] _22;
    reg [7:0] _49;
    wire [5:0] _233;
    wire [11:0] _557;
    wire _558;
    wire [5:0] _559;
    wire _279;
    wire _351;
    wire _350;
    wire _349;
    wire _348;
    wire _347;
    wire _346;
    wire _345;
    wire _344;
    wire [2:0] _275;
    reg _352;
    wire _556;
    wire [5:0] _560;
    wire [11:0] _474;
    wire [11:0] _25;
    reg [11:0] _473;
    wire [11:0] _478;
    wire [11:0] _26;
    reg [11:0] _477;
    wire [11:0] _482;
    wire [11:0] _27;
    reg [11:0] _481;
    wire [11:0] _491;
    wire [11:0] _492;
    wire _490;
    wire [11:0] _493;
    wire [3:0] _483;
    wire _484;
    wire [11:0] _495;
    wire [11:0] _28;
    wire [11:0] _496;
    wire [11:0] _29;
    reg [11:0] _487;
    reg [11:0] _488;
    wire _553;
    wire [5:0] _554;
    wire [5:0] _548;
    wire [11:0] _500;
    wire [11:0] _30;
    reg [11:0] _499;
    wire [11:0] _504;
    wire [11:0] _31;
    reg [11:0] _503;
    wire [11:0] _508;
    wire [11:0] _32;
    reg [11:0] _507;
    wire [11:0] _494;
    wire [11:0] _521;
    wire [11:0] _518;
    wire [3:0] _338;
    wire _512;
    wire [11:0] _519;
    wire [3:0] _269;
    wire _511;
    wire [11:0] _522;
    wire [3:0] _509;
    wire _510;
    wire [11:0] _523;
    wire [11:0] _33;
    wire [11:0] _524;
    wire [11:0] _34;
    reg [11:0] _515;
    reg [11:0] _516;
    wire _546;
    wire _547;
    wire [5:0] _549;
    wire [5:0] _543;
    wire [5:0] _540;
    wire _327;
    wire [5:0] _525;
    wire [5:0] _36;
    reg [5:0] _225;
    wire _330;
    wire [5:0] _526;
    wire [5:0] _37;
    reg [5:0] _228;
    wire _333;
    wire [5:0] _527;
    wire [5:0] _38;
    reg [5:0] _231;
    reg [5:0] _539;
    wire [5:0] _541;
    wire [3:0] _537;
    wire _538;
    wire [5:0] _542;
    wire [3:0] _236;
    wire _536;
    wire [5:0] _544;
    wire [3:0] _534;
    wire _535;
    wire [5:0] _550;
    wire [3:0] _532;
    wire _533;
    wire [5:0] _551;
    wire [3:0] _530;
    wire _531;
    wire [5:0] _555;
    wire [3:0] _528;
    wire [3:0] _50;
    wire _529;
    wire [5:0] _561;
    wire [5:0] _40;
    wire _390;
    wire [5:0] _562;
    wire [5:0] _41;
    reg [5:0] _234;
    reg [5:0] _567;
    wire vdd;
    wire [1:0] _564;
    wire [1:0] _44;
    reg [1:0] _253;
    wire [1:0] _566;
    wire [7:0] _568;
    assign _220 = _64[0:0];
    assign _219 = _49[0:0];
    assign _217 = 2'b00;
    assign _218 = _217 < _59;
    assign _221 = _218 ? _220 : _219;
    assign _215 = _64[0:0];
    assign _214 = _49[0:0];
    assign _212 = 2'b01;
    assign _213 = _212 < _59;
    assign _216 = _213 ? _215 : _214;
    assign _210 = _64[0:0];
    assign _209 = _49[0:0];
    assign _207 = 2'b10;
    assign _208 = _207 < _59;
    assign _211 = _208 ? _210 : _209;
    assign _205 = _64[0:0];
    assign _204 = _49[0:0];
    assign _202 = 2'b11;
    assign _203 = _202 < _59;
    assign _206 = _203 ? _205 : _204;
    assign _200 = _64[1:1];
    assign _199 = _49[1:1];
    assign _198 = _217 < _59;
    assign _201 = _198 ? _200 : _199;
    assign _195 = _64[1:1];
    assign _194 = _49[1:1];
    assign _193 = _212 < _59;
    assign _196 = _193 ? _195 : _194;
    assign _190 = _64[1:1];
    assign _189 = _49[1:1];
    assign _188 = _207 < _59;
    assign _191 = _188 ? _190 : _189;
    assign _185 = _64[1:1];
    assign _184 = _49[1:1];
    assign _183 = _202 < _59;
    assign _186 = _183 ? _185 : _184;
    assign _180 = _64[2:2];
    assign _179 = _49[2:2];
    assign _178 = _217 < _59;
    assign _181 = _178 ? _180 : _179;
    assign _175 = _64[2:2];
    assign _174 = _49[2:2];
    assign _173 = _212 < _59;
    assign _176 = _173 ? _175 : _174;
    assign _170 = _64[2:2];
    assign _169 = _49[2:2];
    assign _168 = _207 < _59;
    assign _171 = _168 ? _170 : _169;
    assign _165 = _64[2:2];
    assign _164 = _49[2:2];
    assign _163 = _202 < _59;
    assign _166 = _163 ? _165 : _164;
    assign _160 = _64[3:3];
    assign _159 = _49[3:3];
    assign _158 = _217 < _59;
    assign _161 = _158 ? _160 : _159;
    assign _155 = _64[3:3];
    assign _154 = _49[3:3];
    assign _153 = _212 < _59;
    assign _156 = _153 ? _155 : _154;
    assign _150 = _64[3:3];
    assign _149 = _49[3:3];
    assign _148 = _207 < _59;
    assign _151 = _148 ? _150 : _149;
    assign _145 = _64[3:3];
    assign _144 = _49[3:3];
    assign _143 = _202 < _59;
    assign _146 = _143 ? _145 : _144;
    assign _140 = _64[4:4];
    assign _139 = _49[4:4];
    assign _138 = _217 < _59;
    assign _141 = _138 ? _140 : _139;
    assign _135 = _64[4:4];
    assign _134 = _49[4:4];
    assign _133 = _212 < _59;
    assign _136 = _133 ? _135 : _134;
    assign _130 = _64[4:4];
    assign _129 = _49[4:4];
    assign _128 = _207 < _59;
    assign _131 = _128 ? _130 : _129;
    assign _125 = _64[4:4];
    assign _124 = _49[4:4];
    assign _123 = _202 < _59;
    assign _126 = _123 ? _125 : _124;
    assign _120 = _64[5:5];
    assign _119 = _49[5:5];
    assign _118 = _217 < _59;
    assign _121 = _118 ? _120 : _119;
    assign _115 = _64[5:5];
    assign _114 = _49[5:5];
    assign _113 = _212 < _59;
    assign _116 = _113 ? _115 : _114;
    assign _110 = _64[5:5];
    assign _109 = _49[5:5];
    assign _108 = _207 < _59;
    assign _111 = _108 ? _110 : _109;
    assign _105 = _64[5:5];
    assign _104 = _49[5:5];
    assign _103 = _202 < _59;
    assign _106 = _103 ? _105 : _104;
    assign _100 = _64[6:6];
    assign _99 = _49[6:6];
    assign _98 = _217 < _59;
    assign _101 = _98 ? _100 : _99;
    assign _95 = _64[6:6];
    assign _94 = _49[6:6];
    assign _93 = _212 < _59;
    assign _96 = _93 ? _95 : _94;
    assign _90 = _64[6:6];
    assign _89 = _49[6:6];
    assign _88 = _207 < _59;
    assign _91 = _88 ? _90 : _89;
    assign _85 = _64[6:6];
    assign _84 = _49[6:6];
    assign _83 = _202 < _59;
    assign _86 = _83 ? _85 : _84;
    assign _80 = _64[7:7];
    assign _79 = _49[7:7];
    assign _78 = _217 < _59;
    assign _81 = _78 ? _80 : _79;
    assign _75 = _64[7:7];
    assign _74 = _49[7:7];
    assign _73 = _212 < _59;
    assign _76 = _73 ? _75 : _74;
    assign _70 = _64[7:7];
    assign _69 = _49[7:7];
    assign _68 = _207 < _59;
    assign _71 = _68 ? _70 : _69;
    assign _63 = 8'b00000000;
    assign _1 = _49;
    always @(posedge clock) begin
        if (clear)
            _64 <= _63;
        else
            _64 <= _1;
    end
    assign _65 = _64[7:7];
    assign _61 = _49[7:7];
    assign _54 = imem_data[1:0];
    assign _52 = _50 == _51;
    assign _55 = _52 ? _54 : _217;
    assign _2 = _55;
    assign _3 = _2;
    always @(posedge clock) begin
        if (clear)
            _59 <= _217;
        else
            _59 <= _3;
    end
    assign _60 = _202 < _59;
    assign _66 = _60 ? _65 : _61;
    assign _222 = { _66,
                    _71,
                    _76,
                    _81,
                    _86,
                    _91,
                    _96,
                    _101,
                    _106,
                    _111,
                    _116,
                    _121,
                    _126,
                    _131,
                    _136,
                    _141,
                    _146,
                    _151,
                    _156,
                    _161,
                    _166,
                    _171,
                    _176,
                    _181,
                    _186,
                    _191,
                    _196,
                    _201,
                    _206,
                    _211,
                    _216,
                    _221 };
    assign _235 = { _225,
                    _228,
                    _231,
                    _234 };
    assign _239 = host_in_valid ? vdd : gnd;
    assign _237 = _50 == _236;
    assign _240 = _237 ? _239 : gnd;
    assign _6 = _240;
    assign _245 = 1'b0;
    assign _242 = _50 == _241;
    assign _243 = _242 ? vdd : gnd;
    assign _8 = _243;
    always @(posedge clock) begin
        if (clear)
            _246 <= _245;
        else
            _246 <= _8;
    end
    assign _241 = 4'b1011;
    assign _247 = _50 == _241;
    assign _267 = _247 ? _266 : _250;
    assign _10 = _267;
    always @(posedge clock) begin
        if (clear)
            _250 <= _63;
        else
            _250 <= _10;
    end
    assign _319 = imem_data[2:2];
    assign _320 = { _319,
                    _319 };
    assign _321 = { _320,
                    _320 };
    assign _322 = { _321,
                    _321 };
    assign _323 = _316 & _322;
    assign _317 = ~ _316;
    assign _318 = _273 & _317;
    assign _324 = _318 | _323;
    assign _311 = _273[0:0];
    assign _309 = 3'b000;
    assign _310 = _275 == _309;
    assign _312 = _310 ? _283 : _311;
    assign _307 = _273[1:1];
    assign _305 = 3'b001;
    assign _306 = _275 == _305;
    assign _308 = _306 ? _283 : _307;
    assign _303 = _273[2:2];
    assign _301 = 3'b010;
    assign _302 = _275 == _301;
    assign _304 = _302 ? _283 : _303;
    assign _299 = _273[3:3];
    assign _297 = 3'b011;
    assign _298 = _275 == _297;
    assign _300 = _298 ? _283 : _299;
    assign _295 = _273[4:4];
    assign _293 = 3'b100;
    assign _294 = _275 == _293;
    assign _296 = _294 ? _283 : _295;
    assign _291 = _273[5:5];
    assign _289 = 3'b101;
    assign _290 = _275 == _289;
    assign _292 = _290 ? _283 : _291;
    assign _287 = _273[6:6];
    assign _285 = 3'b110;
    assign _286 = _275 == _285;
    assign _288 = _286 ? _283 : _287;
    assign _283 = ~ _282;
    assign _278 = _273[7:7];
    assign _276 = 3'b111;
    assign _277 = _275 == _276;
    assign _284 = _277 ? _283 : _278;
    assign _313 = { _284,
                    _288,
                    _292,
                    _296,
                    _300,
                    _304,
                    _308,
                    _312 };
    assign _314 = _274 ? _313 : _273;
    assign _270 = _50 == _269;
    assign _315 = _270 ? _314 : _273;
    assign _268 = _50 == _51;
    assign _325 = _268 ? _324 : _315;
    assign _12 = _325;
    always @(posedge clock) begin
        if (clear)
            _273 <= _63;
        else
            _273 <= _12;
    end
    assign _464 = imem_data[3:3];
    assign _465 = { _464,
                    _464 };
    assign _466 = { _465,
                    _465 };
    assign _467 = { _466,
                    _466 };
    assign _468 = _316 & _467;
    assign _316 = imem_data[11:4];
    assign _462 = ~ _316;
    assign _463 = _49 & _462;
    assign _469 = _463 | _468;
    assign _457 = _49[0:0];
    assign _456 = _275 == _309;
    assign _458 = _456 ? gnd : _457;
    assign _453 = _49[1:1];
    assign _452 = _275 == _305;
    assign _454 = _452 ? gnd : _453;
    assign _449 = _49[2:2];
    assign _448 = _275 == _301;
    assign _450 = _448 ? gnd : _449;
    assign _445 = _49[3:3];
    assign _444 = _275 == _297;
    assign _446 = _444 ? gnd : _445;
    assign _441 = _49[4:4];
    assign _440 = _275 == _293;
    assign _442 = _440 ? gnd : _441;
    assign _437 = _49[5:5];
    assign _436 = _275 == _289;
    assign _438 = _436 ? gnd : _437;
    assign _433 = _49[6:6];
    assign _432 = _275 == _285;
    assign _434 = _432 ? gnd : _433;
    assign gnd = 1'b0;
    assign _429 = _49[7:7];
    assign _428 = _275 == _276;
    assign _430 = _428 ? gnd : _429;
    assign _459 = { _430,
                    _434,
                    _438,
                    _442,
                    _446,
                    _450,
                    _454,
                    _458 };
    assign _424 = _49[0:0];
    assign _423 = _275 == _309;
    assign _425 = _423 ? _282 : _424;
    assign _420 = _49[1:1];
    assign _419 = _275 == _305;
    assign _421 = _419 ? _282 : _420;
    assign _416 = _49[2:2];
    assign _415 = _275 == _301;
    assign _417 = _415 ? _282 : _416;
    assign _412 = _49[3:3];
    assign _411 = _275 == _297;
    assign _413 = _411 ? _282 : _412;
    assign _408 = _49[4:4];
    assign _407 = _275 == _293;
    assign _409 = _407 ? _282 : _408;
    assign _404 = _49[5:5];
    assign _403 = _275 == _289;
    assign _405 = _403 ? _282 : _404;
    assign _400 = _49[6:6];
    assign _399 = _275 == _285;
    assign _401 = _399 ? _282 : _400;
    assign _281 = _266[7:7];
    assign _328 = _327 ? _19 : _265;
    assign _14 = _328;
    always @(posedge clock) begin
        if (clear)
            _265 <= _63;
        else
            _265 <= _14;
    end
    assign _331 = _330 ? _19 : _262;
    assign _15 = _331;
    always @(posedge clock) begin
        if (clear)
            _262 <= _63;
        else
            _262 <= _15;
    end
    assign _334 = _333 ? _19 : _259;
    assign _16 = _334;
    always @(posedge clock) begin
        if (clear)
            _259 <= _63;
        else
            _259 <= _16;
    end
    assign _387 = imem_data[7:0];
    assign _382 = _266[6:0];
    assign _384 = { _382,
                    _245 };
    assign _380 = _266[7:1];
    assign _381 = { _245,
                    _380 };
    assign _385 = _279 ? _384 : _381;
    assign _373 = _366[3:3];
    assign _372 = _366[2:2];
    assign _371 = _366[1:1];
    assign _370 = _366[0:0];
    assign _374 = { _370,
                    _371,
                    _372,
                    _373 };
    assign _369 = _266[3:0];
    assign _375 = { _369,
                    _374 };
    assign _367 = _266[7:4];
    assign _365 = pin_in4[31:28];
    assign _364 = pin_in4[27:24];
    assign _363 = pin_in4[23:20];
    assign _362 = pin_in4[19:16];
    assign _361 = pin_in4[15:12];
    assign _360 = pin_in4[11:8];
    assign _359 = pin_in4[7:4];
    assign _358 = pin_in4[3:0];
    always @* begin
        case (_275)
        0:
            _366 <= _358;
        1:
            _366 <= _359;
        2:
            _366 <= _360;
        3:
            _366 <= _361;
        4:
            _366 <= _362;
        5:
            _366 <= _363;
        6:
            _366 <= _364;
        default:
            _366 <= _365;
        endcase
    end
    assign _368 = { _366,
                    _367 };
    assign _376 = _279 ? _375 : _368;
    assign _355 = _266[6:0];
    assign _356 = { _355,
                    _352 };
    assign _353 = _266[7:1];
    assign _354 = { _352,
                    _353 };
    assign _357 = _279 ? _356 : _354;
    assign _343 = imem_data[7:7];
    assign _377 = _343 ? _376 : _357;
    assign _341 = host_in_valid ? host_in : _266;
    assign _340 = _50 == _236;
    assign _342 = _340 ? _341 : _266;
    assign _339 = _50 == _338;
    assign _378 = _339 ? _377 : _342;
    assign _337 = _50 == _269;
    assign _386 = _337 ? _385 : _378;
    assign _335 = 4'b0100;
    assign _336 = _50 == _335;
    assign _388 = _336 ? _387 : _386;
    assign _19 = _388;
    assign _391 = _390 ? _19 : _256;
    assign _20 = _391;
    always @(posedge clock) begin
        if (clear)
            _256 <= _63;
        else
            _256 <= _20;
    end
    always @* begin
        case (_253)
        0:
            _266 <= _256;
        1:
            _266 <= _259;
        2:
            _266 <= _262;
        default:
            _266 <= _265;
        endcase
    end
    assign _280 = _266[0:0];
    assign _282 = _279 ? _281 : _280;
    assign _396 = _49[7:7];
    assign _395 = _275 == _276;
    assign _397 = _395 ? _282 : _396;
    assign _426 = { _397,
                    _401,
                    _405,
                    _409,
                    _413,
                    _417,
                    _421,
                    _425 };
    assign _274 = imem_data[7:7];
    assign _460 = _274 ? _459 : _426;
    assign _393 = _50 == _269;
    assign _461 = _393 ? _460 : _49;
    assign _51 = 4'b0001;
    assign _392 = _50 == _51;
    assign _470 = _392 ? _469 : _461;
    assign _21 = _470;
    assign _22 = _21;
    always @(posedge clock) begin
        if (clear)
            _49 <= _63;
        else
            _49 <= _22;
    end
    assign _233 = 6'b000000;
    assign _557 = 12'b000000000000;
    assign _558 = _488 == _557;
    assign _559 = _558 ? _548 : _539;
    assign _279 = imem_data[8:8];
    assign _351 = pin_in[7:7];
    assign _350 = pin_in[6:6];
    assign _349 = pin_in[5:5];
    assign _348 = pin_in[4:4];
    assign _347 = pin_in[3:3];
    assign _346 = pin_in[2:2];
    assign _345 = pin_in[1:1];
    assign _344 = pin_in[0:0];
    assign _275 = imem_data[11:9];
    always @* begin
        case (_275)
        0:
            _352 <= _344;
        1:
            _352 <= _345;
        2:
            _352 <= _346;
        3:
            _352 <= _347;
        4:
            _352 <= _348;
        5:
            _352 <= _349;
        6:
            _352 <= _350;
        default:
            _352 <= _351;
        endcase
    end
    assign _556 = _352 == _279;
    assign _560 = _556 ? _541 : _559;
    assign _474 = _327 ? _28 : _473;
    assign _25 = _474;
    always @(posedge clock) begin
        if (clear)
            _473 <= _557;
        else
            _473 <= _25;
    end
    assign _478 = _330 ? _28 : _477;
    assign _26 = _478;
    always @(posedge clock) begin
        if (clear)
            _477 <= _557;
        else
            _477 <= _26;
    end
    assign _482 = _333 ? _28 : _481;
    assign _27 = _482;
    always @(posedge clock) begin
        if (clear)
            _481 <= _557;
        else
            _481 <= _27;
    end
    assign _491 = 12'b000000000001;
    assign _492 = _488 - _491;
    assign _490 = _488 == _557;
    assign _493 = _490 ? _488 : _492;
    assign _483 = 4'b0011;
    assign _484 = _50 == _483;
    assign _495 = _484 ? _494 : _493;
    assign _28 = _495;
    assign _496 = _390 ? _28 : _487;
    assign _29 = _496;
    always @(posedge clock) begin
        if (clear)
            _487 <= _557;
        else
            _487 <= _29;
    end
    always @* begin
        case (_253)
        0:
            _488 <= _487;
        1:
            _488 <= _481;
        2:
            _488 <= _477;
        default:
            _488 <= _473;
        endcase
    end
    assign _553 = _488 == _557;
    assign _554 = _553 ? _541 : _539;
    assign _548 = imem_data[5:0];
    assign _500 = _327 ? _33 : _499;
    assign _30 = _500;
    always @(posedge clock) begin
        if (clear)
            _499 <= _557;
        else
            _499 <= _30;
    end
    assign _504 = _330 ? _33 : _503;
    assign _31 = _504;
    always @(posedge clock) begin
        if (clear)
            _503 <= _557;
        else
            _503 <= _31;
    end
    assign _508 = _333 ? _33 : _507;
    assign _32 = _508;
    always @(posedge clock) begin
        if (clear)
            _507 <= _557;
        else
            _507 <= _32;
    end
    assign _494 = imem_data[11:0];
    assign _521 = _516 - _491;
    assign _518 = _516 - _491;
    assign _338 = 4'b1000;
    assign _512 = _50 == _338;
    assign _519 = _512 ? _518 : _516;
    assign _269 = 4'b0111;
    assign _511 = _50 == _269;
    assign _522 = _511 ? _521 : _519;
    assign _509 = 4'b0010;
    assign _510 = _50 == _509;
    assign _523 = _510 ? _494 : _522;
    assign _33 = _523;
    assign _524 = _390 ? _33 : _515;
    assign _34 = _524;
    always @(posedge clock) begin
        if (clear)
            _515 <= _557;
        else
            _515 <= _34;
    end
    always @* begin
        case (_253)
        0:
            _516 <= _515;
        1:
            _516 <= _507;
        2:
            _516 <= _503;
        default:
            _516 <= _499;
        endcase
    end
    assign _546 = _516 == _557;
    assign _547 = ~ _546;
    assign _549 = _547 ? _548 : _541;
    assign _543 = host_in_valid ? _541 : _539;
    assign _540 = 6'b000001;
    assign _327 = _253 == _202;
    assign _525 = _327 ? _40 : _225;
    assign _36 = _525;
    always @(posedge clock) begin
        if (clear)
            _225 <= _233;
        else
            _225 <= _36;
    end
    assign _330 = _253 == _207;
    assign _526 = _330 ? _40 : _228;
    assign _37 = _526;
    always @(posedge clock) begin
        if (clear)
            _228 <= _233;
        else
            _228 <= _37;
    end
    assign _333 = _253 == _212;
    assign _527 = _333 ? _40 : _231;
    assign _38 = _527;
    always @(posedge clock) begin
        if (clear)
            _231 <= _233;
        else
            _231 <= _38;
    end
    always @* begin
        case (_253)
        0:
            _539 <= _234;
        1:
            _539 <= _231;
        2:
            _539 <= _228;
        default:
            _539 <= _225;
        endcase
    end
    assign _541 = _539 + _540;
    assign _537 = 4'b1101;
    assign _538 = _50 == _537;
    assign _542 = _538 ? _539 : _541;
    assign _236 = 4'b1100;
    assign _536 = _50 == _236;
    assign _544 = _536 ? _543 : _542;
    assign _534 = 4'b1010;
    assign _535 = _50 == _534;
    assign _550 = _535 ? _549 : _544;
    assign _532 = 4'b1001;
    assign _533 = _50 == _532;
    assign _551 = _533 ? _548 : _550;
    assign _530 = 4'b0110;
    assign _531 = _50 == _530;
    assign _555 = _531 ? _554 : _551;
    assign _528 = 4'b0101;
    assign _50 = imem_data[15:12];
    assign _529 = _50 == _528;
    assign _561 = _529 ? _560 : _555;
    assign _40 = _561;
    assign _390 = _253 == _217;
    assign _562 = _390 ? _40 : _234;
    assign _41 = _562;
    always @(posedge clock) begin
        if (clear)
            _234 <= _233;
        else
            _234 <= _41;
    end
    always @* begin
        case (_566)
        0:
            _567 <= _234;
        1:
            _567 <= _231;
        2:
            _567 <= _228;
        default:
            _567 <= _225;
        endcase
    end
    assign vdd = 1'b1;
    assign _564 = _253 + _212;
    assign _44 = _564;
    always @(posedge clock) begin
        if (clear)
            _253 <= _217;
        else
            _253 <= _44;
    end
    assign _566 = _253 + _212;
    assign _568 = { _566,
                    _567 };
    assign imem_addr = _568;
    assign pin_out = _49;
    assign pin_oe = _273;
    assign host_out = _250;
    assign host_out_valid = _246;
    assign host_in_ready = _6;
    assign pcs = _235;
    assign pin_sub = _222;

endmodule
