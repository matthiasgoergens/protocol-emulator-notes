module deadline_sequencer_mb_p6_d1 (
    port_out_ready,
    flags,
    pin_in,
    host_in,
    host_in_valid,
    port_in3,
    port_in2,
    port_in1,
    port_in0,
    port_in_valid,
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
    port_out_data,
    port_out_valid,
    port_in_ready,
    mb_counts
);

    input [3:0] port_out_ready;
    input [3:0] flags;
    input [7:0] pin_in;
    input [7:0] host_in;
    input host_in_valid;
    input [7:0] port_in3;
    input [7:0] port_in2;
    input [7:0] port_in1;
    input [7:0] port_in0;
    input [3:0] port_in_valid;
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
    output [7:0] port_out_data;
    output [3:0] port_out_valid;
    output [3:0] port_in_ready;
    output [11:0] mb_counts;

    wire [1:0] _80;
    wire [2:0] _84;
    wire [2:0] _79;
    wire [2:0] _74;
    wire [2:0] _69;
    wire [11:0] _85;
    wire _105;
    wire [1:0] _102;
    wire _103;
    wire [1:0] _100;
    wire _101;
    wire [1:0] _98;
    wire _99;
    wire [3:0] _106;
    wire [3:0] _107;
    wire [3:0] _108;
    wire [3:0] _109;
    wire [3:0] _89;
    wire _88;
    wire [3:0] _110;
    wire [3:0] _2;
    wire _125;
    wire _123;
    wire _121;
    wire _119;
    wire [3:0] _126;
    wire [3:0] _127;
    wire [3:0] _128;
    wire [3:0] _129;
    wire _111;
    wire [3:0] _130;
    wire [3:0] _4;
    reg [3:0] _133;
    wire [7:0] _136;
    wire [7:0] _154;
    wire [7:0] _155;
    wire [7:0] _156;
    wire _134;
    wire [7:0] _157;
    wire [7:0] _6;
    reg [7:0] _137;
    wire [23:0] _170;
    wire _174;
    wire _172;
    wire _175;
    wire _9;
    wire _180;
    wire _177;
    wire _178;
    wire _11;
    reg _181;
    wire [3:0] _176;
    wire _182;
    wire [7:0] _186;
    wire [7:0] _13;
    reg [7:0] _185;
    wire _239;
    wire [1:0] _240;
    wire [3:0] _241;
    wire [7:0] _242;
    wire [7:0] _243;
    wire [7:0] _237;
    wire [7:0] _238;
    wire [7:0] _244;
    wire _231;
    wire [2:0] _229;
    wire _230;
    wire _232;
    wire _227;
    wire [2:0] _225;
    wire _226;
    wire _228;
    wire _223;
    wire [2:0] _221;
    wire _222;
    wire _224;
    wire _219;
    wire [2:0] _217;
    wire _218;
    wire _220;
    wire _215;
    wire [2:0] _213;
    wire _214;
    wire _216;
    wire _211;
    wire [2:0] _209;
    wire _210;
    wire _212;
    wire _207;
    wire [2:0] _205;
    wire _206;
    wire _208;
    wire _203;
    wire _198;
    wire [2:0] _196;
    wire _197;
    wire _204;
    wire [7:0] _233;
    wire [7:0] _234;
    wire _190;
    wire [7:0] _235;
    wire _188;
    wire [7:0] _245;
    wire [7:0] _15;
    reg [7:0] _193;
    wire _321;
    wire [1:0] _322;
    wire [3:0] _323;
    wire [7:0] _324;
    wire [7:0] _325;
    wire [7:0] _236;
    wire [7:0] _319;
    wire [7:0] _320;
    wire [7:0] _326;
    wire _314;
    wire _313;
    wire _315;
    wire _310;
    wire _309;
    wire _311;
    wire _306;
    wire _305;
    wire _307;
    wire _302;
    wire _301;
    wire _303;
    wire _298;
    wire _297;
    wire _299;
    wire _294;
    wire _293;
    wire _295;
    wire _290;
    wire _289;
    wire _291;
    wire _286;
    wire _285;
    wire _287;
    wire [7:0] _316;
    wire _281;
    wire _280;
    wire _282;
    wire _277;
    wire _276;
    wire _278;
    wire _273;
    wire _272;
    wire _274;
    wire _269;
    wire _268;
    wire _270;
    wire _265;
    wire _264;
    wire _266;
    wire _261;
    wire _260;
    wire _262;
    wire _257;
    wire _256;
    wire _258;
    wire _201;
    wire _200;
    wire _202;
    wire _253;
    wire _252;
    wire _254;
    wire [7:0] _283;
    wire _194;
    wire [7:0] _317;
    wire _247;
    wire [7:0] _318;
    wire [3:0] _187;
    wire _246;
    wire [7:0] _327;
    wire [7:0] _17;
    reg [7:0] _250;
    wire [5:0] _168;
    wire [5:0] _606;
    wire _605;
    wire [5:0] _607;
    wire [11:0] _601;
    wire _602;
    wire [5:0] _603;
    wire [11:0] _333;
    wire [11:0] _19;
    reg [11:0] _332;
    wire [11:0] _339;
    wire [11:0] _20;
    reg [11:0] _338;
    wire [11:0] _345;
    wire [11:0] _21;
    reg [11:0] _344;
    wire [11:0] _358;
    wire [11:0] _359;
    wire [11:0] _356;
    wire _350;
    wire [11:0] _357;
    wire _348;
    wire [11:0] _360;
    wire [3:0] _346;
    wire _347;
    wire [11:0] _362;
    wire [11:0] _22;
    wire [11:0] _365;
    wire [11:0] _23;
    reg [11:0] _353;
    reg [11:0] _354;
    wire _596;
    wire _597;
    wire [5:0] _598;
    wire [5:0] _593;
    wire [5:0] _587;
    wire [5:0] _588;
    wire [5:0] _585;
    wire [5:0] _586;
    wire [5:0] _589;
    wire [5:0] _582;
    wire _116;
    wire _115;
    wire _114;
    wire _113;
    reg _117;
    wire [5:0] _583;
    wire [5:0] _580;
    wire [5:0] _581;
    wire [5:0] _584;
    wire [5:0] _590;
    wire [5:0] _576;
    wire [11:0] _369;
    wire [11:0] _25;
    reg [11:0] _368;
    wire [11:0] _373;
    wire [11:0] _26;
    reg [11:0] _372;
    wire [11:0] _377;
    wire [11:0] _27;
    reg [11:0] _376;
    wire [11:0] _361;
    wire [11:0] _387;
    wire _385;
    wire [11:0] _388;
    wire [3:0] _378;
    wire _379;
    wire [11:0] _389;
    wire [11:0] _28;
    wire [11:0] _390;
    wire [11:0] _29;
    reg [11:0] _382;
    reg [11:0] _383;
    wire _575;
    wire [5:0] _577;
    wire _572;
    wire _570;
    wire _569;
    wire _568;
    wire _567;
    wire _566;
    wire _565;
    wire _564;
    wire _563;
    wire _562;
    wire _561;
    wire _560;
    wire _559;
    wire _558;
    wire _557;
    wire _556;
    wire [7:0] _391;
    wire [7:0] _31;
    reg [7:0] _152;
    wire [7:0] _392;
    wire [7:0] _32;
    reg [7:0] _149;
    wire [7:0] _393;
    wire [7:0] _33;
    reg [7:0] _146;
    wire [7:0] _531;
    wire [6:0] _526;
    wire [7:0] _528;
    wire [6:0] _524;
    wire [7:0] _525;
    wire [7:0] _529;
    wire [6:0] _519;
    wire [7:0] _520;
    wire [6:0] _517;
    wire _515;
    wire _514;
    wire _513;
    wire _512;
    wire _511;
    wire _510;
    wire _509;
    wire _508;
    wire [2:0] _195;
    reg _516;
    wire [7:0] _518;
    wire _199;
    wire [7:0] _521;
    wire [7:0] _506;
    reg [7:0] _501;
    wire _96;
    wire _95;
    wire _94;
    wire _93;
    reg _97;
    wire [7:0] _502;
    wire [7:0] _400;
    wire [7:0] _42;
    reg [7:0] _399;
    wire [7:0] _407;
    wire [7:0] _43;
    reg [7:0] _406;
    wire [7:0] _414;
    wire [7:0] _44;
    reg [7:0] _413;
    wire [7:0] _421;
    wire [7:0] _45;
    reg [7:0] _420;
    reg [7:0] _499;
    wire _480;
    wire _479;
    wire _478;
    wire _474;
    wire _475;
    wire _471;
    wire _472;
    wire _468;
    wire _469;
    wire _490;
    wire _491;
    wire _488;
    wire _456;
    wire _455;
    wire _454;
    wire _427;
    wire _424;
    wire _417;
    wire _425;
    wire _416;
    wire _422;
    wire _428;
    wire _46;
    reg _83;
    wire _451;
    wire _434;
    wire _431;
    wire _410;
    wire _432;
    wire _409;
    wire _429;
    wire _435;
    wire _47;
    reg _78;
    wire _449;
    wire _441;
    wire _438;
    wire _403;
    wire _439;
    wire _402;
    wire _436;
    wire _442;
    wire _48;
    reg _73;
    wire _447;
    wire _445;
    wire [3:0] _452;
    wire _453;
    reg _457;
    wire _458;
    wire _459;
    wire _460;
    wire _461;
    wire _443;
    wire _462;
    wire _49;
    wire _396;
    wire _489;
    wire _395;
    wire _482;
    wire _483;
    wire _484;
    wire gnd;
    wire _463;
    wire _485;
    wire _50;
    wire _486;
    wire _492;
    wire _51;
    reg _68;
    wire _465;
    wire _466;
    wire [3:0] _476;
    wire _477;
    wire [1:0] _92;
    reg _481;
    wire [7:0] _500;
    wire _91;
    wire [7:0] _503;
    wire _90;
    wire [7:0] _504;
    wire _498;
    wire [7:0] _505;
    wire _497;
    wire [7:0] _507;
    wire [3:0] _349;
    wire _496;
    wire [7:0] _522;
    wire [3:0] _189;
    wire _495;
    wire [7:0] _530;
    wire [3:0] _493;
    wire _494;
    wire [7:0] _532;
    wire [7:0] _52;
    wire [7:0] _533;
    wire [7:0] _53;
    reg [7:0] _143;
    reg [7:0] _153;
    wire _555;
    wire [3:0] _554;
    reg _571;
    wire _573;
    wire [5:0] _578;
    wire [5:0] _552;
    wire _329;
    wire [5:0] _534;
    wire [5:0] _54;
    reg [5:0] _160;
    wire _335;
    wire [5:0] _535;
    wire [5:0] _55;
    reg [5:0] _163;
    wire _341;
    wire [5:0] _536;
    wire [5:0] _56;
    reg [5:0] _166;
    reg [5:0] _551;
    wire [5:0] _553;
    wire [3:0] _549;
    wire _550;
    wire [5:0] _579;
    wire [3:0] _87;
    wire _548;
    wire [5:0] _591;
    wire [3:0] _546;
    wire _547;
    wire [5:0] _592;
    wire [3:0] _171;
    wire _545;
    wire [5:0] _594;
    wire [3:0] _543;
    wire _544;
    wire [5:0] _599;
    wire [3:0] _541;
    wire _542;
    wire [5:0] _600;
    wire [3:0] _539;
    wire _540;
    wire [5:0] _604;
    wire [3:0] _537;
    wire [3:0] _86;
    wire _538;
    wire [5:0] _608;
    wire [5:0] _58;
    wire _364;
    wire [5:0] _609;
    wire [5:0] _59;
    reg [5:0] _169;
    reg [5:0] _614;
    wire vdd;
    wire [1:0] _611;
    wire [1:0] _62;
    reg [1:0] _140;
    wire [1:0] _613;
    wire [7:0] _615;
    assign _80 = 2'b00;
    assign _84 = { _80,
                   _83 };
    assign _79 = { _80,
                   _78 };
    assign _74 = { _80,
                   _73 };
    assign _69 = { _80,
                   _68 };
    assign _85 = { _69,
                   _74,
                   _79,
                   _84 };
    assign _105 = _92 == _80;
    assign _102 = 2'b01;
    assign _103 = _92 == _102;
    assign _100 = 2'b10;
    assign _101 = _92 == _100;
    assign _98 = 2'b11;
    assign _99 = _92 == _98;
    assign _106 = { _99,
                    _101,
                    _103,
                    _105 };
    assign _107 = _97 ? _106 : _89;
    assign _108 = _91 ? _107 : _89;
    assign _109 = _90 ? _108 : _89;
    assign _89 = 4'b0000;
    assign _88 = _86 == _87;
    assign _110 = _88 ? _109 : _89;
    assign _2 = _110;
    assign _125 = _92 == _80;
    assign _123 = _92 == _102;
    assign _121 = _92 == _100;
    assign _119 = _92 == _98;
    assign _126 = { _119,
                    _121,
                    _123,
                    _125 };
    assign _127 = _117 ? _126 : _89;
    assign _128 = _91 ? _127 : _89;
    assign _129 = _90 ? _89 : _128;
    assign _111 = _86 == _87;
    assign _130 = _111 ? _129 : _89;
    assign _4 = _130;
    always @(posedge clock) begin
        if (clear)
            _133 <= _89;
        else
            _133 <= _4;
    end
    assign _136 = 8'b00000000;
    assign _154 = _117 ? _153 : _137;
    assign _155 = _91 ? _154 : _137;
    assign _156 = _90 ? _137 : _155;
    assign _134 = _86 == _87;
    assign _157 = _134 ? _156 : _137;
    assign _6 = _157;
    always @(posedge clock) begin
        if (clear)
            _137 <= _136;
        else
            _137 <= _6;
    end
    assign _170 = { _160,
                    _163,
                    _166,
                    _169 };
    assign _174 = host_in_valid ? vdd : gnd;
    assign _172 = _86 == _171;
    assign _175 = _172 ? _174 : gnd;
    assign _9 = _175;
    assign _180 = 1'b0;
    assign _177 = _86 == _176;
    assign _178 = _177 ? vdd : gnd;
    assign _11 = _178;
    always @(posedge clock) begin
        if (clear)
            _181 <= _180;
        else
            _181 <= _11;
    end
    assign _176 = 4'b1011;
    assign _182 = _86 == _176;
    assign _186 = _182 ? _153 : _185;
    assign _13 = _186;
    always @(posedge clock) begin
        if (clear)
            _185 <= _136;
        else
            _185 <= _13;
    end
    assign _239 = imem_data[2:2];
    assign _240 = { _239,
                    _239 };
    assign _241 = { _240,
                    _240 };
    assign _242 = { _241,
                    _241 };
    assign _243 = _236 & _242;
    assign _237 = ~ _236;
    assign _238 = _193 & _237;
    assign _244 = _238 | _243;
    assign _231 = _193[0:0];
    assign _229 = 3'b000;
    assign _230 = _195 == _229;
    assign _232 = _230 ? _203 : _231;
    assign _227 = _193[1:1];
    assign _225 = 3'b001;
    assign _226 = _195 == _225;
    assign _228 = _226 ? _203 : _227;
    assign _223 = _193[2:2];
    assign _221 = 3'b010;
    assign _222 = _195 == _221;
    assign _224 = _222 ? _203 : _223;
    assign _219 = _193[3:3];
    assign _217 = 3'b011;
    assign _218 = _195 == _217;
    assign _220 = _218 ? _203 : _219;
    assign _215 = _193[4:4];
    assign _213 = 3'b100;
    assign _214 = _195 == _213;
    assign _216 = _214 ? _203 : _215;
    assign _211 = _193[5:5];
    assign _209 = 3'b101;
    assign _210 = _195 == _209;
    assign _212 = _210 ? _203 : _211;
    assign _207 = _193[6:6];
    assign _205 = 3'b110;
    assign _206 = _195 == _205;
    assign _208 = _206 ? _203 : _207;
    assign _203 = ~ _202;
    assign _198 = _193[7:7];
    assign _196 = 3'b111;
    assign _197 = _195 == _196;
    assign _204 = _197 ? _203 : _198;
    assign _233 = { _204,
                    _208,
                    _212,
                    _216,
                    _220,
                    _224,
                    _228,
                    _232 };
    assign _234 = _194 ? _233 : _193;
    assign _190 = _86 == _189;
    assign _235 = _190 ? _234 : _193;
    assign _188 = _86 == _187;
    assign _245 = _188 ? _244 : _235;
    assign _15 = _245;
    always @(posedge clock) begin
        if (clear)
            _193 <= _136;
        else
            _193 <= _15;
    end
    assign _321 = imem_data[3:3];
    assign _322 = { _321,
                    _321 };
    assign _323 = { _322,
                    _322 };
    assign _324 = { _323,
                    _323 };
    assign _325 = _236 & _324;
    assign _236 = imem_data[11:4];
    assign _319 = ~ _236;
    assign _320 = _250 & _319;
    assign _326 = _320 | _325;
    assign _314 = _250[0:0];
    assign _313 = _195 == _229;
    assign _315 = _313 ? gnd : _314;
    assign _310 = _250[1:1];
    assign _309 = _195 == _225;
    assign _311 = _309 ? gnd : _310;
    assign _306 = _250[2:2];
    assign _305 = _195 == _221;
    assign _307 = _305 ? gnd : _306;
    assign _302 = _250[3:3];
    assign _301 = _195 == _217;
    assign _303 = _301 ? gnd : _302;
    assign _298 = _250[4:4];
    assign _297 = _195 == _213;
    assign _299 = _297 ? gnd : _298;
    assign _294 = _250[5:5];
    assign _293 = _195 == _209;
    assign _295 = _293 ? gnd : _294;
    assign _290 = _250[6:6];
    assign _289 = _195 == _205;
    assign _291 = _289 ? gnd : _290;
    assign _286 = _250[7:7];
    assign _285 = _195 == _196;
    assign _287 = _285 ? gnd : _286;
    assign _316 = { _287,
                    _291,
                    _295,
                    _299,
                    _303,
                    _307,
                    _311,
                    _315 };
    assign _281 = _250[0:0];
    assign _280 = _195 == _229;
    assign _282 = _280 ? _202 : _281;
    assign _277 = _250[1:1];
    assign _276 = _195 == _225;
    assign _278 = _276 ? _202 : _277;
    assign _273 = _250[2:2];
    assign _272 = _195 == _221;
    assign _274 = _272 ? _202 : _273;
    assign _269 = _250[3:3];
    assign _268 = _195 == _217;
    assign _270 = _268 ? _202 : _269;
    assign _265 = _250[4:4];
    assign _264 = _195 == _213;
    assign _266 = _264 ? _202 : _265;
    assign _261 = _250[5:5];
    assign _260 = _195 == _209;
    assign _262 = _260 ? _202 : _261;
    assign _257 = _250[6:6];
    assign _256 = _195 == _205;
    assign _258 = _256 ? _202 : _257;
    assign _201 = _153[7:7];
    assign _200 = _153[0:0];
    assign _202 = _199 ? _201 : _200;
    assign _253 = _250[7:7];
    assign _252 = _195 == _196;
    assign _254 = _252 ? _202 : _253;
    assign _283 = { _254,
                    _258,
                    _262,
                    _266,
                    _270,
                    _274,
                    _278,
                    _282 };
    assign _194 = imem_data[7:7];
    assign _317 = _194 ? _316 : _283;
    assign _247 = _86 == _189;
    assign _318 = _247 ? _317 : _250;
    assign _187 = 4'b0001;
    assign _246 = _86 == _187;
    assign _327 = _246 ? _326 : _318;
    assign _17 = _327;
    always @(posedge clock) begin
        if (clear)
            _250 <= _136;
        else
            _250 <= _17;
    end
    assign _168 = 6'b000000;
    assign _606 = _575 ? _576 : _551;
    assign _605 = _516 == _199;
    assign _607 = _605 ? _553 : _606;
    assign _601 = 12'b000000000000;
    assign _602 = _383 == _601;
    assign _603 = _602 ? _553 : _551;
    assign _333 = _329 ? _22 : _332;
    assign _19 = _333;
    always @(posedge clock) begin
        if (clear)
            _332 <= _601;
        else
            _332 <= _19;
    end
    assign _339 = _335 ? _22 : _338;
    assign _20 = _339;
    always @(posedge clock) begin
        if (clear)
            _338 <= _601;
        else
            _338 <= _20;
    end
    assign _345 = _341 ? _22 : _344;
    assign _21 = _345;
    always @(posedge clock) begin
        if (clear)
            _344 <= _601;
        else
            _344 <= _21;
    end
    assign _358 = 12'b000000000001;
    assign _359 = _354 - _358;
    assign _356 = _354 - _358;
    assign _350 = _86 == _349;
    assign _357 = _350 ? _356 : _354;
    assign _348 = _86 == _189;
    assign _360 = _348 ? _359 : _357;
    assign _346 = 4'b0010;
    assign _347 = _86 == _346;
    assign _362 = _347 ? _361 : _360;
    assign _22 = _362;
    assign _365 = _364 ? _22 : _353;
    assign _23 = _365;
    always @(posedge clock) begin
        if (clear)
            _353 <= _601;
        else
            _353 <= _23;
    end
    always @* begin
        case (_140)
        0:
            _354 <= _353;
        1:
            _354 <= _344;
        2:
            _354 <= _338;
        default:
            _354 <= _332;
        endcase
    end
    assign _596 = _354 == _601;
    assign _597 = ~ _596;
    assign _598 = _597 ? _576 : _553;
    assign _593 = host_in_valid ? _553 : _551;
    assign _587 = _575 ? _576 : _551;
    assign _588 = _97 ? _553 : _587;
    assign _585 = _575 ? _576 : _551;
    assign _586 = _481 ? _553 : _585;
    assign _589 = _91 ? _588 : _586;
    assign _582 = _575 ? _576 : _551;
    assign _116 = port_out_ready[3:3];
    assign _115 = port_out_ready[2:2];
    assign _114 = port_out_ready[1:1];
    assign _113 = port_out_ready[0:0];
    always @* begin
        case (_92)
        0:
            _117 <= _113;
        1:
            _117 <= _114;
        2:
            _117 <= _115;
        default:
            _117 <= _116;
        endcase
    end
    assign _583 = _117 ? _553 : _582;
    assign _580 = _575 ? _576 : _551;
    assign _581 = _458 ? _553 : _580;
    assign _584 = _91 ? _583 : _581;
    assign _590 = _90 ? _589 : _584;
    assign _576 = imem_data[5:0];
    assign _369 = _329 ? _28 : _368;
    assign _25 = _369;
    always @(posedge clock) begin
        if (clear)
            _368 <= _601;
        else
            _368 <= _25;
    end
    assign _373 = _335 ? _28 : _372;
    assign _26 = _373;
    always @(posedge clock) begin
        if (clear)
            _372 <= _601;
        else
            _372 <= _26;
    end
    assign _377 = _341 ? _28 : _376;
    assign _27 = _377;
    always @(posedge clock) begin
        if (clear)
            _376 <= _601;
        else
            _376 <= _27;
    end
    assign _361 = imem_data[11:0];
    assign _387 = _383 - _358;
    assign _385 = _383 == _601;
    assign _388 = _385 ? _383 : _387;
    assign _378 = 4'b0011;
    assign _379 = _86 == _378;
    assign _389 = _379 ? _361 : _388;
    assign _28 = _389;
    assign _390 = _364 ? _28 : _382;
    assign _29 = _390;
    always @(posedge clock) begin
        if (clear)
            _382 <= _601;
        else
            _382 <= _29;
    end
    always @* begin
        case (_140)
        0:
            _383 <= _382;
        1:
            _383 <= _376;
        2:
            _383 <= _372;
        default:
            _383 <= _368;
        endcase
    end
    assign _575 = _383 == _601;
    assign _577 = _575 ? _576 : _551;
    assign _572 = imem_data[11:11];
    assign _570 = flags[3:3];
    assign _569 = flags[2:2];
    assign _568 = flags[1:1];
    assign _567 = flags[0:0];
    assign _566 = _452[3:3];
    assign _565 = _452[2:2];
    assign _564 = _452[1:1];
    assign _563 = _452[0:0];
    assign _562 = _153[7:7];
    assign _561 = _153[6:6];
    assign _560 = _153[5:5];
    assign _559 = _153[4:4];
    assign _558 = _153[3:3];
    assign _557 = _153[2:2];
    assign _556 = _153[1:1];
    assign _391 = _329 ? _52 : _152;
    assign _31 = _391;
    always @(posedge clock) begin
        if (clear)
            _152 <= _136;
        else
            _152 <= _31;
    end
    assign _392 = _335 ? _52 : _149;
    assign _32 = _392;
    always @(posedge clock) begin
        if (clear)
            _149 <= _136;
        else
            _149 <= _32;
    end
    assign _393 = _341 ? _52 : _146;
    assign _33 = _393;
    always @(posedge clock) begin
        if (clear)
            _146 <= _136;
        else
            _146 <= _33;
    end
    assign _531 = imem_data[7:0];
    assign _526 = _153[6:0];
    assign _528 = { _526,
                    _180 };
    assign _524 = _153[7:1];
    assign _525 = { _180,
                    _524 };
    assign _529 = _199 ? _528 : _525;
    assign _519 = _153[6:0];
    assign _520 = { _519,
                    _516 };
    assign _517 = _153[7:1];
    assign _515 = pin_in[7:7];
    assign _514 = pin_in[6:6];
    assign _513 = pin_in[5:5];
    assign _512 = pin_in[4:4];
    assign _511 = pin_in[3:3];
    assign _510 = pin_in[2:2];
    assign _509 = pin_in[1:1];
    assign _508 = pin_in[0:0];
    assign _195 = imem_data[11:9];
    always @* begin
        case (_195)
        0:
            _516 <= _508;
        1:
            _516 <= _509;
        2:
            _516 <= _510;
        3:
            _516 <= _511;
        4:
            _516 <= _512;
        5:
            _516 <= _513;
        6:
            _516 <= _514;
        default:
            _516 <= _515;
        endcase
    end
    assign _518 = { _516,
                    _517 };
    assign _199 = imem_data[8:8];
    assign _521 = _199 ? _520 : _518;
    assign _506 = host_in_valid ? host_in : _153;
    always @* begin
        case (_92)
        0:
            _501 <= port_in0;
        1:
            _501 <= port_in1;
        2:
            _501 <= port_in2;
        default:
            _501 <= port_in3;
        endcase
    end
    assign _96 = port_in_valid[3:3];
    assign _95 = port_in_valid[2:2];
    assign _94 = port_in_valid[1:1];
    assign _93 = port_in_valid[0:0];
    always @* begin
        case (_92)
        0:
            _97 <= _93;
        1:
            _97 <= _94;
        2:
            _97 <= _95;
        default:
            _97 <= _96;
        endcase
    end
    assign _502 = _97 ? _501 : _153;
    assign _400 = _396 ? _153 : _399;
    assign _42 = _400;
    always @(posedge clock) begin
        if (clear)
            _399 <= _136;
        else
            _399 <= _42;
    end
    assign _407 = _403 ? _153 : _406;
    assign _43 = _407;
    always @(posedge clock) begin
        if (clear)
            _406 <= _136;
        else
            _406 <= _43;
    end
    assign _414 = _410 ? _153 : _413;
    assign _44 = _414;
    always @(posedge clock) begin
        if (clear)
            _413 <= _136;
        else
            _413 <= _44;
    end
    assign _421 = _417 ? _153 : _420;
    assign _45 = _421;
    always @(posedge clock) begin
        if (clear)
            _420 <= _136;
        else
            _420 <= _45;
    end
    always @* begin
        case (_92)
        0:
            _499 <= _420;
        1:
            _499 <= _413;
        2:
            _499 <= _406;
        default:
            _499 <= _399;
        endcase
    end
    assign _480 = _476[3:3];
    assign _479 = _476[2:2];
    assign _478 = _476[1:1];
    assign _474 = _83 == _180;
    assign _475 = ~ _474;
    assign _471 = _78 == _180;
    assign _472 = ~ _471;
    assign _468 = _73 == _180;
    assign _469 = ~ _468;
    assign _490 = 1'b1;
    assign _491 = _68 - _490;
    assign _488 = _68 + _490;
    assign _456 = _452[3:3];
    assign _455 = _452[2:2];
    assign _454 = _452[1:1];
    assign _427 = _83 - _490;
    assign _424 = _83 + _490;
    assign _417 = _49 & _416;
    assign _425 = _417 ? _424 : _83;
    assign _416 = _92 == _80;
    assign _422 = _50 & _416;
    assign _428 = _422 ? _427 : _425;
    assign _46 = _428;
    always @(posedge clock) begin
        if (clear)
            _83 <= _180;
        else
            _83 <= _46;
    end
    assign _451 = _83 == _490;
    assign _434 = _78 - _490;
    assign _431 = _78 + _490;
    assign _410 = _49 & _409;
    assign _432 = _410 ? _431 : _78;
    assign _409 = _92 == _102;
    assign _429 = _50 & _409;
    assign _435 = _429 ? _434 : _432;
    assign _47 = _435;
    always @(posedge clock) begin
        if (clear)
            _78 <= _180;
        else
            _78 <= _47;
    end
    assign _449 = _78 == _490;
    assign _441 = _73 - _490;
    assign _438 = _73 + _490;
    assign _403 = _49 & _402;
    assign _439 = _403 ? _438 : _73;
    assign _402 = _92 == _100;
    assign _436 = _50 & _402;
    assign _442 = _436 ? _441 : _439;
    assign _48 = _442;
    always @(posedge clock) begin
        if (clear)
            _73 <= _180;
        else
            _73 <= _48;
    end
    assign _447 = _73 == _490;
    assign _445 = _68 == _490;
    assign _452 = { _445,
                    _447,
                    _449,
                    _451 };
    assign _453 = _452[0:0];
    always @* begin
        case (_92)
        0:
            _457 <= _453;
        1:
            _457 <= _454;
        2:
            _457 <= _455;
        default:
            _457 <= _456;
        endcase
    end
    assign _458 = ~ _457;
    assign _459 = _458 ? vdd : gnd;
    assign _460 = _91 ? gnd : _459;
    assign _461 = _90 ? gnd : _460;
    assign _443 = _86 == _87;
    assign _462 = _443 ? _461 : gnd;
    assign _49 = _462;
    assign _396 = _49 & _395;
    assign _489 = _396 ? _488 : _68;
    assign _395 = _92 == _98;
    assign _482 = _481 ? vdd : gnd;
    assign _483 = _91 ? gnd : _482;
    assign _484 = _90 ? _483 : gnd;
    assign gnd = 1'b0;
    assign _463 = _86 == _87;
    assign _485 = _463 ? _484 : gnd;
    assign _50 = _485;
    assign _486 = _50 & _395;
    assign _492 = _486 ? _491 : _489;
    assign _51 = _492;
    always @(posedge clock) begin
        if (clear)
            _68 <= _180;
        else
            _68 <= _51;
    end
    assign _465 = _68 == _180;
    assign _466 = ~ _465;
    assign _476 = { _466,
                    _469,
                    _472,
                    _475 };
    assign _477 = _476[0:0];
    assign _92 = imem_data[9:8];
    always @* begin
        case (_92)
        0:
            _481 <= _477;
        1:
            _481 <= _478;
        2:
            _481 <= _479;
        default:
            _481 <= _480;
        endcase
    end
    assign _500 = _481 ? _499 : _153;
    assign _91 = imem_data[10:10];
    assign _503 = _91 ? _502 : _500;
    assign _90 = imem_data[11:11];
    assign _504 = _90 ? _503 : _153;
    assign _498 = _86 == _87;
    assign _505 = _498 ? _504 : _153;
    assign _497 = _86 == _171;
    assign _507 = _497 ? _506 : _505;
    assign _349 = 4'b1000;
    assign _496 = _86 == _349;
    assign _522 = _496 ? _521 : _507;
    assign _189 = 4'b0111;
    assign _495 = _86 == _189;
    assign _530 = _495 ? _529 : _522;
    assign _493 = 4'b0100;
    assign _494 = _86 == _493;
    assign _532 = _494 ? _531 : _530;
    assign _52 = _532;
    assign _533 = _364 ? _52 : _143;
    assign _53 = _533;
    always @(posedge clock) begin
        if (clear)
            _143 <= _136;
        else
            _143 <= _53;
    end
    always @* begin
        case (_140)
        0:
            _153 <= _143;
        1:
            _153 <= _146;
        2:
            _153 <= _149;
        default:
            _153 <= _152;
        endcase
    end
    assign _555 = _153[0:0];
    assign _554 = imem_data[10:7];
    always @* begin
        case (_554)
        0:
            _571 <= _555;
        1:
            _571 <= _556;
        2:
            _571 <= _557;
        3:
            _571 <= _558;
        4:
            _571 <= _559;
        5:
            _571 <= _560;
        6:
            _571 <= _561;
        7:
            _571 <= _562;
        8:
            _571 <= _563;
        9:
            _571 <= _564;
        10:
            _571 <= _565;
        11:
            _571 <= _566;
        12:
            _571 <= _567;
        13:
            _571 <= _568;
        14:
            _571 <= _569;
        default:
            _571 <= _570;
        endcase
    end
    assign _573 = _571 == _572;
    assign _578 = _573 ? _553 : _577;
    assign _552 = 6'b000001;
    assign _329 = _140 == _98;
    assign _534 = _329 ? _58 : _160;
    assign _54 = _534;
    always @(posedge clock) begin
        if (clear)
            _160 <= _168;
        else
            _160 <= _54;
    end
    assign _335 = _140 == _100;
    assign _535 = _335 ? _58 : _163;
    assign _55 = _535;
    always @(posedge clock) begin
        if (clear)
            _163 <= _168;
        else
            _163 <= _55;
    end
    assign _341 = _140 == _102;
    assign _536 = _341 ? _58 : _166;
    assign _56 = _536;
    always @(posedge clock) begin
        if (clear)
            _166 <= _168;
        else
            _166 <= _56;
    end
    always @* begin
        case (_140)
        0:
            _551 <= _169;
        1:
            _551 <= _166;
        2:
            _551 <= _163;
        default:
            _551 <= _160;
        endcase
    end
    assign _553 = _551 + _552;
    assign _549 = 4'b1111;
    assign _550 = _86 == _549;
    assign _579 = _550 ? _578 : _553;
    assign _87 = 4'b1110;
    assign _548 = _86 == _87;
    assign _591 = _548 ? _590 : _579;
    assign _546 = 4'b1101;
    assign _547 = _86 == _546;
    assign _592 = _547 ? _551 : _591;
    assign _171 = 4'b1100;
    assign _545 = _86 == _171;
    assign _594 = _545 ? _593 : _592;
    assign _543 = 4'b1010;
    assign _544 = _86 == _543;
    assign _599 = _544 ? _598 : _594;
    assign _541 = 4'b1001;
    assign _542 = _86 == _541;
    assign _600 = _542 ? _576 : _599;
    assign _539 = 4'b0110;
    assign _540 = _86 == _539;
    assign _604 = _540 ? _603 : _600;
    assign _537 = 4'b0101;
    assign _86 = imem_data[15:12];
    assign _538 = _86 == _537;
    assign _608 = _538 ? _607 : _604;
    assign _58 = _608;
    assign _364 = _140 == _80;
    assign _609 = _364 ? _58 : _169;
    assign _59 = _609;
    always @(posedge clock) begin
        if (clear)
            _169 <= _168;
        else
            _169 <= _59;
    end
    always @* begin
        case (_613)
        0:
            _614 <= _169;
        1:
            _614 <= _166;
        2:
            _614 <= _163;
        default:
            _614 <= _160;
        endcase
    end
    assign vdd = 1'b1;
    assign _611 = _140 + _102;
    assign _62 = _611;
    always @(posedge clock) begin
        if (clear)
            _140 <= _80;
        else
            _140 <= _62;
    end
    assign _613 = _140 + _102;
    assign _615 = { _613,
                    _614 };
    assign imem_addr = _615;
    assign pin_out = _250;
    assign pin_oe = _193;
    assign host_out = _185;
    assign host_out_valid = _181;
    assign host_in_ready = _9;
    assign pcs = _170;
    assign port_out_data = _137;
    assign port_out_valid = _133;
    assign port_in_ready = _2;
    assign mb_counts = _85;

endmodule
