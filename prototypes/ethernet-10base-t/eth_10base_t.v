module eth_10base_t (
    rx_active,
    rx,
    clear,
    clock,
    start,
    txp,
    txn,
    txen,
    rx_byte,
    byte_valid,
    frame_end,
    crc_ok
);

    input rx_active;
    input rx;
    input clear;
    input clock;
    input start;
    output txp;
    output txn;
    output txen;
    output [7:0] rx_byte;
    output byte_valid;
    output frame_end;
    output crc_ok;

    wire [31:0] _97;
    wire [31:0] _57;
    wire [31:0] _88;
    wire [31:0] _89;
    wire [31:0] _80;
    wire [30:0] _78;
    wire _77;
    wire [31:0] _79;
    wire [31:0] _81;
    wire [30:0] _75;
    wire [31:0] _76;
    wire _72;
    wire _73;
    wire [31:0] _82;
    wire [31:0] _83;
    wire [31:0] _84;
    wire [31:0] _85;
    wire [31:0] _86;
    wire [31:0] _90;
    wire [31:0] _1;
    reg [31:0] _58;
    wire _98;
    wire _99;
    wire _100;
    wire _2;
    wire _101;
    wire _102;
    wire _4;
    wire [2:0] _124;
    wire [2:0] _104;
    wire [2:0] _122;
    wire [2:0] _116;
    wire [2:0] _106;
    wire [2:0] _107;
    wire [2:0] _117;
    wire [2:0] _118;
    wire [2:0] _119;
    wire [2:0] _120;
    wire [2:0] _123;
    wire [2:0] _6;
    reg [2:0] _105;
    wire _125;
    wire _126;
    wire _127;
    wire _128;
    wire _129;
    wire _130;
    wire _131;
    wire _7;
    wire [7:0] _109;
    wire _137;
    wire [7:0] _113;
    wire _114;
    wire _132;
    wire _133;
    wire _134;
    wire _135;
    wire _136;
    wire _138;
    wire _9;
    reg _70;
    wire _71;
    wire [7:0] _159;
    wire [7:0] _160;
    wire [7:0] _161;
    wire [7:0] _162;
    wire _157;
    wire [5:0] _92;
    wire [5:0] _63;
    wire [5:0] _154;
    wire [5:0] _65;
    wire _66;
    wire _67;
    wire [5:0] _149;
    wire _87;
    wire _141;
    wire _139;
    wire _140;
    wire _142;
    wire _10;
    reg _61;
    wire [5:0] _151;
    wire [5:0] _145;
    wire [5:0] _146;
    wire [5:0] _143;
    wire _144;
    wire [5:0] _147;
    reg _46;
    wire _47;
    wire _48;
    wire _55;
    wire [5:0] _152;
    wire [5:0] _155;
    wire [5:0] _11;
    reg [5:0] _64;
    wire _93;
    wire _94;
    reg _51;
    reg _54;
    wire _91;
    wire _95;
    wire _156;
    wire _158;
    wire _13;
    reg _36;
    wire _37;
    wire [7:0] _163;
    wire [7:0] _14;
    reg [7:0] _110;
    wire [6:0] _111;
    reg _40;
    reg _43;
    wire [7:0] _112;
    wire _170;
    wire _171;
    wire _194;
    wire _190;
    wire _191;
    wire _188;
    wire _192;
    wire _186;
    wire _193;
    wire _184;
    wire _195;
    wire _196;
    wire _19;
    reg _166;
    wire _309;
    wire _308;
    wire _307;
    wire _306;
    wire _305;
    wire _304;
    wire _303;
    wire [7:0] _298;
    wire [11:0] _296;
    wire _297;
    wire [7:0] _300;
    wire [7:0] _290;
    wire [7:0] _289;
    wire [7:0] _288;
    wire [7:0] _287;
    wire [7:0] _286;
    wire [7:0] _285;
    wire [7:0] _284;
    wire [7:0] _283;
    wire [7:0] _282;
    wire [7:0] _279;
    wire [7:0] _277;
    wire [7:0] _276;
    wire [7:0] _273;
    wire [7:0] _270;
    wire [7:0] _267;
    wire [7:0] _266;
    wire [7:0] _265;
    wire [7:0] _264;
    wire [7:0] _263;
    wire [7:0] _259;
    wire [7:0] _258;
    wire [7:0] _257;
    wire [7:0] _256;
    wire [7:0] _253;
    wire [7:0] _252;
    wire [7:0] _251;
    wire [7:0] _248;
    wire [7:0] _246;
    wire [7:0] _245;
    wire [7:0] _240;
    wire [7:0] _233;
    reg [7:0] _294;
    wire [7:0] _230;
    wire [7:0] _231;
    wire [7:0] _228;
    wire [7:0] _229;
    wire [7:0] _226;
    wire [7:0] _227;
    wire [31:0] _327;
    wire _323;
    wire [31:0] _328;
    wire [30:0] _316;
    wire [31:0] _317;
    wire [31:0] _319;
    wire [30:0] _313;
    wire [31:0] _314;
    wire _215;
    wire _311;
    wire [31:0] _320;
    wire [2:0] _213;
    wire _214;
    wire [31:0] _321;
    wire [31:0] _329;
    wire [31:0] _330;
    wire [31:0] _331;
    wire [31:0] _332;
    wire [31:0] _20;
    reg [31:0] _199;
    wire [7:0] _224;
    wire [7:0] _225;
    wire [1:0] _223;
    reg [7:0] _232;
    wire _219;
    wire [7:0] _295;
    wire _217;
    wire [7:0] _301;
    wire _302;
    reg _310;
    wire _480;
    wire _481;
    wire _475;
    wire _476;
    wire _474;
    wire _477;
    wire _473;
    wire _478;
    wire _472;
    wire _479;
    wire [2:0] _180;
    wire _181;
    wire _178;
    wire [2:0] _466;
    wire [2:0] _463;
    wire [2:0] _459;
    wire [2:0] _460;
    wire _458;
    wire [2:0] _461;
    wire _457;
    wire [2:0] _464;
    wire _456;
    wire [2:0] _467;
    wire [2:0] _468;
    wire [2:0] _469;
    wire [2:0] _470;
    wire [2:0] _451;
    wire [2:0] _452;
    wire [2:0] _454;
    wire [3:0] _446;
    wire _447;
    wire [2:0] _449;
    wire [2:0] _443;
    wire [2:0] _444;
    wire [23:0] _385;
    wire [23:0] _383;
    wire [3:0] _431;
    wire [3:0] _201;
    wire [11:0] _344;
    wire [11:0] _221;
    wire _325;
    wire [11:0] _355;
    wire [11:0] _349;
    wire _350;
    wire [11:0] _352;
    wire [11:0] _347;
    wire [11:0] _342;
    wire [11:0] _343;
    wire _341;
    wire [11:0] _348;
    wire _339;
    wire [11:0] _353;
    wire _337;
    wire [11:0] _356;
    wire [11:0] _357;
    wire [11:0] _358;
    wire [11:0] _359;
    wire [11:0] _335;
    wire _333;
    wire [11:0] _336;
    wire [11:0] _360;
    wire [11:0] _21;
    reg [11:0] _222;
    wire _345;
    wire [3:0] _420;
    wire _418;
    wire [3:0] _421;
    wire [2:0] _366;
    wire [2:0] _367;
    wire [2:0] _368;
    wire [2:0] _363;
    wire _361;
    wire [2:0] _364;
    wire [2:0] _369;
    wire [2:0] _22;
    reg [2:0] _210;
    wire _212;
    wire [3:0] _422;
    wire _373;
    wire _374;
    wire gnd;
    wire _371;
    wire _370;
    wire _372;
    wire _375;
    wire _23;
    reg _207;
    wire [3:0] _423;
    wire [3:0] _414;
    wire [3:0] _415;
    wire [3:0] _417;
    wire [3:0] _203;
    wire _204;
    wire [3:0] _424;
    wire [23:0] _393;
    wire vdd;
    wire [23:0] _395;
    wire [23:0] _396;
    wire [23:0] _398;
    wire [23:0] _391;
    wire [23:0] _388;
    wire _378;
    wire [23:0] _389;
    wire _377;
    wire [23:0] _392;
    wire _376;
    wire [23:0] _399;
    wire [23:0] _26;
    reg [23:0] _381;
    wire _394;
    wire [3:0] _410;
    wire [3:0] _412;
    wire [3:0] _407;
    wire [3:0] _404;
    wire _402;
    wire [3:0] _405;
    wire _401;
    wire [3:0] _408;
    wire _400;
    wire [3:0] _413;
    wire [3:0] _425;
    wire [3:0] _28;
    reg [3:0] _202;
    wire _432;
    wire [23:0] _434;
    wire [23:0] _429;
    wire _427;
    wire [23:0] _430;
    wire _426;
    wire [23:0] _435;
    wire [23:0] _29;
    reg [23:0] _384;
    wire _386;
    wire [2:0] _441;
    wire _439;
    wire [2:0] _442;
    wire _438;
    wire [2:0] _445;
    wire _437;
    wire [2:0] _450;
    wire _436;
    wire [2:0] _455;
    wire [2:0] _471;
    wire [2:0] _30;
    reg [2:0] _174;
    wire _176;
    wire _179;
    wire _182;
    wire _482;
    wire _31;
    reg _169;
    wire _483;
    assign _97 = 32'b11011110101110110010000011100011;
    assign _57 = 32'b00000000000000000000000000000000;
    assign _88 = 32'b11111111111111111111111111111111;
    assign _89 = _87 ? _88 : _58;
    assign _80 = 32'b11101101101110001000001100100000;
    assign _78 = _58[31:1];
    assign _77 = 1'b0;
    assign _79 = { _77,
                   _78 };
    assign _81 = _79 ^ _80;
    assign _75 = _58[31:1];
    assign _76 = { _77,
                   _75 };
    assign _72 = _58[0:0];
    assign _73 = _72 ^ _43;
    assign _82 = _73 ? _81 : _76;
    assign _83 = _71 ? _58 : _82;
    assign _84 = _67 ? _83 : _58;
    assign _85 = _61 ? _58 : _84;
    assign _86 = _55 ? _85 : _58;
    assign _90 = _37 ? _89 : _86;
    assign _1 = _90;
    always @(posedge clock) begin
        if (clear)
            _58 <= _57;
        else
            _58 <= _1;
    end
    assign _98 = _58 == _97;
    assign _99 = _95 ? _98 : gnd;
    assign _100 = _37 ? gnd : _99;
    assign _2 = _100;
    assign _101 = _95 ? vdd : gnd;
    assign _102 = _37 ? gnd : _101;
    assign _4 = _102;
    assign _124 = 3'b111;
    assign _104 = 3'b000;
    assign _122 = _87 ? _104 : _105;
    assign _116 = _114 ? _104 : _105;
    assign _106 = 3'b001;
    assign _107 = _105 + _106;
    assign _117 = _71 ? _116 : _107;
    assign _118 = _67 ? _117 : _105;
    assign _119 = _61 ? _105 : _118;
    assign _120 = _55 ? _119 : _105;
    assign _123 = _37 ? _122 : _120;
    assign _6 = _123;
    always @(posedge clock) begin
        if (clear)
            _105 <= _104;
        else
            _105 <= _6;
    end
    assign _125 = _105 == _124;
    assign _126 = _125 ? vdd : gnd;
    assign _127 = _71 ? gnd : _126;
    assign _128 = _67 ? _127 : gnd;
    assign _129 = _61 ? gnd : _128;
    assign _130 = _55 ? _129 : gnd;
    assign _131 = _37 ? gnd : _130;
    assign _7 = _131;
    assign _109 = 8'b00000000;
    assign _137 = _87 ? gnd : _70;
    assign _113 = 8'b11010101;
    assign _114 = _112 == _113;
    assign _132 = _114 ? vdd : _70;
    assign _133 = _71 ? _132 : _70;
    assign _134 = _67 ? _133 : _70;
    assign _135 = _61 ? _70 : _134;
    assign _136 = _55 ? _135 : _70;
    assign _138 = _37 ? _137 : _136;
    assign _9 = _138;
    always @(posedge clock) begin
        if (clear)
            _70 <= _77;
        else
            _70 <= _9;
    end
    assign _71 = ~ _70;
    assign _159 = _71 ? _112 : _112;
    assign _160 = _67 ? _159 : _110;
    assign _161 = _61 ? _110 : _160;
    assign _162 = _55 ? _161 : _110;
    assign _157 = _87 ? vdd : _36;
    assign _92 = 6'b001100;
    assign _63 = 6'b000000;
    assign _154 = _87 ? _63 : _147;
    assign _65 = 6'b000100;
    assign _66 = _64 < _65;
    assign _67 = ~ _66;
    assign _149 = _67 ? _63 : _147;
    assign _87 = _54 & _55;
    assign _141 = _87 ? vdd : _61;
    assign _139 = _61 ? gnd : _61;
    assign _140 = _55 ? _139 : _61;
    assign _142 = _37 ? _141 : _140;
    assign _10 = _142;
    always @(posedge clock) begin
        if (clear)
            _61 <= _77;
        else
            _61 <= _10;
    end
    assign _151 = _61 ? _63 : _149;
    assign _145 = 6'b000001;
    assign _146 = _64 + _145;
    assign _143 = 6'b111111;
    assign _144 = _64 == _143;
    assign _147 = _144 ? _64 : _146;
    always @(posedge clock) begin
        if (clear)
            _46 <= _77;
        else
            _46 <= _43;
    end
    assign _47 = _43 == _46;
    assign _48 = ~ _47;
    assign _55 = _48 & _54;
    assign _152 = _55 ? _151 : _147;
    assign _155 = _37 ? _154 : _152;
    assign _11 = _155;
    always @(posedge clock) begin
        if (clear)
            _64 <= _63;
        else
            _64 <= _11;
    end
    assign _93 = _64 < _92;
    assign _94 = ~ _93;
    always @(posedge clock) begin
        if (clear)
            _51 <= _77;
        else
            _51 <= rx_active;
    end
    always @(posedge clock) begin
        if (clear)
            _54 <= _77;
        else
            _54 <= _51;
    end
    assign _91 = ~ _54;
    assign _95 = _91 | _94;
    assign _156 = _95 ? gnd : _36;
    assign _158 = _37 ? _157 : _156;
    assign _13 = _158;
    always @(posedge clock) begin
        if (clear)
            _36 <= _77;
        else
            _36 <= _13;
    end
    assign _37 = ~ _36;
    assign _163 = _37 ? _110 : _162;
    assign _14 = _163;
    always @(posedge clock) begin
        if (clear)
            _110 <= _109;
        else
            _110 <= _14;
    end
    assign _111 = _110[7:1];
    always @(posedge clock) begin
        if (clear)
            _40 <= _77;
        else
            _40 <= rx;
    end
    always @(posedge clock) begin
        if (clear)
            _43 <= _77;
        else
            _43 <= _40;
    end
    assign _112 = { _43,
                    _111 };
    assign _170 = ~ _169;
    assign _171 = _170 & _166;
    assign _194 = start ? vdd : gnd;
    assign _190 = _174 == _443;
    assign _191 = _190 ? gnd : _166;
    assign _188 = _174 == _459;
    assign _192 = _188 ? vdd : _191;
    assign _186 = _174 == _451;
    assign _193 = _186 ? vdd : _192;
    assign _184 = _174 == _104;
    assign _195 = _184 ? _194 : _193;
    assign _196 = _182 ? vdd : _195;
    assign _19 = _196;
    always @(posedge clock) begin
        if (clear)
            _166 <= _77;
        else
            _166 <= _19;
    end
    assign _309 = _301[7:7];
    assign _308 = _301[6:6];
    assign _307 = _301[5:5];
    assign _306 = _301[4:4];
    assign _305 = _301[3:3];
    assign _304 = _301[2:2];
    assign _303 = _301[1:1];
    assign _298 = 8'b01010101;
    assign _296 = 12'b000000000111;
    assign _297 = _222 == _296;
    assign _300 = _297 ? _113 : _298;
    assign _290 = 8'b01100011;
    assign _289 = 8'b01101001;
    assign _288 = 8'b01110011;
    assign _287 = 8'b01100001;
    assign _286 = 8'b00100000;
    assign _285 = 8'b01101101;
    assign _284 = 8'b01101111;
    assign _283 = 8'b01110010;
    assign _282 = 8'b01100110;
    assign _279 = 8'b01101100;
    assign _277 = 8'b01100101;
    assign _276 = 8'b01101000;
    assign _273 = 8'b00010111;
    assign _270 = 8'b00010000;
    assign _267 = 8'b11111111;
    assign _266 = 8'b00000001;
    assign _265 = 8'b10101000;
    assign _264 = 8'b11000000;
    assign _263 = 8'b11001000;
    assign _259 = 8'b01110110;
    assign _258 = 8'b10100011;
    assign _257 = 8'b00010001;
    assign _256 = 8'b01000000;
    assign _253 = 8'b00110100;
    assign _252 = 8'b00010010;
    assign _251 = 8'b00101011;
    assign _248 = 8'b01000101;
    assign _246 = 8'b00001000;
    assign _245 = 8'b01010110;
    assign _240 = 8'b00000010;
    assign _233 = _222[7:0];
    always @* begin
        case (_233)
        0:
            _294 <= _267;
        1:
            _294 <= _267;
        2:
            _294 <= _267;
        3:
            _294 <= _267;
        4:
            _294 <= _267;
        5:
            _294 <= _267;
        6:
            _294 <= _240;
        7:
            _294 <= _109;
        8:
            _294 <= _109;
        9:
            _294 <= _252;
        10:
            _294 <= _253;
        11:
            _294 <= _245;
        12:
            _294 <= _246;
        13:
            _294 <= _109;
        14:
            _294 <= _248;
        15:
            _294 <= _109;
        16:
            _294 <= _109;
        17:
            _294 <= _251;
        18:
            _294 <= _252;
        19:
            _294 <= _253;
        20:
            _294 <= _256;
        21:
            _294 <= _109;
        22:
            _294 <= _256;
        23:
            _294 <= _257;
        24:
            _294 <= _258;
        25:
            _294 <= _259;
        26:
            _294 <= _264;
        27:
            _294 <= _265;
        28:
            _294 <= _266;
        29:
            _294 <= _263;
        30:
            _294 <= _264;
        31:
            _294 <= _265;
        32:
            _294 <= _266;
        33:
            _294 <= _267;
        34:
            _294 <= _270;
        35:
            _294 <= _109;
        36:
            _294 <= _270;
        37:
            _294 <= _109;
        38:
            _294 <= _109;
        39:
            _294 <= _273;
        40:
            _294 <= _109;
        41:
            _294 <= _109;
        42:
            _294 <= _276;
        43:
            _294 <= _277;
        44:
            _294 <= _279;
        45:
            _294 <= _279;
        46:
            _294 <= _284;
        47:
            _294 <= _286;
        48:
            _294 <= _282;
        49:
            _294 <= _283;
        50:
            _294 <= _284;
        51:
            _294 <= _285;
        52:
            _294 <= _286;
        53:
            _294 <= _287;
        54:
            _294 <= _288;
        55:
            _294 <= _289;
        56:
            _294 <= _290;
        57:
            _294 <= _109;
        58:
            _294 <= _109;
        default:
            _294 <= _109;
        endcase
    end
    assign _230 = _199[31:24];
    assign _231 = ~ _230;
    assign _228 = _199[23:16];
    assign _229 = ~ _228;
    assign _226 = _199[15:8];
    assign _227 = ~ _226;
    assign _327 = _325 ? _88 : _321;
    assign _323 = _174 == _106;
    assign _328 = _323 ? _327 : _321;
    assign _316 = _199[31:1];
    assign _317 = { _77,
                    _316 };
    assign _319 = _317 ^ _80;
    assign _313 = _199[31:1];
    assign _314 = { _77,
                    _313 };
    assign _215 = _199[0:0];
    assign _311 = _215 ^ _310;
    assign _320 = _311 ? _319 : _314;
    assign _213 = 3'b010;
    assign _214 = _174 == _213;
    assign _321 = _214 ? _320 : _199;
    assign _329 = _212 ? _328 : _321;
    assign _330 = _207 ? _329 : _199;
    assign _331 = _204 ? _330 : _199;
    assign _332 = _182 ? _331 : _199;
    assign _20 = _332;
    always @(posedge clock) begin
        if (clear)
            _199 <= _57;
        else
            _199 <= _20;
    end
    assign _224 = _199[7:0];
    assign _225 = ~ _224;
    assign _223 = _222[1:0];
    always @* begin
        case (_223)
        0:
            _232 <= _225;
        1:
            _232 <= _227;
        2:
            _232 <= _229;
        default:
            _232 <= _231;
        endcase
    end
    assign _219 = _174 == _213;
    assign _295 = _219 ? _294 : _232;
    assign _217 = _174 == _106;
    assign _301 = _217 ? _300 : _295;
    assign _302 = _301[0:0];
    always @* begin
        case (_210)
        0:
            _310 <= _302;
        1:
            _310 <= _303;
        2:
            _310 <= _304;
        3:
            _310 <= _305;
        4:
            _310 <= _306;
        5:
            _310 <= _307;
        6:
            _310 <= _308;
        default:
            _310 <= _309;
        endcase
    end
    assign _480 = ~ _310;
    assign _481 = _207 ? _310 : _480;
    assign _475 = _174 == _443;
    assign _476 = _475 ? gnd : _169;
    assign _474 = _174 == _459;
    assign _477 = _474 ? vdd : _476;
    assign _473 = _174 == _451;
    assign _478 = _473 ? vdd : _477;
    assign _472 = _174 == _104;
    assign _479 = _472 ? gnd : _478;
    assign _180 = 3'b011;
    assign _181 = _174 == _180;
    assign _178 = _174 == _213;
    assign _466 = _325 ? _213 : _455;
    assign _463 = _350 ? _180 : _455;
    assign _459 = 3'b100;
    assign _460 = _345 ? _459 : _455;
    assign _458 = _174 == _180;
    assign _461 = _458 ? _460 : _455;
    assign _457 = _174 == _213;
    assign _464 = _457 ? _463 : _461;
    assign _456 = _174 == _106;
    assign _467 = _456 ? _466 : _464;
    assign _468 = _212 ? _467 : _455;
    assign _469 = _207 ? _468 : _455;
    assign _470 = _204 ? _469 : _455;
    assign _451 = 3'b110;
    assign _452 = _394 ? _451 : _174;
    assign _454 = start ? _106 : _452;
    assign _446 = 4'b0101;
    assign _447 = _202 == _446;
    assign _449 = _447 ? _104 : _174;
    assign _443 = 3'b101;
    assign _444 = _432 ? _443 : _174;
    assign _385 = 24'b000000000000000100011111;
    assign _383 = 24'b000000000000000000000000;
    assign _431 = 4'b1000;
    assign _201 = 4'b0000;
    assign _344 = 12'b000000000011;
    assign _221 = 12'b000000000000;
    assign _325 = _222 == _296;
    assign _355 = _325 ? _221 : _343;
    assign _349 = 12'b000000111011;
    assign _350 = _222 == _349;
    assign _352 = _350 ? _221 : _343;
    assign _347 = _345 ? _221 : _343;
    assign _342 = 12'b000000000001;
    assign _343 = _222 + _342;
    assign _341 = _174 == _180;
    assign _348 = _341 ? _347 : _343;
    assign _339 = _174 == _213;
    assign _353 = _339 ? _352 : _348;
    assign _337 = _174 == _106;
    assign _356 = _337 ? _355 : _353;
    assign _357 = _212 ? _356 : _336;
    assign _358 = _207 ? _357 : _336;
    assign _359 = _204 ? _358 : _336;
    assign _335 = start ? _221 : _222;
    assign _333 = _174 == _104;
    assign _336 = _333 ? _335 : _222;
    assign _360 = _182 ? _359 : _336;
    assign _21 = _360;
    always @(posedge clock) begin
        if (clear)
            _222 <= _221;
        else
            _222 <= _21;
    end
    assign _345 = _222 == _344;
    assign _420 = _345 ? _201 : _417;
    assign _418 = _174 == _180;
    assign _421 = _418 ? _420 : _417;
    assign _366 = _210 + _106;
    assign _367 = _207 ? _366 : _364;
    assign _368 = _204 ? _367 : _364;
    assign _363 = start ? _104 : _210;
    assign _361 = _174 == _104;
    assign _364 = _361 ? _363 : _210;
    assign _369 = _182 ? _368 : _364;
    assign _22 = _369;
    always @(posedge clock) begin
        if (clear)
            _210 <= _104;
        else
            _210 <= _22;
    end
    assign _212 = _210 == _124;
    assign _422 = _212 ? _421 : _417;
    assign _373 = ~ _207;
    assign _374 = _204 ? _373 : _372;
    assign gnd = 1'b0;
    assign _371 = start ? gnd : _207;
    assign _370 = _174 == _104;
    assign _372 = _370 ? _371 : _207;
    assign _375 = _182 ? _374 : _372;
    assign _23 = _375;
    always @(posedge clock) begin
        if (clear)
            _207 <= _77;
        else
            _207 <= _23;
    end
    assign _423 = _207 ? _422 : _417;
    assign _414 = 4'b0001;
    assign _415 = _202 + _414;
    assign _417 = _204 ? _201 : _415;
    assign _203 = 4'b0010;
    assign _204 = _202 == _203;
    assign _424 = _204 ? _423 : _417;
    assign _393 = 24'b000011101010010111111111;
    assign vdd = 1'b1;
    assign _395 = 24'b000000000000000000000001;
    assign _396 = _381 + _395;
    assign _398 = _394 ? _383 : _396;
    assign _391 = _381 + _395;
    assign _388 = _386 ? _383 : _381;
    assign _378 = _174 == _443;
    assign _389 = _378 ? _388 : _381;
    assign _377 = _174 == _451;
    assign _392 = _377 ? _391 : _389;
    assign _376 = _174 == _104;
    assign _399 = _376 ? _398 : _392;
    assign _26 = _399;
    always @(posedge clock) begin
        if (clear)
            _381 <= _383;
        else
            _381 <= _26;
    end
    assign _394 = _381 == _393;
    assign _410 = _394 ? _201 : _202;
    assign _412 = start ? _201 : _410;
    assign _407 = _202 + _414;
    assign _404 = _202 + _414;
    assign _402 = _174 == _459;
    assign _405 = _402 ? _404 : _202;
    assign _401 = _174 == _451;
    assign _408 = _401 ? _407 : _405;
    assign _400 = _174 == _104;
    assign _413 = _400 ? _412 : _408;
    assign _425 = _182 ? _424 : _413;
    assign _28 = _425;
    always @(posedge clock) begin
        if (clear)
            _202 <= _201;
        else
            _202 <= _28;
    end
    assign _432 = _202 == _431;
    assign _434 = _432 ? _383 : _384;
    assign _429 = _384 + _395;
    assign _427 = _174 == _443;
    assign _430 = _427 ? _429 : _384;
    assign _426 = _174 == _459;
    assign _435 = _426 ? _434 : _430;
    assign _29 = _435;
    always @(posedge clock) begin
        if (clear)
            _384 <= _383;
        else
            _384 <= _29;
    end
    assign _386 = _384 == _385;
    assign _441 = _386 ? _104 : _174;
    assign _439 = _174 == _443;
    assign _442 = _439 ? _441 : _174;
    assign _438 = _174 == _459;
    assign _445 = _438 ? _444 : _442;
    assign _437 = _174 == _451;
    assign _450 = _437 ? _449 : _445;
    assign _436 = _174 == _104;
    assign _455 = _436 ? _454 : _450;
    assign _471 = _182 ? _470 : _455;
    assign _30 = _471;
    always @(posedge clock) begin
        if (clear)
            _174 <= _104;
        else
            _174 <= _30;
    end
    assign _176 = _174 == _106;
    assign _179 = _176 | _178;
    assign _182 = _179 | _181;
    assign _482 = _182 ? _481 : _479;
    assign _31 = _482;
    always @(posedge clock) begin
        if (clear)
            _169 <= _77;
        else
            _169 <= _31;
    end
    assign _483 = _169 & _166;
    assign txp = _483;
    assign txn = _171;
    assign txen = _166;
    assign rx_byte = _112;
    assign byte_valid = _7;
    assign frame_end = _4;
    assign crc_ok = _2;

endmodule
