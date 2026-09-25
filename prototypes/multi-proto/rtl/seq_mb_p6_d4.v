module deadline_sequencer_mb_p6_d4 (
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

    wire [11:0] _93;
    wire [1:0] _112;
    wire _113;
    wire [1:0] _110;
    wire _111;
    wire [1:0] _108;
    wire _109;
    wire [1:0] _106;
    wire _107;
    wire [3:0] _114;
    wire [3:0] _115;
    wire [3:0] _116;
    wire [3:0] _117;
    wire [3:0] _97;
    wire _96;
    wire [3:0] _118;
    wire [3:0] _2;
    wire _133;
    wire _131;
    wire _129;
    wire _127;
    wire [3:0] _134;
    wire [3:0] _135;
    wire [3:0] _136;
    wire [3:0] _137;
    wire _119;
    wire [3:0] _138;
    wire [3:0] _4;
    reg [3:0] _141;
    wire [7:0] _144;
    wire [7:0] _162;
    wire [7:0] _163;
    wire [7:0] _164;
    wire _142;
    wire [7:0] _165;
    wire [7:0] _6;
    reg [7:0] _145;
    wire [23:0] _178;
    wire _182;
    wire _180;
    wire _183;
    wire _9;
    wire _188;
    wire _185;
    wire _186;
    wire _11;
    reg _189;
    wire [3:0] _184;
    wire _190;
    wire [7:0] _194;
    wire [7:0] _13;
    reg [7:0] _193;
    wire _247;
    wire [1:0] _248;
    wire [3:0] _249;
    wire [7:0] _250;
    wire [7:0] _251;
    wire [7:0] _245;
    wire [7:0] _246;
    wire [7:0] _252;
    wire _239;
    wire [2:0] _237;
    wire _238;
    wire _240;
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
    wire _206;
    wire [2:0] _204;
    wire _205;
    wire _212;
    wire [7:0] _241;
    wire [7:0] _242;
    wire _198;
    wire [7:0] _243;
    wire _196;
    wire [7:0] _253;
    wire [7:0] _15;
    reg [7:0] _201;
    wire _329;
    wire [1:0] _330;
    wire [3:0] _331;
    wire [7:0] _332;
    wire [7:0] _333;
    wire [7:0] _244;
    wire [7:0] _327;
    wire [7:0] _328;
    wire [7:0] _334;
    wire _322;
    wire _321;
    wire _323;
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
    wire [7:0] _324;
    wire _289;
    wire _288;
    wire _290;
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
    wire _209;
    wire _208;
    wire _210;
    wire _261;
    wire _260;
    wire _262;
    wire [7:0] _291;
    wire _202;
    wire [7:0] _325;
    wire _255;
    wire [7:0] _326;
    wire [3:0] _195;
    wire _254;
    wire [7:0] _335;
    wire [7:0] _17;
    reg [7:0] _258;
    wire [5:0] _176;
    wire [5:0] _764;
    wire _763;
    wire [5:0] _765;
    wire [11:0] _759;
    wire _760;
    wire [5:0] _761;
    wire [11:0] _341;
    wire [11:0] _19;
    reg [11:0] _340;
    wire [11:0] _347;
    wire [11:0] _20;
    reg [11:0] _346;
    wire [11:0] _353;
    wire [11:0] _21;
    reg [11:0] _352;
    wire [11:0] _366;
    wire [11:0] _367;
    wire [11:0] _364;
    wire _358;
    wire [11:0] _365;
    wire _356;
    wire [11:0] _368;
    wire [3:0] _354;
    wire _355;
    wire [11:0] _370;
    wire [11:0] _22;
    wire [11:0] _373;
    wire [11:0] _23;
    reg [11:0] _361;
    reg [11:0] _362;
    wire _754;
    wire _755;
    wire [5:0] _756;
    wire [5:0] _751;
    wire [5:0] _745;
    wire [5:0] _746;
    wire [5:0] _743;
    wire [5:0] _744;
    wire [5:0] _747;
    wire [5:0] _740;
    wire _124;
    wire _123;
    wire _122;
    wire _121;
    reg _125;
    wire [5:0] _741;
    wire [5:0] _738;
    wire [5:0] _739;
    wire [5:0] _742;
    wire [5:0] _748;
    wire [5:0] _734;
    wire [11:0] _377;
    wire [11:0] _25;
    reg [11:0] _376;
    wire [11:0] _381;
    wire [11:0] _26;
    reg [11:0] _380;
    wire [11:0] _385;
    wire [11:0] _27;
    reg [11:0] _384;
    wire [11:0] _369;
    wire [11:0] _395;
    wire _393;
    wire [11:0] _396;
    wire [3:0] _386;
    wire _387;
    wire [11:0] _397;
    wire [11:0] _28;
    wire [11:0] _398;
    wire [11:0] _29;
    reg [11:0] _390;
    reg [11:0] _391;
    wire _733;
    wire [5:0] _735;
    wire _730;
    wire _728;
    wire _727;
    wire _726;
    wire _725;
    wire _724;
    wire _723;
    wire _722;
    wire _721;
    wire _720;
    wire _719;
    wire _718;
    wire _717;
    wire _716;
    wire _715;
    wire _714;
    wire [7:0] _399;
    wire [7:0] _31;
    reg [7:0] _160;
    wire [7:0] _400;
    wire [7:0] _32;
    reg [7:0] _157;
    wire [7:0] _401;
    wire [7:0] _33;
    reg [7:0] _154;
    wire [7:0] _689;
    wire [6:0] _684;
    wire [7:0] _685;
    wire [6:0] _681;
    wire [7:0] _683;
    wire [7:0] _686;
    wire _675;
    wire _674;
    wire _673;
    wire _672;
    wire _671;
    wire _670;
    wire _669;
    wire _668;
    wire [2:0] _667;
    reg _676;
    wire _666;
    wire _677;
    wire [7:0] _679;
    wire [6:0] _664;
    wire [7:0] _665;
    wire [7:0] _680;
    wire [7:0] _687;
    wire [6:0] _659;
    wire [7:0] _660;
    wire [6:0] _657;
    wire _655;
    wire _654;
    wire _653;
    wire _652;
    wire _651;
    wire _650;
    wire _649;
    wire _648;
    wire [2:0] _203;
    reg _656;
    wire [7:0] _658;
    wire _207;
    wire [7:0] _661;
    wire [7:0] _646;
    reg [7:0] _641;
    wire _104;
    wire _103;
    wire _102;
    wire _101;
    reg _105;
    wire [7:0] _642;
    wire _414;
    wire [7:0] _415;
    wire [7:0] _416;
    wire [7:0] _42;
    reg [7:0] _407;
    wire _421;
    wire [7:0] _422;
    wire [7:0] _423;
    wire [7:0] _43;
    reg [7:0] _419;
    wire _428;
    wire [7:0] _429;
    wire [7:0] _430;
    wire [7:0] _44;
    reg [7:0] _426;
    wire [1:0] _411;
    wire [1:0] _412;
    wire _435;
    wire [7:0] _436;
    wire [7:0] _437;
    wire [7:0] _45;
    reg [7:0] _433;
    wire [1:0] _440;
    wire [1:0] _441;
    wire [1:0] _46;
    reg [1:0] _410;
    reg [7:0] _638;
    wire _454;
    wire [7:0] _455;
    wire [7:0] _456;
    wire [7:0] _47;
    reg [7:0] _447;
    wire _461;
    wire [7:0] _462;
    wire [7:0] _463;
    wire [7:0] _48;
    reg [7:0] _459;
    wire _468;
    wire [7:0] _469;
    wire [7:0] _470;
    wire [7:0] _49;
    reg [7:0] _466;
    wire [1:0] _451;
    wire [1:0] _452;
    wire _475;
    wire [7:0] _476;
    wire [7:0] _477;
    wire [7:0] _50;
    reg [7:0] _473;
    wire [1:0] _480;
    wire [1:0] _481;
    wire [1:0] _51;
    reg [1:0] _450;
    reg [7:0] _637;
    wire _494;
    wire [7:0] _495;
    wire [7:0] _496;
    wire [7:0] _52;
    reg [7:0] _487;
    wire _501;
    wire [7:0] _502;
    wire [7:0] _503;
    wire [7:0] _53;
    reg [7:0] _499;
    wire _508;
    wire [7:0] _509;
    wire [7:0] _510;
    wire [7:0] _54;
    reg [7:0] _506;
    wire [1:0] _491;
    wire [1:0] _492;
    wire _515;
    wire [7:0] _516;
    wire [7:0] _517;
    wire [7:0] _55;
    reg [7:0] _513;
    wire [1:0] _520;
    wire [1:0] _521;
    wire [1:0] _56;
    reg [1:0] _490;
    reg [7:0] _636;
    wire _534;
    wire [7:0] _535;
    wire [7:0] _536;
    wire [7:0] _57;
    reg [7:0] _527;
    wire _541;
    wire [7:0] _542;
    wire [7:0] _543;
    wire [7:0] _58;
    reg [7:0] _539;
    wire _548;
    wire [7:0] _549;
    wire [7:0] _550;
    wire [7:0] _59;
    reg [7:0] _546;
    wire [1:0] _531;
    wire [1:0] _532;
    wire _555;
    wire [7:0] _556;
    wire [7:0] _557;
    wire [7:0] _60;
    reg [7:0] _553;
    wire [1:0] _560;
    wire [1:0] _561;
    wire [1:0] _61;
    reg [1:0] _530;
    reg [7:0] _635;
    reg [7:0] _639;
    wire _617;
    wire _616;
    wire _615;
    wire _611;
    wire _612;
    wire _608;
    wire _609;
    wire _605;
    wire _606;
    wire [2:0] _627;
    wire [2:0] _624;
    wire _593;
    wire _592;
    wire _591;
    wire [2:0] _566;
    wire [2:0] _563;
    wire _524;
    wire [2:0] _564;
    wire _523;
    wire _558;
    wire [2:0] _567;
    wire [2:0] _62;
    reg [2:0] _92;
    wire _588;
    wire [2:0] _572;
    wire [2:0] _569;
    wire _484;
    wire [2:0] _570;
    wire _483;
    wire _518;
    wire [2:0] _573;
    wire [2:0] _63;
    reg [2:0] _89;
    wire _586;
    wire [2:0] _578;
    wire [2:0] _575;
    wire _444;
    wire [2:0] _576;
    wire _443;
    wire _478;
    wire [2:0] _579;
    wire [2:0] _64;
    reg [2:0] _86;
    wire _584;
    wire _582;
    wire [3:0] _589;
    wire _590;
    reg _594;
    wire _595;
    wire _596;
    wire _597;
    wire _598;
    wire _580;
    wire _599;
    wire _65;
    wire _404;
    wire [2:0] _625;
    wire _403;
    wire _619;
    wire _620;
    wire _621;
    wire gnd;
    wire _600;
    wire _622;
    wire _66;
    wire _438;
    wire [2:0] _628;
    wire [2:0] _67;
    reg [2:0] _83;
    wire _602;
    wire _603;
    wire [3:0] _613;
    wire _614;
    wire [1:0] _100;
    reg _618;
    wire [7:0] _640;
    wire _99;
    wire [7:0] _643;
    wire _98;
    wire [7:0] _644;
    wire _634;
    wire [7:0] _645;
    wire _633;
    wire [7:0] _647;
    wire [3:0] _357;
    wire _632;
    wire [7:0] _662;
    wire [3:0] _197;
    wire _631;
    wire [7:0] _688;
    wire [3:0] _629;
    wire _630;
    wire [7:0] _690;
    wire [7:0] _68;
    wire [7:0] _691;
    wire [7:0] _69;
    reg [7:0] _151;
    reg [7:0] _161;
    wire _713;
    wire [3:0] _712;
    reg _729;
    wire _731;
    wire [5:0] _736;
    wire [5:0] _710;
    wire _337;
    wire [5:0] _692;
    wire [5:0] _70;
    reg [5:0] _168;
    wire _343;
    wire [5:0] _693;
    wire [5:0] _71;
    reg [5:0] _171;
    wire _349;
    wire [5:0] _694;
    wire [5:0] _72;
    reg [5:0] _174;
    reg [5:0] _709;
    wire [5:0] _711;
    wire [3:0] _707;
    wire _708;
    wire [5:0] _737;
    wire [3:0] _95;
    wire _706;
    wire [5:0] _749;
    wire [3:0] _704;
    wire _705;
    wire [5:0] _750;
    wire [3:0] _179;
    wire _703;
    wire [5:0] _752;
    wire [3:0] _701;
    wire _702;
    wire [5:0] _757;
    wire [3:0] _699;
    wire _700;
    wire [5:0] _758;
    wire [3:0] _697;
    wire _698;
    wire [5:0] _762;
    wire [3:0] _695;
    wire [3:0] _94;
    wire _696;
    wire [5:0] _766;
    wire [5:0] _74;
    wire _372;
    wire [5:0] _767;
    wire [5:0] _75;
    reg [5:0] _177;
    reg [5:0] _772;
    wire vdd;
    wire [1:0] _769;
    wire [1:0] _78;
    reg [1:0] _148;
    wire [1:0] _771;
    wire [7:0] _773;
    assign _93 = { _83,
                   _86,
                   _89,
                   _92 };
    assign _112 = 2'b00;
    assign _113 = _100 == _112;
    assign _110 = 2'b01;
    assign _111 = _100 == _110;
    assign _108 = 2'b10;
    assign _109 = _100 == _108;
    assign _106 = 2'b11;
    assign _107 = _100 == _106;
    assign _114 = { _107,
                    _109,
                    _111,
                    _113 };
    assign _115 = _105 ? _114 : _97;
    assign _116 = _99 ? _115 : _97;
    assign _117 = _98 ? _116 : _97;
    assign _97 = 4'b0000;
    assign _96 = _94 == _95;
    assign _118 = _96 ? _117 : _97;
    assign _2 = _118;
    assign _133 = _100 == _112;
    assign _131 = _100 == _110;
    assign _129 = _100 == _108;
    assign _127 = _100 == _106;
    assign _134 = { _127,
                    _129,
                    _131,
                    _133 };
    assign _135 = _125 ? _134 : _97;
    assign _136 = _99 ? _135 : _97;
    assign _137 = _98 ? _97 : _136;
    assign _119 = _94 == _95;
    assign _138 = _119 ? _137 : _97;
    assign _4 = _138;
    always @(posedge clock) begin
        if (clear)
            _141 <= _97;
        else
            _141 <= _4;
    end
    assign _144 = 8'b00000000;
    assign _162 = _125 ? _161 : _145;
    assign _163 = _99 ? _162 : _145;
    assign _164 = _98 ? _145 : _163;
    assign _142 = _94 == _95;
    assign _165 = _142 ? _164 : _145;
    assign _6 = _165;
    always @(posedge clock) begin
        if (clear)
            _145 <= _144;
        else
            _145 <= _6;
    end
    assign _178 = { _168,
                    _171,
                    _174,
                    _177 };
    assign _182 = host_in_valid ? vdd : gnd;
    assign _180 = _94 == _179;
    assign _183 = _180 ? _182 : gnd;
    assign _9 = _183;
    assign _188 = 1'b0;
    assign _185 = _94 == _184;
    assign _186 = _185 ? vdd : gnd;
    assign _11 = _186;
    always @(posedge clock) begin
        if (clear)
            _189 <= _188;
        else
            _189 <= _11;
    end
    assign _184 = 4'b1011;
    assign _190 = _94 == _184;
    assign _194 = _190 ? _161 : _193;
    assign _13 = _194;
    always @(posedge clock) begin
        if (clear)
            _193 <= _144;
        else
            _193 <= _13;
    end
    assign _247 = imem_data[2:2];
    assign _248 = { _247,
                    _247 };
    assign _249 = { _248,
                    _248 };
    assign _250 = { _249,
                    _249 };
    assign _251 = _244 & _250;
    assign _245 = ~ _244;
    assign _246 = _201 & _245;
    assign _252 = _246 | _251;
    assign _239 = _201[0:0];
    assign _237 = 3'b000;
    assign _238 = _203 == _237;
    assign _240 = _238 ? _211 : _239;
    assign _235 = _201[1:1];
    assign _233 = 3'b001;
    assign _234 = _203 == _233;
    assign _236 = _234 ? _211 : _235;
    assign _231 = _201[2:2];
    assign _229 = 3'b010;
    assign _230 = _203 == _229;
    assign _232 = _230 ? _211 : _231;
    assign _227 = _201[3:3];
    assign _225 = 3'b011;
    assign _226 = _203 == _225;
    assign _228 = _226 ? _211 : _227;
    assign _223 = _201[4:4];
    assign _221 = 3'b100;
    assign _222 = _203 == _221;
    assign _224 = _222 ? _211 : _223;
    assign _219 = _201[5:5];
    assign _217 = 3'b101;
    assign _218 = _203 == _217;
    assign _220 = _218 ? _211 : _219;
    assign _215 = _201[6:6];
    assign _213 = 3'b110;
    assign _214 = _203 == _213;
    assign _216 = _214 ? _211 : _215;
    assign _211 = ~ _210;
    assign _206 = _201[7:7];
    assign _204 = 3'b111;
    assign _205 = _203 == _204;
    assign _212 = _205 ? _211 : _206;
    assign _241 = { _212,
                    _216,
                    _220,
                    _224,
                    _228,
                    _232,
                    _236,
                    _240 };
    assign _242 = _202 ? _241 : _201;
    assign _198 = _94 == _197;
    assign _243 = _198 ? _242 : _201;
    assign _196 = _94 == _195;
    assign _253 = _196 ? _252 : _243;
    assign _15 = _253;
    always @(posedge clock) begin
        if (clear)
            _201 <= _144;
        else
            _201 <= _15;
    end
    assign _329 = imem_data[3:3];
    assign _330 = { _329,
                    _329 };
    assign _331 = { _330,
                    _330 };
    assign _332 = { _331,
                    _331 };
    assign _333 = _244 & _332;
    assign _244 = imem_data[11:4];
    assign _327 = ~ _244;
    assign _328 = _258 & _327;
    assign _334 = _328 | _333;
    assign _322 = _258[0:0];
    assign _321 = _203 == _237;
    assign _323 = _321 ? gnd : _322;
    assign _318 = _258[1:1];
    assign _317 = _203 == _233;
    assign _319 = _317 ? gnd : _318;
    assign _314 = _258[2:2];
    assign _313 = _203 == _229;
    assign _315 = _313 ? gnd : _314;
    assign _310 = _258[3:3];
    assign _309 = _203 == _225;
    assign _311 = _309 ? gnd : _310;
    assign _306 = _258[4:4];
    assign _305 = _203 == _221;
    assign _307 = _305 ? gnd : _306;
    assign _302 = _258[5:5];
    assign _301 = _203 == _217;
    assign _303 = _301 ? gnd : _302;
    assign _298 = _258[6:6];
    assign _297 = _203 == _213;
    assign _299 = _297 ? gnd : _298;
    assign _294 = _258[7:7];
    assign _293 = _203 == _204;
    assign _295 = _293 ? gnd : _294;
    assign _324 = { _295,
                    _299,
                    _303,
                    _307,
                    _311,
                    _315,
                    _319,
                    _323 };
    assign _289 = _258[0:0];
    assign _288 = _203 == _237;
    assign _290 = _288 ? _210 : _289;
    assign _285 = _258[1:1];
    assign _284 = _203 == _233;
    assign _286 = _284 ? _210 : _285;
    assign _281 = _258[2:2];
    assign _280 = _203 == _229;
    assign _282 = _280 ? _210 : _281;
    assign _277 = _258[3:3];
    assign _276 = _203 == _225;
    assign _278 = _276 ? _210 : _277;
    assign _273 = _258[4:4];
    assign _272 = _203 == _221;
    assign _274 = _272 ? _210 : _273;
    assign _269 = _258[5:5];
    assign _268 = _203 == _217;
    assign _270 = _268 ? _210 : _269;
    assign _265 = _258[6:6];
    assign _264 = _203 == _213;
    assign _266 = _264 ? _210 : _265;
    assign _209 = _161[7:7];
    assign _208 = _161[0:0];
    assign _210 = _207 ? _209 : _208;
    assign _261 = _258[7:7];
    assign _260 = _203 == _204;
    assign _262 = _260 ? _210 : _261;
    assign _291 = { _262,
                    _266,
                    _270,
                    _274,
                    _278,
                    _282,
                    _286,
                    _290 };
    assign _202 = imem_data[7:7];
    assign _325 = _202 ? _324 : _291;
    assign _255 = _94 == _197;
    assign _326 = _255 ? _325 : _258;
    assign _195 = 4'b0001;
    assign _254 = _94 == _195;
    assign _335 = _254 ? _334 : _326;
    assign _17 = _335;
    always @(posedge clock) begin
        if (clear)
            _258 <= _144;
        else
            _258 <= _17;
    end
    assign _176 = 6'b000000;
    assign _764 = _733 ? _734 : _709;
    assign _763 = _656 == _207;
    assign _765 = _763 ? _711 : _764;
    assign _759 = 12'b000000000000;
    assign _760 = _391 == _759;
    assign _761 = _760 ? _711 : _709;
    assign _341 = _337 ? _22 : _340;
    assign _19 = _341;
    always @(posedge clock) begin
        if (clear)
            _340 <= _759;
        else
            _340 <= _19;
    end
    assign _347 = _343 ? _22 : _346;
    assign _20 = _347;
    always @(posedge clock) begin
        if (clear)
            _346 <= _759;
        else
            _346 <= _20;
    end
    assign _353 = _349 ? _22 : _352;
    assign _21 = _353;
    always @(posedge clock) begin
        if (clear)
            _352 <= _759;
        else
            _352 <= _21;
    end
    assign _366 = 12'b000000000001;
    assign _367 = _362 - _366;
    assign _364 = _362 - _366;
    assign _358 = _94 == _357;
    assign _365 = _358 ? _364 : _362;
    assign _356 = _94 == _197;
    assign _368 = _356 ? _367 : _365;
    assign _354 = 4'b0010;
    assign _355 = _94 == _354;
    assign _370 = _355 ? _369 : _368;
    assign _22 = _370;
    assign _373 = _372 ? _22 : _361;
    assign _23 = _373;
    always @(posedge clock) begin
        if (clear)
            _361 <= _759;
        else
            _361 <= _23;
    end
    always @* begin
        case (_148)
        0:
            _362 <= _361;
        1:
            _362 <= _352;
        2:
            _362 <= _346;
        default:
            _362 <= _340;
        endcase
    end
    assign _754 = _362 == _759;
    assign _755 = ~ _754;
    assign _756 = _755 ? _734 : _711;
    assign _751 = host_in_valid ? _711 : _709;
    assign _745 = _733 ? _734 : _709;
    assign _746 = _105 ? _711 : _745;
    assign _743 = _733 ? _734 : _709;
    assign _744 = _618 ? _711 : _743;
    assign _747 = _99 ? _746 : _744;
    assign _740 = _733 ? _734 : _709;
    assign _124 = port_out_ready[3:3];
    assign _123 = port_out_ready[2:2];
    assign _122 = port_out_ready[1:1];
    assign _121 = port_out_ready[0:0];
    always @* begin
        case (_100)
        0:
            _125 <= _121;
        1:
            _125 <= _122;
        2:
            _125 <= _123;
        default:
            _125 <= _124;
        endcase
    end
    assign _741 = _125 ? _711 : _740;
    assign _738 = _733 ? _734 : _709;
    assign _739 = _595 ? _711 : _738;
    assign _742 = _99 ? _741 : _739;
    assign _748 = _98 ? _747 : _742;
    assign _734 = imem_data[5:0];
    assign _377 = _337 ? _28 : _376;
    assign _25 = _377;
    always @(posedge clock) begin
        if (clear)
            _376 <= _759;
        else
            _376 <= _25;
    end
    assign _381 = _343 ? _28 : _380;
    assign _26 = _381;
    always @(posedge clock) begin
        if (clear)
            _380 <= _759;
        else
            _380 <= _26;
    end
    assign _385 = _349 ? _28 : _384;
    assign _27 = _385;
    always @(posedge clock) begin
        if (clear)
            _384 <= _759;
        else
            _384 <= _27;
    end
    assign _369 = imem_data[11:0];
    assign _395 = _391 - _366;
    assign _393 = _391 == _759;
    assign _396 = _393 ? _391 : _395;
    assign _386 = 4'b0011;
    assign _387 = _94 == _386;
    assign _397 = _387 ? _369 : _396;
    assign _28 = _397;
    assign _398 = _372 ? _28 : _390;
    assign _29 = _398;
    always @(posedge clock) begin
        if (clear)
            _390 <= _759;
        else
            _390 <= _29;
    end
    always @* begin
        case (_148)
        0:
            _391 <= _390;
        1:
            _391 <= _384;
        2:
            _391 <= _380;
        default:
            _391 <= _376;
        endcase
    end
    assign _733 = _391 == _759;
    assign _735 = _733 ? _734 : _709;
    assign _730 = imem_data[11:11];
    assign _728 = flags[3:3];
    assign _727 = flags[2:2];
    assign _726 = flags[1:1];
    assign _725 = flags[0:0];
    assign _724 = _589[3:3];
    assign _723 = _589[2:2];
    assign _722 = _589[1:1];
    assign _721 = _589[0:0];
    assign _720 = _161[7:7];
    assign _719 = _161[6:6];
    assign _718 = _161[5:5];
    assign _717 = _161[4:4];
    assign _716 = _161[3:3];
    assign _715 = _161[2:2];
    assign _714 = _161[1:1];
    assign _399 = _337 ? _68 : _160;
    assign _31 = _399;
    always @(posedge clock) begin
        if (clear)
            _160 <= _144;
        else
            _160 <= _31;
    end
    assign _400 = _343 ? _68 : _157;
    assign _32 = _400;
    always @(posedge clock) begin
        if (clear)
            _157 <= _144;
        else
            _157 <= _32;
    end
    assign _401 = _349 ? _68 : _154;
    assign _33 = _401;
    always @(posedge clock) begin
        if (clear)
            _154 <= _144;
        else
            _154 <= _33;
    end
    assign _689 = imem_data[7:0];
    assign _684 = 7'b0000000;
    assign _685 = { _684,
                    _677 };
    assign _681 = _161[6:0];
    assign _683 = { _681,
                    _188 };
    assign _686 = _683 | _685;
    assign _675 = pin_in[7:7];
    assign _674 = pin_in[6:6];
    assign _673 = pin_in[5:5];
    assign _672 = pin_in[4:4];
    assign _671 = pin_in[3:3];
    assign _670 = pin_in[2:2];
    assign _669 = pin_in[1:1];
    assign _668 = pin_in[0:0];
    assign _667 = imem_data[5:3];
    always @* begin
        case (_667)
        0:
            _676 <= _668;
        1:
            _676 <= _669;
        2:
            _676 <= _670;
        3:
            _676 <= _671;
        4:
            _676 <= _672;
        5:
            _676 <= _673;
        6:
            _676 <= _674;
        default:
            _676 <= _675;
        endcase
    end
    assign _666 = imem_data[6:6];
    assign _677 = _666 & _676;
    assign _679 = { _677,
                    _684 };
    assign _664 = _161[7:1];
    assign _665 = { _188,
                    _664 };
    assign _680 = _665 | _679;
    assign _687 = _207 ? _686 : _680;
    assign _659 = _161[6:0];
    assign _660 = { _659,
                    _656 };
    assign _657 = _161[7:1];
    assign _655 = pin_in[7:7];
    assign _654 = pin_in[6:6];
    assign _653 = pin_in[5:5];
    assign _652 = pin_in[4:4];
    assign _651 = pin_in[3:3];
    assign _650 = pin_in[2:2];
    assign _649 = pin_in[1:1];
    assign _648 = pin_in[0:0];
    assign _203 = imem_data[11:9];
    always @* begin
        case (_203)
        0:
            _656 <= _648;
        1:
            _656 <= _649;
        2:
            _656 <= _650;
        3:
            _656 <= _651;
        4:
            _656 <= _652;
        5:
            _656 <= _653;
        6:
            _656 <= _654;
        default:
            _656 <= _655;
        endcase
    end
    assign _658 = { _656,
                    _657 };
    assign _207 = imem_data[8:8];
    assign _661 = _207 ? _660 : _658;
    assign _646 = host_in_valid ? host_in : _161;
    always @* begin
        case (_100)
        0:
            _641 <= port_in0;
        1:
            _641 <= port_in1;
        2:
            _641 <= port_in2;
        default:
            _641 <= port_in3;
        endcase
    end
    assign _104 = port_in_valid[3:3];
    assign _103 = port_in_valid[2:2];
    assign _102 = port_in_valid[1:1];
    assign _101 = port_in_valid[0:0];
    always @* begin
        case (_100)
        0:
            _105 <= _101;
        1:
            _105 <= _102;
        2:
            _105 <= _103;
        default:
            _105 <= _104;
        endcase
    end
    assign _642 = _105 ? _641 : _161;
    assign _414 = _412 == _106;
    assign _415 = _414 ? _161 : _407;
    assign _416 = _404 ? _415 : _407;
    assign _42 = _416;
    always @(posedge clock) begin
        if (clear)
            _407 <= _144;
        else
            _407 <= _42;
    end
    assign _421 = _412 == _108;
    assign _422 = _421 ? _161 : _419;
    assign _423 = _404 ? _422 : _419;
    assign _43 = _423;
    always @(posedge clock) begin
        if (clear)
            _419 <= _144;
        else
            _419 <= _43;
    end
    assign _428 = _412 == _110;
    assign _429 = _428 ? _161 : _426;
    assign _430 = _404 ? _429 : _426;
    assign _44 = _430;
    always @(posedge clock) begin
        if (clear)
            _426 <= _144;
        else
            _426 <= _44;
    end
    assign _411 = _83[1:0];
    assign _412 = _410 + _411;
    assign _435 = _412 == _112;
    assign _436 = _435 ? _161 : _433;
    assign _437 = _404 ? _436 : _433;
    assign _45 = _437;
    always @(posedge clock) begin
        if (clear)
            _433 <= _144;
        else
            _433 <= _45;
    end
    assign _440 = _410 + _110;
    assign _441 = _438 ? _440 : _410;
    assign _46 = _441;
    always @(posedge clock) begin
        if (clear)
            _410 <= _112;
        else
            _410 <= _46;
    end
    always @* begin
        case (_410)
        0:
            _638 <= _433;
        1:
            _638 <= _426;
        2:
            _638 <= _419;
        default:
            _638 <= _407;
        endcase
    end
    assign _454 = _452 == _106;
    assign _455 = _454 ? _161 : _447;
    assign _456 = _444 ? _455 : _447;
    assign _47 = _456;
    always @(posedge clock) begin
        if (clear)
            _447 <= _144;
        else
            _447 <= _47;
    end
    assign _461 = _452 == _108;
    assign _462 = _461 ? _161 : _459;
    assign _463 = _444 ? _462 : _459;
    assign _48 = _463;
    always @(posedge clock) begin
        if (clear)
            _459 <= _144;
        else
            _459 <= _48;
    end
    assign _468 = _452 == _110;
    assign _469 = _468 ? _161 : _466;
    assign _470 = _444 ? _469 : _466;
    assign _49 = _470;
    always @(posedge clock) begin
        if (clear)
            _466 <= _144;
        else
            _466 <= _49;
    end
    assign _451 = _86[1:0];
    assign _452 = _450 + _451;
    assign _475 = _452 == _112;
    assign _476 = _475 ? _161 : _473;
    assign _477 = _444 ? _476 : _473;
    assign _50 = _477;
    always @(posedge clock) begin
        if (clear)
            _473 <= _144;
        else
            _473 <= _50;
    end
    assign _480 = _450 + _110;
    assign _481 = _478 ? _480 : _450;
    assign _51 = _481;
    always @(posedge clock) begin
        if (clear)
            _450 <= _112;
        else
            _450 <= _51;
    end
    always @* begin
        case (_450)
        0:
            _637 <= _473;
        1:
            _637 <= _466;
        2:
            _637 <= _459;
        default:
            _637 <= _447;
        endcase
    end
    assign _494 = _492 == _106;
    assign _495 = _494 ? _161 : _487;
    assign _496 = _484 ? _495 : _487;
    assign _52 = _496;
    always @(posedge clock) begin
        if (clear)
            _487 <= _144;
        else
            _487 <= _52;
    end
    assign _501 = _492 == _108;
    assign _502 = _501 ? _161 : _499;
    assign _503 = _484 ? _502 : _499;
    assign _53 = _503;
    always @(posedge clock) begin
        if (clear)
            _499 <= _144;
        else
            _499 <= _53;
    end
    assign _508 = _492 == _110;
    assign _509 = _508 ? _161 : _506;
    assign _510 = _484 ? _509 : _506;
    assign _54 = _510;
    always @(posedge clock) begin
        if (clear)
            _506 <= _144;
        else
            _506 <= _54;
    end
    assign _491 = _89[1:0];
    assign _492 = _490 + _491;
    assign _515 = _492 == _112;
    assign _516 = _515 ? _161 : _513;
    assign _517 = _484 ? _516 : _513;
    assign _55 = _517;
    always @(posedge clock) begin
        if (clear)
            _513 <= _144;
        else
            _513 <= _55;
    end
    assign _520 = _490 + _110;
    assign _521 = _518 ? _520 : _490;
    assign _56 = _521;
    always @(posedge clock) begin
        if (clear)
            _490 <= _112;
        else
            _490 <= _56;
    end
    always @* begin
        case (_490)
        0:
            _636 <= _513;
        1:
            _636 <= _506;
        2:
            _636 <= _499;
        default:
            _636 <= _487;
        endcase
    end
    assign _534 = _532 == _106;
    assign _535 = _534 ? _161 : _527;
    assign _536 = _524 ? _535 : _527;
    assign _57 = _536;
    always @(posedge clock) begin
        if (clear)
            _527 <= _144;
        else
            _527 <= _57;
    end
    assign _541 = _532 == _108;
    assign _542 = _541 ? _161 : _539;
    assign _543 = _524 ? _542 : _539;
    assign _58 = _543;
    always @(posedge clock) begin
        if (clear)
            _539 <= _144;
        else
            _539 <= _58;
    end
    assign _548 = _532 == _110;
    assign _549 = _548 ? _161 : _546;
    assign _550 = _524 ? _549 : _546;
    assign _59 = _550;
    always @(posedge clock) begin
        if (clear)
            _546 <= _144;
        else
            _546 <= _59;
    end
    assign _531 = _92[1:0];
    assign _532 = _530 + _531;
    assign _555 = _532 == _112;
    assign _556 = _555 ? _161 : _553;
    assign _557 = _524 ? _556 : _553;
    assign _60 = _557;
    always @(posedge clock) begin
        if (clear)
            _553 <= _144;
        else
            _553 <= _60;
    end
    assign _560 = _530 + _110;
    assign _561 = _558 ? _560 : _530;
    assign _61 = _561;
    always @(posedge clock) begin
        if (clear)
            _530 <= _112;
        else
            _530 <= _61;
    end
    always @* begin
        case (_530)
        0:
            _635 <= _553;
        1:
            _635 <= _546;
        2:
            _635 <= _539;
        default:
            _635 <= _527;
        endcase
    end
    always @* begin
        case (_100)
        0:
            _639 <= _635;
        1:
            _639 <= _636;
        2:
            _639 <= _637;
        default:
            _639 <= _638;
        endcase
    end
    assign _617 = _613[3:3];
    assign _616 = _613[2:2];
    assign _615 = _613[1:1];
    assign _611 = _92 == _237;
    assign _612 = ~ _611;
    assign _608 = _89 == _237;
    assign _609 = ~ _608;
    assign _605 = _86 == _237;
    assign _606 = ~ _605;
    assign _627 = _83 - _233;
    assign _624 = _83 + _233;
    assign _593 = _589[3:3];
    assign _592 = _589[2:2];
    assign _591 = _589[1:1];
    assign _566 = _92 - _233;
    assign _563 = _92 + _233;
    assign _524 = _65 & _523;
    assign _564 = _524 ? _563 : _92;
    assign _523 = _100 == _112;
    assign _558 = _66 & _523;
    assign _567 = _558 ? _566 : _564;
    assign _62 = _567;
    always @(posedge clock) begin
        if (clear)
            _92 <= _237;
        else
            _92 <= _62;
    end
    assign _588 = _92 == _221;
    assign _572 = _89 - _233;
    assign _569 = _89 + _233;
    assign _484 = _65 & _483;
    assign _570 = _484 ? _569 : _89;
    assign _483 = _100 == _110;
    assign _518 = _66 & _483;
    assign _573 = _518 ? _572 : _570;
    assign _63 = _573;
    always @(posedge clock) begin
        if (clear)
            _89 <= _237;
        else
            _89 <= _63;
    end
    assign _586 = _89 == _221;
    assign _578 = _86 - _233;
    assign _575 = _86 + _233;
    assign _444 = _65 & _443;
    assign _576 = _444 ? _575 : _86;
    assign _443 = _100 == _108;
    assign _478 = _66 & _443;
    assign _579 = _478 ? _578 : _576;
    assign _64 = _579;
    always @(posedge clock) begin
        if (clear)
            _86 <= _237;
        else
            _86 <= _64;
    end
    assign _584 = _86 == _221;
    assign _582 = _83 == _221;
    assign _589 = { _582,
                    _584,
                    _586,
                    _588 };
    assign _590 = _589[0:0];
    always @* begin
        case (_100)
        0:
            _594 <= _590;
        1:
            _594 <= _591;
        2:
            _594 <= _592;
        default:
            _594 <= _593;
        endcase
    end
    assign _595 = ~ _594;
    assign _596 = _595 ? vdd : gnd;
    assign _597 = _99 ? gnd : _596;
    assign _598 = _98 ? gnd : _597;
    assign _580 = _94 == _95;
    assign _599 = _580 ? _598 : gnd;
    assign _65 = _599;
    assign _404 = _65 & _403;
    assign _625 = _404 ? _624 : _83;
    assign _403 = _100 == _106;
    assign _619 = _618 ? vdd : gnd;
    assign _620 = _99 ? gnd : _619;
    assign _621 = _98 ? _620 : gnd;
    assign gnd = 1'b0;
    assign _600 = _94 == _95;
    assign _622 = _600 ? _621 : gnd;
    assign _66 = _622;
    assign _438 = _66 & _403;
    assign _628 = _438 ? _627 : _625;
    assign _67 = _628;
    always @(posedge clock) begin
        if (clear)
            _83 <= _237;
        else
            _83 <= _67;
    end
    assign _602 = _83 == _237;
    assign _603 = ~ _602;
    assign _613 = { _603,
                    _606,
                    _609,
                    _612 };
    assign _614 = _613[0:0];
    assign _100 = imem_data[9:8];
    always @* begin
        case (_100)
        0:
            _618 <= _614;
        1:
            _618 <= _615;
        2:
            _618 <= _616;
        default:
            _618 <= _617;
        endcase
    end
    assign _640 = _618 ? _639 : _161;
    assign _99 = imem_data[10:10];
    assign _643 = _99 ? _642 : _640;
    assign _98 = imem_data[11:11];
    assign _644 = _98 ? _643 : _161;
    assign _634 = _94 == _95;
    assign _645 = _634 ? _644 : _161;
    assign _633 = _94 == _179;
    assign _647 = _633 ? _646 : _645;
    assign _357 = 4'b1000;
    assign _632 = _94 == _357;
    assign _662 = _632 ? _661 : _647;
    assign _197 = 4'b0111;
    assign _631 = _94 == _197;
    assign _688 = _631 ? _687 : _662;
    assign _629 = 4'b0100;
    assign _630 = _94 == _629;
    assign _690 = _630 ? _689 : _688;
    assign _68 = _690;
    assign _691 = _372 ? _68 : _151;
    assign _69 = _691;
    always @(posedge clock) begin
        if (clear)
            _151 <= _144;
        else
            _151 <= _69;
    end
    always @* begin
        case (_148)
        0:
            _161 <= _151;
        1:
            _161 <= _154;
        2:
            _161 <= _157;
        default:
            _161 <= _160;
        endcase
    end
    assign _713 = _161[0:0];
    assign _712 = imem_data[10:7];
    always @* begin
        case (_712)
        0:
            _729 <= _713;
        1:
            _729 <= _714;
        2:
            _729 <= _715;
        3:
            _729 <= _716;
        4:
            _729 <= _717;
        5:
            _729 <= _718;
        6:
            _729 <= _719;
        7:
            _729 <= _720;
        8:
            _729 <= _721;
        9:
            _729 <= _722;
        10:
            _729 <= _723;
        11:
            _729 <= _724;
        12:
            _729 <= _725;
        13:
            _729 <= _726;
        14:
            _729 <= _727;
        default:
            _729 <= _728;
        endcase
    end
    assign _731 = _729 == _730;
    assign _736 = _731 ? _711 : _735;
    assign _710 = 6'b000001;
    assign _337 = _148 == _106;
    assign _692 = _337 ? _74 : _168;
    assign _70 = _692;
    always @(posedge clock) begin
        if (clear)
            _168 <= _176;
        else
            _168 <= _70;
    end
    assign _343 = _148 == _108;
    assign _693 = _343 ? _74 : _171;
    assign _71 = _693;
    always @(posedge clock) begin
        if (clear)
            _171 <= _176;
        else
            _171 <= _71;
    end
    assign _349 = _148 == _110;
    assign _694 = _349 ? _74 : _174;
    assign _72 = _694;
    always @(posedge clock) begin
        if (clear)
            _174 <= _176;
        else
            _174 <= _72;
    end
    always @* begin
        case (_148)
        0:
            _709 <= _177;
        1:
            _709 <= _174;
        2:
            _709 <= _171;
        default:
            _709 <= _168;
        endcase
    end
    assign _711 = _709 + _710;
    assign _707 = 4'b1111;
    assign _708 = _94 == _707;
    assign _737 = _708 ? _736 : _711;
    assign _95 = 4'b1110;
    assign _706 = _94 == _95;
    assign _749 = _706 ? _748 : _737;
    assign _704 = 4'b1101;
    assign _705 = _94 == _704;
    assign _750 = _705 ? _709 : _749;
    assign _179 = 4'b1100;
    assign _703 = _94 == _179;
    assign _752 = _703 ? _751 : _750;
    assign _701 = 4'b1010;
    assign _702 = _94 == _701;
    assign _757 = _702 ? _756 : _752;
    assign _699 = 4'b1001;
    assign _700 = _94 == _699;
    assign _758 = _700 ? _734 : _757;
    assign _697 = 4'b0110;
    assign _698 = _94 == _697;
    assign _762 = _698 ? _761 : _758;
    assign _695 = 4'b0101;
    assign _94 = imem_data[15:12];
    assign _696 = _94 == _695;
    assign _766 = _696 ? _765 : _762;
    assign _74 = _766;
    assign _372 = _148 == _112;
    assign _767 = _372 ? _74 : _177;
    assign _75 = _767;
    always @(posedge clock) begin
        if (clear)
            _177 <= _176;
        else
            _177 <= _75;
    end
    always @* begin
        case (_771)
        0:
            _772 <= _177;
        1:
            _772 <= _174;
        2:
            _772 <= _171;
        default:
            _772 <= _168;
        endcase
    end
    assign vdd = 1'b1;
    assign _769 = _148 + _110;
    assign _78 = _769;
    always @(posedge clock) begin
        if (clear)
            _148 <= _112;
        else
            _148 <= _78;
    end
    assign _771 = _148 + _110;
    assign _773 = { _771,
                    _772 };
    assign imem_addr = _773;
    assign pin_out = _258;
    assign pin_oe = _201;
    assign host_out = _193;
    assign host_out_valid = _189;
    assign host_in_ready = _9;
    assign pcs = _178;
    assign port_out_data = _145;
    assign port_out_valid = _141;
    assign port_in_ready = _2;
    assign mb_counts = _93;

endmodule
