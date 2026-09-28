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

    wire _225;
    wire _224;
    wire [1:0] _222;
    wire _223;
    wire _226;
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
    wire [7:0] _68;
    wire [7:0] _1;
    reg [7:0] _69;
    wire _70;
    wire _66;
    wire [1:0] _57;
    wire [1:0] _58;
    wire _54;
    wire [1:0] _59;
    wire _52;
    wire [1:0] _60;
    wire [1:0] _2;
    wire [1:0] _3;
    reg [1:0] _64;
    wire _65;
    wire _71;
    wire [31:0] _227;
    wire [23:0] _240;
    wire _244;
    wire _242;
    wire _245;
    wire _6;
    wire _250;
    wire _247;
    wire _248;
    wire _8;
    reg _251;
    wire [3:0] _246;
    wire _252;
    wire [7:0] _272;
    wire [7:0] _10;
    reg [7:0] _255;
    wire _322;
    wire [1:0] _323;
    wire [3:0] _324;
    wire [7:0] _325;
    wire [7:0] _326;
    wire [7:0] _320;
    wire [7:0] _321;
    wire [7:0] _327;
    wire _314;
    wire [2:0] _312;
    wire _313;
    wire _315;
    wire _310;
    wire [2:0] _308;
    wire _309;
    wire _311;
    wire _306;
    wire [2:0] _304;
    wire _305;
    wire _307;
    wire _302;
    wire [2:0] _300;
    wire _301;
    wire _303;
    wire _298;
    wire [2:0] _296;
    wire _297;
    wire _299;
    wire _294;
    wire [2:0] _292;
    wire _293;
    wire _295;
    wire _290;
    wire [2:0] _288;
    wire _289;
    wire _291;
    wire _286;
    wire _281;
    wire [2:0] _279;
    wire _280;
    wire _287;
    wire [7:0] _316;
    wire [7:0] _317;
    wire _274;
    wire [7:0] _318;
    wire _273;
    wire [7:0] _328;
    wire [7:0] _12;
    reg [7:0] _277;
    wire _467;
    wire [1:0] _468;
    wire [3:0] _469;
    wire [7:0] _470;
    wire [7:0] _471;
    wire [7:0] _319;
    wire [7:0] _465;
    wire [7:0] _466;
    wire [7:0] _472;
    wire _460;
    wire _459;
    wire _461;
    wire _456;
    wire _455;
    wire _457;
    wire _452;
    wire _451;
    wire _453;
    wire _448;
    wire _447;
    wire _449;
    wire _444;
    wire _443;
    wire _445;
    wire _440;
    wire _439;
    wire _441;
    wire _436;
    wire _435;
    wire _437;
    wire gnd;
    wire _432;
    wire _431;
    wire _433;
    wire [7:0] _462;
    wire _427;
    wire _426;
    wire _428;
    wire _423;
    wire _422;
    wire _424;
    wire _419;
    wire _418;
    wire _420;
    wire _415;
    wire _414;
    wire _416;
    wire _411;
    wire _410;
    wire _412;
    wire _407;
    wire _406;
    wire _408;
    wire _403;
    wire _402;
    wire _404;
    wire _284;
    wire [7:0] _331;
    wire [7:0] _14;
    reg [7:0] _270;
    wire [7:0] _334;
    wire [7:0] _15;
    reg [7:0] _267;
    wire [7:0] _337;
    wire [7:0] _16;
    reg [7:0] _264;
    wire [7:0] _390;
    wire [6:0] _385;
    wire [7:0] _387;
    wire [6:0] _383;
    wire [7:0] _384;
    wire [7:0] _388;
    wire _376;
    wire _375;
    wire _374;
    wire _373;
    wire [3:0] _377;
    wire [3:0] _372;
    wire [7:0] _378;
    wire [3:0] _370;
    wire [3:0] _368;
    wire [3:0] _367;
    wire [3:0] _366;
    wire [3:0] _365;
    wire [3:0] _364;
    wire [3:0] _363;
    wire [3:0] _362;
    wire [3:0] _361;
    reg [3:0] _369;
    wire [7:0] _371;
    wire [7:0] _379;
    wire [6:0] _358;
    wire [7:0] _359;
    wire [6:0] _356;
    wire [7:0] _357;
    wire [7:0] _360;
    wire _346;
    wire [7:0] _380;
    wire [7:0] _344;
    wire _343;
    wire [7:0] _345;
    wire _342;
    wire [7:0] _381;
    wire _340;
    wire [7:0] _389;
    wire [3:0] _338;
    wire _339;
    wire [7:0] _391;
    wire [7:0] _19;
    wire [7:0] _394;
    wire [7:0] _20;
    reg [7:0] _261;
    reg [7:0] _271;
    wire _283;
    wire _285;
    wire _399;
    wire _398;
    wire _400;
    wire [7:0] _429;
    wire _56;
    wire [7:0] _463;
    wire _396;
    wire [7:0] _464;
    wire [3:0] _51;
    wire _395;
    wire [7:0] _473;
    wire [7:0] _21;
    wire [7:0] _22;
    reg [7:0] _49;
    wire [5:0] _238;
    wire [11:0] _560;
    wire _561;
    wire [5:0] _562;
    wire _282;
    wire _354;
    wire _353;
    wire _352;
    wire _351;
    wire _350;
    wire _349;
    wire _348;
    wire _347;
    wire [2:0] _278;
    reg _355;
    wire _559;
    wire [5:0] _563;
    wire [11:0] _477;
    wire [11:0] _25;
    reg [11:0] _476;
    wire [11:0] _481;
    wire [11:0] _26;
    reg [11:0] _480;
    wire [11:0] _485;
    wire [11:0] _27;
    reg [11:0] _484;
    wire [11:0] _494;
    wire [11:0] _495;
    wire _493;
    wire [11:0] _496;
    wire [3:0] _486;
    wire _487;
    wire [11:0] _498;
    wire [11:0] _28;
    wire [11:0] _499;
    wire [11:0] _29;
    reg [11:0] _490;
    reg [11:0] _491;
    wire _556;
    wire [5:0] _557;
    wire [5:0] _551;
    wire [11:0] _503;
    wire [11:0] _30;
    reg [11:0] _502;
    wire [11:0] _507;
    wire [11:0] _31;
    reg [11:0] _506;
    wire [11:0] _511;
    wire [11:0] _32;
    reg [11:0] _510;
    wire [11:0] _497;
    wire [11:0] _524;
    wire [11:0] _521;
    wire [3:0] _341;
    wire _515;
    wire [11:0] _522;
    wire [3:0] _53;
    wire _514;
    wire [11:0] _525;
    wire [3:0] _512;
    wire _513;
    wire [11:0] _526;
    wire [11:0] _33;
    wire [11:0] _527;
    wire [11:0] _34;
    reg [11:0] _518;
    reg [11:0] _519;
    wire _549;
    wire _550;
    wire [5:0] _552;
    wire [5:0] _546;
    wire [5:0] _543;
    wire _330;
    wire [5:0] _528;
    wire [5:0] _36;
    reg [5:0] _230;
    wire _333;
    wire [5:0] _529;
    wire [5:0] _37;
    reg [5:0] _233;
    wire _336;
    wire [5:0] _530;
    wire [5:0] _38;
    reg [5:0] _236;
    reg [5:0] _542;
    wire [5:0] _544;
    wire [3:0] _540;
    wire _541;
    wire [5:0] _545;
    wire [3:0] _241;
    wire _539;
    wire [5:0] _547;
    wire [3:0] _537;
    wire _538;
    wire [5:0] _553;
    wire [3:0] _535;
    wire _536;
    wire [5:0] _554;
    wire [3:0] _533;
    wire _534;
    wire [5:0] _558;
    wire [3:0] _531;
    wire [3:0] _50;
    wire _532;
    wire [5:0] _564;
    wire [5:0] _40;
    wire _393;
    wire [5:0] _565;
    wire [5:0] _41;
    reg [5:0] _239;
    reg [5:0] _570;
    wire vdd;
    wire [1:0] _567;
    wire [1:0] _44;
    reg [1:0] _258;
    wire [1:0] _569;
    wire [7:0] _571;
    assign _225 = _69[0:0];
    assign _224 = _49[0:0];
    assign _222 = 2'b00;
    assign _223 = _222 < _64;
    assign _226 = _223 ? _225 : _224;
    assign _220 = _69[0:0];
    assign _219 = _49[0:0];
    assign _217 = 2'b01;
    assign _218 = _217 < _64;
    assign _221 = _218 ? _220 : _219;
    assign _215 = _69[0:0];
    assign _214 = _49[0:0];
    assign _212 = 2'b10;
    assign _213 = _212 < _64;
    assign _216 = _213 ? _215 : _214;
    assign _210 = _69[0:0];
    assign _209 = _49[0:0];
    assign _207 = 2'b11;
    assign _208 = _207 < _64;
    assign _211 = _208 ? _210 : _209;
    assign _205 = _69[1:1];
    assign _204 = _49[1:1];
    assign _203 = _222 < _64;
    assign _206 = _203 ? _205 : _204;
    assign _200 = _69[1:1];
    assign _199 = _49[1:1];
    assign _198 = _217 < _64;
    assign _201 = _198 ? _200 : _199;
    assign _195 = _69[1:1];
    assign _194 = _49[1:1];
    assign _193 = _212 < _64;
    assign _196 = _193 ? _195 : _194;
    assign _190 = _69[1:1];
    assign _189 = _49[1:1];
    assign _188 = _207 < _64;
    assign _191 = _188 ? _190 : _189;
    assign _185 = _69[2:2];
    assign _184 = _49[2:2];
    assign _183 = _222 < _64;
    assign _186 = _183 ? _185 : _184;
    assign _180 = _69[2:2];
    assign _179 = _49[2:2];
    assign _178 = _217 < _64;
    assign _181 = _178 ? _180 : _179;
    assign _175 = _69[2:2];
    assign _174 = _49[2:2];
    assign _173 = _212 < _64;
    assign _176 = _173 ? _175 : _174;
    assign _170 = _69[2:2];
    assign _169 = _49[2:2];
    assign _168 = _207 < _64;
    assign _171 = _168 ? _170 : _169;
    assign _165 = _69[3:3];
    assign _164 = _49[3:3];
    assign _163 = _222 < _64;
    assign _166 = _163 ? _165 : _164;
    assign _160 = _69[3:3];
    assign _159 = _49[3:3];
    assign _158 = _217 < _64;
    assign _161 = _158 ? _160 : _159;
    assign _155 = _69[3:3];
    assign _154 = _49[3:3];
    assign _153 = _212 < _64;
    assign _156 = _153 ? _155 : _154;
    assign _150 = _69[3:3];
    assign _149 = _49[3:3];
    assign _148 = _207 < _64;
    assign _151 = _148 ? _150 : _149;
    assign _145 = _69[4:4];
    assign _144 = _49[4:4];
    assign _143 = _222 < _64;
    assign _146 = _143 ? _145 : _144;
    assign _140 = _69[4:4];
    assign _139 = _49[4:4];
    assign _138 = _217 < _64;
    assign _141 = _138 ? _140 : _139;
    assign _135 = _69[4:4];
    assign _134 = _49[4:4];
    assign _133 = _212 < _64;
    assign _136 = _133 ? _135 : _134;
    assign _130 = _69[4:4];
    assign _129 = _49[4:4];
    assign _128 = _207 < _64;
    assign _131 = _128 ? _130 : _129;
    assign _125 = _69[5:5];
    assign _124 = _49[5:5];
    assign _123 = _222 < _64;
    assign _126 = _123 ? _125 : _124;
    assign _120 = _69[5:5];
    assign _119 = _49[5:5];
    assign _118 = _217 < _64;
    assign _121 = _118 ? _120 : _119;
    assign _115 = _69[5:5];
    assign _114 = _49[5:5];
    assign _113 = _212 < _64;
    assign _116 = _113 ? _115 : _114;
    assign _110 = _69[5:5];
    assign _109 = _49[5:5];
    assign _108 = _207 < _64;
    assign _111 = _108 ? _110 : _109;
    assign _105 = _69[6:6];
    assign _104 = _49[6:6];
    assign _103 = _222 < _64;
    assign _106 = _103 ? _105 : _104;
    assign _100 = _69[6:6];
    assign _99 = _49[6:6];
    assign _98 = _217 < _64;
    assign _101 = _98 ? _100 : _99;
    assign _95 = _69[6:6];
    assign _94 = _49[6:6];
    assign _93 = _212 < _64;
    assign _96 = _93 ? _95 : _94;
    assign _90 = _69[6:6];
    assign _89 = _49[6:6];
    assign _88 = _207 < _64;
    assign _91 = _88 ? _90 : _89;
    assign _85 = _69[7:7];
    assign _84 = _49[7:7];
    assign _83 = _222 < _64;
    assign _86 = _83 ? _85 : _84;
    assign _80 = _69[7:7];
    assign _79 = _49[7:7];
    assign _78 = _217 < _64;
    assign _81 = _78 ? _80 : _79;
    assign _75 = _69[7:7];
    assign _74 = _49[7:7];
    assign _73 = _212 < _64;
    assign _76 = _73 ? _75 : _74;
    assign _68 = 8'b00000000;
    assign _1 = _49;
    always @(posedge clock) begin
        if (clear)
            _69 <= _68;
        else
            _69 <= _1;
    end
    assign _70 = _69[7:7];
    assign _66 = _49[7:7];
    assign _57 = imem_data[1:0];
    assign _58 = _56 ? _222 : _57;
    assign _54 = _50 == _53;
    assign _59 = _54 ? _58 : _222;
    assign _52 = _50 == _51;
    assign _60 = _52 ? _57 : _59;
    assign _2 = _60;
    assign _3 = _2;
    always @(posedge clock) begin
        if (clear)
            _64 <= _222;
        else
            _64 <= _3;
    end
    assign _65 = _207 < _64;
    assign _71 = _65 ? _70 : _66;
    assign _227 = { _71,
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
                    _221,
                    _226 };
    assign _240 = { _230,
                    _233,
                    _236,
                    _239 };
    assign _244 = host_in_valid ? vdd : gnd;
    assign _242 = _50 == _241;
    assign _245 = _242 ? _244 : gnd;
    assign _6 = _245;
    assign _250 = 1'b0;
    assign _247 = _50 == _246;
    assign _248 = _247 ? vdd : gnd;
    assign _8 = _248;
    always @(posedge clock) begin
        if (clear)
            _251 <= _250;
        else
            _251 <= _8;
    end
    assign _246 = 4'b1011;
    assign _252 = _50 == _246;
    assign _272 = _252 ? _271 : _255;
    assign _10 = _272;
    always @(posedge clock) begin
        if (clear)
            _255 <= _68;
        else
            _255 <= _10;
    end
    assign _322 = imem_data[2:2];
    assign _323 = { _322,
                    _322 };
    assign _324 = { _323,
                    _323 };
    assign _325 = { _324,
                    _324 };
    assign _326 = _319 & _325;
    assign _320 = ~ _319;
    assign _321 = _277 & _320;
    assign _327 = _321 | _326;
    assign _314 = _277[0:0];
    assign _312 = 3'b000;
    assign _313 = _278 == _312;
    assign _315 = _313 ? _286 : _314;
    assign _310 = _277[1:1];
    assign _308 = 3'b001;
    assign _309 = _278 == _308;
    assign _311 = _309 ? _286 : _310;
    assign _306 = _277[2:2];
    assign _304 = 3'b010;
    assign _305 = _278 == _304;
    assign _307 = _305 ? _286 : _306;
    assign _302 = _277[3:3];
    assign _300 = 3'b011;
    assign _301 = _278 == _300;
    assign _303 = _301 ? _286 : _302;
    assign _298 = _277[4:4];
    assign _296 = 3'b100;
    assign _297 = _278 == _296;
    assign _299 = _297 ? _286 : _298;
    assign _294 = _277[5:5];
    assign _292 = 3'b101;
    assign _293 = _278 == _292;
    assign _295 = _293 ? _286 : _294;
    assign _290 = _277[6:6];
    assign _288 = 3'b110;
    assign _289 = _278 == _288;
    assign _291 = _289 ? _286 : _290;
    assign _286 = ~ _285;
    assign _281 = _277[7:7];
    assign _279 = 3'b111;
    assign _280 = _278 == _279;
    assign _287 = _280 ? _286 : _281;
    assign _316 = { _287,
                    _291,
                    _295,
                    _299,
                    _303,
                    _307,
                    _311,
                    _315 };
    assign _317 = _56 ? _316 : _277;
    assign _274 = _50 == _53;
    assign _318 = _274 ? _317 : _277;
    assign _273 = _50 == _51;
    assign _328 = _273 ? _327 : _318;
    assign _12 = _328;
    always @(posedge clock) begin
        if (clear)
            _277 <= _68;
        else
            _277 <= _12;
    end
    assign _467 = imem_data[3:3];
    assign _468 = { _467,
                    _467 };
    assign _469 = { _468,
                    _468 };
    assign _470 = { _469,
                    _469 };
    assign _471 = _319 & _470;
    assign _319 = imem_data[11:4];
    assign _465 = ~ _319;
    assign _466 = _49 & _465;
    assign _472 = _466 | _471;
    assign _460 = _49[0:0];
    assign _459 = _278 == _312;
    assign _461 = _459 ? gnd : _460;
    assign _456 = _49[1:1];
    assign _455 = _278 == _308;
    assign _457 = _455 ? gnd : _456;
    assign _452 = _49[2:2];
    assign _451 = _278 == _304;
    assign _453 = _451 ? gnd : _452;
    assign _448 = _49[3:3];
    assign _447 = _278 == _300;
    assign _449 = _447 ? gnd : _448;
    assign _444 = _49[4:4];
    assign _443 = _278 == _296;
    assign _445 = _443 ? gnd : _444;
    assign _440 = _49[5:5];
    assign _439 = _278 == _292;
    assign _441 = _439 ? gnd : _440;
    assign _436 = _49[6:6];
    assign _435 = _278 == _288;
    assign _437 = _435 ? gnd : _436;
    assign gnd = 1'b0;
    assign _432 = _49[7:7];
    assign _431 = _278 == _279;
    assign _433 = _431 ? gnd : _432;
    assign _462 = { _433,
                    _437,
                    _441,
                    _445,
                    _449,
                    _453,
                    _457,
                    _461 };
    assign _427 = _49[0:0];
    assign _426 = _278 == _312;
    assign _428 = _426 ? _285 : _427;
    assign _423 = _49[1:1];
    assign _422 = _278 == _308;
    assign _424 = _422 ? _285 : _423;
    assign _419 = _49[2:2];
    assign _418 = _278 == _304;
    assign _420 = _418 ? _285 : _419;
    assign _415 = _49[3:3];
    assign _414 = _278 == _300;
    assign _416 = _414 ? _285 : _415;
    assign _411 = _49[4:4];
    assign _410 = _278 == _296;
    assign _412 = _410 ? _285 : _411;
    assign _407 = _49[5:5];
    assign _406 = _278 == _292;
    assign _408 = _406 ? _285 : _407;
    assign _403 = _49[6:6];
    assign _402 = _278 == _288;
    assign _404 = _402 ? _285 : _403;
    assign _284 = _271[7:7];
    assign _331 = _330 ? _19 : _270;
    assign _14 = _331;
    always @(posedge clock) begin
        if (clear)
            _270 <= _68;
        else
            _270 <= _14;
    end
    assign _334 = _333 ? _19 : _267;
    assign _15 = _334;
    always @(posedge clock) begin
        if (clear)
            _267 <= _68;
        else
            _267 <= _15;
    end
    assign _337 = _336 ? _19 : _264;
    assign _16 = _337;
    always @(posedge clock) begin
        if (clear)
            _264 <= _68;
        else
            _264 <= _16;
    end
    assign _390 = imem_data[7:0];
    assign _385 = _271[6:0];
    assign _387 = { _385,
                    _250 };
    assign _383 = _271[7:1];
    assign _384 = { _250,
                    _383 };
    assign _388 = _282 ? _387 : _384;
    assign _376 = _369[3:3];
    assign _375 = _369[2:2];
    assign _374 = _369[1:1];
    assign _373 = _369[0:0];
    assign _377 = { _373,
                    _374,
                    _375,
                    _376 };
    assign _372 = _271[3:0];
    assign _378 = { _372,
                    _377 };
    assign _370 = _271[7:4];
    assign _368 = pin_in4[31:28];
    assign _367 = pin_in4[27:24];
    assign _366 = pin_in4[23:20];
    assign _365 = pin_in4[19:16];
    assign _364 = pin_in4[15:12];
    assign _363 = pin_in4[11:8];
    assign _362 = pin_in4[7:4];
    assign _361 = pin_in4[3:0];
    always @* begin
        case (_278)
        0:
            _369 <= _361;
        1:
            _369 <= _362;
        2:
            _369 <= _363;
        3:
            _369 <= _364;
        4:
            _369 <= _365;
        5:
            _369 <= _366;
        6:
            _369 <= _367;
        default:
            _369 <= _368;
        endcase
    end
    assign _371 = { _369,
                    _370 };
    assign _379 = _282 ? _378 : _371;
    assign _358 = _271[6:0];
    assign _359 = { _358,
                    _355 };
    assign _356 = _271[7:1];
    assign _357 = { _355,
                    _356 };
    assign _360 = _282 ? _359 : _357;
    assign _346 = imem_data[7:7];
    assign _380 = _346 ? _379 : _360;
    assign _344 = host_in_valid ? host_in : _271;
    assign _343 = _50 == _241;
    assign _345 = _343 ? _344 : _271;
    assign _342 = _50 == _341;
    assign _381 = _342 ? _380 : _345;
    assign _340 = _50 == _53;
    assign _389 = _340 ? _388 : _381;
    assign _338 = 4'b0100;
    assign _339 = _50 == _338;
    assign _391 = _339 ? _390 : _389;
    assign _19 = _391;
    assign _394 = _393 ? _19 : _261;
    assign _20 = _394;
    always @(posedge clock) begin
        if (clear)
            _261 <= _68;
        else
            _261 <= _20;
    end
    always @* begin
        case (_258)
        0:
            _271 <= _261;
        1:
            _271 <= _264;
        2:
            _271 <= _267;
        default:
            _271 <= _270;
        endcase
    end
    assign _283 = _271[0:0];
    assign _285 = _282 ? _284 : _283;
    assign _399 = _49[7:7];
    assign _398 = _278 == _279;
    assign _400 = _398 ? _285 : _399;
    assign _429 = { _400,
                    _404,
                    _408,
                    _412,
                    _416,
                    _420,
                    _424,
                    _428 };
    assign _56 = imem_data[7:7];
    assign _463 = _56 ? _462 : _429;
    assign _396 = _50 == _53;
    assign _464 = _396 ? _463 : _49;
    assign _51 = 4'b0001;
    assign _395 = _50 == _51;
    assign _473 = _395 ? _472 : _464;
    assign _21 = _473;
    assign _22 = _21;
    always @(posedge clock) begin
        if (clear)
            _49 <= _68;
        else
            _49 <= _22;
    end
    assign _238 = 6'b000000;
    assign _560 = 12'b000000000000;
    assign _561 = _491 == _560;
    assign _562 = _561 ? _551 : _542;
    assign _282 = imem_data[8:8];
    assign _354 = pin_in[7:7];
    assign _353 = pin_in[6:6];
    assign _352 = pin_in[5:5];
    assign _351 = pin_in[4:4];
    assign _350 = pin_in[3:3];
    assign _349 = pin_in[2:2];
    assign _348 = pin_in[1:1];
    assign _347 = pin_in[0:0];
    assign _278 = imem_data[11:9];
    always @* begin
        case (_278)
        0:
            _355 <= _347;
        1:
            _355 <= _348;
        2:
            _355 <= _349;
        3:
            _355 <= _350;
        4:
            _355 <= _351;
        5:
            _355 <= _352;
        6:
            _355 <= _353;
        default:
            _355 <= _354;
        endcase
    end
    assign _559 = _355 == _282;
    assign _563 = _559 ? _544 : _562;
    assign _477 = _330 ? _28 : _476;
    assign _25 = _477;
    always @(posedge clock) begin
        if (clear)
            _476 <= _560;
        else
            _476 <= _25;
    end
    assign _481 = _333 ? _28 : _480;
    assign _26 = _481;
    always @(posedge clock) begin
        if (clear)
            _480 <= _560;
        else
            _480 <= _26;
    end
    assign _485 = _336 ? _28 : _484;
    assign _27 = _485;
    always @(posedge clock) begin
        if (clear)
            _484 <= _560;
        else
            _484 <= _27;
    end
    assign _494 = 12'b000000000001;
    assign _495 = _491 - _494;
    assign _493 = _491 == _560;
    assign _496 = _493 ? _491 : _495;
    assign _486 = 4'b0011;
    assign _487 = _50 == _486;
    assign _498 = _487 ? _497 : _496;
    assign _28 = _498;
    assign _499 = _393 ? _28 : _490;
    assign _29 = _499;
    always @(posedge clock) begin
        if (clear)
            _490 <= _560;
        else
            _490 <= _29;
    end
    always @* begin
        case (_258)
        0:
            _491 <= _490;
        1:
            _491 <= _484;
        2:
            _491 <= _480;
        default:
            _491 <= _476;
        endcase
    end
    assign _556 = _491 == _560;
    assign _557 = _556 ? _544 : _542;
    assign _551 = imem_data[5:0];
    assign _503 = _330 ? _33 : _502;
    assign _30 = _503;
    always @(posedge clock) begin
        if (clear)
            _502 <= _560;
        else
            _502 <= _30;
    end
    assign _507 = _333 ? _33 : _506;
    assign _31 = _507;
    always @(posedge clock) begin
        if (clear)
            _506 <= _560;
        else
            _506 <= _31;
    end
    assign _511 = _336 ? _33 : _510;
    assign _32 = _511;
    always @(posedge clock) begin
        if (clear)
            _510 <= _560;
        else
            _510 <= _32;
    end
    assign _497 = imem_data[11:0];
    assign _524 = _519 - _494;
    assign _521 = _519 - _494;
    assign _341 = 4'b1000;
    assign _515 = _50 == _341;
    assign _522 = _515 ? _521 : _519;
    assign _53 = 4'b0111;
    assign _514 = _50 == _53;
    assign _525 = _514 ? _524 : _522;
    assign _512 = 4'b0010;
    assign _513 = _50 == _512;
    assign _526 = _513 ? _497 : _525;
    assign _33 = _526;
    assign _527 = _393 ? _33 : _518;
    assign _34 = _527;
    always @(posedge clock) begin
        if (clear)
            _518 <= _560;
        else
            _518 <= _34;
    end
    always @* begin
        case (_258)
        0:
            _519 <= _518;
        1:
            _519 <= _510;
        2:
            _519 <= _506;
        default:
            _519 <= _502;
        endcase
    end
    assign _549 = _519 == _560;
    assign _550 = ~ _549;
    assign _552 = _550 ? _551 : _544;
    assign _546 = host_in_valid ? _544 : _542;
    assign _543 = 6'b000001;
    assign _330 = _258 == _207;
    assign _528 = _330 ? _40 : _230;
    assign _36 = _528;
    always @(posedge clock) begin
        if (clear)
            _230 <= _238;
        else
            _230 <= _36;
    end
    assign _333 = _258 == _212;
    assign _529 = _333 ? _40 : _233;
    assign _37 = _529;
    always @(posedge clock) begin
        if (clear)
            _233 <= _238;
        else
            _233 <= _37;
    end
    assign _336 = _258 == _217;
    assign _530 = _336 ? _40 : _236;
    assign _38 = _530;
    always @(posedge clock) begin
        if (clear)
            _236 <= _238;
        else
            _236 <= _38;
    end
    always @* begin
        case (_258)
        0:
            _542 <= _239;
        1:
            _542 <= _236;
        2:
            _542 <= _233;
        default:
            _542 <= _230;
        endcase
    end
    assign _544 = _542 + _543;
    assign _540 = 4'b1101;
    assign _541 = _50 == _540;
    assign _545 = _541 ? _542 : _544;
    assign _241 = 4'b1100;
    assign _539 = _50 == _241;
    assign _547 = _539 ? _546 : _545;
    assign _537 = 4'b1010;
    assign _538 = _50 == _537;
    assign _553 = _538 ? _552 : _547;
    assign _535 = 4'b1001;
    assign _536 = _50 == _535;
    assign _554 = _536 ? _551 : _553;
    assign _533 = 4'b0110;
    assign _534 = _50 == _533;
    assign _558 = _534 ? _557 : _554;
    assign _531 = 4'b0101;
    assign _50 = imem_data[15:12];
    assign _532 = _50 == _531;
    assign _564 = _532 ? _563 : _558;
    assign _40 = _564;
    assign _393 = _258 == _222;
    assign _565 = _393 ? _40 : _239;
    assign _41 = _565;
    always @(posedge clock) begin
        if (clear)
            _239 <= _238;
        else
            _239 <= _41;
    end
    always @* begin
        case (_569)
        0:
            _570 <= _239;
        1:
            _570 <= _236;
        2:
            _570 <= _233;
        default:
            _570 <= _230;
        endcase
    end
    assign vdd = 1'b1;
    assign _567 = _258 + _217;
    assign _44 = _567;
    always @(posedge clock) begin
        if (clear)
            _258 <= _222;
        else
            _258 <= _44;
    end
    assign _569 = _258 + _217;
    assign _571 = { _569,
                    _570 };
    assign imem_addr = _571;
    assign pin_out = _49;
    assign pin_oe = _277;
    assign host_out = _255;
    assign host_out_valid = _251;
    assign host_in_ready = _6;
    assign pcs = _240;
    assign pin_sub = _227;

endmodule
