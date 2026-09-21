module deadline_sequencer (
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
    pcs
);

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

    wire [23:0] _53;
    wire _58;
    wire _56;
    wire _59;
    wire _2;
    wire _64;
    wire _61;
    wire _62;
    wire _4;
    reg _65;
    wire [7:0] _68;
    wire [3:0] _60;
    wire _66;
    wire [7:0] _86;
    wire [7:0] _6;
    reg [7:0] _69;
    wire _139;
    wire [1:0] _140;
    wire [3:0] _141;
    wire [7:0] _142;
    wire [7:0] _143;
    wire [7:0] _137;
    wire [7:0] _138;
    wire [7:0] _144;
    wire _131;
    wire [2:0] _129;
    wire _130;
    wire _132;
    wire _127;
    wire [2:0] _125;
    wire _126;
    wire _128;
    wire _123;
    wire [2:0] _121;
    wire _122;
    wire _124;
    wire _119;
    wire [2:0] _117;
    wire _118;
    wire _120;
    wire _115;
    wire [2:0] _113;
    wire _114;
    wire _116;
    wire _111;
    wire [2:0] _109;
    wire _110;
    wire _112;
    wire _107;
    wire [2:0] _105;
    wire _106;
    wire _108;
    wire _103;
    wire _98;
    wire [2:0] _96;
    wire _97;
    wire _104;
    wire [7:0] _133;
    wire [7:0] _134;
    wire _90;
    wire [7:0] _135;
    wire _88;
    wire [7:0] _145;
    wire [7:0] _8;
    reg [7:0] _93;
    wire _266;
    wire [1:0] _267;
    wire [3:0] _268;
    wire [7:0] _269;
    wire [7:0] _270;
    wire [7:0] _136;
    wire [7:0] _264;
    wire [7:0] _265;
    wire [7:0] _271;
    wire _259;
    wire _258;
    wire _260;
    wire _255;
    wire _254;
    wire _256;
    wire _251;
    wire _250;
    wire _252;
    wire _247;
    wire _246;
    wire _248;
    wire _243;
    wire _242;
    wire _244;
    wire _239;
    wire _238;
    wire _240;
    wire _235;
    wire _234;
    wire _236;
    wire gnd;
    wire _231;
    wire _230;
    wire _232;
    wire [7:0] _261;
    wire _226;
    wire _225;
    wire _227;
    wire _222;
    wire _221;
    wire _223;
    wire _218;
    wire _217;
    wire _219;
    wire _214;
    wire _213;
    wire _215;
    wire _210;
    wire _209;
    wire _211;
    wire _206;
    wire _205;
    wire _207;
    wire _202;
    wire _201;
    wire _203;
    wire _101;
    wire [7:0] _148;
    wire [7:0] _10;
    reg [7:0] _84;
    wire [7:0] _151;
    wire [7:0] _11;
    reg [7:0] _81;
    wire [7:0] _154;
    wire [7:0] _12;
    reg [7:0] _78;
    wire [7:0] _186;
    wire [6:0] _181;
    wire [7:0] _183;
    wire [6:0] _179;
    wire [7:0] _180;
    wire [7:0] _184;
    wire [6:0] _174;
    wire [7:0] _175;
    wire [6:0] _172;
    wire [7:0] _173;
    wire [7:0] _176;
    wire [7:0] _161;
    wire _160;
    wire [7:0] _162;
    wire _159;
    wire [7:0] _177;
    wire _157;
    wire [7:0] _185;
    wire [3:0] _155;
    wire _156;
    wire [7:0] _187;
    wire [7:0] _14;
    wire [7:0] _190;
    wire [7:0] _15;
    reg [7:0] _75;
    reg [7:0] _85;
    wire _100;
    wire _102;
    wire _198;
    wire _197;
    wire _199;
    wire [7:0] _228;
    wire _94;
    wire [7:0] _262;
    wire _192;
    wire [7:0] _263;
    wire [3:0] _87;
    wire _191;
    wire [7:0] _272;
    wire [7:0] _16;
    reg [7:0] _195;
    wire [5:0] _51;
    wire [11:0] _359;
    wire _360;
    wire [5:0] _361;
    wire _99;
    wire _170;
    wire _169;
    wire _168;
    wire _167;
    wire _166;
    wire _165;
    wire _164;
    wire _163;
    wire [2:0] _95;
    reg _171;
    wire _358;
    wire [5:0] _362;
    wire [11:0] _276;
    wire [11:0] _19;
    reg [11:0] _275;
    wire [11:0] _280;
    wire [11:0] _20;
    reg [11:0] _279;
    wire [11:0] _284;
    wire [11:0] _21;
    reg [11:0] _283;
    wire [11:0] _293;
    wire [11:0] _294;
    wire _292;
    wire [11:0] _295;
    wire [3:0] _285;
    wire _286;
    wire [11:0] _297;
    wire [11:0] _22;
    wire [11:0] _298;
    wire [11:0] _23;
    reg [11:0] _289;
    reg [11:0] _290;
    wire _355;
    wire [5:0] _356;
    wire [5:0] _350;
    wire [11:0] _302;
    wire [11:0] _24;
    reg [11:0] _301;
    wire [11:0] _306;
    wire [11:0] _25;
    reg [11:0] _305;
    wire [11:0] _310;
    wire [11:0] _26;
    reg [11:0] _309;
    wire [11:0] _296;
    wire [11:0] _323;
    wire [11:0] _320;
    wire [3:0] _158;
    wire _314;
    wire [11:0] _321;
    wire [3:0] _89;
    wire _313;
    wire [11:0] _324;
    wire [3:0] _311;
    wire _312;
    wire [11:0] _325;
    wire [11:0] _27;
    wire [11:0] _326;
    wire [11:0] _28;
    reg [11:0] _317;
    reg [11:0] _318;
    wire _348;
    wire _349;
    wire [5:0] _351;
    wire [5:0] _345;
    wire [5:0] _342;
    wire [1:0] _146;
    wire _147;
    wire [5:0] _327;
    wire [5:0] _30;
    reg [5:0] _43;
    wire [1:0] _149;
    wire _150;
    wire [5:0] _328;
    wire [5:0] _31;
    reg [5:0] _46;
    wire [1:0] _152;
    wire _153;
    wire [5:0] _329;
    wire [5:0] _32;
    reg [5:0] _49;
    reg [5:0] _341;
    wire [5:0] _343;
    wire [3:0] _339;
    wire _340;
    wire [5:0] _344;
    wire [3:0] _55;
    wire _338;
    wire [5:0] _346;
    wire [3:0] _336;
    wire _337;
    wire [5:0] _352;
    wire [3:0] _334;
    wire _335;
    wire [5:0] _353;
    wire [3:0] _332;
    wire _333;
    wire [5:0] _357;
    wire [3:0] _330;
    wire [3:0] _54;
    wire _331;
    wire [5:0] _363;
    wire [5:0] _34;
    wire [1:0] _188;
    wire _189;
    wire [5:0] _364;
    wire [5:0] _35;
    reg [5:0] _52;
    reg [5:0] _369;
    wire vdd;
    wire [1:0] _366;
    wire [1:0] _38;
    reg [1:0] _72;
    wire [1:0] _368;
    wire [7:0] _370;
    assign _53 = { _43,
                   _46,
                   _49,
                   _52 };
    assign _58 = host_in_valid ? vdd : gnd;
    assign _56 = _54 == _55;
    assign _59 = _56 ? _58 : gnd;
    assign _2 = _59;
    assign _64 = 1'b0;
    assign _61 = _54 == _60;
    assign _62 = _61 ? vdd : gnd;
    assign _4 = _62;
    always @(posedge clock) begin
        if (clear)
            _65 <= _64;
        else
            _65 <= _4;
    end
    assign _68 = 8'b00000000;
    assign _60 = 4'b1011;
    assign _66 = _54 == _60;
    assign _86 = _66 ? _85 : _69;
    assign _6 = _86;
    always @(posedge clock) begin
        if (clear)
            _69 <= _68;
        else
            _69 <= _6;
    end
    assign _139 = imem_data[2:2];
    assign _140 = { _139,
                    _139 };
    assign _141 = { _140,
                    _140 };
    assign _142 = { _141,
                    _141 };
    assign _143 = _136 & _142;
    assign _137 = ~ _136;
    assign _138 = _93 & _137;
    assign _144 = _138 | _143;
    assign _131 = _93[0:0];
    assign _129 = 3'b000;
    assign _130 = _95 == _129;
    assign _132 = _130 ? _103 : _131;
    assign _127 = _93[1:1];
    assign _125 = 3'b001;
    assign _126 = _95 == _125;
    assign _128 = _126 ? _103 : _127;
    assign _123 = _93[2:2];
    assign _121 = 3'b010;
    assign _122 = _95 == _121;
    assign _124 = _122 ? _103 : _123;
    assign _119 = _93[3:3];
    assign _117 = 3'b011;
    assign _118 = _95 == _117;
    assign _120 = _118 ? _103 : _119;
    assign _115 = _93[4:4];
    assign _113 = 3'b100;
    assign _114 = _95 == _113;
    assign _116 = _114 ? _103 : _115;
    assign _111 = _93[5:5];
    assign _109 = 3'b101;
    assign _110 = _95 == _109;
    assign _112 = _110 ? _103 : _111;
    assign _107 = _93[6:6];
    assign _105 = 3'b110;
    assign _106 = _95 == _105;
    assign _108 = _106 ? _103 : _107;
    assign _103 = ~ _102;
    assign _98 = _93[7:7];
    assign _96 = 3'b111;
    assign _97 = _95 == _96;
    assign _104 = _97 ? _103 : _98;
    assign _133 = { _104,
                    _108,
                    _112,
                    _116,
                    _120,
                    _124,
                    _128,
                    _132 };
    assign _134 = _94 ? _133 : _93;
    assign _90 = _54 == _89;
    assign _135 = _90 ? _134 : _93;
    assign _88 = _54 == _87;
    assign _145 = _88 ? _144 : _135;
    assign _8 = _145;
    always @(posedge clock) begin
        if (clear)
            _93 <= _68;
        else
            _93 <= _8;
    end
    assign _266 = imem_data[3:3];
    assign _267 = { _266,
                    _266 };
    assign _268 = { _267,
                    _267 };
    assign _269 = { _268,
                    _268 };
    assign _270 = _136 & _269;
    assign _136 = imem_data[11:4];
    assign _264 = ~ _136;
    assign _265 = _195 & _264;
    assign _271 = _265 | _270;
    assign _259 = _195[0:0];
    assign _258 = _95 == _129;
    assign _260 = _258 ? gnd : _259;
    assign _255 = _195[1:1];
    assign _254 = _95 == _125;
    assign _256 = _254 ? gnd : _255;
    assign _251 = _195[2:2];
    assign _250 = _95 == _121;
    assign _252 = _250 ? gnd : _251;
    assign _247 = _195[3:3];
    assign _246 = _95 == _117;
    assign _248 = _246 ? gnd : _247;
    assign _243 = _195[4:4];
    assign _242 = _95 == _113;
    assign _244 = _242 ? gnd : _243;
    assign _239 = _195[5:5];
    assign _238 = _95 == _109;
    assign _240 = _238 ? gnd : _239;
    assign _235 = _195[6:6];
    assign _234 = _95 == _105;
    assign _236 = _234 ? gnd : _235;
    assign gnd = 1'b0;
    assign _231 = _195[7:7];
    assign _230 = _95 == _96;
    assign _232 = _230 ? gnd : _231;
    assign _261 = { _232,
                    _236,
                    _240,
                    _244,
                    _248,
                    _252,
                    _256,
                    _260 };
    assign _226 = _195[0:0];
    assign _225 = _95 == _129;
    assign _227 = _225 ? _102 : _226;
    assign _222 = _195[1:1];
    assign _221 = _95 == _125;
    assign _223 = _221 ? _102 : _222;
    assign _218 = _195[2:2];
    assign _217 = _95 == _121;
    assign _219 = _217 ? _102 : _218;
    assign _214 = _195[3:3];
    assign _213 = _95 == _117;
    assign _215 = _213 ? _102 : _214;
    assign _210 = _195[4:4];
    assign _209 = _95 == _113;
    assign _211 = _209 ? _102 : _210;
    assign _206 = _195[5:5];
    assign _205 = _95 == _109;
    assign _207 = _205 ? _102 : _206;
    assign _202 = _195[6:6];
    assign _201 = _95 == _105;
    assign _203 = _201 ? _102 : _202;
    assign _101 = _85[7:7];
    assign _148 = _147 ? _14 : _84;
    assign _10 = _148;
    always @(posedge clock) begin
        if (clear)
            _84 <= _68;
        else
            _84 <= _10;
    end
    assign _151 = _150 ? _14 : _81;
    assign _11 = _151;
    always @(posedge clock) begin
        if (clear)
            _81 <= _68;
        else
            _81 <= _11;
    end
    assign _154 = _153 ? _14 : _78;
    assign _12 = _154;
    always @(posedge clock) begin
        if (clear)
            _78 <= _68;
        else
            _78 <= _12;
    end
    assign _186 = imem_data[7:0];
    assign _181 = _85[6:0];
    assign _183 = { _181,
                    _64 };
    assign _179 = _85[7:1];
    assign _180 = { _64,
                    _179 };
    assign _184 = _99 ? _183 : _180;
    assign _174 = _85[6:0];
    assign _175 = { _174,
                    _171 };
    assign _172 = _85[7:1];
    assign _173 = { _171,
                    _172 };
    assign _176 = _99 ? _175 : _173;
    assign _161 = host_in_valid ? host_in : _85;
    assign _160 = _54 == _55;
    assign _162 = _160 ? _161 : _85;
    assign _159 = _54 == _158;
    assign _177 = _159 ? _176 : _162;
    assign _157 = _54 == _89;
    assign _185 = _157 ? _184 : _177;
    assign _155 = 4'b0100;
    assign _156 = _54 == _155;
    assign _187 = _156 ? _186 : _185;
    assign _14 = _187;
    assign _190 = _189 ? _14 : _75;
    assign _15 = _190;
    always @(posedge clock) begin
        if (clear)
            _75 <= _68;
        else
            _75 <= _15;
    end
    always @* begin
        case (_72)
        0:
            _85 <= _75;
        1:
            _85 <= _78;
        2:
            _85 <= _81;
        default:
            _85 <= _84;
        endcase
    end
    assign _100 = _85[0:0];
    assign _102 = _99 ? _101 : _100;
    assign _198 = _195[7:7];
    assign _197 = _95 == _96;
    assign _199 = _197 ? _102 : _198;
    assign _228 = { _199,
                    _203,
                    _207,
                    _211,
                    _215,
                    _219,
                    _223,
                    _227 };
    assign _94 = imem_data[7:7];
    assign _262 = _94 ? _261 : _228;
    assign _192 = _54 == _89;
    assign _263 = _192 ? _262 : _195;
    assign _87 = 4'b0001;
    assign _191 = _54 == _87;
    assign _272 = _191 ? _271 : _263;
    assign _16 = _272;
    always @(posedge clock) begin
        if (clear)
            _195 <= _68;
        else
            _195 <= _16;
    end
    assign _51 = 6'b000000;
    assign _359 = 12'b000000000000;
    assign _360 = _290 == _359;
    assign _361 = _360 ? _350 : _341;
    assign _99 = imem_data[8:8];
    assign _170 = pin_in[7:7];
    assign _169 = pin_in[6:6];
    assign _168 = pin_in[5:5];
    assign _167 = pin_in[4:4];
    assign _166 = pin_in[3:3];
    assign _165 = pin_in[2:2];
    assign _164 = pin_in[1:1];
    assign _163 = pin_in[0:0];
    assign _95 = imem_data[11:9];
    always @* begin
        case (_95)
        0:
            _171 <= _163;
        1:
            _171 <= _164;
        2:
            _171 <= _165;
        3:
            _171 <= _166;
        4:
            _171 <= _167;
        5:
            _171 <= _168;
        6:
            _171 <= _169;
        default:
            _171 <= _170;
        endcase
    end
    assign _358 = _171 == _99;
    assign _362 = _358 ? _343 : _361;
    assign _276 = _147 ? _22 : _275;
    assign _19 = _276;
    always @(posedge clock) begin
        if (clear)
            _275 <= _359;
        else
            _275 <= _19;
    end
    assign _280 = _150 ? _22 : _279;
    assign _20 = _280;
    always @(posedge clock) begin
        if (clear)
            _279 <= _359;
        else
            _279 <= _20;
    end
    assign _284 = _153 ? _22 : _283;
    assign _21 = _284;
    always @(posedge clock) begin
        if (clear)
            _283 <= _359;
        else
            _283 <= _21;
    end
    assign _293 = 12'b000000000001;
    assign _294 = _290 - _293;
    assign _292 = _290 == _359;
    assign _295 = _292 ? _290 : _294;
    assign _285 = 4'b0011;
    assign _286 = _54 == _285;
    assign _297 = _286 ? _296 : _295;
    assign _22 = _297;
    assign _298 = _189 ? _22 : _289;
    assign _23 = _298;
    always @(posedge clock) begin
        if (clear)
            _289 <= _359;
        else
            _289 <= _23;
    end
    always @* begin
        case (_72)
        0:
            _290 <= _289;
        1:
            _290 <= _283;
        2:
            _290 <= _279;
        default:
            _290 <= _275;
        endcase
    end
    assign _355 = _290 == _359;
    assign _356 = _355 ? _343 : _341;
    assign _350 = imem_data[5:0];
    assign _302 = _147 ? _27 : _301;
    assign _24 = _302;
    always @(posedge clock) begin
        if (clear)
            _301 <= _359;
        else
            _301 <= _24;
    end
    assign _306 = _150 ? _27 : _305;
    assign _25 = _306;
    always @(posedge clock) begin
        if (clear)
            _305 <= _359;
        else
            _305 <= _25;
    end
    assign _310 = _153 ? _27 : _309;
    assign _26 = _310;
    always @(posedge clock) begin
        if (clear)
            _309 <= _359;
        else
            _309 <= _26;
    end
    assign _296 = imem_data[11:0];
    assign _323 = _318 - _293;
    assign _320 = _318 - _293;
    assign _158 = 4'b1000;
    assign _314 = _54 == _158;
    assign _321 = _314 ? _320 : _318;
    assign _89 = 4'b0111;
    assign _313 = _54 == _89;
    assign _324 = _313 ? _323 : _321;
    assign _311 = 4'b0010;
    assign _312 = _54 == _311;
    assign _325 = _312 ? _296 : _324;
    assign _27 = _325;
    assign _326 = _189 ? _27 : _317;
    assign _28 = _326;
    always @(posedge clock) begin
        if (clear)
            _317 <= _359;
        else
            _317 <= _28;
    end
    always @* begin
        case (_72)
        0:
            _318 <= _317;
        1:
            _318 <= _309;
        2:
            _318 <= _305;
        default:
            _318 <= _301;
        endcase
    end
    assign _348 = _318 == _359;
    assign _349 = ~ _348;
    assign _351 = _349 ? _350 : _343;
    assign _345 = host_in_valid ? _343 : _341;
    assign _342 = 6'b000001;
    assign _146 = 2'b11;
    assign _147 = _72 == _146;
    assign _327 = _147 ? _34 : _43;
    assign _30 = _327;
    always @(posedge clock) begin
        if (clear)
            _43 <= _51;
        else
            _43 <= _30;
    end
    assign _149 = 2'b10;
    assign _150 = _72 == _149;
    assign _328 = _150 ? _34 : _46;
    assign _31 = _328;
    always @(posedge clock) begin
        if (clear)
            _46 <= _51;
        else
            _46 <= _31;
    end
    assign _152 = 2'b01;
    assign _153 = _72 == _152;
    assign _329 = _153 ? _34 : _49;
    assign _32 = _329;
    always @(posedge clock) begin
        if (clear)
            _49 <= _51;
        else
            _49 <= _32;
    end
    always @* begin
        case (_72)
        0:
            _341 <= _52;
        1:
            _341 <= _49;
        2:
            _341 <= _46;
        default:
            _341 <= _43;
        endcase
    end
    assign _343 = _341 + _342;
    assign _339 = 4'b1101;
    assign _340 = _54 == _339;
    assign _344 = _340 ? _341 : _343;
    assign _55 = 4'b1100;
    assign _338 = _54 == _55;
    assign _346 = _338 ? _345 : _344;
    assign _336 = 4'b1010;
    assign _337 = _54 == _336;
    assign _352 = _337 ? _351 : _346;
    assign _334 = 4'b1001;
    assign _335 = _54 == _334;
    assign _353 = _335 ? _350 : _352;
    assign _332 = 4'b0110;
    assign _333 = _54 == _332;
    assign _357 = _333 ? _356 : _353;
    assign _330 = 4'b0101;
    assign _54 = imem_data[15:12];
    assign _331 = _54 == _330;
    assign _363 = _331 ? _362 : _357;
    assign _34 = _363;
    assign _188 = 2'b00;
    assign _189 = _72 == _188;
    assign _364 = _189 ? _34 : _52;
    assign _35 = _364;
    always @(posedge clock) begin
        if (clear)
            _52 <= _51;
        else
            _52 <= _35;
    end
    always @* begin
        case (_368)
        0:
            _369 <= _52;
        1:
            _369 <= _49;
        2:
            _369 <= _46;
        default:
            _369 <= _43;
        endcase
    end
    assign vdd = 1'b1;
    assign _366 = _72 + _152;
    assign _38 = _366;
    always @(posedge clock) begin
        if (clear)
            _72 <= _188;
        else
            _72 <= _38;
    end
    assign _368 = _72 + _152;
    assign _370 = { _368,
                    _369 };
    assign imem_addr = _370;
    assign pin_out = _195;
    assign pin_oe = _93;
    assign host_out = _69;
    assign host_out_valid = _65;
    assign host_in_ready = _2;
    assign pcs = _53;

endmodule
