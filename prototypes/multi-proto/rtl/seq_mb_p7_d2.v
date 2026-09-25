module deadline_sequencer_mb_p7_d2 (
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
    output [8:0] imem_addr;
    output [7:0] pin_out;
    output [7:0] pin_oe;
    output [7:0] host_out;
    output host_out_valid;
    output host_in_ready;
    output [27:0] pcs;
    output [7:0] port_out_data;
    output [3:0] port_out_valid;
    output [3:0] port_in_ready;
    output [11:0] mb_counts;

    wire [2:0] _89;
    wire [2:0] _85;
    wire [2:0] _81;
    wire [2:0] _77;
    wire [11:0] _90;
    wire [1:0] _109;
    wire _110;
    wire [1:0] _107;
    wire _108;
    wire [1:0] _105;
    wire _106;
    wire [1:0] _103;
    wire _104;
    wire [3:0] _111;
    wire [3:0] _112;
    wire [3:0] _113;
    wire [3:0] _114;
    wire [3:0] _94;
    wire _93;
    wire [3:0] _115;
    wire [3:0] _2;
    wire _130;
    wire _128;
    wire _126;
    wire _124;
    wire [3:0] _131;
    wire [3:0] _132;
    wire [3:0] _133;
    wire [3:0] _134;
    wire _116;
    wire [3:0] _135;
    wire [3:0] _4;
    reg [3:0] _138;
    wire [7:0] _141;
    wire [7:0] _159;
    wire [7:0] _160;
    wire [7:0] _161;
    wire _139;
    wire [7:0] _162;
    wire [7:0] _6;
    reg [7:0] _142;
    wire [27:0] _175;
    wire _178;
    wire _177;
    wire _179;
    wire _9;
    wire _184;
    wire _181;
    wire _182;
    wire _11;
    reg _185;
    wire [3:0] _180;
    wire _186;
    wire [7:0] _190;
    wire [7:0] _13;
    reg [7:0] _189;
    wire _243;
    wire [1:0] _244;
    wire [3:0] _245;
    wire [7:0] _246;
    wire [7:0] _247;
    wire [7:0] _241;
    wire [7:0] _242;
    wire [7:0] _248;
    wire _235;
    wire [2:0] _233;
    wire _234;
    wire _236;
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
    wire _202;
    wire [2:0] _200;
    wire _201;
    wire _208;
    wire [7:0] _237;
    wire [7:0] _238;
    wire _194;
    wire [7:0] _239;
    wire _192;
    wire [7:0] _249;
    wire [7:0] _15;
    reg [7:0] _197;
    wire _325;
    wire [1:0] _326;
    wire [3:0] _327;
    wire [7:0] _328;
    wire [7:0] _329;
    wire [7:0] _240;
    wire [7:0] _323;
    wire [7:0] _324;
    wire [7:0] _330;
    wire _318;
    wire _317;
    wire _319;
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
    wire [7:0] _320;
    wire _285;
    wire _284;
    wire _286;
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
    wire _205;
    wire _204;
    wire _206;
    wire _257;
    wire _256;
    wire _258;
    wire [7:0] _287;
    wire _198;
    wire [7:0] _321;
    wire _251;
    wire [7:0] _322;
    wire [3:0] _191;
    wire _250;
    wire [7:0] _331;
    wire [7:0] _17;
    reg [7:0] _254;
    wire [6:0] _173;
    wire [6:0] _704;
    wire _703;
    wire [6:0] _705;
    wire [11:0] _699;
    wire _700;
    wire [6:0] _701;
    wire [11:0] _337;
    wire [11:0] _19;
    reg [11:0] _336;
    wire [11:0] _343;
    wire [11:0] _20;
    reg [11:0] _342;
    wire [11:0] _349;
    wire [11:0] _21;
    reg [11:0] _348;
    wire [11:0] _362;
    wire [11:0] _363;
    wire [11:0] _360;
    wire _354;
    wire [11:0] _361;
    wire _352;
    wire [11:0] _364;
    wire [3:0] _350;
    wire _351;
    wire [11:0] _366;
    wire [11:0] _22;
    wire [11:0] _369;
    wire [11:0] _23;
    reg [11:0] _357;
    reg [11:0] _358;
    wire _694;
    wire _695;
    wire [6:0] _696;
    wire [6:0] _691;
    wire [6:0] _685;
    wire [6:0] _686;
    wire [6:0] _683;
    wire [6:0] _684;
    wire [6:0] _687;
    wire [6:0] _680;
    wire _121;
    wire _120;
    wire _119;
    wire _118;
    reg _122;
    wire [6:0] _681;
    wire [6:0] _678;
    wire [6:0] _679;
    wire [6:0] _682;
    wire [6:0] _688;
    wire [6:0] _674;
    wire [11:0] _373;
    wire [11:0] _25;
    reg [11:0] _372;
    wire [11:0] _377;
    wire [11:0] _26;
    reg [11:0] _376;
    wire [11:0] _381;
    wire [11:0] _27;
    reg [11:0] _380;
    wire [11:0] _365;
    wire [11:0] _391;
    wire _389;
    wire [11:0] _392;
    wire [3:0] _382;
    wire _383;
    wire [11:0] _393;
    wire [11:0] _28;
    wire [11:0] _394;
    wire [11:0] _29;
    reg [11:0] _386;
    reg [11:0] _387;
    wire _673;
    wire [6:0] _675;
    wire _670;
    wire _668;
    wire _667;
    wire _666;
    wire _665;
    wire _664;
    wire _663;
    wire _662;
    wire _661;
    wire _660;
    wire _659;
    wire _658;
    wire _657;
    wire _656;
    wire _655;
    wire _654;
    wire [7:0] _395;
    wire [7:0] _31;
    reg [7:0] _157;
    wire [7:0] _396;
    wire [7:0] _32;
    reg [7:0] _154;
    wire [7:0] _397;
    wire [7:0] _33;
    reg [7:0] _151;
    wire [7:0] _629;
    wire [7:0] _625;
    wire [6:0] _621;
    wire [7:0] _623;
    wire [7:0] _626;
    wire _615;
    wire _614;
    wire _613;
    wire _612;
    wire _611;
    wire _610;
    wire _609;
    wire _608;
    wire [2:0] _607;
    reg _616;
    wire _606;
    wire _617;
    wire [7:0] _619;
    wire [6:0] _604;
    wire [7:0] _605;
    wire [7:0] _620;
    wire [7:0] _627;
    wire [6:0] _599;
    wire [7:0] _600;
    wire [6:0] _597;
    wire _595;
    wire _594;
    wire _593;
    wire _592;
    wire _591;
    wire _590;
    wire _589;
    wire _588;
    wire [2:0] _199;
    reg _596;
    wire [7:0] _598;
    wire _203;
    wire [7:0] _601;
    wire [7:0] _586;
    reg [7:0] _581;
    wire _101;
    wire _100;
    wire _99;
    wire _98;
    reg _102;
    wire [7:0] _582;
    wire _409;
    wire _410;
    wire [7:0] _411;
    wire [7:0] _412;
    wire [7:0] _42;
    reg [7:0] _403;
    wire _407;
    wire _408;
    wire _417;
    wire [7:0] _418;
    wire [7:0] _419;
    wire [7:0] _43;
    reg [7:0] _415;
    wire _422;
    wire _423;
    wire _44;
    reg _406;
    wire [7:0] _578;
    wire _436;
    wire [7:0] _437;
    wire [7:0] _438;
    wire [7:0] _45;
    reg [7:0] _429;
    wire _433;
    wire _434;
    wire _443;
    wire [7:0] _444;
    wire [7:0] _445;
    wire [7:0] _46;
    reg [7:0] _441;
    wire _448;
    wire _449;
    wire _47;
    reg _432;
    wire [7:0] _577;
    wire _462;
    wire [7:0] _463;
    wire [7:0] _464;
    wire [7:0] _48;
    reg [7:0] _455;
    wire _459;
    wire _460;
    wire _469;
    wire [7:0] _470;
    wire [7:0] _471;
    wire [7:0] _49;
    reg [7:0] _467;
    wire _474;
    wire _475;
    wire _50;
    reg _458;
    wire [7:0] _576;
    wire _488;
    wire [7:0] _489;
    wire [7:0] _490;
    wire [7:0] _51;
    reg [7:0] _481;
    wire _485;
    wire _486;
    wire _495;
    wire [7:0] _496;
    wire [7:0] _497;
    wire [7:0] _52;
    reg [7:0] _493;
    wire _500;
    wire _501;
    wire _53;
    reg _484;
    wire [7:0] _575;
    reg [7:0] _579;
    wire _557;
    wire _556;
    wire _555;
    wire _551;
    wire _552;
    wire _548;
    wire _549;
    wire _545;
    wire _546;
    wire [1:0] _567;
    wire [1:0] _564;
    wire _533;
    wire _532;
    wire _531;
    wire [1:0] _506;
    wire [1:0] _503;
    wire _478;
    wire [1:0] _504;
    wire _477;
    wire _498;
    wire [1:0] _507;
    wire [1:0] _54;
    reg [1:0] _88;
    wire _528;
    wire [1:0] _512;
    wire [1:0] _509;
    wire _452;
    wire [1:0] _510;
    wire _451;
    wire _472;
    wire [1:0] _513;
    wire [1:0] _55;
    reg [1:0] _84;
    wire _526;
    wire [1:0] _518;
    wire [1:0] _515;
    wire _426;
    wire [1:0] _516;
    wire _425;
    wire _446;
    wire [1:0] _519;
    wire [1:0] _56;
    reg [1:0] _80;
    wire _524;
    wire _522;
    wire [3:0] _529;
    wire _530;
    reg _534;
    wire _535;
    wire _536;
    wire _537;
    wire _538;
    wire _520;
    wire _539;
    wire _57;
    wire _400;
    wire [1:0] _565;
    wire _399;
    wire _559;
    wire _560;
    wire _561;
    wire gnd;
    wire _540;
    wire _562;
    wire _58;
    wire _420;
    wire [1:0] _568;
    wire [1:0] _59;
    reg [1:0] _76;
    wire _542;
    wire _543;
    wire [3:0] _553;
    wire _554;
    wire [1:0] _97;
    reg _558;
    wire [7:0] _580;
    wire _96;
    wire [7:0] _583;
    wire _95;
    wire [7:0] _584;
    wire _574;
    wire [7:0] _585;
    wire _573;
    wire [7:0] _587;
    wire [3:0] _353;
    wire _572;
    wire [7:0] _602;
    wire [3:0] _193;
    wire _571;
    wire [7:0] _628;
    wire [3:0] _569;
    wire _570;
    wire [7:0] _630;
    wire [7:0] _60;
    wire [7:0] _631;
    wire [7:0] _61;
    reg [7:0] _148;
    reg [7:0] _158;
    wire _653;
    wire [3:0] _652;
    reg _669;
    wire _671;
    wire [6:0] _676;
    wire [6:0] _650;
    wire _333;
    wire [6:0] _632;
    wire [6:0] _62;
    reg [6:0] _165;
    wire _339;
    wire [6:0] _633;
    wire [6:0] _63;
    reg [6:0] _168;
    wire _345;
    wire [6:0] _634;
    wire [6:0] _64;
    reg [6:0] _171;
    reg [6:0] _649;
    wire [6:0] _651;
    wire [3:0] _647;
    wire _648;
    wire [6:0] _677;
    wire [3:0] _92;
    wire _646;
    wire [6:0] _689;
    wire [3:0] _644;
    wire _645;
    wire [6:0] _690;
    wire [3:0] _176;
    wire _643;
    wire [6:0] _692;
    wire [3:0] _641;
    wire _642;
    wire [6:0] _697;
    wire [3:0] _639;
    wire _640;
    wire [6:0] _698;
    wire [3:0] _637;
    wire _638;
    wire [6:0] _702;
    wire [3:0] _635;
    wire [3:0] _91;
    wire _636;
    wire [6:0] _706;
    wire [6:0] _66;
    wire _368;
    wire [6:0] _707;
    wire [6:0] _67;
    reg [6:0] _174;
    reg [6:0] _712;
    wire vdd;
    wire [1:0] _709;
    wire [1:0] _70;
    reg [1:0] _145;
    wire [1:0] _711;
    wire [8:0] _713;
    assign _89 = { gnd,
                   _88 };
    assign _85 = { gnd,
                   _84 };
    assign _81 = { gnd,
                   _80 };
    assign _77 = { gnd,
                   _76 };
    assign _90 = { _77,
                   _81,
                   _85,
                   _89 };
    assign _109 = 2'b00;
    assign _110 = _97 == _109;
    assign _107 = 2'b01;
    assign _108 = _97 == _107;
    assign _105 = 2'b10;
    assign _106 = _97 == _105;
    assign _103 = 2'b11;
    assign _104 = _97 == _103;
    assign _111 = { _104,
                    _106,
                    _108,
                    _110 };
    assign _112 = _102 ? _111 : _94;
    assign _113 = _96 ? _112 : _94;
    assign _114 = _95 ? _113 : _94;
    assign _94 = 4'b0000;
    assign _93 = _91 == _92;
    assign _115 = _93 ? _114 : _94;
    assign _2 = _115;
    assign _130 = _97 == _109;
    assign _128 = _97 == _107;
    assign _126 = _97 == _105;
    assign _124 = _97 == _103;
    assign _131 = { _124,
                    _126,
                    _128,
                    _130 };
    assign _132 = _122 ? _131 : _94;
    assign _133 = _96 ? _132 : _94;
    assign _134 = _95 ? _94 : _133;
    assign _116 = _91 == _92;
    assign _135 = _116 ? _134 : _94;
    assign _4 = _135;
    always @(posedge clock) begin
        if (clear)
            _138 <= _94;
        else
            _138 <= _4;
    end
    assign _141 = 8'b00000000;
    assign _159 = _122 ? _158 : _142;
    assign _160 = _96 ? _159 : _142;
    assign _161 = _95 ? _142 : _160;
    assign _139 = _91 == _92;
    assign _162 = _139 ? _161 : _142;
    assign _6 = _162;
    always @(posedge clock) begin
        if (clear)
            _142 <= _141;
        else
            _142 <= _6;
    end
    assign _175 = { _165,
                    _168,
                    _171,
                    _174 };
    assign _178 = host_in_valid ? vdd : gnd;
    assign _177 = _91 == _176;
    assign _179 = _177 ? _178 : gnd;
    assign _9 = _179;
    assign _184 = 1'b0;
    assign _181 = _91 == _180;
    assign _182 = _181 ? vdd : gnd;
    assign _11 = _182;
    always @(posedge clock) begin
        if (clear)
            _185 <= _184;
        else
            _185 <= _11;
    end
    assign _180 = 4'b1011;
    assign _186 = _91 == _180;
    assign _190 = _186 ? _158 : _189;
    assign _13 = _190;
    always @(posedge clock) begin
        if (clear)
            _189 <= _141;
        else
            _189 <= _13;
    end
    assign _243 = imem_data[2:2];
    assign _244 = { _243,
                    _243 };
    assign _245 = { _244,
                    _244 };
    assign _246 = { _245,
                    _245 };
    assign _247 = _240 & _246;
    assign _241 = ~ _240;
    assign _242 = _197 & _241;
    assign _248 = _242 | _247;
    assign _235 = _197[0:0];
    assign _233 = 3'b000;
    assign _234 = _199 == _233;
    assign _236 = _234 ? _207 : _235;
    assign _231 = _197[1:1];
    assign _229 = 3'b001;
    assign _230 = _199 == _229;
    assign _232 = _230 ? _207 : _231;
    assign _227 = _197[2:2];
    assign _225 = 3'b010;
    assign _226 = _199 == _225;
    assign _228 = _226 ? _207 : _227;
    assign _223 = _197[3:3];
    assign _221 = 3'b011;
    assign _222 = _199 == _221;
    assign _224 = _222 ? _207 : _223;
    assign _219 = _197[4:4];
    assign _217 = 3'b100;
    assign _218 = _199 == _217;
    assign _220 = _218 ? _207 : _219;
    assign _215 = _197[5:5];
    assign _213 = 3'b101;
    assign _214 = _199 == _213;
    assign _216 = _214 ? _207 : _215;
    assign _211 = _197[6:6];
    assign _209 = 3'b110;
    assign _210 = _199 == _209;
    assign _212 = _210 ? _207 : _211;
    assign _207 = ~ _206;
    assign _202 = _197[7:7];
    assign _200 = 3'b111;
    assign _201 = _199 == _200;
    assign _208 = _201 ? _207 : _202;
    assign _237 = { _208,
                    _212,
                    _216,
                    _220,
                    _224,
                    _228,
                    _232,
                    _236 };
    assign _238 = _198 ? _237 : _197;
    assign _194 = _91 == _193;
    assign _239 = _194 ? _238 : _197;
    assign _192 = _91 == _191;
    assign _249 = _192 ? _248 : _239;
    assign _15 = _249;
    always @(posedge clock) begin
        if (clear)
            _197 <= _141;
        else
            _197 <= _15;
    end
    assign _325 = imem_data[3:3];
    assign _326 = { _325,
                    _325 };
    assign _327 = { _326,
                    _326 };
    assign _328 = { _327,
                    _327 };
    assign _329 = _240 & _328;
    assign _240 = imem_data[11:4];
    assign _323 = ~ _240;
    assign _324 = _254 & _323;
    assign _330 = _324 | _329;
    assign _318 = _254[0:0];
    assign _317 = _199 == _233;
    assign _319 = _317 ? gnd : _318;
    assign _314 = _254[1:1];
    assign _313 = _199 == _229;
    assign _315 = _313 ? gnd : _314;
    assign _310 = _254[2:2];
    assign _309 = _199 == _225;
    assign _311 = _309 ? gnd : _310;
    assign _306 = _254[3:3];
    assign _305 = _199 == _221;
    assign _307 = _305 ? gnd : _306;
    assign _302 = _254[4:4];
    assign _301 = _199 == _217;
    assign _303 = _301 ? gnd : _302;
    assign _298 = _254[5:5];
    assign _297 = _199 == _213;
    assign _299 = _297 ? gnd : _298;
    assign _294 = _254[6:6];
    assign _293 = _199 == _209;
    assign _295 = _293 ? gnd : _294;
    assign _290 = _254[7:7];
    assign _289 = _199 == _200;
    assign _291 = _289 ? gnd : _290;
    assign _320 = { _291,
                    _295,
                    _299,
                    _303,
                    _307,
                    _311,
                    _315,
                    _319 };
    assign _285 = _254[0:0];
    assign _284 = _199 == _233;
    assign _286 = _284 ? _206 : _285;
    assign _281 = _254[1:1];
    assign _280 = _199 == _229;
    assign _282 = _280 ? _206 : _281;
    assign _277 = _254[2:2];
    assign _276 = _199 == _225;
    assign _278 = _276 ? _206 : _277;
    assign _273 = _254[3:3];
    assign _272 = _199 == _221;
    assign _274 = _272 ? _206 : _273;
    assign _269 = _254[4:4];
    assign _268 = _199 == _217;
    assign _270 = _268 ? _206 : _269;
    assign _265 = _254[5:5];
    assign _264 = _199 == _213;
    assign _266 = _264 ? _206 : _265;
    assign _261 = _254[6:6];
    assign _260 = _199 == _209;
    assign _262 = _260 ? _206 : _261;
    assign _205 = _158[7:7];
    assign _204 = _158[0:0];
    assign _206 = _203 ? _205 : _204;
    assign _257 = _254[7:7];
    assign _256 = _199 == _200;
    assign _258 = _256 ? _206 : _257;
    assign _287 = { _258,
                    _262,
                    _266,
                    _270,
                    _274,
                    _278,
                    _282,
                    _286 };
    assign _198 = imem_data[7:7];
    assign _321 = _198 ? _320 : _287;
    assign _251 = _91 == _193;
    assign _322 = _251 ? _321 : _254;
    assign _191 = 4'b0001;
    assign _250 = _91 == _191;
    assign _331 = _250 ? _330 : _322;
    assign _17 = _331;
    always @(posedge clock) begin
        if (clear)
            _254 <= _141;
        else
            _254 <= _17;
    end
    assign _173 = 7'b0000000;
    assign _704 = _673 ? _674 : _649;
    assign _703 = _596 == _203;
    assign _705 = _703 ? _651 : _704;
    assign _699 = 12'b000000000000;
    assign _700 = _387 == _699;
    assign _701 = _700 ? _651 : _649;
    assign _337 = _333 ? _22 : _336;
    assign _19 = _337;
    always @(posedge clock) begin
        if (clear)
            _336 <= _699;
        else
            _336 <= _19;
    end
    assign _343 = _339 ? _22 : _342;
    assign _20 = _343;
    always @(posedge clock) begin
        if (clear)
            _342 <= _699;
        else
            _342 <= _20;
    end
    assign _349 = _345 ? _22 : _348;
    assign _21 = _349;
    always @(posedge clock) begin
        if (clear)
            _348 <= _699;
        else
            _348 <= _21;
    end
    assign _362 = 12'b000000000001;
    assign _363 = _358 - _362;
    assign _360 = _358 - _362;
    assign _354 = _91 == _353;
    assign _361 = _354 ? _360 : _358;
    assign _352 = _91 == _193;
    assign _364 = _352 ? _363 : _361;
    assign _350 = 4'b0010;
    assign _351 = _91 == _350;
    assign _366 = _351 ? _365 : _364;
    assign _22 = _366;
    assign _369 = _368 ? _22 : _357;
    assign _23 = _369;
    always @(posedge clock) begin
        if (clear)
            _357 <= _699;
        else
            _357 <= _23;
    end
    always @* begin
        case (_145)
        0:
            _358 <= _357;
        1:
            _358 <= _348;
        2:
            _358 <= _342;
        default:
            _358 <= _336;
        endcase
    end
    assign _694 = _358 == _699;
    assign _695 = ~ _694;
    assign _696 = _695 ? _674 : _651;
    assign _691 = host_in_valid ? _651 : _649;
    assign _685 = _673 ? _674 : _649;
    assign _686 = _102 ? _651 : _685;
    assign _683 = _673 ? _674 : _649;
    assign _684 = _558 ? _651 : _683;
    assign _687 = _96 ? _686 : _684;
    assign _680 = _673 ? _674 : _649;
    assign _121 = port_out_ready[3:3];
    assign _120 = port_out_ready[2:2];
    assign _119 = port_out_ready[1:1];
    assign _118 = port_out_ready[0:0];
    always @* begin
        case (_97)
        0:
            _122 <= _118;
        1:
            _122 <= _119;
        2:
            _122 <= _120;
        default:
            _122 <= _121;
        endcase
    end
    assign _681 = _122 ? _651 : _680;
    assign _678 = _673 ? _674 : _649;
    assign _679 = _535 ? _651 : _678;
    assign _682 = _96 ? _681 : _679;
    assign _688 = _95 ? _687 : _682;
    assign _674 = imem_data[6:0];
    assign _373 = _333 ? _28 : _372;
    assign _25 = _373;
    always @(posedge clock) begin
        if (clear)
            _372 <= _699;
        else
            _372 <= _25;
    end
    assign _377 = _339 ? _28 : _376;
    assign _26 = _377;
    always @(posedge clock) begin
        if (clear)
            _376 <= _699;
        else
            _376 <= _26;
    end
    assign _381 = _345 ? _28 : _380;
    assign _27 = _381;
    always @(posedge clock) begin
        if (clear)
            _380 <= _699;
        else
            _380 <= _27;
    end
    assign _365 = imem_data[11:0];
    assign _391 = _387 - _362;
    assign _389 = _387 == _699;
    assign _392 = _389 ? _387 : _391;
    assign _382 = 4'b0011;
    assign _383 = _91 == _382;
    assign _393 = _383 ? _365 : _392;
    assign _28 = _393;
    assign _394 = _368 ? _28 : _386;
    assign _29 = _394;
    always @(posedge clock) begin
        if (clear)
            _386 <= _699;
        else
            _386 <= _29;
    end
    always @* begin
        case (_145)
        0:
            _387 <= _386;
        1:
            _387 <= _380;
        2:
            _387 <= _376;
        default:
            _387 <= _372;
        endcase
    end
    assign _673 = _387 == _699;
    assign _675 = _673 ? _674 : _649;
    assign _670 = imem_data[11:11];
    assign _668 = flags[3:3];
    assign _667 = flags[2:2];
    assign _666 = flags[1:1];
    assign _665 = flags[0:0];
    assign _664 = _529[3:3];
    assign _663 = _529[2:2];
    assign _662 = _529[1:1];
    assign _661 = _529[0:0];
    assign _660 = _158[7:7];
    assign _659 = _158[6:6];
    assign _658 = _158[5:5];
    assign _657 = _158[4:4];
    assign _656 = _158[3:3];
    assign _655 = _158[2:2];
    assign _654 = _158[1:1];
    assign _395 = _333 ? _60 : _157;
    assign _31 = _395;
    always @(posedge clock) begin
        if (clear)
            _157 <= _141;
        else
            _157 <= _31;
    end
    assign _396 = _339 ? _60 : _154;
    assign _32 = _396;
    always @(posedge clock) begin
        if (clear)
            _154 <= _141;
        else
            _154 <= _32;
    end
    assign _397 = _345 ? _60 : _151;
    assign _33 = _397;
    always @(posedge clock) begin
        if (clear)
            _151 <= _141;
        else
            _151 <= _33;
    end
    assign _629 = imem_data[7:0];
    assign _625 = { _173,
                    _617 };
    assign _621 = _158[6:0];
    assign _623 = { _621,
                    _184 };
    assign _626 = _623 | _625;
    assign _615 = pin_in[7:7];
    assign _614 = pin_in[6:6];
    assign _613 = pin_in[5:5];
    assign _612 = pin_in[4:4];
    assign _611 = pin_in[3:3];
    assign _610 = pin_in[2:2];
    assign _609 = pin_in[1:1];
    assign _608 = pin_in[0:0];
    assign _607 = imem_data[5:3];
    always @* begin
        case (_607)
        0:
            _616 <= _608;
        1:
            _616 <= _609;
        2:
            _616 <= _610;
        3:
            _616 <= _611;
        4:
            _616 <= _612;
        5:
            _616 <= _613;
        6:
            _616 <= _614;
        default:
            _616 <= _615;
        endcase
    end
    assign _606 = imem_data[6:6];
    assign _617 = _606 & _616;
    assign _619 = { _617,
                    _173 };
    assign _604 = _158[7:1];
    assign _605 = { _184,
                    _604 };
    assign _620 = _605 | _619;
    assign _627 = _203 ? _626 : _620;
    assign _599 = _158[6:0];
    assign _600 = { _599,
                    _596 };
    assign _597 = _158[7:1];
    assign _595 = pin_in[7:7];
    assign _594 = pin_in[6:6];
    assign _593 = pin_in[5:5];
    assign _592 = pin_in[4:4];
    assign _591 = pin_in[3:3];
    assign _590 = pin_in[2:2];
    assign _589 = pin_in[1:1];
    assign _588 = pin_in[0:0];
    assign _199 = imem_data[11:9];
    always @* begin
        case (_199)
        0:
            _596 <= _588;
        1:
            _596 <= _589;
        2:
            _596 <= _590;
        3:
            _596 <= _591;
        4:
            _596 <= _592;
        5:
            _596 <= _593;
        6:
            _596 <= _594;
        default:
            _596 <= _595;
        endcase
    end
    assign _598 = { _596,
                    _597 };
    assign _203 = imem_data[8:8];
    assign _601 = _203 ? _600 : _598;
    assign _586 = host_in_valid ? host_in : _158;
    always @* begin
        case (_97)
        0:
            _581 <= port_in0;
        1:
            _581 <= port_in1;
        2:
            _581 <= port_in2;
        default:
            _581 <= port_in3;
        endcase
    end
    assign _101 = port_in_valid[3:3];
    assign _100 = port_in_valid[2:2];
    assign _99 = port_in_valid[1:1];
    assign _98 = port_in_valid[0:0];
    always @* begin
        case (_97)
        0:
            _102 <= _98;
        1:
            _102 <= _99;
        2:
            _102 <= _100;
        default:
            _102 <= _101;
        endcase
    end
    assign _582 = _102 ? _581 : _158;
    assign _409 = 1'b1;
    assign _410 = _408 == _409;
    assign _411 = _410 ? _158 : _403;
    assign _412 = _400 ? _411 : _403;
    assign _42 = _412;
    always @(posedge clock) begin
        if (clear)
            _403 <= _141;
        else
            _403 <= _42;
    end
    assign _407 = _76[0:0];
    assign _408 = _406 + _407;
    assign _417 = _408 == _184;
    assign _418 = _417 ? _158 : _415;
    assign _419 = _400 ? _418 : _415;
    assign _43 = _419;
    always @(posedge clock) begin
        if (clear)
            _415 <= _141;
        else
            _415 <= _43;
    end
    assign _422 = _406 + _409;
    assign _423 = _420 ? _422 : _406;
    assign _44 = _423;
    always @(posedge clock) begin
        if (clear)
            _406 <= _184;
        else
            _406 <= _44;
    end
    assign _578 = _406 ? _403 : _415;
    assign _436 = _434 == _409;
    assign _437 = _436 ? _158 : _429;
    assign _438 = _426 ? _437 : _429;
    assign _45 = _438;
    always @(posedge clock) begin
        if (clear)
            _429 <= _141;
        else
            _429 <= _45;
    end
    assign _433 = _80[0:0];
    assign _434 = _432 + _433;
    assign _443 = _434 == _184;
    assign _444 = _443 ? _158 : _441;
    assign _445 = _426 ? _444 : _441;
    assign _46 = _445;
    always @(posedge clock) begin
        if (clear)
            _441 <= _141;
        else
            _441 <= _46;
    end
    assign _448 = _432 + _409;
    assign _449 = _446 ? _448 : _432;
    assign _47 = _449;
    always @(posedge clock) begin
        if (clear)
            _432 <= _184;
        else
            _432 <= _47;
    end
    assign _577 = _432 ? _429 : _441;
    assign _462 = _460 == _409;
    assign _463 = _462 ? _158 : _455;
    assign _464 = _452 ? _463 : _455;
    assign _48 = _464;
    always @(posedge clock) begin
        if (clear)
            _455 <= _141;
        else
            _455 <= _48;
    end
    assign _459 = _84[0:0];
    assign _460 = _458 + _459;
    assign _469 = _460 == _184;
    assign _470 = _469 ? _158 : _467;
    assign _471 = _452 ? _470 : _467;
    assign _49 = _471;
    always @(posedge clock) begin
        if (clear)
            _467 <= _141;
        else
            _467 <= _49;
    end
    assign _474 = _458 + _409;
    assign _475 = _472 ? _474 : _458;
    assign _50 = _475;
    always @(posedge clock) begin
        if (clear)
            _458 <= _184;
        else
            _458 <= _50;
    end
    assign _576 = _458 ? _455 : _467;
    assign _488 = _486 == _409;
    assign _489 = _488 ? _158 : _481;
    assign _490 = _478 ? _489 : _481;
    assign _51 = _490;
    always @(posedge clock) begin
        if (clear)
            _481 <= _141;
        else
            _481 <= _51;
    end
    assign _485 = _88[0:0];
    assign _486 = _484 + _485;
    assign _495 = _486 == _184;
    assign _496 = _495 ? _158 : _493;
    assign _497 = _478 ? _496 : _493;
    assign _52 = _497;
    always @(posedge clock) begin
        if (clear)
            _493 <= _141;
        else
            _493 <= _52;
    end
    assign _500 = _484 + _409;
    assign _501 = _498 ? _500 : _484;
    assign _53 = _501;
    always @(posedge clock) begin
        if (clear)
            _484 <= _184;
        else
            _484 <= _53;
    end
    assign _575 = _484 ? _481 : _493;
    always @* begin
        case (_97)
        0:
            _579 <= _575;
        1:
            _579 <= _576;
        2:
            _579 <= _577;
        default:
            _579 <= _578;
        endcase
    end
    assign _557 = _553[3:3];
    assign _556 = _553[2:2];
    assign _555 = _553[1:1];
    assign _551 = _88 == _109;
    assign _552 = ~ _551;
    assign _548 = _84 == _109;
    assign _549 = ~ _548;
    assign _545 = _80 == _109;
    assign _546 = ~ _545;
    assign _567 = _76 - _107;
    assign _564 = _76 + _107;
    assign _533 = _529[3:3];
    assign _532 = _529[2:2];
    assign _531 = _529[1:1];
    assign _506 = _88 - _107;
    assign _503 = _88 + _107;
    assign _478 = _57 & _477;
    assign _504 = _478 ? _503 : _88;
    assign _477 = _97 == _109;
    assign _498 = _58 & _477;
    assign _507 = _498 ? _506 : _504;
    assign _54 = _507;
    always @(posedge clock) begin
        if (clear)
            _88 <= _109;
        else
            _88 <= _54;
    end
    assign _528 = _88 == _105;
    assign _512 = _84 - _107;
    assign _509 = _84 + _107;
    assign _452 = _57 & _451;
    assign _510 = _452 ? _509 : _84;
    assign _451 = _97 == _107;
    assign _472 = _58 & _451;
    assign _513 = _472 ? _512 : _510;
    assign _55 = _513;
    always @(posedge clock) begin
        if (clear)
            _84 <= _109;
        else
            _84 <= _55;
    end
    assign _526 = _84 == _105;
    assign _518 = _80 - _107;
    assign _515 = _80 + _107;
    assign _426 = _57 & _425;
    assign _516 = _426 ? _515 : _80;
    assign _425 = _97 == _105;
    assign _446 = _58 & _425;
    assign _519 = _446 ? _518 : _516;
    assign _56 = _519;
    always @(posedge clock) begin
        if (clear)
            _80 <= _109;
        else
            _80 <= _56;
    end
    assign _524 = _80 == _105;
    assign _522 = _76 == _105;
    assign _529 = { _522,
                    _524,
                    _526,
                    _528 };
    assign _530 = _529[0:0];
    always @* begin
        case (_97)
        0:
            _534 <= _530;
        1:
            _534 <= _531;
        2:
            _534 <= _532;
        default:
            _534 <= _533;
        endcase
    end
    assign _535 = ~ _534;
    assign _536 = _535 ? vdd : gnd;
    assign _537 = _96 ? gnd : _536;
    assign _538 = _95 ? gnd : _537;
    assign _520 = _91 == _92;
    assign _539 = _520 ? _538 : gnd;
    assign _57 = _539;
    assign _400 = _57 & _399;
    assign _565 = _400 ? _564 : _76;
    assign _399 = _97 == _103;
    assign _559 = _558 ? vdd : gnd;
    assign _560 = _96 ? gnd : _559;
    assign _561 = _95 ? _560 : gnd;
    assign gnd = 1'b0;
    assign _540 = _91 == _92;
    assign _562 = _540 ? _561 : gnd;
    assign _58 = _562;
    assign _420 = _58 & _399;
    assign _568 = _420 ? _567 : _565;
    assign _59 = _568;
    always @(posedge clock) begin
        if (clear)
            _76 <= _109;
        else
            _76 <= _59;
    end
    assign _542 = _76 == _109;
    assign _543 = ~ _542;
    assign _553 = { _543,
                    _546,
                    _549,
                    _552 };
    assign _554 = _553[0:0];
    assign _97 = imem_data[9:8];
    always @* begin
        case (_97)
        0:
            _558 <= _554;
        1:
            _558 <= _555;
        2:
            _558 <= _556;
        default:
            _558 <= _557;
        endcase
    end
    assign _580 = _558 ? _579 : _158;
    assign _96 = imem_data[10:10];
    assign _583 = _96 ? _582 : _580;
    assign _95 = imem_data[11:11];
    assign _584 = _95 ? _583 : _158;
    assign _574 = _91 == _92;
    assign _585 = _574 ? _584 : _158;
    assign _573 = _91 == _176;
    assign _587 = _573 ? _586 : _585;
    assign _353 = 4'b1000;
    assign _572 = _91 == _353;
    assign _602 = _572 ? _601 : _587;
    assign _193 = 4'b0111;
    assign _571 = _91 == _193;
    assign _628 = _571 ? _627 : _602;
    assign _569 = 4'b0100;
    assign _570 = _91 == _569;
    assign _630 = _570 ? _629 : _628;
    assign _60 = _630;
    assign _631 = _368 ? _60 : _148;
    assign _61 = _631;
    always @(posedge clock) begin
        if (clear)
            _148 <= _141;
        else
            _148 <= _61;
    end
    always @* begin
        case (_145)
        0:
            _158 <= _148;
        1:
            _158 <= _151;
        2:
            _158 <= _154;
        default:
            _158 <= _157;
        endcase
    end
    assign _653 = _158[0:0];
    assign _652 = imem_data[10:7];
    always @* begin
        case (_652)
        0:
            _669 <= _653;
        1:
            _669 <= _654;
        2:
            _669 <= _655;
        3:
            _669 <= _656;
        4:
            _669 <= _657;
        5:
            _669 <= _658;
        6:
            _669 <= _659;
        7:
            _669 <= _660;
        8:
            _669 <= _661;
        9:
            _669 <= _662;
        10:
            _669 <= _663;
        11:
            _669 <= _664;
        12:
            _669 <= _665;
        13:
            _669 <= _666;
        14:
            _669 <= _667;
        default:
            _669 <= _668;
        endcase
    end
    assign _671 = _669 == _670;
    assign _676 = _671 ? _651 : _675;
    assign _650 = 7'b0000001;
    assign _333 = _145 == _103;
    assign _632 = _333 ? _66 : _165;
    assign _62 = _632;
    always @(posedge clock) begin
        if (clear)
            _165 <= _173;
        else
            _165 <= _62;
    end
    assign _339 = _145 == _105;
    assign _633 = _339 ? _66 : _168;
    assign _63 = _633;
    always @(posedge clock) begin
        if (clear)
            _168 <= _173;
        else
            _168 <= _63;
    end
    assign _345 = _145 == _107;
    assign _634 = _345 ? _66 : _171;
    assign _64 = _634;
    always @(posedge clock) begin
        if (clear)
            _171 <= _173;
        else
            _171 <= _64;
    end
    always @* begin
        case (_145)
        0:
            _649 <= _174;
        1:
            _649 <= _171;
        2:
            _649 <= _168;
        default:
            _649 <= _165;
        endcase
    end
    assign _651 = _649 + _650;
    assign _647 = 4'b1111;
    assign _648 = _91 == _647;
    assign _677 = _648 ? _676 : _651;
    assign _92 = 4'b1110;
    assign _646 = _91 == _92;
    assign _689 = _646 ? _688 : _677;
    assign _644 = 4'b1101;
    assign _645 = _91 == _644;
    assign _690 = _645 ? _649 : _689;
    assign _176 = 4'b1100;
    assign _643 = _91 == _176;
    assign _692 = _643 ? _691 : _690;
    assign _641 = 4'b1010;
    assign _642 = _91 == _641;
    assign _697 = _642 ? _696 : _692;
    assign _639 = 4'b1001;
    assign _640 = _91 == _639;
    assign _698 = _640 ? _674 : _697;
    assign _637 = 4'b0110;
    assign _638 = _91 == _637;
    assign _702 = _638 ? _701 : _698;
    assign _635 = 4'b0101;
    assign _91 = imem_data[15:12];
    assign _636 = _91 == _635;
    assign _706 = _636 ? _705 : _702;
    assign _66 = _706;
    assign _368 = _145 == _109;
    assign _707 = _368 ? _66 : _174;
    assign _67 = _707;
    always @(posedge clock) begin
        if (clear)
            _174 <= _173;
        else
            _174 <= _67;
    end
    always @* begin
        case (_711)
        0:
            _712 <= _174;
        1:
            _712 <= _171;
        2:
            _712 <= _168;
        default:
            _712 <= _165;
        endcase
    end
    assign vdd = 1'b1;
    assign _709 = _145 + _107;
    assign _70 = _709;
    always @(posedge clock) begin
        if (clear)
            _145 <= _109;
        else
            _145 <= _70;
    end
    assign _711 = _145 + _107;
    assign _713 = { _711,
                    _712 };
    assign imem_addr = _713;
    assign pin_out = _254;
    assign pin_oe = _197;
    assign host_out = _189;
    assign host_out_valid = _185;
    assign host_in_ready = _9;
    assign pcs = _175;
    assign port_out_data = _142;
    assign port_out_valid = _138;
    assign port_in_ready = _2;
    assign mb_counts = _90;

endmodule
