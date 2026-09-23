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

    wire [31:0] _103;
    wire [31:0] _58;
    wire [31:0] _89;
    wire [31:0] _90;
    wire [31:0] _81;
    wire [30:0] _79;
    wire _78;
    wire [31:0] _80;
    wire [31:0] _82;
    wire [30:0] _76;
    wire [31:0] _77;
    wire _73;
    wire _74;
    wire [31:0] _83;
    wire [31:0] _84;
    wire [31:0] _85;
    wire [31:0] _86;
    wire [31:0] _87;
    wire [31:0] _91;
    wire [31:0] _1;
    reg [31:0] _59;
    wire _104;
    wire _105;
    wire _106;
    wire _2;
    wire _107;
    wire _108;
    wire _4;
    wire [2:0] _130;
    wire [2:0] _110;
    wire [2:0] _128;
    wire [2:0] _122;
    wire [2:0] _112;
    wire [2:0] _113;
    wire [2:0] _123;
    wire [2:0] _124;
    wire [2:0] _125;
    wire [2:0] _126;
    wire [2:0] _129;
    wire [2:0] _6;
    reg [2:0] _111;
    wire _131;
    wire _132;
    wire _133;
    wire _134;
    wire _135;
    wire _136;
    wire _137;
    wire _7;
    wire [7:0] _115;
    wire _143;
    wire [7:0] _119;
    wire _120;
    wire _138;
    wire _139;
    wire _140;
    wire _141;
    wire _142;
    wire _144;
    wire _9;
    reg _71;
    wire _72;
    wire [7:0] _172;
    wire [7:0] _173;
    wire [7:0] _174;
    wire [7:0] _175;
    wire _170;
    wire [5:0] _98;
    wire [5:0] _64;
    wire [5:0] _160;
    wire [5:0] _66;
    wire _67;
    wire _68;
    wire [5:0] _155;
    wire _88;
    wire _147;
    wire _145;
    wire _146;
    wire _148;
    wire _10;
    reg _62;
    wire [5:0] _157;
    wire [5:0] _151;
    wire [5:0] _152;
    wire [5:0] _149;
    wire _150;
    wire [5:0] _153;
    reg _47;
    wire _48;
    wire _49;
    wire _56;
    wire [5:0] _158;
    wire [5:0] _161;
    wire [5:0] _11;
    reg [5:0] _65;
    wire _99;
    wire _100;
    wire [3:0] _95;
    wire [3:0] _93;
    wire [3:0] _164;
    wire [3:0] _165;
    wire [3:0] _162;
    wire _163;
    wire [3:0] _166;
    reg _52;
    reg _55;
    wire [3:0] _168;
    wire [3:0] _13;
    reg [3:0] _94;
    wire _96;
    wire _97;
    wire _101;
    wire _169;
    wire _171;
    wire _14;
    reg _37;
    wire _38;
    wire [7:0] _176;
    wire [7:0] _15;
    reg [7:0] _116;
    wire [6:0] _117;
    reg _41;
    reg _44;
    wire [7:0] _118;
    wire _183;
    wire _184;
    wire _207;
    wire _203;
    wire _204;
    wire _201;
    wire _205;
    wire _199;
    wire _206;
    wire _197;
    wire _208;
    wire _209;
    wire _20;
    reg _179;
    wire _322;
    wire _321;
    wire _320;
    wire _319;
    wire _318;
    wire _317;
    wire _316;
    wire [7:0] _311;
    wire [11:0] _309;
    wire _310;
    wire [7:0] _313;
    wire [7:0] _303;
    wire [7:0] _302;
    wire [7:0] _301;
    wire [7:0] _300;
    wire [7:0] _299;
    wire [7:0] _298;
    wire [7:0] _297;
    wire [7:0] _296;
    wire [7:0] _295;
    wire [7:0] _292;
    wire [7:0] _290;
    wire [7:0] _289;
    wire [7:0] _286;
    wire [7:0] _283;
    wire [7:0] _280;
    wire [7:0] _279;
    wire [7:0] _278;
    wire [7:0] _277;
    wire [7:0] _276;
    wire [7:0] _272;
    wire [7:0] _271;
    wire [7:0] _270;
    wire [7:0] _269;
    wire [7:0] _266;
    wire [7:0] _265;
    wire [7:0] _264;
    wire [7:0] _261;
    wire [7:0] _259;
    wire [7:0] _258;
    wire [7:0] _253;
    wire [7:0] _246;
    reg [7:0] _307;
    wire [7:0] _243;
    wire [7:0] _244;
    wire [7:0] _241;
    wire [7:0] _242;
    wire [7:0] _239;
    wire [7:0] _240;
    wire [31:0] _340;
    wire _336;
    wire [31:0] _341;
    wire [30:0] _329;
    wire [31:0] _330;
    wire [31:0] _332;
    wire [30:0] _326;
    wire [31:0] _327;
    wire _228;
    wire _324;
    wire [31:0] _333;
    wire [2:0] _226;
    wire _227;
    wire [31:0] _334;
    wire [31:0] _342;
    wire [31:0] _343;
    wire [31:0] _344;
    wire [31:0] _345;
    wire [31:0] _21;
    reg [31:0] _212;
    wire [7:0] _237;
    wire [7:0] _238;
    wire [1:0] _236;
    reg [7:0] _245;
    wire _232;
    wire [7:0] _308;
    wire _230;
    wire [7:0] _314;
    wire _315;
    reg _323;
    wire _493;
    wire _494;
    wire _488;
    wire _489;
    wire _487;
    wire _490;
    wire _486;
    wire _491;
    wire _485;
    wire _492;
    wire [2:0] _193;
    wire _194;
    wire _191;
    wire [2:0] _479;
    wire [2:0] _476;
    wire [2:0] _472;
    wire [2:0] _473;
    wire _471;
    wire [2:0] _474;
    wire _470;
    wire [2:0] _477;
    wire _469;
    wire [2:0] _480;
    wire [2:0] _481;
    wire [2:0] _482;
    wire [2:0] _483;
    wire [2:0] _464;
    wire [2:0] _465;
    wire [2:0] _467;
    wire _460;
    wire [2:0] _462;
    wire [2:0] _456;
    wire [2:0] _457;
    wire [23:0] _398;
    wire [23:0] _396;
    wire [3:0] _444;
    wire [11:0] _357;
    wire [11:0] _234;
    wire _338;
    wire [11:0] _368;
    wire [11:0] _362;
    wire _363;
    wire [11:0] _365;
    wire [11:0] _360;
    wire [11:0] _355;
    wire [11:0] _356;
    wire _354;
    wire [11:0] _361;
    wire _352;
    wire [11:0] _366;
    wire _350;
    wire [11:0] _369;
    wire [11:0] _370;
    wire [11:0] _371;
    wire [11:0] _372;
    wire [11:0] _348;
    wire _346;
    wire [11:0] _349;
    wire [11:0] _373;
    wire [11:0] _22;
    reg [11:0] _235;
    wire _358;
    wire [3:0] _433;
    wire _431;
    wire [3:0] _434;
    wire [2:0] _379;
    wire [2:0] _380;
    wire [2:0] _381;
    wire [2:0] _376;
    wire _374;
    wire [2:0] _377;
    wire [2:0] _382;
    wire [2:0] _23;
    reg [2:0] _223;
    wire _225;
    wire [3:0] _435;
    wire _386;
    wire _387;
    wire gnd;
    wire _384;
    wire _383;
    wire _385;
    wire _388;
    wire _24;
    reg _220;
    wire [3:0] _436;
    wire [3:0] _428;
    wire [3:0] _430;
    wire [3:0] _216;
    wire _217;
    wire [3:0] _437;
    wire [23:0] _406;
    wire vdd;
    wire [23:0] _408;
    wire [23:0] _409;
    wire [23:0] _411;
    wire [23:0] _404;
    wire [23:0] _401;
    wire _391;
    wire [23:0] _402;
    wire _390;
    wire [23:0] _405;
    wire _389;
    wire [23:0] _412;
    wire [23:0] _27;
    reg [23:0] _394;
    wire _407;
    wire [3:0] _423;
    wire [3:0] _425;
    wire [3:0] _420;
    wire [3:0] _417;
    wire _415;
    wire [3:0] _418;
    wire _414;
    wire [3:0] _421;
    wire _413;
    wire [3:0] _426;
    wire [3:0] _438;
    wire [3:0] _29;
    reg [3:0] _215;
    wire _445;
    wire [23:0] _447;
    wire [23:0] _442;
    wire _440;
    wire [23:0] _443;
    wire _439;
    wire [23:0] _448;
    wire [23:0] _30;
    reg [23:0] _397;
    wire _399;
    wire [2:0] _454;
    wire _452;
    wire [2:0] _455;
    wire _451;
    wire [2:0] _458;
    wire _450;
    wire [2:0] _463;
    wire _449;
    wire [2:0] _468;
    wire [2:0] _484;
    wire [2:0] _31;
    reg [2:0] _187;
    wire _189;
    wire _192;
    wire _195;
    wire _495;
    wire _32;
    reg _182;
    wire _496;
    assign _103 = 32'b11011110101110110010000011100011;
    assign _58 = 32'b00000000000000000000000000000000;
    assign _89 = 32'b11111111111111111111111111111111;
    assign _90 = _88 ? _89 : _59;
    assign _81 = 32'b11101101101110001000001100100000;
    assign _79 = _59[31:1];
    assign _78 = 1'b0;
    assign _80 = { _78,
                   _79 };
    assign _82 = _80 ^ _81;
    assign _76 = _59[31:1];
    assign _77 = { _78,
                   _76 };
    assign _73 = _59[0:0];
    assign _74 = _73 ^ _44;
    assign _83 = _74 ? _82 : _77;
    assign _84 = _72 ? _59 : _83;
    assign _85 = _68 ? _84 : _59;
    assign _86 = _62 ? _59 : _85;
    assign _87 = _56 ? _86 : _59;
    assign _91 = _38 ? _90 : _87;
    assign _1 = _91;
    always @(posedge clock) begin
        if (clear)
            _59 <= _58;
        else
            _59 <= _1;
    end
    assign _104 = _59 == _103;
    assign _105 = _101 ? _104 : gnd;
    assign _106 = _38 ? gnd : _105;
    assign _2 = _106;
    assign _107 = _101 ? vdd : gnd;
    assign _108 = _38 ? gnd : _107;
    assign _4 = _108;
    assign _130 = 3'b111;
    assign _110 = 3'b000;
    assign _128 = _88 ? _110 : _111;
    assign _122 = _120 ? _110 : _111;
    assign _112 = 3'b001;
    assign _113 = _111 + _112;
    assign _123 = _72 ? _122 : _113;
    assign _124 = _68 ? _123 : _111;
    assign _125 = _62 ? _111 : _124;
    assign _126 = _56 ? _125 : _111;
    assign _129 = _38 ? _128 : _126;
    assign _6 = _129;
    always @(posedge clock) begin
        if (clear)
            _111 <= _110;
        else
            _111 <= _6;
    end
    assign _131 = _111 == _130;
    assign _132 = _131 ? vdd : gnd;
    assign _133 = _72 ? gnd : _132;
    assign _134 = _68 ? _133 : gnd;
    assign _135 = _62 ? gnd : _134;
    assign _136 = _56 ? _135 : gnd;
    assign _137 = _38 ? gnd : _136;
    assign _7 = _137;
    assign _115 = 8'b00000000;
    assign _143 = _88 ? gnd : _71;
    assign _119 = 8'b11010101;
    assign _120 = _118 == _119;
    assign _138 = _120 ? vdd : _71;
    assign _139 = _72 ? _138 : _71;
    assign _140 = _68 ? _139 : _71;
    assign _141 = _62 ? _71 : _140;
    assign _142 = _56 ? _141 : _71;
    assign _144 = _38 ? _143 : _142;
    assign _9 = _144;
    always @(posedge clock) begin
        if (clear)
            _71 <= _78;
        else
            _71 <= _9;
    end
    assign _72 = ~ _71;
    assign _172 = _72 ? _118 : _118;
    assign _173 = _68 ? _172 : _116;
    assign _174 = _62 ? _116 : _173;
    assign _175 = _56 ? _174 : _116;
    assign _170 = _88 ? vdd : _37;
    assign _98 = 6'b001100;
    assign _64 = 6'b000000;
    assign _160 = _88 ? _64 : _153;
    assign _66 = 6'b000100;
    assign _67 = _65 < _66;
    assign _68 = ~ _67;
    assign _155 = _68 ? _64 : _153;
    assign _88 = _55 & _56;
    assign _147 = _88 ? vdd : _62;
    assign _145 = _62 ? gnd : _62;
    assign _146 = _56 ? _145 : _62;
    assign _148 = _38 ? _147 : _146;
    assign _10 = _148;
    always @(posedge clock) begin
        if (clear)
            _62 <= _78;
        else
            _62 <= _10;
    end
    assign _157 = _62 ? _64 : _155;
    assign _151 = 6'b000001;
    assign _152 = _65 + _151;
    assign _149 = 6'b111111;
    assign _150 = _65 == _149;
    assign _153 = _150 ? _65 : _152;
    always @(posedge clock) begin
        if (clear)
            _47 <= _78;
        else
            _47 <= _44;
    end
    assign _48 = _44 == _47;
    assign _49 = ~ _48;
    assign _56 = _49 & _55;
    assign _158 = _56 ? _157 : _153;
    assign _161 = _38 ? _160 : _158;
    assign _11 = _161;
    always @(posedge clock) begin
        if (clear)
            _65 <= _64;
        else
            _65 <= _11;
    end
    assign _99 = _65 < _98;
    assign _100 = ~ _99;
    assign _95 = 4'b0101;
    assign _93 = 4'b0000;
    assign _164 = 4'b0001;
    assign _165 = _94 + _164;
    assign _162 = 4'b1111;
    assign _163 = _94 == _162;
    assign _166 = _163 ? _94 : _165;
    always @(posedge clock) begin
        if (clear)
            _52 <= _78;
        else
            _52 <= rx_active;
    end
    always @(posedge clock) begin
        if (clear)
            _55 <= _78;
        else
            _55 <= _52;
    end
    assign _168 = _55 ? _93 : _166;
    assign _13 = _168;
    always @(posedge clock) begin
        if (clear)
            _94 <= _93;
        else
            _94 <= _13;
    end
    assign _96 = _94 < _95;
    assign _97 = ~ _96;
    assign _101 = _97 | _100;
    assign _169 = _101 ? gnd : _37;
    assign _171 = _38 ? _170 : _169;
    assign _14 = _171;
    always @(posedge clock) begin
        if (clear)
            _37 <= _78;
        else
            _37 <= _14;
    end
    assign _38 = ~ _37;
    assign _176 = _38 ? _116 : _175;
    assign _15 = _176;
    always @(posedge clock) begin
        if (clear)
            _116 <= _115;
        else
            _116 <= _15;
    end
    assign _117 = _116[7:1];
    always @(posedge clock) begin
        if (clear)
            _41 <= _78;
        else
            _41 <= rx;
    end
    always @(posedge clock) begin
        if (clear)
            _44 <= _78;
        else
            _44 <= _41;
    end
    assign _118 = { _44,
                    _117 };
    assign _183 = ~ _182;
    assign _184 = _183 & _179;
    assign _207 = start ? vdd : gnd;
    assign _203 = _187 == _456;
    assign _204 = _203 ? gnd : _179;
    assign _201 = _187 == _472;
    assign _205 = _201 ? vdd : _204;
    assign _199 = _187 == _464;
    assign _206 = _199 ? vdd : _205;
    assign _197 = _187 == _110;
    assign _208 = _197 ? _207 : _206;
    assign _209 = _195 ? vdd : _208;
    assign _20 = _209;
    always @(posedge clock) begin
        if (clear)
            _179 <= _78;
        else
            _179 <= _20;
    end
    assign _322 = _314[7:7];
    assign _321 = _314[6:6];
    assign _320 = _314[5:5];
    assign _319 = _314[4:4];
    assign _318 = _314[3:3];
    assign _317 = _314[2:2];
    assign _316 = _314[1:1];
    assign _311 = 8'b01010101;
    assign _309 = 12'b000000000111;
    assign _310 = _235 == _309;
    assign _313 = _310 ? _119 : _311;
    assign _303 = 8'b01100011;
    assign _302 = 8'b01101001;
    assign _301 = 8'b01110011;
    assign _300 = 8'b01100001;
    assign _299 = 8'b00100000;
    assign _298 = 8'b01101101;
    assign _297 = 8'b01101111;
    assign _296 = 8'b01110010;
    assign _295 = 8'b01100110;
    assign _292 = 8'b01101100;
    assign _290 = 8'b01100101;
    assign _289 = 8'b01101000;
    assign _286 = 8'b00010111;
    assign _283 = 8'b00010000;
    assign _280 = 8'b11111111;
    assign _279 = 8'b00000001;
    assign _278 = 8'b10101000;
    assign _277 = 8'b11000000;
    assign _276 = 8'b11001000;
    assign _272 = 8'b01110110;
    assign _271 = 8'b10100011;
    assign _270 = 8'b00010001;
    assign _269 = 8'b01000000;
    assign _266 = 8'b00110100;
    assign _265 = 8'b00010010;
    assign _264 = 8'b00101011;
    assign _261 = 8'b01000101;
    assign _259 = 8'b00001000;
    assign _258 = 8'b01010110;
    assign _253 = 8'b00000010;
    assign _246 = _235[7:0];
    always @* begin
        case (_246)
        0:
            _307 <= _280;
        1:
            _307 <= _280;
        2:
            _307 <= _280;
        3:
            _307 <= _280;
        4:
            _307 <= _280;
        5:
            _307 <= _280;
        6:
            _307 <= _253;
        7:
            _307 <= _115;
        8:
            _307 <= _115;
        9:
            _307 <= _265;
        10:
            _307 <= _266;
        11:
            _307 <= _258;
        12:
            _307 <= _259;
        13:
            _307 <= _115;
        14:
            _307 <= _261;
        15:
            _307 <= _115;
        16:
            _307 <= _115;
        17:
            _307 <= _264;
        18:
            _307 <= _265;
        19:
            _307 <= _266;
        20:
            _307 <= _269;
        21:
            _307 <= _115;
        22:
            _307 <= _269;
        23:
            _307 <= _270;
        24:
            _307 <= _271;
        25:
            _307 <= _272;
        26:
            _307 <= _277;
        27:
            _307 <= _278;
        28:
            _307 <= _279;
        29:
            _307 <= _276;
        30:
            _307 <= _277;
        31:
            _307 <= _278;
        32:
            _307 <= _279;
        33:
            _307 <= _280;
        34:
            _307 <= _283;
        35:
            _307 <= _115;
        36:
            _307 <= _283;
        37:
            _307 <= _115;
        38:
            _307 <= _115;
        39:
            _307 <= _286;
        40:
            _307 <= _115;
        41:
            _307 <= _115;
        42:
            _307 <= _289;
        43:
            _307 <= _290;
        44:
            _307 <= _292;
        45:
            _307 <= _292;
        46:
            _307 <= _297;
        47:
            _307 <= _299;
        48:
            _307 <= _295;
        49:
            _307 <= _296;
        50:
            _307 <= _297;
        51:
            _307 <= _298;
        52:
            _307 <= _299;
        53:
            _307 <= _300;
        54:
            _307 <= _301;
        55:
            _307 <= _302;
        56:
            _307 <= _303;
        57:
            _307 <= _115;
        58:
            _307 <= _115;
        default:
            _307 <= _115;
        endcase
    end
    assign _243 = _212[31:24];
    assign _244 = ~ _243;
    assign _241 = _212[23:16];
    assign _242 = ~ _241;
    assign _239 = _212[15:8];
    assign _240 = ~ _239;
    assign _340 = _338 ? _89 : _334;
    assign _336 = _187 == _112;
    assign _341 = _336 ? _340 : _334;
    assign _329 = _212[31:1];
    assign _330 = { _78,
                    _329 };
    assign _332 = _330 ^ _81;
    assign _326 = _212[31:1];
    assign _327 = { _78,
                    _326 };
    assign _228 = _212[0:0];
    assign _324 = _228 ^ _323;
    assign _333 = _324 ? _332 : _327;
    assign _226 = 3'b010;
    assign _227 = _187 == _226;
    assign _334 = _227 ? _333 : _212;
    assign _342 = _225 ? _341 : _334;
    assign _343 = _220 ? _342 : _212;
    assign _344 = _217 ? _343 : _212;
    assign _345 = _195 ? _344 : _212;
    assign _21 = _345;
    always @(posedge clock) begin
        if (clear)
            _212 <= _58;
        else
            _212 <= _21;
    end
    assign _237 = _212[7:0];
    assign _238 = ~ _237;
    assign _236 = _235[1:0];
    always @* begin
        case (_236)
        0:
            _245 <= _238;
        1:
            _245 <= _240;
        2:
            _245 <= _242;
        default:
            _245 <= _244;
        endcase
    end
    assign _232 = _187 == _226;
    assign _308 = _232 ? _307 : _245;
    assign _230 = _187 == _112;
    assign _314 = _230 ? _313 : _308;
    assign _315 = _314[0:0];
    always @* begin
        case (_223)
        0:
            _323 <= _315;
        1:
            _323 <= _316;
        2:
            _323 <= _317;
        3:
            _323 <= _318;
        4:
            _323 <= _319;
        5:
            _323 <= _320;
        6:
            _323 <= _321;
        default:
            _323 <= _322;
        endcase
    end
    assign _493 = ~ _323;
    assign _494 = _220 ? _323 : _493;
    assign _488 = _187 == _456;
    assign _489 = _488 ? gnd : _182;
    assign _487 = _187 == _472;
    assign _490 = _487 ? vdd : _489;
    assign _486 = _187 == _464;
    assign _491 = _486 ? vdd : _490;
    assign _485 = _187 == _110;
    assign _492 = _485 ? gnd : _491;
    assign _193 = 3'b011;
    assign _194 = _187 == _193;
    assign _191 = _187 == _226;
    assign _479 = _338 ? _226 : _468;
    assign _476 = _363 ? _193 : _468;
    assign _472 = 3'b100;
    assign _473 = _358 ? _472 : _468;
    assign _471 = _187 == _193;
    assign _474 = _471 ? _473 : _468;
    assign _470 = _187 == _226;
    assign _477 = _470 ? _476 : _474;
    assign _469 = _187 == _112;
    assign _480 = _469 ? _479 : _477;
    assign _481 = _225 ? _480 : _468;
    assign _482 = _220 ? _481 : _468;
    assign _483 = _217 ? _482 : _468;
    assign _464 = 3'b110;
    assign _465 = _407 ? _464 : _187;
    assign _467 = start ? _112 : _465;
    assign _460 = _215 == _95;
    assign _462 = _460 ? _110 : _187;
    assign _456 = 3'b101;
    assign _457 = _445 ? _456 : _187;
    assign _398 = 24'b000000000000000100011111;
    assign _396 = 24'b000000000000000000000000;
    assign _444 = 4'b1000;
    assign _357 = 12'b000000000011;
    assign _234 = 12'b000000000000;
    assign _338 = _235 == _309;
    assign _368 = _338 ? _234 : _356;
    assign _362 = 12'b000000111011;
    assign _363 = _235 == _362;
    assign _365 = _363 ? _234 : _356;
    assign _360 = _358 ? _234 : _356;
    assign _355 = 12'b000000000001;
    assign _356 = _235 + _355;
    assign _354 = _187 == _193;
    assign _361 = _354 ? _360 : _356;
    assign _352 = _187 == _226;
    assign _366 = _352 ? _365 : _361;
    assign _350 = _187 == _112;
    assign _369 = _350 ? _368 : _366;
    assign _370 = _225 ? _369 : _349;
    assign _371 = _220 ? _370 : _349;
    assign _372 = _217 ? _371 : _349;
    assign _348 = start ? _234 : _235;
    assign _346 = _187 == _110;
    assign _349 = _346 ? _348 : _235;
    assign _373 = _195 ? _372 : _349;
    assign _22 = _373;
    always @(posedge clock) begin
        if (clear)
            _235 <= _234;
        else
            _235 <= _22;
    end
    assign _358 = _235 == _357;
    assign _433 = _358 ? _93 : _430;
    assign _431 = _187 == _193;
    assign _434 = _431 ? _433 : _430;
    assign _379 = _223 + _112;
    assign _380 = _220 ? _379 : _377;
    assign _381 = _217 ? _380 : _377;
    assign _376 = start ? _110 : _223;
    assign _374 = _187 == _110;
    assign _377 = _374 ? _376 : _223;
    assign _382 = _195 ? _381 : _377;
    assign _23 = _382;
    always @(posedge clock) begin
        if (clear)
            _223 <= _110;
        else
            _223 <= _23;
    end
    assign _225 = _223 == _130;
    assign _435 = _225 ? _434 : _430;
    assign _386 = ~ _220;
    assign _387 = _217 ? _386 : _385;
    assign gnd = 1'b0;
    assign _384 = start ? gnd : _220;
    assign _383 = _187 == _110;
    assign _385 = _383 ? _384 : _220;
    assign _388 = _195 ? _387 : _385;
    assign _24 = _388;
    always @(posedge clock) begin
        if (clear)
            _220 <= _78;
        else
            _220 <= _24;
    end
    assign _436 = _220 ? _435 : _430;
    assign _428 = _215 + _164;
    assign _430 = _217 ? _93 : _428;
    assign _216 = 4'b0010;
    assign _217 = _215 == _216;
    assign _437 = _217 ? _436 : _430;
    assign _406 = 24'b000011101010010111111111;
    assign vdd = 1'b1;
    assign _408 = 24'b000000000000000000000001;
    assign _409 = _394 + _408;
    assign _411 = _407 ? _396 : _409;
    assign _404 = _394 + _408;
    assign _401 = _399 ? _396 : _394;
    assign _391 = _187 == _456;
    assign _402 = _391 ? _401 : _394;
    assign _390 = _187 == _464;
    assign _405 = _390 ? _404 : _402;
    assign _389 = _187 == _110;
    assign _412 = _389 ? _411 : _405;
    assign _27 = _412;
    always @(posedge clock) begin
        if (clear)
            _394 <= _396;
        else
            _394 <= _27;
    end
    assign _407 = _394 == _406;
    assign _423 = _407 ? _93 : _215;
    assign _425 = start ? _93 : _423;
    assign _420 = _215 + _164;
    assign _417 = _215 + _164;
    assign _415 = _187 == _472;
    assign _418 = _415 ? _417 : _215;
    assign _414 = _187 == _464;
    assign _421 = _414 ? _420 : _418;
    assign _413 = _187 == _110;
    assign _426 = _413 ? _425 : _421;
    assign _438 = _195 ? _437 : _426;
    assign _29 = _438;
    always @(posedge clock) begin
        if (clear)
            _215 <= _93;
        else
            _215 <= _29;
    end
    assign _445 = _215 == _444;
    assign _447 = _445 ? _396 : _397;
    assign _442 = _397 + _408;
    assign _440 = _187 == _456;
    assign _443 = _440 ? _442 : _397;
    assign _439 = _187 == _472;
    assign _448 = _439 ? _447 : _443;
    assign _30 = _448;
    always @(posedge clock) begin
        if (clear)
            _397 <= _396;
        else
            _397 <= _30;
    end
    assign _399 = _397 == _398;
    assign _454 = _399 ? _110 : _187;
    assign _452 = _187 == _456;
    assign _455 = _452 ? _454 : _187;
    assign _451 = _187 == _472;
    assign _458 = _451 ? _457 : _455;
    assign _450 = _187 == _464;
    assign _463 = _450 ? _462 : _458;
    assign _449 = _187 == _110;
    assign _468 = _449 ? _467 : _463;
    assign _484 = _195 ? _483 : _468;
    assign _31 = _484;
    always @(posedge clock) begin
        if (clear)
            _187 <= _110;
        else
            _187 <= _31;
    end
    assign _189 = _187 == _112;
    assign _192 = _189 | _191;
    assign _195 = _192 | _194;
    assign _495 = _195 ? _494 : _492;
    assign _32 = _495;
    always @(posedge clock) begin
        if (clear)
            _182 <= _78;
        else
            _182 <= _32;
    end
    assign _496 = _182 & _179;
    assign txp = _496;
    assign txn = _184;
    assign txen = _179;
    assign rx_byte = _118;
    assign byte_valid = _7;
    assign frame_end = _4;
    assign crc_ok = _2;

endmodule
