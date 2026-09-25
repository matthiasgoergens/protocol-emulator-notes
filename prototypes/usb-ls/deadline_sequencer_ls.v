module deadline_sequencer_ls (
    pin_in,
    host_in,
    host_in_valid,
    imem_data,
    clear,
    clock,
    imem_addr,
    pin_out,
    pin_oe,
    host_out,
    host_out_tag,
    host_out_valid,
    host_in_ready,
    pcs
);

    input [7:0] pin_in;
    input [7:0] host_in;
    input host_in_valid;
    input [15:0] imem_data;
    input clear;
    input clock;
    output [9:0] imem_addr;
    output [7:0] pin_out;
    output [7:0] pin_oe;
    output [7:0] host_out;
    output host_out_tag;
    output host_out_valid;
    output host_in_ready;
    output [31:0] pcs;

    wire [31:0] _55;
    wire _60;
    wire _58;
    wire _61;
    wire _2;
    wire _66;
    wire _63;
    wire _64;
    wire _4;
    reg _67;
    wire _68;
    wire _73;
    wire _6;
    reg _71;
    wire [7:0] _76;
    wire [7:0] _95;
    wire [3:0] _62;
    wire _74;
    wire [7:0] _96;
    wire [7:0] _8;
    reg [7:0] _77;
    wire _224;
    wire [1:0] _225;
    wire [3:0] _226;
    wire [7:0] _227;
    wire [7:0] _228;
    wire [7:0] _222;
    wire [7:0] _223;
    wire [7:0] _229;
    wire [2:0] _214;
    wire _215;
    wire _216;
    wire _217;
    wire _213;
    wire _209;
    wire _210;
    wire _207;
    wire _211;
    wire _212;
    wire _218;
    wire [2:0] _201;
    wire _202;
    wire _203;
    wire _204;
    wire _200;
    wire _196;
    wire _197;
    wire _194;
    wire _198;
    wire _199;
    wire _205;
    wire [2:0] _188;
    wire _189;
    wire _190;
    wire _191;
    wire _187;
    wire _183;
    wire _184;
    wire _181;
    wire _185;
    wire _186;
    wire _192;
    wire [2:0] _175;
    wire _176;
    wire _177;
    wire _178;
    wire _174;
    wire _170;
    wire _171;
    wire _168;
    wire _172;
    wire _173;
    wire _179;
    wire [2:0] _162;
    wire _163;
    wire _164;
    wire _165;
    wire _161;
    wire _157;
    wire _158;
    wire _155;
    wire _159;
    wire _160;
    wire _166;
    wire [2:0] _149;
    wire _150;
    wire _151;
    wire _152;
    wire _148;
    wire _144;
    wire _145;
    wire _142;
    wire _146;
    wire _147;
    wire _153;
    wire [2:0] _136;
    wire _137;
    wire _138;
    wire _139;
    wire _135;
    wire _131;
    wire _132;
    wire _129;
    wire _133;
    wire _134;
    wire _140;
    wire [2:0] _117;
    wire _118;
    wire _125;
    wire _126;
    wire _116;
    wire _111;
    wire _112;
    wire _106;
    wire _113;
    wire _115;
    wire _127;
    wire [7:0] _219;
    wire _100;
    wire [7:0] _220;
    wire _98;
    wire [7:0] _230;
    wire [7:0] _10;
    reg [7:0] _103;
    wire _336;
    wire [1:0] _337;
    wire [3:0] _338;
    wire [7:0] _339;
    wire [7:0] _340;
    wire [7:0] _221;
    wire [7:0] _334;
    wire [7:0] _335;
    wire [7:0] _341;
    wire _328;
    wire _329;
    wire _330;
    wire _326;
    wire _323;
    wire _324;
    wire _321;
    wire _325;
    wire _331;
    wire _316;
    wire _317;
    wire _318;
    wire _314;
    wire _311;
    wire _312;
    wire _309;
    wire _313;
    wire _319;
    wire _304;
    wire _305;
    wire _306;
    wire _302;
    wire _299;
    wire _300;
    wire _297;
    wire _301;
    wire _307;
    wire _292;
    wire _293;
    wire _294;
    wire _290;
    wire _287;
    wire _288;
    wire _285;
    wire _289;
    wire _295;
    wire _280;
    wire _281;
    wire _282;
    wire _278;
    wire _275;
    wire _276;
    wire _273;
    wire _277;
    wire _283;
    wire _268;
    wire _269;
    wire _270;
    wire _266;
    wire _263;
    wire _264;
    wire _261;
    wire _265;
    wire _271;
    wire _256;
    wire _257;
    wire _258;
    wire _254;
    wire _251;
    wire _252;
    wire _249;
    wire _253;
    wire _259;
    wire gnd;
    wire _123;
    wire _122;
    wire _124;
    wire _120;
    wire _119;
    wire _121;
    wire _244;
    wire _245;
    wire _114;
    wire _246;
    wire _242;
    wire [2:0] _109;
    wire _239;
    wire _240;
    wire _237;
    wire _241;
    wire _247;
    wire [7:0] _332;
    wire _232;
    wire [7:0] _333;
    wire [3:0] _97;
    wire _231;
    wire [7:0] _342;
    wire [7:0] _12;
    reg [7:0] _235;
    wire [11:0] _491;
    wire _492;
    wire [7:0] _493;
    wire _490;
    wire [7:0] _494;
    wire [11:0] _348;
    wire [11:0] _14;
    reg [11:0] _347;
    wire [11:0] _354;
    wire [11:0] _15;
    reg [11:0] _353;
    wire [11:0] _360;
    wire [11:0] _16;
    reg [11:0] _359;
    wire [11:0] _369;
    wire [11:0] _370;
    wire _368;
    wire [11:0] _371;
    wire [3:0] _361;
    wire _362;
    wire [11:0] _373;
    wire [11:0] _17;
    wire [11:0] _376;
    wire [11:0] _18;
    reg [11:0] _365;
    reg [11:0] _366;
    wire _487;
    wire [7:0] _488;
    wire [7:0] _482;
    wire [11:0] _380;
    wire [11:0] _19;
    reg [11:0] _379;
    wire [11:0] _384;
    wire [11:0] _20;
    reg [11:0] _383;
    wire [11:0] _388;
    wire [11:0] _21;
    reg [11:0] _387;
    wire [11:0] _372;
    wire [11:0] _402;
    wire [11:0] _399;
    wire _393;
    wire [11:0] _400;
    wire _391;
    wire [11:0] _403;
    wire [3:0] _389;
    wire _390;
    wire [11:0] _404;
    wire [11:0] _22;
    wire [11:0] _405;
    wire [11:0] _23;
    reg [11:0] _396;
    reg [11:0] _397;
    wire _480;
    wire _481;
    wire [7:0] _483;
    wire [7:0] _477;
    wire [7:0] _472;
    wire [7:0] _473;
    wire _470;
    wire [7:0] _406;
    wire [7:0] _24;
    reg [7:0] _92;
    wire [7:0] _407;
    wire [7:0] _25;
    reg [7:0] _89;
    wire [7:0] _408;
    wire [7:0] _26;
    reg [7:0] _86;
    wire [7:0] _94;
    wire [1:0] _442;
    wire [5:0] _441;
    wire [7:0] _443;
    wire [5:0] _439;
    wire [7:0] _440;
    wire [7:0] _444;
    wire [6:0] _434;
    wire [7:0] _436;
    wire [6:0] _432;
    wire [7:0] _433;
    wire [7:0] _437;
    wire _107;
    wire [7:0] _445;
    wire [6:0] _427;
    wire [7:0] _428;
    wire [6:0] _425;
    wire _423;
    wire _422;
    wire _421;
    wire _420;
    wire _419;
    wire _418;
    wire _417;
    wire _416;
    wire [2:0] _104;
    reg _424;
    wire [7:0] _426;
    wire _72;
    wire [7:0] _429;
    wire [7:0] _414;
    wire _413;
    wire [7:0] _415;
    wire [3:0] _392;
    wire _412;
    wire [7:0] _430;
    wire [3:0] _99;
    wire _411;
    wire [7:0] _446;
    wire [3:0] _409;
    wire _410;
    wire [7:0] _447;
    wire [7:0] _30;
    wire [7:0] _448;
    wire [7:0] _31;
    reg [7:0] _83;
    reg [7:0] _93;
    wire _468;
    wire _469;
    wire _471;
    wire [7:0] _474;
    wire [7:0] _466;
    wire [1:0] _343;
    wire _344;
    wire [7:0] _449;
    wire [7:0] _32;
    reg [7:0] _45;
    wire [1:0] _349;
    wire _350;
    wire [7:0] _450;
    wire [7:0] _33;
    reg [7:0] _48;
    wire [1:0] _355;
    wire _356;
    wire [7:0] _451;
    wire [7:0] _34;
    reg [7:0] _51;
    reg [7:0] _465;
    wire [7:0] _467;
    wire [3:0] _463;
    wire _464;
    wire [7:0] _475;
    wire [3:0] _461;
    wire _462;
    wire [7:0] _476;
    wire [3:0] _57;
    wire _460;
    wire [7:0] _478;
    wire [3:0] _458;
    wire _459;
    wire [7:0] _484;
    wire [3:0] _456;
    wire _457;
    wire [7:0] _485;
    wire [3:0] _454;
    wire _455;
    wire [7:0] _489;
    wire [3:0] _452;
    wire [3:0] _56;
    wire _453;
    wire [7:0] _495;
    wire [7:0] _36;
    wire _375;
    wire [7:0] _496;
    wire [7:0] _37;
    reg [7:0] _54;
    reg [7:0] _501;
    wire vdd;
    wire [1:0] _498;
    wire [1:0] _40;
    reg [1:0] _80;
    wire [1:0] _500;
    wire [9:0] _502;
    assign _55 = { _45,
                   _48,
                   _51,
                   _54 };
    assign _60 = host_in_valid ? vdd : gnd;
    assign _58 = _56 == _57;
    assign _61 = _58 ? _60 : gnd;
    assign _2 = _61;
    assign _66 = 1'b0;
    assign _63 = _56 == _62;
    assign _64 = _63 ? vdd : gnd;
    assign _4 = _64;
    always @(posedge clock) begin
        if (clear)
            _67 <= _66;
        else
            _67 <= _4;
    end
    assign _68 = _56 == _62;
    assign _73 = _68 ? _72 : _71;
    assign _6 = _73;
    always @(posedge clock) begin
        if (clear)
            _71 <= _66;
        else
            _71 <= _6;
    end
    assign _76 = 8'b00000000;
    assign _95 = _72 ? _94 : _93;
    assign _62 = 4'b1011;
    assign _74 = _56 == _62;
    assign _96 = _74 ? _95 : _77;
    assign _8 = _96;
    always @(posedge clock) begin
        if (clear)
            _77 <= _76;
        else
            _77 <= _8;
    end
    assign _224 = imem_data[2:2];
    assign _225 = { _224,
                    _224 };
    assign _226 = { _225,
                    _225 };
    assign _227 = { _226,
                    _226 };
    assign _228 = _221 & _227;
    assign _222 = ~ _221;
    assign _223 = _103 & _222;
    assign _229 = _223 | _228;
    assign _214 = 3'b000;
    assign _215 = _104 == _214;
    assign _216 = _215 ? _124 : _121;
    assign _217 = ~ _216;
    assign _213 = _103[0:0];
    assign _209 = _109 == _214;
    assign _210 = _107 & _209;
    assign _207 = _104 == _214;
    assign _211 = _207 | _210;
    assign _212 = _211 & _114;
    assign _218 = _212 ? _217 : _213;
    assign _201 = 3'b001;
    assign _202 = _104 == _201;
    assign _203 = _202 ? _124 : _121;
    assign _204 = ~ _203;
    assign _200 = _103[1:1];
    assign _196 = _109 == _201;
    assign _197 = _107 & _196;
    assign _194 = _104 == _201;
    assign _198 = _194 | _197;
    assign _199 = _198 & _114;
    assign _205 = _199 ? _204 : _200;
    assign _188 = 3'b010;
    assign _189 = _104 == _188;
    assign _190 = _189 ? _124 : _121;
    assign _191 = ~ _190;
    assign _187 = _103[2:2];
    assign _183 = _109 == _188;
    assign _184 = _107 & _183;
    assign _181 = _104 == _188;
    assign _185 = _181 | _184;
    assign _186 = _185 & _114;
    assign _192 = _186 ? _191 : _187;
    assign _175 = 3'b011;
    assign _176 = _104 == _175;
    assign _177 = _176 ? _124 : _121;
    assign _178 = ~ _177;
    assign _174 = _103[3:3];
    assign _170 = _109 == _175;
    assign _171 = _107 & _170;
    assign _168 = _104 == _175;
    assign _172 = _168 | _171;
    assign _173 = _172 & _114;
    assign _179 = _173 ? _178 : _174;
    assign _162 = 3'b100;
    assign _163 = _104 == _162;
    assign _164 = _163 ? _124 : _121;
    assign _165 = ~ _164;
    assign _161 = _103[4:4];
    assign _157 = _109 == _162;
    assign _158 = _107 & _157;
    assign _155 = _104 == _162;
    assign _159 = _155 | _158;
    assign _160 = _159 & _114;
    assign _166 = _160 ? _165 : _161;
    assign _149 = 3'b101;
    assign _150 = _104 == _149;
    assign _151 = _150 ? _124 : _121;
    assign _152 = ~ _151;
    assign _148 = _103[5:5];
    assign _144 = _109 == _149;
    assign _145 = _107 & _144;
    assign _142 = _104 == _149;
    assign _146 = _142 | _145;
    assign _147 = _146 & _114;
    assign _153 = _147 ? _152 : _148;
    assign _136 = 3'b110;
    assign _137 = _104 == _136;
    assign _138 = _137 ? _124 : _121;
    assign _139 = ~ _138;
    assign _135 = _103[6:6];
    assign _131 = _109 == _136;
    assign _132 = _107 & _131;
    assign _129 = _104 == _136;
    assign _133 = _129 | _132;
    assign _134 = _133 & _114;
    assign _140 = _134 ? _139 : _135;
    assign _117 = 3'b111;
    assign _118 = _104 == _117;
    assign _125 = _118 ? _124 : _121;
    assign _126 = ~ _125;
    assign _116 = _103[7:7];
    assign _111 = _109 == _117;
    assign _112 = _107 & _111;
    assign _106 = _104 == _117;
    assign _113 = _106 | _112;
    assign _115 = _113 & _114;
    assign _127 = _115 ? _126 : _116;
    assign _219 = { _127,
                    _140,
                    _153,
                    _166,
                    _179,
                    _192,
                    _205,
                    _218 };
    assign _100 = _56 == _99;
    assign _220 = _100 ? _219 : _103;
    assign _98 = _56 == _97;
    assign _230 = _98 ? _229 : _220;
    assign _10 = _230;
    always @(posedge clock) begin
        if (clear)
            _103 <= _76;
        else
            _103 <= _10;
    end
    assign _336 = imem_data[3:3];
    assign _337 = { _336,
                    _336 };
    assign _338 = { _337,
                    _337 };
    assign _339 = { _338,
                    _338 };
    assign _340 = _221 & _339;
    assign _221 = imem_data[11:4];
    assign _334 = ~ _221;
    assign _335 = _235 & _334;
    assign _341 = _335 | _340;
    assign _328 = _104 == _214;
    assign _329 = _328 ? _124 : _121;
    assign _330 = _114 ? gnd : _329;
    assign _326 = _235[0:0];
    assign _323 = _109 == _214;
    assign _324 = _107 & _323;
    assign _321 = _104 == _214;
    assign _325 = _321 | _324;
    assign _331 = _325 ? _330 : _326;
    assign _316 = _104 == _201;
    assign _317 = _316 ? _124 : _121;
    assign _318 = _114 ? gnd : _317;
    assign _314 = _235[1:1];
    assign _311 = _109 == _201;
    assign _312 = _107 & _311;
    assign _309 = _104 == _201;
    assign _313 = _309 | _312;
    assign _319 = _313 ? _318 : _314;
    assign _304 = _104 == _188;
    assign _305 = _304 ? _124 : _121;
    assign _306 = _114 ? gnd : _305;
    assign _302 = _235[2:2];
    assign _299 = _109 == _188;
    assign _300 = _107 & _299;
    assign _297 = _104 == _188;
    assign _301 = _297 | _300;
    assign _307 = _301 ? _306 : _302;
    assign _292 = _104 == _175;
    assign _293 = _292 ? _124 : _121;
    assign _294 = _114 ? gnd : _293;
    assign _290 = _235[3:3];
    assign _287 = _109 == _175;
    assign _288 = _107 & _287;
    assign _285 = _104 == _175;
    assign _289 = _285 | _288;
    assign _295 = _289 ? _294 : _290;
    assign _280 = _104 == _162;
    assign _281 = _280 ? _124 : _121;
    assign _282 = _114 ? gnd : _281;
    assign _278 = _235[4:4];
    assign _275 = _109 == _162;
    assign _276 = _107 & _275;
    assign _273 = _104 == _162;
    assign _277 = _273 | _276;
    assign _283 = _277 ? _282 : _278;
    assign _268 = _104 == _149;
    assign _269 = _268 ? _124 : _121;
    assign _270 = _114 ? gnd : _269;
    assign _266 = _235[5:5];
    assign _263 = _109 == _149;
    assign _264 = _107 & _263;
    assign _261 = _104 == _149;
    assign _265 = _261 | _264;
    assign _271 = _265 ? _270 : _266;
    assign _256 = _104 == _136;
    assign _257 = _256 ? _124 : _121;
    assign _258 = _114 ? gnd : _257;
    assign _254 = _235[6:6];
    assign _251 = _109 == _136;
    assign _252 = _107 & _251;
    assign _249 = _104 == _136;
    assign _253 = _249 | _252;
    assign _259 = _253 ? _258 : _254;
    assign gnd = 1'b0;
    assign _123 = _93[7:7];
    assign _122 = _93[0:0];
    assign _124 = _72 ? _123 : _122;
    assign _120 = _93[6:6];
    assign _119 = _93[1:1];
    assign _121 = _72 ? _120 : _119;
    assign _244 = _104 == _117;
    assign _245 = _244 ? _124 : _121;
    assign _114 = imem_data[7:7];
    assign _246 = _114 ? gnd : _245;
    assign _242 = _235[7:7];
    assign _109 = _104 + _201;
    assign _239 = _109 == _117;
    assign _240 = _107 & _239;
    assign _237 = _104 == _117;
    assign _241 = _237 | _240;
    assign _247 = _241 ? _246 : _242;
    assign _332 = { _247,
                    _259,
                    _271,
                    _283,
                    _295,
                    _307,
                    _319,
                    _331 };
    assign _232 = _56 == _99;
    assign _333 = _232 ? _332 : _235;
    assign _97 = 4'b0001;
    assign _231 = _56 == _97;
    assign _342 = _231 ? _341 : _333;
    assign _12 = _342;
    always @(posedge clock) begin
        if (clear)
            _235 <= _76;
        else
            _235 <= _12;
    end
    assign _491 = 12'b000000000000;
    assign _492 = _366 == _491;
    assign _493 = _492 ? _482 : _465;
    assign _490 = _424 == _72;
    assign _494 = _490 ? _467 : _493;
    assign _348 = _344 ? _17 : _347;
    assign _14 = _348;
    always @(posedge clock) begin
        if (clear)
            _347 <= _491;
        else
            _347 <= _14;
    end
    assign _354 = _350 ? _17 : _353;
    assign _15 = _354;
    always @(posedge clock) begin
        if (clear)
            _353 <= _491;
        else
            _353 <= _15;
    end
    assign _360 = _356 ? _17 : _359;
    assign _16 = _360;
    always @(posedge clock) begin
        if (clear)
            _359 <= _491;
        else
            _359 <= _16;
    end
    assign _369 = 12'b000000000001;
    assign _370 = _366 - _369;
    assign _368 = _366 == _491;
    assign _371 = _368 ? _366 : _370;
    assign _361 = 4'b0011;
    assign _362 = _56 == _361;
    assign _373 = _362 ? _372 : _371;
    assign _17 = _373;
    assign _376 = _375 ? _17 : _365;
    assign _18 = _376;
    always @(posedge clock) begin
        if (clear)
            _365 <= _491;
        else
            _365 <= _18;
    end
    always @* begin
        case (_80)
        0:
            _366 <= _365;
        1:
            _366 <= _359;
        2:
            _366 <= _353;
        default:
            _366 <= _347;
        endcase
    end
    assign _487 = _366 == _491;
    assign _488 = _487 ? _467 : _465;
    assign _482 = imem_data[7:0];
    assign _380 = _344 ? _22 : _379;
    assign _19 = _380;
    always @(posedge clock) begin
        if (clear)
            _379 <= _491;
        else
            _379 <= _19;
    end
    assign _384 = _350 ? _22 : _383;
    assign _20 = _384;
    always @(posedge clock) begin
        if (clear)
            _383 <= _491;
        else
            _383 <= _20;
    end
    assign _388 = _356 ? _22 : _387;
    assign _21 = _388;
    always @(posedge clock) begin
        if (clear)
            _387 <= _491;
        else
            _387 <= _21;
    end
    assign _372 = imem_data[11:0];
    assign _402 = _397 - _369;
    assign _399 = _397 - _369;
    assign _393 = _56 == _392;
    assign _400 = _393 ? _399 : _397;
    assign _391 = _56 == _99;
    assign _403 = _391 ? _402 : _400;
    assign _389 = 4'b0010;
    assign _390 = _56 == _389;
    assign _404 = _390 ? _372 : _403;
    assign _22 = _404;
    assign _405 = _375 ? _22 : _396;
    assign _23 = _405;
    always @(posedge clock) begin
        if (clear)
            _396 <= _491;
        else
            _396 <= _23;
    end
    always @* begin
        case (_80)
        0:
            _397 <= _396;
        1:
            _397 <= _387;
        2:
            _397 <= _383;
        default:
            _397 <= _379;
        endcase
    end
    assign _480 = _397 == _491;
    assign _481 = ~ _480;
    assign _483 = _481 ? _482 : _467;
    assign _477 = host_in_valid ? _467 : _465;
    assign _472 = 8'b00000010;
    assign _473 = _465 + _472;
    assign _470 = ~ _72;
    assign _406 = _344 ? _30 : _92;
    assign _24 = _406;
    always @(posedge clock) begin
        if (clear)
            _92 <= _76;
        else
            _92 <= _24;
    end
    assign _407 = _350 ? _30 : _89;
    assign _25 = _407;
    always @(posedge clock) begin
        if (clear)
            _89 <= _76;
        else
            _89 <= _25;
    end
    assign _408 = _356 ? _30 : _86;
    assign _26 = _408;
    always @(posedge clock) begin
        if (clear)
            _86 <= _76;
        else
            _86 <= _26;
    end
    assign _94 = imem_data[7:0];
    assign _442 = 2'b00;
    assign _441 = _93[5:0];
    assign _443 = { _441,
                    _442 };
    assign _439 = _93[7:2];
    assign _440 = { _442,
                    _439 };
    assign _444 = _72 ? _443 : _440;
    assign _434 = _93[6:0];
    assign _436 = { _434,
                    _66 };
    assign _432 = _93[7:1];
    assign _433 = { _66,
                    _432 };
    assign _437 = _72 ? _436 : _433;
    assign _107 = imem_data[6:6];
    assign _445 = _107 ? _444 : _437;
    assign _427 = _93[6:0];
    assign _428 = { _427,
                    _424 };
    assign _425 = _93[7:1];
    assign _423 = pin_in[7:7];
    assign _422 = pin_in[6:6];
    assign _421 = pin_in[5:5];
    assign _420 = pin_in[4:4];
    assign _419 = pin_in[3:3];
    assign _418 = pin_in[2:2];
    assign _417 = pin_in[1:1];
    assign _416 = pin_in[0:0];
    assign _104 = imem_data[11:9];
    always @* begin
        case (_104)
        0:
            _424 <= _416;
        1:
            _424 <= _417;
        2:
            _424 <= _418;
        3:
            _424 <= _419;
        4:
            _424 <= _420;
        5:
            _424 <= _421;
        6:
            _424 <= _422;
        default:
            _424 <= _423;
        endcase
    end
    assign _426 = { _424,
                    _425 };
    assign _72 = imem_data[8:8];
    assign _429 = _72 ? _428 : _426;
    assign _414 = host_in_valid ? host_in : _93;
    assign _413 = _56 == _57;
    assign _415 = _413 ? _414 : _93;
    assign _392 = 4'b1000;
    assign _412 = _56 == _392;
    assign _430 = _412 ? _429 : _415;
    assign _99 = 4'b0111;
    assign _411 = _56 == _99;
    assign _446 = _411 ? _445 : _430;
    assign _409 = 4'b0100;
    assign _410 = _56 == _409;
    assign _447 = _410 ? _94 : _446;
    assign _30 = _447;
    assign _448 = _375 ? _30 : _83;
    assign _31 = _448;
    always @(posedge clock) begin
        if (clear)
            _83 <= _76;
        else
            _83 <= _31;
    end
    always @* begin
        case (_80)
        0:
            _93 <= _83;
        1:
            _93 <= _86;
        2:
            _93 <= _89;
        default:
            _93 <= _92;
        endcase
    end
    assign _468 = _93 == _94;
    assign _469 = ~ _468;
    assign _471 = _469 == _470;
    assign _474 = _471 ? _473 : _467;
    assign _466 = 8'b00000001;
    assign _343 = 2'b11;
    assign _344 = _80 == _343;
    assign _449 = _344 ? _36 : _45;
    assign _32 = _449;
    always @(posedge clock) begin
        if (clear)
            _45 <= _76;
        else
            _45 <= _32;
    end
    assign _349 = 2'b10;
    assign _350 = _80 == _349;
    assign _450 = _350 ? _36 : _48;
    assign _33 = _450;
    always @(posedge clock) begin
        if (clear)
            _48 <= _76;
        else
            _48 <= _33;
    end
    assign _355 = 2'b01;
    assign _356 = _80 == _355;
    assign _451 = _356 ? _36 : _51;
    assign _34 = _451;
    always @(posedge clock) begin
        if (clear)
            _51 <= _76;
        else
            _51 <= _34;
    end
    always @* begin
        case (_80)
        0:
            _465 <= _54;
        1:
            _465 <= _51;
        2:
            _465 <= _48;
        default:
            _465 <= _45;
        endcase
    end
    assign _467 = _465 + _466;
    assign _463 = 4'b1110;
    assign _464 = _56 == _463;
    assign _475 = _464 ? _474 : _467;
    assign _461 = 4'b1101;
    assign _462 = _56 == _461;
    assign _476 = _462 ? _465 : _475;
    assign _57 = 4'b1100;
    assign _460 = _56 == _57;
    assign _478 = _460 ? _477 : _476;
    assign _458 = 4'b1010;
    assign _459 = _56 == _458;
    assign _484 = _459 ? _483 : _478;
    assign _456 = 4'b1001;
    assign _457 = _56 == _456;
    assign _485 = _457 ? _482 : _484;
    assign _454 = 4'b0110;
    assign _455 = _56 == _454;
    assign _489 = _455 ? _488 : _485;
    assign _452 = 4'b0101;
    assign _56 = imem_data[15:12];
    assign _453 = _56 == _452;
    assign _495 = _453 ? _494 : _489;
    assign _36 = _495;
    assign _375 = _80 == _442;
    assign _496 = _375 ? _36 : _54;
    assign _37 = _496;
    always @(posedge clock) begin
        if (clear)
            _54 <= _76;
        else
            _54 <= _37;
    end
    always @* begin
        case (_500)
        0:
            _501 <= _54;
        1:
            _501 <= _51;
        2:
            _501 <= _48;
        default:
            _501 <= _45;
        endcase
    end
    assign vdd = 1'b1;
    assign _498 = _80 + _355;
    assign _40 = _498;
    always @(posedge clock) begin
        if (clear)
            _80 <= _442;
        else
            _80 <= _40;
    end
    assign _500 = _80 + _355;
    assign _502 = { _500,
                    _501 };
    assign imem_addr = _502;
    assign pin_out = _235;
    assign pin_oe = _103;
    assign host_out = _77;
    assign host_out_tag = _71;
    assign host_out_valid = _67;
    assign host_in_ready = _2;
    assign pcs = _55;

endmodule
