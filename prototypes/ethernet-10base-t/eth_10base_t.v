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
    wire [7:0] _177;
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
    wire [7:0] _178;
    wire [7:0] _15;
    reg [7:0] _116;
    wire [6:0] _117;
    reg _41;
    reg _44;
    wire [7:0] _118;
    wire _185;
    wire _186;
    wire _209;
    wire _205;
    wire _206;
    wire _203;
    wire _207;
    wire _201;
    wire _208;
    wire _199;
    wire _210;
    wire _211;
    wire _20;
    reg _181;
    wire _324;
    wire _323;
    wire _322;
    wire _321;
    wire _320;
    wire _319;
    wire _318;
    wire [7:0] _313;
    wire [11:0] _311;
    wire _312;
    wire [7:0] _315;
    wire [7:0] _305;
    wire [7:0] _304;
    wire [7:0] _303;
    wire [7:0] _302;
    wire [7:0] _301;
    wire [7:0] _300;
    wire [7:0] _299;
    wire [7:0] _298;
    wire [7:0] _297;
    wire [7:0] _294;
    wire [7:0] _292;
    wire [7:0] _291;
    wire [7:0] _288;
    wire [7:0] _285;
    wire [7:0] _282;
    wire [7:0] _281;
    wire [7:0] _280;
    wire [7:0] _279;
    wire [7:0] _278;
    wire [7:0] _274;
    wire [7:0] _273;
    wire [7:0] _272;
    wire [7:0] _271;
    wire [7:0] _268;
    wire [7:0] _267;
    wire [7:0] _266;
    wire [7:0] _263;
    wire [7:0] _261;
    wire [7:0] _260;
    wire [7:0] _255;
    wire [7:0] _248;
    reg [7:0] _309;
    wire [7:0] _245;
    wire [7:0] _246;
    wire [7:0] _243;
    wire [7:0] _244;
    wire [7:0] _241;
    wire [7:0] _242;
    wire [31:0] _342;
    wire _338;
    wire [31:0] _343;
    wire [30:0] _331;
    wire [31:0] _332;
    wire [31:0] _334;
    wire [30:0] _328;
    wire [31:0] _329;
    wire _230;
    wire _326;
    wire [31:0] _335;
    wire [2:0] _228;
    wire _229;
    wire [31:0] _336;
    wire [31:0] _344;
    wire [31:0] _345;
    wire [31:0] _346;
    wire [31:0] _347;
    wire [31:0] _21;
    reg [31:0] _214;
    wire [7:0] _239;
    wire [7:0] _240;
    wire [1:0] _238;
    reg [7:0] _247;
    wire _234;
    wire [7:0] _310;
    wire _232;
    wire [7:0] _316;
    wire _317;
    reg _325;
    wire _495;
    wire _496;
    wire _490;
    wire _491;
    wire _489;
    wire _492;
    wire _488;
    wire _493;
    wire _487;
    wire _494;
    wire [2:0] _195;
    wire _196;
    wire _193;
    wire [2:0] _481;
    wire [2:0] _478;
    wire [2:0] _474;
    wire [2:0] _475;
    wire _473;
    wire [2:0] _476;
    wire _472;
    wire [2:0] _479;
    wire _471;
    wire [2:0] _482;
    wire [2:0] _483;
    wire [2:0] _484;
    wire [2:0] _485;
    wire [2:0] _466;
    wire [2:0] _467;
    wire [2:0] _469;
    wire _462;
    wire [2:0] _464;
    wire [2:0] _458;
    wire [2:0] _459;
    wire [23:0] _400;
    wire [23:0] _398;
    wire [3:0] _446;
    wire [11:0] _359;
    wire [11:0] _236;
    wire _340;
    wire [11:0] _370;
    wire [11:0] _364;
    wire _365;
    wire [11:0] _367;
    wire [11:0] _362;
    wire [11:0] _357;
    wire [11:0] _358;
    wire _356;
    wire [11:0] _363;
    wire _354;
    wire [11:0] _368;
    wire _352;
    wire [11:0] _371;
    wire [11:0] _372;
    wire [11:0] _373;
    wire [11:0] _374;
    wire [11:0] _350;
    wire _348;
    wire [11:0] _351;
    wire [11:0] _375;
    wire [11:0] _22;
    reg [11:0] _237;
    wire _360;
    wire [3:0] _435;
    wire _433;
    wire [3:0] _436;
    wire [2:0] _381;
    wire [2:0] _382;
    wire [2:0] _383;
    wire [2:0] _378;
    wire _376;
    wire [2:0] _379;
    wire [2:0] _384;
    wire [2:0] _23;
    reg [2:0] _225;
    wire _227;
    wire [3:0] _437;
    wire _388;
    wire _389;
    wire gnd;
    wire _386;
    wire _385;
    wire _387;
    wire _390;
    wire _24;
    reg _222;
    wire [3:0] _438;
    wire [3:0] _430;
    wire [3:0] _432;
    wire [3:0] _218;
    wire _219;
    wire [3:0] _439;
    wire [23:0] _408;
    wire vdd;
    wire [23:0] _410;
    wire [23:0] _411;
    wire [23:0] _413;
    wire [23:0] _406;
    wire [23:0] _403;
    wire _393;
    wire [23:0] _404;
    wire _392;
    wire [23:0] _407;
    wire _391;
    wire [23:0] _414;
    wire [23:0] _27;
    reg [23:0] _396;
    wire _409;
    wire [3:0] _425;
    wire [3:0] _427;
    wire [3:0] _422;
    wire [3:0] _419;
    wire _417;
    wire [3:0] _420;
    wire _416;
    wire [3:0] _423;
    wire _415;
    wire [3:0] _428;
    wire [3:0] _440;
    wire [3:0] _29;
    reg [3:0] _217;
    wire _447;
    wire [23:0] _449;
    wire [23:0] _444;
    wire _442;
    wire [23:0] _445;
    wire _441;
    wire [23:0] _450;
    wire [23:0] _30;
    reg [23:0] _399;
    wire _401;
    wire [2:0] _456;
    wire _454;
    wire [2:0] _457;
    wire _453;
    wire [2:0] _460;
    wire _452;
    wire [2:0] _465;
    wire _451;
    wire [2:0] _470;
    wire [2:0] _486;
    wire [2:0] _31;
    reg [2:0] _189;
    wire _191;
    wire _194;
    wire _197;
    wire _497;
    wire _32;
    reg _184;
    wire _498;
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
    assign _177 = _88 ? _115 : _116;
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
    assign _178 = _38 ? _177 : _175;
    assign _15 = _178;
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
    assign _185 = ~ _184;
    assign _186 = _185 & _181;
    assign _209 = start ? vdd : gnd;
    assign _205 = _189 == _458;
    assign _206 = _205 ? gnd : _181;
    assign _203 = _189 == _474;
    assign _207 = _203 ? vdd : _206;
    assign _201 = _189 == _466;
    assign _208 = _201 ? vdd : _207;
    assign _199 = _189 == _110;
    assign _210 = _199 ? _209 : _208;
    assign _211 = _197 ? vdd : _210;
    assign _20 = _211;
    always @(posedge clock) begin
        if (clear)
            _181 <= _78;
        else
            _181 <= _20;
    end
    assign _324 = _316[7:7];
    assign _323 = _316[6:6];
    assign _322 = _316[5:5];
    assign _321 = _316[4:4];
    assign _320 = _316[3:3];
    assign _319 = _316[2:2];
    assign _318 = _316[1:1];
    assign _313 = 8'b01010101;
    assign _311 = 12'b000000000111;
    assign _312 = _237 == _311;
    assign _315 = _312 ? _119 : _313;
    assign _305 = 8'b01100011;
    assign _304 = 8'b01101001;
    assign _303 = 8'b01110011;
    assign _302 = 8'b01100001;
    assign _301 = 8'b00100000;
    assign _300 = 8'b01101101;
    assign _299 = 8'b01101111;
    assign _298 = 8'b01110010;
    assign _297 = 8'b01100110;
    assign _294 = 8'b01101100;
    assign _292 = 8'b01100101;
    assign _291 = 8'b01101000;
    assign _288 = 8'b00010111;
    assign _285 = 8'b00010000;
    assign _282 = 8'b11111111;
    assign _281 = 8'b00000001;
    assign _280 = 8'b10101000;
    assign _279 = 8'b11000000;
    assign _278 = 8'b11001000;
    assign _274 = 8'b01110110;
    assign _273 = 8'b10100011;
    assign _272 = 8'b00010001;
    assign _271 = 8'b01000000;
    assign _268 = 8'b00110100;
    assign _267 = 8'b00010010;
    assign _266 = 8'b00101011;
    assign _263 = 8'b01000101;
    assign _261 = 8'b00001000;
    assign _260 = 8'b01010110;
    assign _255 = 8'b00000010;
    assign _248 = _237[7:0];
    always @* begin
        case (_248)
        0:
            _309 <= _282;
        1:
            _309 <= _282;
        2:
            _309 <= _282;
        3:
            _309 <= _282;
        4:
            _309 <= _282;
        5:
            _309 <= _282;
        6:
            _309 <= _255;
        7:
            _309 <= _115;
        8:
            _309 <= _115;
        9:
            _309 <= _267;
        10:
            _309 <= _268;
        11:
            _309 <= _260;
        12:
            _309 <= _261;
        13:
            _309 <= _115;
        14:
            _309 <= _263;
        15:
            _309 <= _115;
        16:
            _309 <= _115;
        17:
            _309 <= _266;
        18:
            _309 <= _267;
        19:
            _309 <= _268;
        20:
            _309 <= _271;
        21:
            _309 <= _115;
        22:
            _309 <= _271;
        23:
            _309 <= _272;
        24:
            _309 <= _273;
        25:
            _309 <= _274;
        26:
            _309 <= _279;
        27:
            _309 <= _280;
        28:
            _309 <= _281;
        29:
            _309 <= _278;
        30:
            _309 <= _279;
        31:
            _309 <= _280;
        32:
            _309 <= _281;
        33:
            _309 <= _282;
        34:
            _309 <= _285;
        35:
            _309 <= _115;
        36:
            _309 <= _285;
        37:
            _309 <= _115;
        38:
            _309 <= _115;
        39:
            _309 <= _288;
        40:
            _309 <= _115;
        41:
            _309 <= _115;
        42:
            _309 <= _291;
        43:
            _309 <= _292;
        44:
            _309 <= _294;
        45:
            _309 <= _294;
        46:
            _309 <= _299;
        47:
            _309 <= _301;
        48:
            _309 <= _297;
        49:
            _309 <= _298;
        50:
            _309 <= _299;
        51:
            _309 <= _300;
        52:
            _309 <= _301;
        53:
            _309 <= _302;
        54:
            _309 <= _303;
        55:
            _309 <= _304;
        56:
            _309 <= _305;
        57:
            _309 <= _115;
        58:
            _309 <= _115;
        default:
            _309 <= _115;
        endcase
    end
    assign _245 = _214[31:24];
    assign _246 = ~ _245;
    assign _243 = _214[23:16];
    assign _244 = ~ _243;
    assign _241 = _214[15:8];
    assign _242 = ~ _241;
    assign _342 = _340 ? _89 : _336;
    assign _338 = _189 == _112;
    assign _343 = _338 ? _342 : _336;
    assign _331 = _214[31:1];
    assign _332 = { _78,
                    _331 };
    assign _334 = _332 ^ _81;
    assign _328 = _214[31:1];
    assign _329 = { _78,
                    _328 };
    assign _230 = _214[0:0];
    assign _326 = _230 ^ _325;
    assign _335 = _326 ? _334 : _329;
    assign _228 = 3'b010;
    assign _229 = _189 == _228;
    assign _336 = _229 ? _335 : _214;
    assign _344 = _227 ? _343 : _336;
    assign _345 = _222 ? _344 : _214;
    assign _346 = _219 ? _345 : _214;
    assign _347 = _197 ? _346 : _214;
    assign _21 = _347;
    always @(posedge clock) begin
        if (clear)
            _214 <= _58;
        else
            _214 <= _21;
    end
    assign _239 = _214[7:0];
    assign _240 = ~ _239;
    assign _238 = _237[1:0];
    always @* begin
        case (_238)
        0:
            _247 <= _240;
        1:
            _247 <= _242;
        2:
            _247 <= _244;
        default:
            _247 <= _246;
        endcase
    end
    assign _234 = _189 == _228;
    assign _310 = _234 ? _309 : _247;
    assign _232 = _189 == _112;
    assign _316 = _232 ? _315 : _310;
    assign _317 = _316[0:0];
    always @* begin
        case (_225)
        0:
            _325 <= _317;
        1:
            _325 <= _318;
        2:
            _325 <= _319;
        3:
            _325 <= _320;
        4:
            _325 <= _321;
        5:
            _325 <= _322;
        6:
            _325 <= _323;
        default:
            _325 <= _324;
        endcase
    end
    assign _495 = ~ _325;
    assign _496 = _222 ? _325 : _495;
    assign _490 = _189 == _458;
    assign _491 = _490 ? gnd : _184;
    assign _489 = _189 == _474;
    assign _492 = _489 ? vdd : _491;
    assign _488 = _189 == _466;
    assign _493 = _488 ? vdd : _492;
    assign _487 = _189 == _110;
    assign _494 = _487 ? gnd : _493;
    assign _195 = 3'b011;
    assign _196 = _189 == _195;
    assign _193 = _189 == _228;
    assign _481 = _340 ? _228 : _470;
    assign _478 = _365 ? _195 : _470;
    assign _474 = 3'b100;
    assign _475 = _360 ? _474 : _470;
    assign _473 = _189 == _195;
    assign _476 = _473 ? _475 : _470;
    assign _472 = _189 == _228;
    assign _479 = _472 ? _478 : _476;
    assign _471 = _189 == _112;
    assign _482 = _471 ? _481 : _479;
    assign _483 = _227 ? _482 : _470;
    assign _484 = _222 ? _483 : _470;
    assign _485 = _219 ? _484 : _470;
    assign _466 = 3'b110;
    assign _467 = _409 ? _466 : _189;
    assign _469 = start ? _112 : _467;
    assign _462 = _217 == _95;
    assign _464 = _462 ? _110 : _189;
    assign _458 = 3'b101;
    assign _459 = _447 ? _458 : _189;
    assign _400 = 24'b000000000000000100011111;
    assign _398 = 24'b000000000000000000000000;
    assign _446 = 4'b1000;
    assign _359 = 12'b000000000011;
    assign _236 = 12'b000000000000;
    assign _340 = _237 == _311;
    assign _370 = _340 ? _236 : _358;
    assign _364 = 12'b000000111011;
    assign _365 = _237 == _364;
    assign _367 = _365 ? _236 : _358;
    assign _362 = _360 ? _236 : _358;
    assign _357 = 12'b000000000001;
    assign _358 = _237 + _357;
    assign _356 = _189 == _195;
    assign _363 = _356 ? _362 : _358;
    assign _354 = _189 == _228;
    assign _368 = _354 ? _367 : _363;
    assign _352 = _189 == _112;
    assign _371 = _352 ? _370 : _368;
    assign _372 = _227 ? _371 : _351;
    assign _373 = _222 ? _372 : _351;
    assign _374 = _219 ? _373 : _351;
    assign _350 = start ? _236 : _237;
    assign _348 = _189 == _110;
    assign _351 = _348 ? _350 : _237;
    assign _375 = _197 ? _374 : _351;
    assign _22 = _375;
    always @(posedge clock) begin
        if (clear)
            _237 <= _236;
        else
            _237 <= _22;
    end
    assign _360 = _237 == _359;
    assign _435 = _360 ? _93 : _432;
    assign _433 = _189 == _195;
    assign _436 = _433 ? _435 : _432;
    assign _381 = _225 + _112;
    assign _382 = _222 ? _381 : _379;
    assign _383 = _219 ? _382 : _379;
    assign _378 = start ? _110 : _225;
    assign _376 = _189 == _110;
    assign _379 = _376 ? _378 : _225;
    assign _384 = _197 ? _383 : _379;
    assign _23 = _384;
    always @(posedge clock) begin
        if (clear)
            _225 <= _110;
        else
            _225 <= _23;
    end
    assign _227 = _225 == _130;
    assign _437 = _227 ? _436 : _432;
    assign _388 = ~ _222;
    assign _389 = _219 ? _388 : _387;
    assign gnd = 1'b0;
    assign _386 = start ? gnd : _222;
    assign _385 = _189 == _110;
    assign _387 = _385 ? _386 : _222;
    assign _390 = _197 ? _389 : _387;
    assign _24 = _390;
    always @(posedge clock) begin
        if (clear)
            _222 <= _78;
        else
            _222 <= _24;
    end
    assign _438 = _222 ? _437 : _432;
    assign _430 = _217 + _164;
    assign _432 = _219 ? _93 : _430;
    assign _218 = 4'b0010;
    assign _219 = _217 == _218;
    assign _439 = _219 ? _438 : _432;
    assign _408 = 24'b000011101010010111111111;
    assign vdd = 1'b1;
    assign _410 = 24'b000000000000000000000001;
    assign _411 = _396 + _410;
    assign _413 = _409 ? _398 : _411;
    assign _406 = _396 + _410;
    assign _403 = _401 ? _398 : _396;
    assign _393 = _189 == _458;
    assign _404 = _393 ? _403 : _396;
    assign _392 = _189 == _466;
    assign _407 = _392 ? _406 : _404;
    assign _391 = _189 == _110;
    assign _414 = _391 ? _413 : _407;
    assign _27 = _414;
    always @(posedge clock) begin
        if (clear)
            _396 <= _398;
        else
            _396 <= _27;
    end
    assign _409 = _396 == _408;
    assign _425 = _409 ? _93 : _217;
    assign _427 = start ? _93 : _425;
    assign _422 = _217 + _164;
    assign _419 = _217 + _164;
    assign _417 = _189 == _474;
    assign _420 = _417 ? _419 : _217;
    assign _416 = _189 == _466;
    assign _423 = _416 ? _422 : _420;
    assign _415 = _189 == _110;
    assign _428 = _415 ? _427 : _423;
    assign _440 = _197 ? _439 : _428;
    assign _29 = _440;
    always @(posedge clock) begin
        if (clear)
            _217 <= _93;
        else
            _217 <= _29;
    end
    assign _447 = _217 == _446;
    assign _449 = _447 ? _398 : _399;
    assign _444 = _399 + _410;
    assign _442 = _189 == _458;
    assign _445 = _442 ? _444 : _399;
    assign _441 = _189 == _474;
    assign _450 = _441 ? _449 : _445;
    assign _30 = _450;
    always @(posedge clock) begin
        if (clear)
            _399 <= _398;
        else
            _399 <= _30;
    end
    assign _401 = _399 == _400;
    assign _456 = _401 ? _110 : _189;
    assign _454 = _189 == _458;
    assign _457 = _454 ? _456 : _189;
    assign _453 = _189 == _474;
    assign _460 = _453 ? _459 : _457;
    assign _452 = _189 == _466;
    assign _465 = _452 ? _464 : _460;
    assign _451 = _189 == _110;
    assign _470 = _451 ? _469 : _465;
    assign _486 = _197 ? _485 : _470;
    assign _31 = _486;
    always @(posedge clock) begin
        if (clear)
            _189 <= _110;
        else
            _189 <= _31;
    end
    assign _191 = _189 == _112;
    assign _194 = _191 | _193;
    assign _197 = _194 | _196;
    assign _497 = _197 ? _496 : _494;
    assign _32 = _497;
    always @(posedge clock) begin
        if (clear)
            _184 <= _78;
        else
            _184 <= _32;
    end
    assign _498 = _184 & _181;
    assign txp = _498;
    assign txn = _186;
    assign txen = _181;
    assign rx_byte = _118;
    assign byte_valid = _7;
    assign frame_end = _4;
    assign crc_ok = _2;

endmodule
