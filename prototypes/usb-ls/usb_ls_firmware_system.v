module usb_ls_firmware_system (
    dp_in,
    dm_in,
    rdy,
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
    pcs,
    crc_ok
);

    input dp_in;
    input dm_in;
    input rdy;
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
    output crc_ok;

    wire [31:0] _63;
    wire _68;
    wire _66;
    wire _69;
    wire _3;
    wire _74;
    wire _71;
    wire _72;
    wire _5;
    reg _75;
    wire _76;
    wire _81;
    wire _7;
    reg _79;
    wire [7:0] _84;
    wire [7:0] _103;
    wire [3:0] _70;
    wire _82;
    wire [7:0] _104;
    wire [7:0] _9;
    reg [7:0] _85;
    wire [11:0] _553;
    wire _554;
    wire [7:0] _555;
    wire _552;
    wire [7:0] _556;
    wire [11:0] _116;
    wire [11:0] _13;
    reg [11:0] _115;
    wire [11:0] _122;
    wire [11:0] _14;
    reg [11:0] _121;
    wire [11:0] _128;
    wire [11:0] _15;
    reg [11:0] _127;
    wire [11:0] _137;
    wire [11:0] _138;
    wire _136;
    wire [11:0] _139;
    wire [3:0] _129;
    wire _130;
    wire [11:0] _141;
    wire [11:0] _16;
    wire [11:0] _144;
    wire [11:0] _17;
    reg [11:0] _133;
    reg [11:0] _134;
    wire _549;
    wire [7:0] _550;
    wire [7:0] _544;
    wire [11:0] _148;
    wire [11:0] _18;
    reg [11:0] _147;
    wire [11:0] _152;
    wire [11:0] _19;
    reg [11:0] _151;
    wire [11:0] _156;
    wire [11:0] _20;
    reg [11:0] _155;
    wire [11:0] _140;
    wire [11:0] _171;
    wire [11:0] _168;
    wire _162;
    wire [11:0] _169;
    wire _160;
    wire [11:0] _172;
    wire [3:0] _157;
    wire _158;
    wire [11:0] _173;
    wire [11:0] _21;
    wire [11:0] _174;
    wire [11:0] _22;
    reg [11:0] _165;
    reg [11:0] _166;
    wire _542;
    wire _543;
    wire [7:0] _545;
    wire [7:0] _539;
    wire [7:0] _534;
    wire [7:0] _535;
    wire _532;
    wire [7:0] _175;
    wire [7:0] _23;
    reg [7:0] _100;
    wire [7:0] _176;
    wire [7:0] _24;
    reg [7:0] _97;
    wire [7:0] _177;
    wire [7:0] _25;
    reg [7:0] _94;
    wire [7:0] _102;
    wire [1:0] _504;
    wire [5:0] _503;
    wire [7:0] _505;
    wire [5:0] _501;
    wire [7:0] _502;
    wire [7:0] _506;
    wire [6:0] _496;
    wire [7:0] _498;
    wire [6:0] _494;
    wire [7:0] _495;
    wire [7:0] _499;
    wire [7:0] _507;
    wire [6:0] _489;
    wire [7:0] _490;
    wire [6:0] _487;
    wire _485;
    wire _484;
    wire _483;
    wire _482;
    wire _481;
    wire _480;
    wire _479;
    wire [3:0] _461;
    wire [15:0] _48;
    wire [15:0] _218;
    wire [15:0] _212;
    wire _209;
    wire _208;
    wire _210;
    wire [15:0] _213;
    wire [14:0] _206;
    wire [15:0] _207;
    wire [15:0] _214;
    wire [4:0] _202;
    wire [4:0] _193;
    wire [4:0] _194;
    wire _190;
    wire _191;
    wire _192;
    wire [4:0] _195;
    wire [4:0] _196;
    reg [4:0] _199;
    wire [4:0] _28;
    wire _203;
    reg _186;
    wire _187;
    wire _181;
    wire _182;
    wire _180;
    wire _183;
    wire _188;
    wire _201;
    wire _204;
    wire [15:0] _215;
    wire [15:0] _200;
    wire _178;
    wire [15:0] _216;
    reg [15:0] _219;
    wire [15:0] _29;
    wire _49;
    wire [7:0] _462;
    wire [7:0] _460;
    wire [7:0] _463;
    wire _335;
    wire [1:0] _336;
    wire [3:0] _337;
    wire [7:0] _338;
    wire [7:0] _339;
    wire [7:0] _333;
    wire [7:0] _334;
    wire [7:0] _340;
    wire [2:0] _325;
    wire _326;
    wire _327;
    wire _328;
    wire _324;
    wire _321;
    wire _322;
    wire _319;
    wire _323;
    wire _329;
    wire [2:0] _313;
    wire _314;
    wire _315;
    wire _316;
    wire _312;
    wire _309;
    wire _310;
    wire _307;
    wire _311;
    wire _317;
    wire [2:0] _301;
    wire _302;
    wire _303;
    wire _304;
    wire _300;
    wire _297;
    wire _298;
    wire _295;
    wire _299;
    wire _305;
    wire [2:0] _289;
    wire _290;
    wire _291;
    wire _292;
    wire _288;
    wire _285;
    wire _286;
    wire _283;
    wire _287;
    wire _293;
    wire [2:0] _277;
    wire _278;
    wire _279;
    wire _280;
    wire _276;
    wire _273;
    wire _274;
    wire _271;
    wire _275;
    wire _281;
    wire [2:0] _265;
    wire _266;
    wire _267;
    wire _268;
    wire _264;
    wire _261;
    wire _262;
    wire _259;
    wire _263;
    wire _269;
    wire [2:0] _253;
    wire _254;
    wire _255;
    wire _256;
    wire _252;
    wire _249;
    wire _250;
    wire _247;
    wire _251;
    wire _257;
    wire gnd;
    wire [2:0] _235;
    wire _236;
    wire _243;
    wire _244;
    wire _233;
    wire _230;
    wire _231;
    wire _225;
    wire _232;
    wire _245;
    wire [7:0] _330;
    wire _222;
    wire [7:0] _331;
    wire _221;
    wire [7:0] _341;
    wire [7:0] _31;
    reg [7:0] _110;
    wire _452;
    wire [1:0] _453;
    wire [3:0] _454;
    wire [7:0] _455;
    wire [7:0] _456;
    wire [7:0] _332;
    wire [7:0] _450;
    wire [7:0] _451;
    wire [7:0] _457;
    wire _444;
    wire _445;
    wire _446;
    wire _442;
    wire _438;
    wire _439;
    wire _436;
    wire _440;
    wire _441;
    wire _447;
    wire _431;
    wire _432;
    wire _433;
    wire _429;
    wire _425;
    wire _426;
    wire _423;
    wire _427;
    wire _428;
    wire _434;
    wire _418;
    wire _419;
    wire _420;
    wire _416;
    wire _412;
    wire _413;
    wire _410;
    wire _414;
    wire _415;
    wire _421;
    wire _405;
    wire _406;
    wire _407;
    wire _403;
    wire _399;
    wire _400;
    wire _397;
    wire _401;
    wire _402;
    wire _408;
    wire _392;
    wire _393;
    wire _394;
    wire _390;
    wire _386;
    wire _387;
    wire _384;
    wire _388;
    wire _389;
    wire _395;
    wire _379;
    wire _380;
    wire _381;
    wire _377;
    wire _373;
    wire _374;
    wire _371;
    wire _375;
    wire _376;
    wire _382;
    wire _366;
    wire _367;
    wire _368;
    wire _364;
    wire _360;
    wire _361;
    wire _358;
    wire _362;
    wire _363;
    wire _369;
    wire _241;
    wire _240;
    wire _242;
    wire _238;
    wire _237;
    wire _239;
    wire _353;
    wire _354;
    wire _355;
    wire _351;
    wire _234;
    wire [2:0] _228;
    wire _347;
    wire _226;
    wire _348;
    wire _345;
    wire _349;
    wire _350;
    wire _356;
    wire [7:0] _448;
    wire _343;
    wire [7:0] _449;
    wire [3:0] _220;
    wire _342;
    wire [7:0] _458;
    wire [7:0] _32;
    reg [7:0] _107;
    wire [7:0] _459;
    wire [7:0] _464;
    reg [7:0] _467;
    reg [7:0] _470;
    wire [7:0] _33;
    wire _478;
    wire [2:0] _223;
    reg _486;
    wire [7:0] _488;
    wire _80;
    wire [7:0] _491;
    wire [7:0] _476;
    wire _475;
    wire [7:0] _477;
    wire [3:0] _161;
    wire _474;
    wire [7:0] _492;
    wire [3:0] _159;
    wire _473;
    wire [7:0] _508;
    wire [3:0] _471;
    wire _472;
    wire [7:0] _509;
    wire [7:0] _36;
    wire [7:0] _510;
    wire [7:0] _37;
    reg [7:0] _91;
    reg [7:0] _101;
    wire _530;
    wire _531;
    wire _533;
    wire [7:0] _536;
    wire [7:0] _528;
    wire [1:0] _111;
    wire _112;
    wire [7:0] _511;
    wire [7:0] _38;
    reg [7:0] _53;
    wire [1:0] _117;
    wire _118;
    wire [7:0] _512;
    wire [7:0] _39;
    reg [7:0] _56;
    wire [1:0] _123;
    wire _124;
    wire [7:0] _513;
    wire [7:0] _40;
    reg [7:0] _59;
    reg [7:0] _527;
    wire [7:0] _529;
    wire [3:0] _525;
    wire _526;
    wire [7:0] _537;
    wire [3:0] _523;
    wire _524;
    wire [7:0] _538;
    wire [3:0] _65;
    wire _522;
    wire [7:0] _540;
    wire [3:0] _520;
    wire _521;
    wire [7:0] _546;
    wire [3:0] _518;
    wire _519;
    wire [7:0] _547;
    wire [3:0] _516;
    wire _517;
    wire [7:0] _551;
    wire [3:0] _514;
    wire [3:0] _64;
    wire _515;
    wire [7:0] _557;
    wire [7:0] _42;
    wire _143;
    wire [7:0] _558;
    wire [7:0] _43;
    reg [7:0] _62;
    reg [7:0] _563;
    wire vdd;
    wire [1:0] _560;
    wire [1:0] _46;
    reg [1:0] _88;
    wire [1:0] _562;
    wire [9:0] _564;
    assign _63 = { _53,
                   _56,
                   _59,
                   _62 };
    assign _68 = host_in_valid ? vdd : gnd;
    assign _66 = _64 == _65;
    assign _69 = _66 ? _68 : gnd;
    assign _3 = _69;
    assign _74 = 1'b0;
    assign _71 = _64 == _70;
    assign _72 = _71 ? vdd : gnd;
    assign _5 = _72;
    always @(posedge clock) begin
        if (clear)
            _75 <= _74;
        else
            _75 <= _5;
    end
    assign _76 = _64 == _70;
    assign _81 = _76 ? _80 : _79;
    assign _7 = _81;
    always @(posedge clock) begin
        if (clear)
            _79 <= _74;
        else
            _79 <= _7;
    end
    assign _84 = 8'b00000000;
    assign _103 = _80 ? _102 : _101;
    assign _70 = 4'b1011;
    assign _82 = _64 == _70;
    assign _104 = _82 ? _103 : _85;
    assign _9 = _104;
    always @(posedge clock) begin
        if (clear)
            _85 <= _84;
        else
            _85 <= _9;
    end
    assign _553 = 12'b000000000000;
    assign _554 = _134 == _553;
    assign _555 = _554 ? _544 : _527;
    assign _552 = _486 == _80;
    assign _556 = _552 ? _529 : _555;
    assign _116 = _112 ? _16 : _115;
    assign _13 = _116;
    always @(posedge clock) begin
        if (clear)
            _115 <= _553;
        else
            _115 <= _13;
    end
    assign _122 = _118 ? _16 : _121;
    assign _14 = _122;
    always @(posedge clock) begin
        if (clear)
            _121 <= _553;
        else
            _121 <= _14;
    end
    assign _128 = _124 ? _16 : _127;
    assign _15 = _128;
    always @(posedge clock) begin
        if (clear)
            _127 <= _553;
        else
            _127 <= _15;
    end
    assign _137 = 12'b000000000001;
    assign _138 = _134 - _137;
    assign _136 = _134 == _553;
    assign _139 = _136 ? _134 : _138;
    assign _129 = 4'b0011;
    assign _130 = _64 == _129;
    assign _141 = _130 ? _140 : _139;
    assign _16 = _141;
    assign _144 = _143 ? _16 : _133;
    assign _17 = _144;
    always @(posedge clock) begin
        if (clear)
            _133 <= _553;
        else
            _133 <= _17;
    end
    always @* begin
        case (_88)
        0:
            _134 <= _133;
        1:
            _134 <= _127;
        2:
            _134 <= _121;
        default:
            _134 <= _115;
        endcase
    end
    assign _549 = _134 == _553;
    assign _550 = _549 ? _529 : _527;
    assign _544 = imem_data[7:0];
    assign _148 = _112 ? _21 : _147;
    assign _18 = _148;
    always @(posedge clock) begin
        if (clear)
            _147 <= _553;
        else
            _147 <= _18;
    end
    assign _152 = _118 ? _21 : _151;
    assign _19 = _152;
    always @(posedge clock) begin
        if (clear)
            _151 <= _553;
        else
            _151 <= _19;
    end
    assign _156 = _124 ? _21 : _155;
    assign _20 = _156;
    always @(posedge clock) begin
        if (clear)
            _155 <= _553;
        else
            _155 <= _20;
    end
    assign _140 = imem_data[11:0];
    assign _171 = _166 - _137;
    assign _168 = _166 - _137;
    assign _162 = _64 == _161;
    assign _169 = _162 ? _168 : _166;
    assign _160 = _64 == _159;
    assign _172 = _160 ? _171 : _169;
    assign _157 = 4'b0010;
    assign _158 = _64 == _157;
    assign _173 = _158 ? _140 : _172;
    assign _21 = _173;
    assign _174 = _143 ? _21 : _165;
    assign _22 = _174;
    always @(posedge clock) begin
        if (clear)
            _165 <= _553;
        else
            _165 <= _22;
    end
    always @* begin
        case (_88)
        0:
            _166 <= _165;
        1:
            _166 <= _155;
        2:
            _166 <= _151;
        default:
            _166 <= _147;
        endcase
    end
    assign _542 = _166 == _553;
    assign _543 = ~ _542;
    assign _545 = _543 ? _544 : _529;
    assign _539 = host_in_valid ? _529 : _527;
    assign _534 = 8'b00000010;
    assign _535 = _527 + _534;
    assign _532 = ~ _80;
    assign _175 = _112 ? _36 : _100;
    assign _23 = _175;
    always @(posedge clock) begin
        if (clear)
            _100 <= _84;
        else
            _100 <= _23;
    end
    assign _176 = _118 ? _36 : _97;
    assign _24 = _176;
    always @(posedge clock) begin
        if (clear)
            _97 <= _84;
        else
            _97 <= _24;
    end
    assign _177 = _124 ? _36 : _94;
    assign _25 = _177;
    always @(posedge clock) begin
        if (clear)
            _94 <= _84;
        else
            _94 <= _25;
    end
    assign _102 = imem_data[7:0];
    assign _504 = 2'b00;
    assign _503 = _101[5:0];
    assign _505 = { _503,
                    _504 };
    assign _501 = _101[7:2];
    assign _502 = { _504,
                    _501 };
    assign _506 = _80 ? _505 : _502;
    assign _496 = _101[6:0];
    assign _498 = { _496,
                    _74 };
    assign _494 = _101[7:1];
    assign _495 = { _74,
                    _494 };
    assign _499 = _80 ? _498 : _495;
    assign _507 = _226 ? _506 : _499;
    assign _489 = _101[6:0];
    assign _490 = { _489,
                    _486 };
    assign _487 = _101[7:1];
    assign _485 = _33[7:7];
    assign _484 = _33[6:6];
    assign _483 = _33[5:5];
    assign _482 = _33[4:4];
    assign _481 = _33[3:3];
    assign _480 = _33[2:2];
    assign _479 = _33[1:1];
    assign _461 = 4'b0000;
    assign _48 = 16'b1011000000000001;
    assign _218 = 16'b0000000000000000;
    assign _212 = 16'b1010000000000001;
    assign _209 = _110[2:2];
    assign _208 = _29[0:0];
    assign _210 = _208 ^ _209;
    assign _213 = _210 ? _212 : _218;
    assign _206 = _29[15:1];
    assign _207 = { _74,
                    _206 };
    assign _214 = _207 ^ _213;
    assign _202 = 5'b00000;
    assign _193 = 5'b00001;
    assign _194 = _28 - _193;
    assign _190 = _28 == _202;
    assign _191 = ~ _190;
    assign _192 = _188 & _191;
    assign _195 = _192 ? _194 : _28;
    assign _196 = _178 ? _195 : _202;
    always @(posedge clock) begin
        if (clear)
            _199 <= _202;
        else
            _199 <= _196;
    end
    assign _28 = _199;
    assign _203 = _28 == _202;
    always @(posedge clock) begin
        if (clear)
            _186 <= _74;
        else
            _186 <= _183;
    end
    assign _187 = ~ _186;
    assign _181 = _110[4:4];
    assign _182 = ~ _181;
    assign _180 = _110[3:3];
    assign _183 = _180 & _182;
    assign _188 = _183 & _187;
    assign _201 = _178 & _188;
    assign _204 = _201 & _203;
    assign _215 = _204 ? _214 : _29;
    assign _200 = 16'b1111111111111111;
    assign _178 = _110[5:5];
    assign _216 = _178 ? _215 : _200;
    always @(posedge clock) begin
        if (clear)
            _219 <= _218;
        else
            _219 <= _216;
    end
    assign _29 = _219;
    assign _49 = _29 == _48;
    assign _462 = { rdy,
                    _49,
                    _461,
                    dm_in,
                    dp_in };
    assign _460 = ~ _107;
    assign _463 = _460 & _462;
    assign _335 = imem_data[3:3];
    assign _336 = { _335,
                    _335 };
    assign _337 = { _336,
                    _336 };
    assign _338 = { _337,
                    _337 };
    assign _339 = _332 & _338;
    assign _333 = ~ _332;
    assign _334 = _110 & _333;
    assign _340 = _334 | _339;
    assign _325 = 3'b000;
    assign _326 = _223 == _325;
    assign _327 = _326 ? _242 : _239;
    assign _328 = _234 ? gnd : _327;
    assign _324 = _110[0:0];
    assign _321 = _228 == _325;
    assign _322 = _226 & _321;
    assign _319 = _223 == _325;
    assign _323 = _319 | _322;
    assign _329 = _323 ? _328 : _324;
    assign _313 = 3'b001;
    assign _314 = _223 == _313;
    assign _315 = _314 ? _242 : _239;
    assign _316 = _234 ? gnd : _315;
    assign _312 = _110[1:1];
    assign _309 = _228 == _313;
    assign _310 = _226 & _309;
    assign _307 = _223 == _313;
    assign _311 = _307 | _310;
    assign _317 = _311 ? _316 : _312;
    assign _301 = 3'b010;
    assign _302 = _223 == _301;
    assign _303 = _302 ? _242 : _239;
    assign _304 = _234 ? gnd : _303;
    assign _300 = _110[2:2];
    assign _297 = _228 == _301;
    assign _298 = _226 & _297;
    assign _295 = _223 == _301;
    assign _299 = _295 | _298;
    assign _305 = _299 ? _304 : _300;
    assign _289 = 3'b011;
    assign _290 = _223 == _289;
    assign _291 = _290 ? _242 : _239;
    assign _292 = _234 ? gnd : _291;
    assign _288 = _110[3:3];
    assign _285 = _228 == _289;
    assign _286 = _226 & _285;
    assign _283 = _223 == _289;
    assign _287 = _283 | _286;
    assign _293 = _287 ? _292 : _288;
    assign _277 = 3'b100;
    assign _278 = _223 == _277;
    assign _279 = _278 ? _242 : _239;
    assign _280 = _234 ? gnd : _279;
    assign _276 = _110[4:4];
    assign _273 = _228 == _277;
    assign _274 = _226 & _273;
    assign _271 = _223 == _277;
    assign _275 = _271 | _274;
    assign _281 = _275 ? _280 : _276;
    assign _265 = 3'b101;
    assign _266 = _223 == _265;
    assign _267 = _266 ? _242 : _239;
    assign _268 = _234 ? gnd : _267;
    assign _264 = _110[5:5];
    assign _261 = _228 == _265;
    assign _262 = _226 & _261;
    assign _259 = _223 == _265;
    assign _263 = _259 | _262;
    assign _269 = _263 ? _268 : _264;
    assign _253 = 3'b110;
    assign _254 = _223 == _253;
    assign _255 = _254 ? _242 : _239;
    assign _256 = _234 ? gnd : _255;
    assign _252 = _110[6:6];
    assign _249 = _228 == _253;
    assign _250 = _226 & _249;
    assign _247 = _223 == _253;
    assign _251 = _247 | _250;
    assign _257 = _251 ? _256 : _252;
    assign gnd = 1'b0;
    assign _235 = 3'b111;
    assign _236 = _223 == _235;
    assign _243 = _236 ? _242 : _239;
    assign _244 = _234 ? gnd : _243;
    assign _233 = _110[7:7];
    assign _230 = _228 == _235;
    assign _231 = _226 & _230;
    assign _225 = _223 == _235;
    assign _232 = _225 | _231;
    assign _245 = _232 ? _244 : _233;
    assign _330 = { _245,
                    _257,
                    _269,
                    _281,
                    _293,
                    _305,
                    _317,
                    _329 };
    assign _222 = _64 == _159;
    assign _331 = _222 ? _330 : _110;
    assign _221 = _64 == _220;
    assign _341 = _221 ? _340 : _331;
    assign _31 = _341;
    always @(posedge clock) begin
        if (clear)
            _110 <= _84;
        else
            _110 <= _31;
    end
    assign _452 = imem_data[2:2];
    assign _453 = { _452,
                    _452 };
    assign _454 = { _453,
                    _453 };
    assign _455 = { _454,
                    _454 };
    assign _456 = _332 & _455;
    assign _332 = imem_data[11:4];
    assign _450 = ~ _332;
    assign _451 = _107 & _450;
    assign _457 = _451 | _456;
    assign _444 = _223 == _325;
    assign _445 = _444 ? _242 : _239;
    assign _446 = ~ _445;
    assign _442 = _107[0:0];
    assign _438 = _228 == _325;
    assign _439 = _226 & _438;
    assign _436 = _223 == _325;
    assign _440 = _436 | _439;
    assign _441 = _440 & _234;
    assign _447 = _441 ? _446 : _442;
    assign _431 = _223 == _313;
    assign _432 = _431 ? _242 : _239;
    assign _433 = ~ _432;
    assign _429 = _107[1:1];
    assign _425 = _228 == _313;
    assign _426 = _226 & _425;
    assign _423 = _223 == _313;
    assign _427 = _423 | _426;
    assign _428 = _427 & _234;
    assign _434 = _428 ? _433 : _429;
    assign _418 = _223 == _301;
    assign _419 = _418 ? _242 : _239;
    assign _420 = ~ _419;
    assign _416 = _107[2:2];
    assign _412 = _228 == _301;
    assign _413 = _226 & _412;
    assign _410 = _223 == _301;
    assign _414 = _410 | _413;
    assign _415 = _414 & _234;
    assign _421 = _415 ? _420 : _416;
    assign _405 = _223 == _289;
    assign _406 = _405 ? _242 : _239;
    assign _407 = ~ _406;
    assign _403 = _107[3:3];
    assign _399 = _228 == _289;
    assign _400 = _226 & _399;
    assign _397 = _223 == _289;
    assign _401 = _397 | _400;
    assign _402 = _401 & _234;
    assign _408 = _402 ? _407 : _403;
    assign _392 = _223 == _277;
    assign _393 = _392 ? _242 : _239;
    assign _394 = ~ _393;
    assign _390 = _107[4:4];
    assign _386 = _228 == _277;
    assign _387 = _226 & _386;
    assign _384 = _223 == _277;
    assign _388 = _384 | _387;
    assign _389 = _388 & _234;
    assign _395 = _389 ? _394 : _390;
    assign _379 = _223 == _265;
    assign _380 = _379 ? _242 : _239;
    assign _381 = ~ _380;
    assign _377 = _107[5:5];
    assign _373 = _228 == _265;
    assign _374 = _226 & _373;
    assign _371 = _223 == _265;
    assign _375 = _371 | _374;
    assign _376 = _375 & _234;
    assign _382 = _376 ? _381 : _377;
    assign _366 = _223 == _253;
    assign _367 = _366 ? _242 : _239;
    assign _368 = ~ _367;
    assign _364 = _107[6:6];
    assign _360 = _228 == _253;
    assign _361 = _226 & _360;
    assign _358 = _223 == _253;
    assign _362 = _358 | _361;
    assign _363 = _362 & _234;
    assign _369 = _363 ? _368 : _364;
    assign _241 = _101[7:7];
    assign _240 = _101[0:0];
    assign _242 = _80 ? _241 : _240;
    assign _238 = _101[6:6];
    assign _237 = _101[1:1];
    assign _239 = _80 ? _238 : _237;
    assign _353 = _223 == _235;
    assign _354 = _353 ? _242 : _239;
    assign _355 = ~ _354;
    assign _351 = _107[7:7];
    assign _234 = imem_data[7:7];
    assign _228 = _223 + _313;
    assign _347 = _228 == _235;
    assign _226 = imem_data[6:6];
    assign _348 = _226 & _347;
    assign _345 = _223 == _235;
    assign _349 = _345 | _348;
    assign _350 = _349 & _234;
    assign _356 = _350 ? _355 : _351;
    assign _448 = { _356,
                    _369,
                    _382,
                    _395,
                    _408,
                    _421,
                    _434,
                    _447 };
    assign _343 = _64 == _159;
    assign _449 = _343 ? _448 : _107;
    assign _220 = 4'b0001;
    assign _342 = _64 == _220;
    assign _458 = _342 ? _457 : _449;
    assign _32 = _458;
    always @(posedge clock) begin
        if (clear)
            _107 <= _84;
        else
            _107 <= _32;
    end
    assign _459 = _107 & _110;
    assign _464 = _459 | _463;
    always @(posedge clock) begin
        if (clear)
            _467 <= _84;
        else
            _467 <= _464;
    end
    always @(posedge clock) begin
        if (clear)
            _470 <= _84;
        else
            _470 <= _467;
    end
    assign _33 = _470;
    assign _478 = _33[0:0];
    assign _223 = imem_data[11:9];
    always @* begin
        case (_223)
        0:
            _486 <= _478;
        1:
            _486 <= _479;
        2:
            _486 <= _480;
        3:
            _486 <= _481;
        4:
            _486 <= _482;
        5:
            _486 <= _483;
        6:
            _486 <= _484;
        default:
            _486 <= _485;
        endcase
    end
    assign _488 = { _486,
                    _487 };
    assign _80 = imem_data[8:8];
    assign _491 = _80 ? _490 : _488;
    assign _476 = host_in_valid ? host_in : _101;
    assign _475 = _64 == _65;
    assign _477 = _475 ? _476 : _101;
    assign _161 = 4'b1000;
    assign _474 = _64 == _161;
    assign _492 = _474 ? _491 : _477;
    assign _159 = 4'b0111;
    assign _473 = _64 == _159;
    assign _508 = _473 ? _507 : _492;
    assign _471 = 4'b0100;
    assign _472 = _64 == _471;
    assign _509 = _472 ? _102 : _508;
    assign _36 = _509;
    assign _510 = _143 ? _36 : _91;
    assign _37 = _510;
    always @(posedge clock) begin
        if (clear)
            _91 <= _84;
        else
            _91 <= _37;
    end
    always @* begin
        case (_88)
        0:
            _101 <= _91;
        1:
            _101 <= _94;
        2:
            _101 <= _97;
        default:
            _101 <= _100;
        endcase
    end
    assign _530 = _101 == _102;
    assign _531 = ~ _530;
    assign _533 = _531 == _532;
    assign _536 = _533 ? _535 : _529;
    assign _528 = 8'b00000001;
    assign _111 = 2'b11;
    assign _112 = _88 == _111;
    assign _511 = _112 ? _42 : _53;
    assign _38 = _511;
    always @(posedge clock) begin
        if (clear)
            _53 <= _84;
        else
            _53 <= _38;
    end
    assign _117 = 2'b10;
    assign _118 = _88 == _117;
    assign _512 = _118 ? _42 : _56;
    assign _39 = _512;
    always @(posedge clock) begin
        if (clear)
            _56 <= _84;
        else
            _56 <= _39;
    end
    assign _123 = 2'b01;
    assign _124 = _88 == _123;
    assign _513 = _124 ? _42 : _59;
    assign _40 = _513;
    always @(posedge clock) begin
        if (clear)
            _59 <= _84;
        else
            _59 <= _40;
    end
    always @* begin
        case (_88)
        0:
            _527 <= _62;
        1:
            _527 <= _59;
        2:
            _527 <= _56;
        default:
            _527 <= _53;
        endcase
    end
    assign _529 = _527 + _528;
    assign _525 = 4'b1110;
    assign _526 = _64 == _525;
    assign _537 = _526 ? _536 : _529;
    assign _523 = 4'b1101;
    assign _524 = _64 == _523;
    assign _538 = _524 ? _527 : _537;
    assign _65 = 4'b1100;
    assign _522 = _64 == _65;
    assign _540 = _522 ? _539 : _538;
    assign _520 = 4'b1010;
    assign _521 = _64 == _520;
    assign _546 = _521 ? _545 : _540;
    assign _518 = 4'b1001;
    assign _519 = _64 == _518;
    assign _547 = _519 ? _544 : _546;
    assign _516 = 4'b0110;
    assign _517 = _64 == _516;
    assign _551 = _517 ? _550 : _547;
    assign _514 = 4'b0101;
    assign _64 = imem_data[15:12];
    assign _515 = _64 == _514;
    assign _557 = _515 ? _556 : _551;
    assign _42 = _557;
    assign _143 = _88 == _504;
    assign _558 = _143 ? _42 : _62;
    assign _43 = _558;
    always @(posedge clock) begin
        if (clear)
            _62 <= _84;
        else
            _62 <= _43;
    end
    always @* begin
        case (_562)
        0:
            _563 <= _62;
        1:
            _563 <= _59;
        2:
            _563 <= _56;
        default:
            _563 <= _53;
        endcase
    end
    assign vdd = 1'b1;
    assign _560 = _88 + _123;
    assign _46 = _560;
    always @(posedge clock) begin
        if (clear)
            _88 <= _504;
        else
            _88 <= _46;
    end
    assign _562 = _88 + _123;
    assign _564 = { _562,
                    _563 };
    assign imem_addr = _564;
    assign pin_out = _110;
    assign pin_oe = _107;
    assign host_out = _85;
    assign host_out_tag = _79;
    assign host_out_valid = _75;
    assign host_in_ready = _3;
    assign pcs = _63;
    assign crc_ok = _49;

endmodule
