module deadline_sequencer_v2 (
    flags,
    port_out_ready,
    bank_rdata,
    pin_in4,
    pin_in,
    host_in,
    host_in_valid,
    port_in3,
    port_in2,
    port_in1,
    port_in0,
    port_in_valid,
    boot_pc,
    ctl_pc,
    imem_data,
    boot_page,
    ctl_page,
    clock,
    ctl_thread,
    ctl_valid,
    clear,
    imem_addr,
    pin_out,
    pin_oe,
    pin_sub,
    host_out,
    host_tag,
    host_out_valid,
    host_in_ready,
    port_out_data,
    port_out_valid,
    port_in_ready,
    bank_addr,
    bank_we,
    bank_re,
    bank_wdata,
    fine_out,
    fine_valid,
    cfg_out
);

    input [15:0] flags;
    input [3:0] port_out_ready;
    input [7:0] bank_rdata;
    input [31:0] pin_in4;
    input [7:0] pin_in;
    input [7:0] host_in;
    input host_in_valid;
    input [7:0] port_in3;
    input [7:0] port_in2;
    input [7:0] port_in1;
    input [7:0] port_in0;
    input [3:0] port_in_valid;
    input [31:0] boot_pc;
    input [7:0] ctl_pc;
    input [15:0] imem_data;
    input [7:0] boot_page;
    input [1:0] ctl_page;
    input clock;
    input [1:0] ctl_thread;
    input ctl_valid;
    input clear;
    output [9:0] imem_addr;
    output [7:0] pin_out;
    output [7:0] pin_oe;
    output [31:0] pin_sub;
    output [7:0] host_out;
    output [2:0] host_tag;
    output host_out_valid;
    output host_in_ready;
    output [7:0] port_out_data;
    output [3:0] port_out_valid;
    output [3:0] port_in_ready;
    output [9:0] bank_addr;
    output bank_we;
    output bank_re;
    output [7:0] bank_wdata;
    output [7:0] fine_out;
    output fine_valid;
    output [31:0] cfg_out;

    wire [31:0] _134;
    wire _164;
    wire _161;
    wire _159;
    wire _139;
    wire _160;
    wire _137;
    wire _162;
    wire _2;
    reg _165;
    wire [7:0] _216;
    wire [7:0] _221;
    wire _192;
    wire [7:0] _194;
    wire [7:0] _171;
    wire [7:0] _4;
    reg [7:0] _170;
    wire [7:0] _177;
    wire [7:0] _5;
    reg [7:0] _176;
    wire [7:0] _183;
    wire [7:0] _6;
    reg [7:0] _182;
    reg [7:0] _189;
    wire _185;
    wire [7:0] _195;
    wire [7:0] _7;
    wire [7:0] _198;
    wire [7:0] _8;
    reg [7:0] _188;
    reg [7:0] _218;
    wire _157;
    wire _199;
    wire _9;
    reg _155;
    wire _200;
    wire _10;
    reg _152;
    wire _201;
    wire _11;
    reg _149;
    wire _210;
    wire _208;
    wire [3:0] _191;
    wire _205;
    wire _206;
    wire _204;
    wire _207;
    wire _203;
    wire _209;
    wire _202;
    wire _211;
    wire _12;
    wire _212;
    wire _13;
    reg _146;
    reg _156;
    wire _158;
    wire [7:0] _219;
    wire _214;
    wire [7:0] _220;
    wire _213;
    wire [7:0] _222;
    wire [7:0] _14;
    reg [7:0] _217;
    wire _238;
    wire _239;
    wire _236;
    wire _240;
    wire _18;
    wire [9:0] _242;
    wire [9:0] _244;
    wire [9:0] _20;
    reg [9:0] _243;
    wire [9:0] _248;
    wire [9:0] _21;
    reg [9:0] _247;
    wire [9:0] _252;
    wire [9:0] _22;
    reg [9:0] _251;
    wire [9:0] _269;
    wire [9:0] _270;
    wire [9:0] _267;
    wire [1:0] _263;
    wire [9:0] _264;
    wire [3:0] _261;
    wire _262;
    wire [9:0] _265;
    wire [3:0] _237;
    wire _260;
    wire [9:0] _268;
    wire _259;
    wire [9:0] _271;
    wire _253;
    wire [9:0] _272;
    wire [9:0] _23;
    wire [9:0] _273;
    wire [9:0] _24;
    reg [9:0] _256;
    reg [9:0] _257;
    wire [1:0] _292;
    wire _293;
    wire [1:0] _290;
    wire _291;
    wire [1:0] _288;
    wire _289;
    wire [1:0] _286;
    wire _287;
    wire [3:0] _294;
    wire [3:0] _295;
    wire [3:0] _296;
    wire [3:0] _297;
    wire [3:0] _276;
    wire _275;
    wire [3:0] _298;
    wire [3:0] _26;
    wire _313;
    wire _311;
    wire _309;
    wire _307;
    wire [3:0] _314;
    wire [3:0] _315;
    wire [3:0] _316;
    wire [3:0] _317;
    wire _299;
    wire [3:0] _318;
    wire [3:0] _28;
    reg [3:0] _321;
    wire [7:0] _326;
    wire [7:0] _327;
    wire [7:0] _328;
    wire _322;
    wire [7:0] _329;
    wire [7:0] _30;
    reg [7:0] _325;
    wire _332;
    wire _331;
    wire _333;
    wire _32;
    wire _335;
    wire _336;
    wire _34;
    reg _339;
    wire [2:0] _342;
    wire [2:0] _344;
    wire _340;
    wire [2:0] _345;
    wire [2:0] _36;
    reg [2:0] _343;
    wire _350;
    wire [7:0] _351;
    wire [3:0] _334;
    wire _346;
    wire [7:0] _352;
    wire [7:0] _38;
    reg [7:0] _349;
    wire _528;
    wire _527;
    wire _526;
    wire _529;
    wire _523;
    wire _522;
    wire _521;
    wire _524;
    wire _518;
    wire _517;
    wire _516;
    wire _519;
    wire _513;
    wire _512;
    wire _511;
    wire _514;
    wire _508;
    wire _507;
    wire _506;
    wire _509;
    wire _503;
    wire _502;
    wire _501;
    wire _504;
    wire _498;
    wire _497;
    wire _496;
    wire _499;
    wire _493;
    wire _492;
    wire _491;
    wire _494;
    wire _488;
    wire _487;
    wire _486;
    wire _489;
    wire _483;
    wire _482;
    wire _481;
    wire _484;
    wire _478;
    wire _477;
    wire _476;
    wire _479;
    wire _473;
    wire _472;
    wire _471;
    wire _474;
    wire _468;
    wire _467;
    wire _466;
    wire _469;
    wire _463;
    wire _462;
    wire _461;
    wire _464;
    wire _458;
    wire _457;
    wire _456;
    wire _459;
    wire _453;
    wire _452;
    wire _451;
    wire _454;
    wire _448;
    wire _447;
    wire _446;
    wire _449;
    wire _443;
    wire _442;
    wire _441;
    wire _444;
    wire _438;
    wire _437;
    wire _436;
    wire _439;
    wire _433;
    wire _432;
    wire _431;
    wire _434;
    wire _428;
    wire _427;
    wire _426;
    wire _429;
    wire _423;
    wire _422;
    wire _421;
    wire _424;
    wire _418;
    wire _417;
    wire _416;
    wire _419;
    wire _413;
    wire _412;
    wire _411;
    wire _414;
    wire _408;
    wire _407;
    wire _406;
    wire _409;
    wire _403;
    wire _402;
    wire _401;
    wire _404;
    wire _398;
    wire _397;
    wire _396;
    wire _399;
    wire _393;
    wire _392;
    wire _391;
    wire _394;
    wire _388;
    wire _387;
    wire _386;
    wire _389;
    wire _383;
    wire _382;
    wire _381;
    wire _384;
    wire _378;
    wire _377;
    wire _376;
    wire _379;
    wire [7:0] _40;
    reg [7:0] _372;
    wire _373;
    wire _369;
    wire [1:0] _360;
    wire [1:0] _361;
    wire _357;
    wire [1:0] _362;
    wire _356;
    wire [1:0] _363;
    wire [1:0] _41;
    wire [1:0] _42;
    reg [1:0] _367;
    wire _368;
    wire _374;
    wire [31:0] _530;
    wire _622;
    wire [1:0] _623;
    wire [3:0] _624;
    wire [7:0] _625;
    wire [7:0] _626;
    wire [7:0] _620;
    wire [7:0] _621;
    wire [7:0] _627;
    wire [7:0] _614;
    wire [7:0] _615;
    wire [7:0] _577;
    wire [7:0] _578;
    wire [7:0] _616;
    wire [7:0] _617;
    wire _532;
    wire [7:0] _618;
    wire _531;
    wire [7:0] _628;
    wire [7:0] _44;
    wire [7:0] _45;
    reg [7:0] _535;
    wire _641;
    wire [1:0] _642;
    wire [3:0] _643;
    wire [7:0] _644;
    wire [7:0] _645;
    wire [7:0] _619;
    wire [7:0] _639;
    wire [7:0] _640;
    wire [7:0] _646;
    wire [7:0] _635;
    wire [7:0] _636;
    wire _611;
    wire _612;
    wire [2:0] _607;
    wire _608;
    wire _609;
    wire [2:0] _604;
    wire _605;
    wire _606;
    wire [2:0] _601;
    wire _602;
    wire _603;
    wire [2:0] _598;
    wire _599;
    wire _600;
    wire [2:0] _595;
    wire _596;
    wire _597;
    wire [2:0] _592;
    wire _593;
    wire _594;
    wire _588;
    wire _587;
    wire _589;
    wire _584;
    wire _583;
    wire _585;
    wire _586;
    wire _590;
    wire [2:0] _579;
    wire _580;
    wire _591;
    wire [7:0] _613;
    wire [7:0] _633;
    wire _573;
    wire _571;
    wire _569;
    wire _567;
    wire _565;
    wire _563;
    wire _561;
    wire [2:0] _557;
    wire _559;
    wire [7:0] _574;
    wire [7:0] _575;
    wire _552;
    wire _550;
    wire _548;
    wire _546;
    wire _544;
    wire _542;
    wire _540;
    wire _538;
    wire [7:0] _553;
    wire [7:0] _576;
    wire [7:0] _631;
    wire [7:0] _632;
    wire [7:0] _634;
    wire _359;
    wire [7:0] _637;
    wire _630;
    wire [7:0] _638;
    wire [3:0] _136;
    wire _629;
    wire [7:0] _647;
    wire [7:0] _47;
    wire [7:0] _48;
    reg [7:0] _355;
    wire [7:0] _1131;
    wire [1:0] _1130;
    wire [9:0] _1132;
    wire [7:0] _1093;
    wire [7:0] _1085;
    wire _1084;
    wire [7:0] _1086;
    wire [11:0] _1080;
    wire _1081;
    wire [7:0] _1082;
    wire _1075;
    wire _1076;
    wire [7:0] _1077;
    wire [7:0] _1072;
    wire [7:0] _1067;
    wire [7:0] _1068;
    wire [7:0] _1065;
    wire [7:0] _1066;
    wire [7:0] _1069;
    wire [7:0] _1062;
    wire _304;
    wire _303;
    wire _302;
    wire _301;
    reg _305;
    wire [7:0] _1063;
    wire [7:0] _1060;
    wire [7:0] _1061;
    wire [7:0] _1064;
    wire [7:0] _1070;
    wire [7:0] _1056;
    wire [11:0] _651;
    wire [11:0] _50;
    reg [11:0] _650;
    wire [11:0] _655;
    wire [11:0] _51;
    reg [11:0] _654;
    wire [11:0] _659;
    wire [11:0] _52;
    reg [11:0] _658;
    wire [11:0] _668;
    wire [11:0] _669;
    wire _667;
    wire [11:0] _670;
    wire [3:0] _660;
    wire _661;
    wire [11:0] _672;
    wire [11:0] _53;
    wire [11:0] _673;
    wire [11:0] _54;
    reg [11:0] _664;
    reg [11:0] _665;
    wire _1055;
    wire [7:0] _1057;
    wire _1052;
    wire _1051;
    wire _1050;
    wire [3:0] _1047;
    wire [3:0] _1046;
    wire [3:0] _1045;
    wire [3:0] _1044;
    reg [3:0] _1048;
    wire _1049;
    wire _1041;
    wire _1040;
    wire _1039;
    wire _1038;
    wire [1:0] _1037;
    reg _1042;
    wire _1034;
    wire _1033;
    wire _1032;
    wire _1031;
    wire [1:0] _1030;
    reg _1035;
    wire _1036;
    wire [2:0] _677;
    wire [2:0] _57;
    reg [2:0] _676;
    wire [2:0] _681;
    wire [2:0] _58;
    reg [2:0] _680;
    wire [2:0] _685;
    wire [2:0] _59;
    reg [2:0] _684;
    wire [2:0] _691;
    wire _686;
    wire [2:0] _692;
    wire [2:0] _60;
    wire [2:0] _693;
    wire [2:0] _61;
    reg [2:0] _689;
    reg [2:0] _690;
    wire _1029;
    wire _1043;
    wire _1027;
    wire _1026;
    wire _1025;
    wire _1024;
    reg _1028;
    wire [11:0] _697;
    wire [11:0] _62;
    reg [11:0] _696;
    wire [11:0] _701;
    wire [11:0] _63;
    reg [11:0] _700;
    wire [11:0] _705;
    wire [11:0] _64;
    reg [11:0] _704;
    wire [11:0] _671;
    wire [11:0] _726;
    wire [11:0] _723;
    wire [11:0] _719;
    wire _717;
    wire [11:0] _720;
    wire _711;
    wire [11:0] _721;
    wire _710;
    wire [11:0] _724;
    wire _708;
    wire [11:0] _727;
    wire _707;
    wire [11:0] _728;
    wire [11:0] _65;
    wire [11:0] _729;
    wire [11:0] _66;
    reg [11:0] _714;
    reg [11:0] _715;
    wire [2:0] _1021;
    wire _1023;
    wire _1020;
    wire _1019;
    wire _1018;
    wire _1017;
    wire _1016;
    wire _1015;
    wire _1014;
    wire _1013;
    wire [3:0] _1012;
    reg _1053;
    wire [7:0] _1058;
    wire _1007;
    wire _1008;
    wire [7:0] _1009;
    wire [7:0] _1003;
    wire [7:0] _1004;
    wire [7:0] _739;
    wire _737;
    wire _738;
    wire [7:0] _740;
    wire [7:0] _67;
    reg [7:0] _234;
    wire [7:0] _744;
    wire _742;
    wire _743;
    wire [7:0] _745;
    wire [7:0] _68;
    reg [7:0] _231;
    wire [7:0] _749;
    wire _747;
    wire _748;
    wire [7:0] _750;
    wire [7:0] _69;
    reg [7:0] _228;
    wire [5:0] _931;
    wire [7:0] _933;
    wire [6:0] _929;
    wire [7:0] _930;
    wire [7:0] _934;
    wire [5:0] _926;
    wire [7:0] _927;
    wire [6:0] _923;
    wire _920;
    wire _919;
    wire _918;
    wire _917;
    wire _916;
    wire _915;
    wire _914;
    wire _913;
    wire [2:0] _912;
    reg _921;
    wire _910;
    wire _922;
    wire [7:0] _924;
    wire _581;
    wire _554;
    wire _909;
    wire [7:0] _928;
    wire [7:0] _935;
    wire _903;
    wire _902;
    wire _901;
    wire _900;
    wire [3:0] _904;
    wire [3:0] _899;
    wire [7:0] _905;
    wire [3:0] _897;
    wire [3:0] _895;
    wire [3:0] _894;
    wire [3:0] _893;
    wire [3:0] _892;
    wire [3:0] _891;
    wire [3:0] _890;
    wire [3:0] _889;
    wire [3:0] _888;
    reg [3:0] _896;
    wire [7:0] _898;
    wire [7:0] _906;
    wire [6:0] _885;
    wire [7:0] _886;
    wire [6:0] _883;
    wire _881;
    wire _880;
    wire _879;
    wire _878;
    wire _877;
    wire _876;
    wire _875;
    wire _752;
    wire [7:0] _756;
    wire [7:0] _72;
    reg [7:0] _755;
    wire _871;
    wire [7:0] _872;
    wire [7:0] _757;
    wire [7:0] _74;
    reg [7:0] _124;
    wire [7:0] _758;
    wire [7:0] _75;
    reg [7:0] _127;
    wire [7:0] _759;
    wire [7:0] _76;
    reg [7:0] _130;
    wire [7:0] _193;
    wire [3:0] _762;
    wire _763;
    wire [7:0] _764;
    wire _760;
    wire [7:0] _765;
    wire [7:0] _77;
    wire [7:0] _766;
    wire [7:0] _78;
    reg [7:0] _133;
    reg [7:0] _761;
    wire _869;
    wire [7:0] _873;
    wire _874;
    wire [2:0] _536;
    reg _882;
    wire [7:0] _884;
    wire _582;
    wire [7:0] _887;
    wire _868;
    wire [7:0] _907;
    wire [7:0] _866;
    reg [7:0] _861;
    wire _284;
    wire _283;
    wire _282;
    wire _281;
    wire [1:0] _280;
    reg _285;
    wire [7:0] _862;
    wire [7:0] _774;
    wire [7:0] _86;
    reg [7:0] _773;
    wire [7:0] _782;
    wire [7:0] _87;
    reg [7:0] _781;
    wire [7:0] _790;
    wire [7:0] _88;
    reg [7:0] _789;
    wire [7:0] _798;
    wire [7:0] _89;
    reg [7:0] _797;
    wire [1:0] _858;
    reg [7:0] _859;
    wire _835;
    wire _834;
    wire _833;
    wire [1:0] _791;
    wire _793;
    wire _794;
    wire _806;
    wire [1:0] _799;
    wire _801;
    wire _802;
    wire _807;
    wire _90;
    reg _805;
    wire [1:0] _783;
    wire _785;
    wire _786;
    wire _815;
    wire [1:0] _808;
    wire _810;
    wire _811;
    wire _816;
    wire _91;
    reg _814;
    wire [1:0] _775;
    wire _777;
    wire _778;
    wire _824;
    wire [1:0] _817;
    wire _819;
    wire _820;
    wire _825;
    wire _92;
    reg _823;
    wire [1:0] _767;
    wire _769;
    wire _837;
    wire _838;
    wire _839;
    wire _826;
    wire _840;
    wire _93;
    wire _770;
    wire _850;
    wire [1:0] _846;
    wire _848;
    wire _842;
    wire _843;
    wire _844;
    wire _841;
    wire _845;
    wire _94;
    wire _849;
    wire _851;
    wire _95;
    reg _830;
    wire [3:0] _831;
    wire _832;
    wire [1:0] _827;
    reg _836;
    wire [7:0] _860;
    wire [2:0] _278;
    wire _279;
    wire [7:0] _863;
    wire _277;
    wire [7:0] _864;
    wire _857;
    wire [7:0] _865;
    wire _856;
    wire [7:0] _867;
    wire [3:0] _709;
    wire _855;
    wire [7:0] _908;
    wire _854;
    wire [7:0] _936;
    wire [3:0] _852;
    wire _853;
    wire [7:0] _937;
    wire [7:0] _96;
    wire [7:0] _947;
    wire [1:0] _938;
    wire [1:0] _97;
    reg [1:0] _735;
    wire _945;
    wire _940;
    wire _941;
    wire gnd;
    wire _939;
    wire _942;
    wire _98;
    wire _943;
    wire _99;
    reg _732;
    wire _946;
    wire [7:0] _948;
    wire [7:0] _100;
    reg [7:0] _225;
    reg [7:0] _235;
    wire _1002;
    wire [7:0] _1005;
    wire _1001;
    wire [7:0] _1006;
    wire [3:0] _190;
    wire _999;
    wire [7:0] _1010;
    wire [7:0] _996;
    wire [7:0] _957;
    wire _167;
    wire [7:0] _955;
    wire [7:0] _956;
    wire [7:0] _958;
    wire [7:0] _101;
    reg [7:0] _954;
    wire [7:0] _967;
    wire _173;
    wire [7:0] _965;
    wire [7:0] _966;
    wire [7:0] _968;
    wire [7:0] _102;
    reg [7:0] _964;
    wire [7:0] _977;
    wire _179;
    wire [7:0] _975;
    wire [7:0] _976;
    wire [7:0] _978;
    wire [7:0] _105;
    reg [7:0] _974;
    reg [7:0] _995;
    wire [7:0] _997;
    wire [3:0] _184;
    wire _991;
    wire [7:0] _1011;
    wire [3:0] _989;
    wire _990;
    wire [7:0] _1059;
    wire [3:0] _274;
    wire _988;
    wire [7:0] _1071;
    wire [3:0] _330;
    wire _987;
    wire [7:0] _1073;
    wire [3:0] _985;
    wire _986;
    wire [7:0] _1078;
    wire [3:0] _983;
    wire _984;
    wire [7:0] _1079;
    wire _982;
    wire [7:0] _1083;
    wire [3:0] _135;
    wire _980;
    wire [7:0] _1087;
    wire [7:0] _107;
    wire _197;
    wire [7:0] _1091;
    wire [7:0] _1092;
    wire [7:0] _1094;
    wire [7:0] _108;
    reg [7:0] _994;
    reg [7:0] _1127;
    wire [7:0] _1128;
    wire [1:0] _1099;
    wire _950;
    wire _951;
    wire [1:0] _1098;
    wire [1:0] _1100;
    wire [1:0] _109;
    reg [1:0] _1097;
    wire [1:0] _1105;
    wire _960;
    wire _961;
    wire [1:0] _1104;
    wire [1:0] _1106;
    wire [1:0] _110;
    reg [1:0] _1103;
    wire [1:0] _1111;
    wire _970;
    wire _971;
    wire [1:0] _1110;
    wire [1:0] _1112;
    wire [1:0] _111;
    reg [1:0] _1109;
    wire [1:0] _1117;
    wire _1089;
    wire _1090;
    wire [1:0] _1116;
    wire [1:0] _1118;
    wire [1:0] _114;
    reg [1:0] _1115;
    reg [1:0] _1125;
    wire vdd;
    wire [1:0] _1120;
    wire [1:0] _116;
    reg [1:0] _143;
    wire [1:0] _1122;
    wire _1123;
    wire _1124;
    wire [1:0] _1126;
    wire [9:0] _1129;
    wire [9:0] _1133;
    assign _134 = { _124,
                    _127,
                    _130,
                    _133 };
    assign _164 = 1'b0;
    assign _161 = _158 ? vdd : gnd;
    assign _159 = _158 ? vdd : gnd;
    assign _139 = _135 == _762;
    assign _160 = _139 ? _159 : gnd;
    assign _137 = _135 == _136;
    assign _162 = _137 ? _161 : _160;
    assign _2 = _162;
    always @(posedge clock) begin
        if (clear)
            _165 <= _164;
        else
            _165 <= _2;
    end
    assign _216 = 8'b00000000;
    assign _221 = _158 ? _218 : _217;
    assign _192 = _190 == _191;
    assign _194 = _192 ? _193 : _189;
    assign _171 = _167 ? _7 : _170;
    assign _4 = _171;
    always @(posedge clock) begin
        if (clear)
            _170 <= _216;
        else
            _170 <= _4;
    end
    assign _177 = _173 ? _7 : _176;
    assign _5 = _177;
    always @(posedge clock) begin
        if (clear)
            _176 <= _216;
        else
            _176 <= _5;
    end
    assign _183 = _179 ? _7 : _182;
    assign _6 = _183;
    always @(posedge clock) begin
        if (clear)
            _182 <= _216;
        else
            _182 <= _6;
    end
    always @* begin
        case (_143)
        0:
            _189 <= _188;
        1:
            _189 <= _182;
        2:
            _189 <= _176;
        default:
            _189 <= _170;
        endcase
    end
    assign _185 = _135 == _184;
    assign _195 = _185 ? _194 : _189;
    assign _7 = _195;
    assign _198 = _197 ? _7 : _188;
    assign _8 = _198;
    always @(posedge clock) begin
        if (clear)
            _188 <= _216;
        else
            _188 <= _8;
    end
    always @* begin
        case (_143)
        0:
            _218 <= _188;
        1:
            _218 <= _182;
        2:
            _218 <= _176;
        default:
            _218 <= _170;
        endcase
    end
    assign _157 = 1'b1;
    assign _199 = _167 ? _12 : _155;
    assign _9 = _199;
    always @(posedge clock) begin
        if (clear)
            _155 <= _164;
        else
            _155 <= _9;
    end
    assign _200 = _173 ? _12 : _152;
    assign _10 = _200;
    always @(posedge clock) begin
        if (clear)
            _152 <= _164;
        else
            _152 <= _10;
    end
    assign _201 = _179 ? _12 : _149;
    assign _11 = _201;
    always @(posedge clock) begin
        if (clear)
            _149 <= _164;
        else
            _149 <= _11;
    end
    assign _210 = _158 ? gnd : _156;
    assign _208 = _158 ? gnd : _156;
    assign _191 = 4'b0010;
    assign _205 = _190 == _191;
    assign _206 = _205 ? vdd : _156;
    assign _204 = _135 == _184;
    assign _207 = _204 ? _206 : _156;
    assign _203 = _135 == _762;
    assign _209 = _203 ? _208 : _207;
    assign _202 = _135 == _136;
    assign _211 = _202 ? _210 : _209;
    assign _12 = _211;
    assign _212 = _197 ? _12 : _146;
    assign _13 = _212;
    always @(posedge clock) begin
        if (clear)
            _146 <= _164;
        else
            _146 <= _13;
    end
    always @* begin
        case (_143)
        0:
            _156 <= _146;
        1:
            _156 <= _149;
        2:
            _156 <= _152;
        default:
            _156 <= _155;
        endcase
    end
    assign _158 = _156 == _157;
    assign _219 = _158 ? _218 : _217;
    assign _214 = _135 == _762;
    assign _220 = _214 ? _219 : _217;
    assign _213 = _135 == _136;
    assign _222 = _213 ? _221 : _220;
    assign _14 = _222;
    always @(posedge clock) begin
        if (clear)
            _217 <= _216;
        else
            _217 <= _14;
    end
    assign _238 = _190 == _237;
    assign _239 = _238 ? vdd : gnd;
    assign _236 = _135 == _184;
    assign _240 = _236 ? _239 : gnd;
    assign _18 = _240;
    assign _242 = 10'b0000000000;
    assign _244 = _167 ? _23 : _243;
    assign _20 = _244;
    always @(posedge clock) begin
        if (clear)
            _243 <= _242;
        else
            _243 <= _20;
    end
    assign _248 = _173 ? _23 : _247;
    assign _21 = _248;
    always @(posedge clock) begin
        if (clear)
            _247 <= _242;
        else
            _247 <= _21;
    end
    assign _252 = _179 ? _23 : _251;
    assign _22 = _252;
    always @(posedge clock) begin
        if (clear)
            _251 <= _242;
        else
            _251 <= _22;
    end
    assign _269 = 10'b0000000001;
    assign _270 = _257 + _269;
    assign _267 = _257 + _269;
    assign _263 = _193[1:0];
    assign _264 = { _263,
                    _235 };
    assign _261 = 4'b0110;
    assign _262 = _190 == _261;
    assign _265 = _262 ? _264 : _257;
    assign _237 = 4'b0101;
    assign _260 = _190 == _237;
    assign _268 = _260 ? _267 : _265;
    assign _259 = _190 == _852;
    assign _271 = _259 ? _270 : _268;
    assign _253 = _135 == _184;
    assign _272 = _253 ? _271 : _257;
    assign _23 = _272;
    assign _273 = _197 ? _23 : _256;
    assign _24 = _273;
    always @(posedge clock) begin
        if (clear)
            _256 <= _242;
        else
            _256 <= _24;
    end
    always @* begin
        case (_143)
        0:
            _257 <= _256;
        1:
            _257 <= _251;
        2:
            _257 <= _247;
        default:
            _257 <= _243;
        endcase
    end
    assign _292 = 2'b00;
    assign _293 = _280 == _292;
    assign _290 = 2'b01;
    assign _291 = _280 == _290;
    assign _288 = 2'b10;
    assign _289 = _280 == _288;
    assign _286 = 2'b11;
    assign _287 = _280 == _286;
    assign _294 = { _287,
                    _289,
                    _291,
                    _293 };
    assign _295 = _285 ? _294 : _276;
    assign _296 = _279 ? _295 : _276;
    assign _297 = _277 ? _296 : _276;
    assign _276 = 4'b0000;
    assign _275 = _135 == _274;
    assign _298 = _275 ? _297 : _276;
    assign _26 = _298;
    assign _313 = _280 == _292;
    assign _311 = _280 == _290;
    assign _309 = _280 == _288;
    assign _307 = _280 == _286;
    assign _314 = { _307,
                    _309,
                    _311,
                    _313 };
    assign _315 = _305 ? _314 : _276;
    assign _316 = _279 ? _315 : _276;
    assign _317 = _277 ? _276 : _316;
    assign _299 = _135 == _274;
    assign _318 = _299 ? _317 : _276;
    assign _28 = _318;
    always @(posedge clock) begin
        if (clear)
            _321 <= _276;
        else
            _321 <= _28;
    end
    assign _326 = _305 ? _235 : _325;
    assign _327 = _279 ? _326 : _325;
    assign _328 = _277 ? _325 : _327;
    assign _322 = _135 == _274;
    assign _329 = _322 ? _328 : _325;
    assign _30 = _329;
    always @(posedge clock) begin
        if (clear)
            _325 <= _216;
        else
            _325 <= _30;
    end
    assign _332 = host_in_valid ? vdd : gnd;
    assign _331 = _135 == _330;
    assign _333 = _331 ? _332 : gnd;
    assign _32 = _333;
    assign _335 = _135 == _334;
    assign _336 = _335 ? vdd : gnd;
    assign _34 = _336;
    always @(posedge clock) begin
        if (clear)
            _339 <= _164;
        else
            _339 <= _34;
    end
    assign _342 = 3'b000;
    assign _344 = imem_data[10:8];
    assign _340 = _135 == _334;
    assign _345 = _340 ? _344 : _343;
    assign _36 = _345;
    always @(posedge clock) begin
        if (clear)
            _343 <= _342;
        else
            _343 <= _36;
    end
    assign _350 = imem_data[11:11];
    assign _351 = _350 ? _193 : _235;
    assign _334 = 4'b1011;
    assign _346 = _135 == _334;
    assign _352 = _346 ? _351 : _349;
    assign _38 = _352;
    always @(posedge clock) begin
        if (clear)
            _349 <= _216;
        else
            _349 <= _38;
    end
    assign _528 = _372[0:0];
    assign _527 = _355[0:0];
    assign _526 = _292 < _367;
    assign _529 = _526 ? _528 : _527;
    assign _523 = _372[0:0];
    assign _522 = _355[0:0];
    assign _521 = _290 < _367;
    assign _524 = _521 ? _523 : _522;
    assign _518 = _372[0:0];
    assign _517 = _355[0:0];
    assign _516 = _288 < _367;
    assign _519 = _516 ? _518 : _517;
    assign _513 = _372[0:0];
    assign _512 = _355[0:0];
    assign _511 = _286 < _367;
    assign _514 = _511 ? _513 : _512;
    assign _508 = _372[1:1];
    assign _507 = _355[1:1];
    assign _506 = _292 < _367;
    assign _509 = _506 ? _508 : _507;
    assign _503 = _372[1:1];
    assign _502 = _355[1:1];
    assign _501 = _290 < _367;
    assign _504 = _501 ? _503 : _502;
    assign _498 = _372[1:1];
    assign _497 = _355[1:1];
    assign _496 = _288 < _367;
    assign _499 = _496 ? _498 : _497;
    assign _493 = _372[1:1];
    assign _492 = _355[1:1];
    assign _491 = _286 < _367;
    assign _494 = _491 ? _493 : _492;
    assign _488 = _372[2:2];
    assign _487 = _355[2:2];
    assign _486 = _292 < _367;
    assign _489 = _486 ? _488 : _487;
    assign _483 = _372[2:2];
    assign _482 = _355[2:2];
    assign _481 = _290 < _367;
    assign _484 = _481 ? _483 : _482;
    assign _478 = _372[2:2];
    assign _477 = _355[2:2];
    assign _476 = _288 < _367;
    assign _479 = _476 ? _478 : _477;
    assign _473 = _372[2:2];
    assign _472 = _355[2:2];
    assign _471 = _286 < _367;
    assign _474 = _471 ? _473 : _472;
    assign _468 = _372[3:3];
    assign _467 = _355[3:3];
    assign _466 = _292 < _367;
    assign _469 = _466 ? _468 : _467;
    assign _463 = _372[3:3];
    assign _462 = _355[3:3];
    assign _461 = _290 < _367;
    assign _464 = _461 ? _463 : _462;
    assign _458 = _372[3:3];
    assign _457 = _355[3:3];
    assign _456 = _288 < _367;
    assign _459 = _456 ? _458 : _457;
    assign _453 = _372[3:3];
    assign _452 = _355[3:3];
    assign _451 = _286 < _367;
    assign _454 = _451 ? _453 : _452;
    assign _448 = _372[4:4];
    assign _447 = _355[4:4];
    assign _446 = _292 < _367;
    assign _449 = _446 ? _448 : _447;
    assign _443 = _372[4:4];
    assign _442 = _355[4:4];
    assign _441 = _290 < _367;
    assign _444 = _441 ? _443 : _442;
    assign _438 = _372[4:4];
    assign _437 = _355[4:4];
    assign _436 = _288 < _367;
    assign _439 = _436 ? _438 : _437;
    assign _433 = _372[4:4];
    assign _432 = _355[4:4];
    assign _431 = _286 < _367;
    assign _434 = _431 ? _433 : _432;
    assign _428 = _372[5:5];
    assign _427 = _355[5:5];
    assign _426 = _292 < _367;
    assign _429 = _426 ? _428 : _427;
    assign _423 = _372[5:5];
    assign _422 = _355[5:5];
    assign _421 = _290 < _367;
    assign _424 = _421 ? _423 : _422;
    assign _418 = _372[5:5];
    assign _417 = _355[5:5];
    assign _416 = _288 < _367;
    assign _419 = _416 ? _418 : _417;
    assign _413 = _372[5:5];
    assign _412 = _355[5:5];
    assign _411 = _286 < _367;
    assign _414 = _411 ? _413 : _412;
    assign _408 = _372[6:6];
    assign _407 = _355[6:6];
    assign _406 = _292 < _367;
    assign _409 = _406 ? _408 : _407;
    assign _403 = _372[6:6];
    assign _402 = _355[6:6];
    assign _401 = _290 < _367;
    assign _404 = _401 ? _403 : _402;
    assign _398 = _372[6:6];
    assign _397 = _355[6:6];
    assign _396 = _288 < _367;
    assign _399 = _396 ? _398 : _397;
    assign _393 = _372[6:6];
    assign _392 = _355[6:6];
    assign _391 = _286 < _367;
    assign _394 = _391 ? _393 : _392;
    assign _388 = _372[7:7];
    assign _387 = _355[7:7];
    assign _386 = _292 < _367;
    assign _389 = _386 ? _388 : _387;
    assign _383 = _372[7:7];
    assign _382 = _355[7:7];
    assign _381 = _290 < _367;
    assign _384 = _381 ? _383 : _382;
    assign _378 = _372[7:7];
    assign _377 = _355[7:7];
    assign _376 = _288 < _367;
    assign _379 = _376 ? _378 : _377;
    assign _40 = _355;
    always @(posedge clock) begin
        if (clear)
            _372 <= _216;
        else
            _372 <= _40;
    end
    assign _373 = _372[7:7];
    assign _369 = _355[7:7];
    assign _360 = imem_data[1:0];
    assign _361 = _359 ? _292 : _360;
    assign _357 = _135 == _762;
    assign _362 = _357 ? _361 : _292;
    assign _356 = _135 == _136;
    assign _363 = _356 ? _360 : _362;
    assign _41 = _363;
    assign _42 = _41;
    always @(posedge clock) begin
        if (clear)
            _367 <= _292;
        else
            _367 <= _42;
    end
    assign _368 = _286 < _367;
    assign _374 = _368 ? _373 : _369;
    assign _530 = { _374,
                    _379,
                    _384,
                    _389,
                    _394,
                    _399,
                    _404,
                    _409,
                    _414,
                    _419,
                    _424,
                    _429,
                    _434,
                    _439,
                    _444,
                    _449,
                    _454,
                    _459,
                    _464,
                    _469,
                    _474,
                    _479,
                    _484,
                    _489,
                    _494,
                    _499,
                    _504,
                    _509,
                    _514,
                    _519,
                    _524,
                    _529 };
    assign _622 = imem_data[2:2];
    assign _623 = { _622,
                    _622 };
    assign _624 = { _623,
                    _623 };
    assign _625 = { _624,
                    _624 };
    assign _626 = _619 & _625;
    assign _620 = ~ _619;
    assign _621 = _535 & _620;
    assign _627 = _621 | _626;
    assign _614 = ~ _613;
    assign _615 = _576 & _614;
    assign _577 = ~ _576;
    assign _578 = _535 & _577;
    assign _616 = _578 | _615;
    assign _617 = _359 ? _616 : _535;
    assign _532 = _135 == _762;
    assign _618 = _532 ? _617 : _535;
    assign _531 = _135 == _136;
    assign _628 = _531 ? _627 : _618;
    assign _44 = _628;
    assign _45 = _44;
    always @(posedge clock) begin
        if (clear)
            _535 <= _216;
        else
            _535 <= _45;
    end
    assign _641 = imem_data[3:3];
    assign _642 = { _641,
                    _641 };
    assign _643 = { _642,
                    _642 };
    assign _644 = { _643,
                    _643 };
    assign _645 = _619 & _644;
    assign _619 = imem_data[11:4];
    assign _639 = ~ _619;
    assign _640 = _355 & _639;
    assign _646 = _640 | _645;
    assign _635 = ~ _576;
    assign _636 = _355 & _635;
    assign _611 = _536 == _342;
    assign _612 = _611 ? _585 : _590;
    assign _607 = 3'b001;
    assign _608 = _536 == _607;
    assign _609 = _608 ? _585 : _590;
    assign _604 = 3'b010;
    assign _605 = _536 == _604;
    assign _606 = _605 ? _585 : _590;
    assign _601 = 3'b011;
    assign _602 = _536 == _601;
    assign _603 = _602 ? _585 : _590;
    assign _598 = 3'b100;
    assign _599 = _536 == _598;
    assign _600 = _599 ? _585 : _590;
    assign _595 = 3'b101;
    assign _596 = _536 == _595;
    assign _597 = _596 ? _585 : _590;
    assign _592 = 3'b110;
    assign _593 = _536 == _592;
    assign _594 = _593 ? _585 : _590;
    assign _588 = _235[6:6];
    assign _587 = _235[1:1];
    assign _589 = _582 ? _588 : _587;
    assign _584 = _235[7:7];
    assign _583 = _235[0:0];
    assign _585 = _582 ? _584 : _583;
    assign _586 = ~ _585;
    assign _590 = _581 ? _589 : _586;
    assign _579 = 3'b111;
    assign _580 = _536 == _579;
    assign _591 = _580 ? _585 : _590;
    assign _613 = { _591,
                    _594,
                    _597,
                    _600,
                    _603,
                    _606,
                    _609,
                    _612 };
    assign _633 = _576 & _613;
    assign _573 = _557 == _342;
    assign _571 = _557 == _607;
    assign _569 = _557 == _604;
    assign _567 = _557 == _601;
    assign _565 = _557 == _598;
    assign _563 = _557 == _595;
    assign _561 = _557 == _592;
    assign _557 = _536 + _607;
    assign _559 = _557 == _579;
    assign _574 = { _559,
                    _561,
                    _563,
                    _565,
                    _567,
                    _569,
                    _571,
                    _573 };
    assign _575 = _554 ? _574 : _216;
    assign _552 = _536 == _342;
    assign _550 = _536 == _607;
    assign _548 = _536 == _604;
    assign _546 = _536 == _601;
    assign _544 = _536 == _598;
    assign _542 = _536 == _595;
    assign _540 = _536 == _592;
    assign _538 = _536 == _579;
    assign _553 = { _538,
                    _540,
                    _542,
                    _544,
                    _546,
                    _548,
                    _550,
                    _552 };
    assign _576 = _553 | _575;
    assign _631 = ~ _576;
    assign _632 = _355 & _631;
    assign _634 = _632 | _633;
    assign _359 = imem_data[7:7];
    assign _637 = _359 ? _636 : _634;
    assign _630 = _135 == _762;
    assign _638 = _630 ? _637 : _355;
    assign _136 = 4'b0001;
    assign _629 = _135 == _136;
    assign _647 = _629 ? _646 : _638;
    assign _47 = _647;
    assign _48 = _47;
    always @(posedge clock) begin
        if (clear)
            _355 <= _216;
        else
            _355 <= _48;
    end
    assign _1131 = boot_pc[7:0];
    assign _1130 = boot_page[1:0];
    assign _1132 = { _1130,
                     _1131 };
    assign _1093 = boot_pc[7:0];
    assign _1085 = _1055 ? _1056 : _995;
    assign _1084 = _882 == _582;
    assign _1086 = _1084 ? _997 : _1085;
    assign _1080 = 12'b000000000000;
    assign _1081 = _665 == _1080;
    assign _1082 = _1081 ? _997 : _995;
    assign _1075 = _715 == _1080;
    assign _1076 = ~ _1075;
    assign _1077 = _1076 ? _1056 : _997;
    assign _1072 = host_in_valid ? _997 : _995;
    assign _1067 = _1055 ? _1056 : _995;
    assign _1068 = _285 ? _997 : _1067;
    assign _1065 = _1055 ? _1056 : _995;
    assign _1066 = _836 ? _997 : _1065;
    assign _1069 = _279 ? _1068 : _1066;
    assign _1062 = _1055 ? _1056 : _995;
    assign _304 = port_out_ready[3:3];
    assign _303 = port_out_ready[2:2];
    assign _302 = port_out_ready[1:1];
    assign _301 = port_out_ready[0:0];
    always @* begin
        case (_280)
        0:
            _305 <= _301;
        1:
            _305 <= _302;
        2:
            _305 <= _303;
        default:
            _305 <= _304;
        endcase
    end
    assign _1063 = _305 ? _997 : _1062;
    assign _1060 = _1055 ? _1056 : _995;
    assign _1061 = _836 ? _1060 : _997;
    assign _1064 = _279 ? _1063 : _1061;
    assign _1070 = _277 ? _1069 : _1064;
    assign _1056 = imem_data[7:0];
    assign _651 = _167 ? _53 : _650;
    assign _50 = _651;
    always @(posedge clock) begin
        if (clear)
            _650 <= _1080;
        else
            _650 <= _50;
    end
    assign _655 = _173 ? _53 : _654;
    assign _51 = _655;
    always @(posedge clock) begin
        if (clear)
            _654 <= _1080;
        else
            _654 <= _51;
    end
    assign _659 = _179 ? _53 : _658;
    assign _52 = _659;
    always @(posedge clock) begin
        if (clear)
            _658 <= _1080;
        else
            _658 <= _52;
    end
    assign _668 = 12'b000000000001;
    assign _669 = _665 - _668;
    assign _667 = _665 == _1080;
    assign _670 = _667 ? _665 : _669;
    assign _660 = 4'b0011;
    assign _661 = _135 == _660;
    assign _672 = _661 ? _671 : _670;
    assign _53 = _672;
    assign _673 = _197 ? _53 : _664;
    assign _54 = _673;
    always @(posedge clock) begin
        if (clear)
            _664 <= _1080;
        else
            _664 <= _54;
    end
    always @* begin
        case (_143)
        0:
            _665 <= _664;
        1:
            _665 <= _658;
        2:
            _665 <= _654;
        default:
            _665 <= _650;
        endcase
    end
    assign _1055 = _665 == _1080;
    assign _1057 = _1055 ? _1056 : _995;
    assign _1052 = _1048[3:3];
    assign _1051 = _1048[2:2];
    assign _1050 = _1048[1:1];
    assign _1047 = flags[15:12];
    assign _1046 = flags[11:8];
    assign _1045 = flags[7:4];
    assign _1044 = flags[3:0];
    always @* begin
        case (_143)
        0:
            _1048 <= _1044;
        1:
            _1048 <= _1045;
        2:
            _1048 <= _1046;
        default:
            _1048 <= _1047;
        endcase
    end
    assign _1049 = _1048[0:0];
    assign _1041 = port_out_ready[3:3];
    assign _1040 = port_out_ready[2:2];
    assign _1039 = port_out_ready[1:1];
    assign _1038 = port_out_ready[0:0];
    assign _1037 = _690[1:0];
    always @* begin
        case (_1037)
        0:
            _1042 <= _1038;
        1:
            _1042 <= _1039;
        2:
            _1042 <= _1040;
        default:
            _1042 <= _1041;
        endcase
    end
    assign _1034 = _831[3:3];
    assign _1033 = _831[2:2];
    assign _1032 = _831[1:1];
    assign _1031 = _831[0:0];
    assign _1030 = _690[1:0];
    always @* begin
        case (_1030)
        0:
            _1035 <= _1031;
        1:
            _1035 <= _1032;
        2:
            _1035 <= _1033;
        default:
            _1035 <= _1034;
        endcase
    end
    assign _1036 = ~ _1035;
    assign _677 = _167 ? _60 : _676;
    assign _57 = _677;
    always @(posedge clock) begin
        if (clear)
            _676 <= _342;
        else
            _676 <= _57;
    end
    assign _681 = _173 ? _60 : _680;
    assign _58 = _681;
    always @(posedge clock) begin
        if (clear)
            _680 <= _342;
        else
            _680 <= _58;
    end
    assign _685 = _179 ? _60 : _684;
    assign _59 = _685;
    always @(posedge clock) begin
        if (clear)
            _684 <= _342;
        else
            _684 <= _59;
    end
    assign _691 = _277 ? _690 : _278;
    assign _686 = _135 == _274;
    assign _692 = _686 ? _691 : _690;
    assign _60 = _692;
    assign _693 = _197 ? _60 : _689;
    assign _61 = _693;
    always @(posedge clock) begin
        if (clear)
            _689 <= _342;
        else
            _689 <= _61;
    end
    always @* begin
        case (_143)
        0:
            _690 <= _689;
        1:
            _690 <= _684;
        2:
            _690 <= _680;
        default:
            _690 <= _676;
        endcase
    end
    assign _1029 = _690[2:2];
    assign _1043 = _1029 ? _1042 : _1036;
    assign _1027 = _831[3:3];
    assign _1026 = _831[2:2];
    assign _1025 = _831[1:1];
    assign _1024 = _831[0:0];
    always @* begin
        case (_143)
        0:
            _1028 <= _1024;
        1:
            _1028 <= _1025;
        2:
            _1028 <= _1026;
        default:
            _1028 <= _1027;
        endcase
    end
    assign _697 = _167 ? _65 : _696;
    assign _62 = _697;
    always @(posedge clock) begin
        if (clear)
            _696 <= _1080;
        else
            _696 <= _62;
    end
    assign _701 = _173 ? _65 : _700;
    assign _63 = _701;
    always @(posedge clock) begin
        if (clear)
            _700 <= _1080;
        else
            _700 <= _63;
    end
    assign _705 = _179 ? _65 : _704;
    assign _64 = _705;
    always @(posedge clock) begin
        if (clear)
            _704 <= _1080;
        else
            _704 <= _64;
    end
    assign _671 = imem_data[11:0];
    assign _726 = _715 - _668;
    assign _723 = _715 - _668;
    assign _719 = { _276,
                    _235 };
    assign _717 = _190 == _660;
    assign _720 = _717 ? _719 : _715;
    assign _711 = _135 == _184;
    assign _721 = _711 ? _720 : _715;
    assign _710 = _135 == _709;
    assign _724 = _710 ? _723 : _721;
    assign _708 = _135 == _762;
    assign _727 = _708 ? _726 : _724;
    assign _707 = _135 == _191;
    assign _728 = _707 ? _671 : _727;
    assign _65 = _728;
    assign _729 = _197 ? _65 : _714;
    assign _66 = _729;
    always @(posedge clock) begin
        if (clear)
            _714 <= _1080;
        else
            _714 <= _66;
    end
    always @* begin
        case (_143)
        0:
            _715 <= _714;
        1:
            _715 <= _704;
        2:
            _715 <= _700;
        default:
            _715 <= _696;
        endcase
    end
    assign _1021 = _715[2:0];
    assign _1023 = _1021 == _342;
    assign _1020 = _235[7:7];
    assign _1019 = _235[6:6];
    assign _1018 = _235[5:5];
    assign _1017 = _235[4:4];
    assign _1016 = _235[3:3];
    assign _1015 = _235[2:2];
    assign _1014 = _235[1:1];
    assign _1013 = _235[0:0];
    assign _1012 = imem_data[11:8];
    always @* begin
        case (_1012)
        0:
            _1053 <= _1013;
        1:
            _1053 <= _1014;
        2:
            _1053 <= _1015;
        3:
            _1053 <= _1016;
        4:
            _1053 <= _1017;
        5:
            _1053 <= _1018;
        6:
            _1053 <= _1019;
        7:
            _1053 <= _1020;
        8:
            _1053 <= _1023;
        9:
            _1053 <= host_in_valid;
        10:
            _1053 <= _1028;
        11:
            _1053 <= _1043;
        12:
            _1053 <= _1049;
        13:
            _1053 <= _1050;
        14:
            _1053 <= _1051;
        default:
            _1053 <= _1052;
        endcase
    end
    assign _1058 = _1053 ? _997 : _1057;
    assign _1007 = _235 == _193;
    assign _1008 = ~ _1007;
    assign _1009 = _1008 ? _1004 : _997;
    assign _1003 = 8'b00000010;
    assign _1004 = _995 + _1003;
    assign _739 = _167 ? _96 : _234;
    assign _737 = _735 == _286;
    assign _738 = _732 & _737;
    assign _740 = _738 ? bank_rdata : _739;
    assign _67 = _740;
    always @(posedge clock) begin
        if (clear)
            _234 <= _216;
        else
            _234 <= _67;
    end
    assign _744 = _173 ? _96 : _231;
    assign _742 = _735 == _288;
    assign _743 = _732 & _742;
    assign _745 = _743 ? bank_rdata : _744;
    assign _68 = _745;
    always @(posedge clock) begin
        if (clear)
            _231 <= _216;
        else
            _231 <= _68;
    end
    assign _749 = _179 ? _96 : _228;
    assign _747 = _735 == _290;
    assign _748 = _732 & _747;
    assign _750 = _748 ? bank_rdata : _749;
    assign _69 = _750;
    always @(posedge clock) begin
        if (clear)
            _228 <= _216;
        else
            _228 <= _69;
    end
    assign _931 = _235[5:0];
    assign _933 = { _931,
                    _164,
                    _922 };
    assign _929 = _235[6:0];
    assign _930 = { _929,
                    _922 };
    assign _934 = _909 ? _933 : _930;
    assign _926 = _235[7:2];
    assign _927 = { _922,
                    _164,
                    _926 };
    assign _923 = _235[7:1];
    assign _920 = _873[7:7];
    assign _919 = _873[6:6];
    assign _918 = _873[5:5];
    assign _917 = _873[4:4];
    assign _916 = _873[3:3];
    assign _915 = _873[2:2];
    assign _914 = _873[1:1];
    assign _913 = _873[0:0];
    assign _912 = _536 ^ _607;
    always @* begin
        case (_912)
        0:
            _921 <= _913;
        1:
            _921 <= _914;
        2:
            _921 <= _915;
        3:
            _921 <= _916;
        4:
            _921 <= _917;
        5:
            _921 <= _918;
        6:
            _921 <= _919;
        default:
            _921 <= _920;
        endcase
    end
    assign _910 = imem_data[4:4];
    assign _922 = _910 & _921;
    assign _924 = { _922,
                    _923 };
    assign _581 = imem_data[5:5];
    assign _554 = imem_data[6:6];
    assign _909 = _554 & _581;
    assign _928 = _909 ? _927 : _924;
    assign _935 = _582 ? _934 : _928;
    assign _903 = _896[3:3];
    assign _902 = _896[2:2];
    assign _901 = _896[1:1];
    assign _900 = _896[0:0];
    assign _904 = { _900,
                    _901,
                    _902,
                    _903 };
    assign _899 = _235[3:0];
    assign _905 = { _899,
                    _904 };
    assign _897 = _235[7:4];
    assign _895 = pin_in4[31:28];
    assign _894 = pin_in4[27:24];
    assign _893 = pin_in4[23:20];
    assign _892 = pin_in4[19:16];
    assign _891 = pin_in4[15:12];
    assign _890 = pin_in4[11:8];
    assign _889 = pin_in4[7:4];
    assign _888 = pin_in4[3:0];
    always @* begin
        case (_536)
        0:
            _896 <= _888;
        1:
            _896 <= _889;
        2:
            _896 <= _890;
        3:
            _896 <= _891;
        4:
            _896 <= _892;
        5:
            _896 <= _893;
        6:
            _896 <= _894;
        default:
            _896 <= _895;
        endcase
    end
    assign _898 = { _896,
                    _897 };
    assign _906 = _582 ? _905 : _898;
    assign _885 = _235[6:0];
    assign _886 = { _885,
                    _882 };
    assign _883 = _235[7:1];
    assign _881 = _873[7:7];
    assign _880 = _873[6:6];
    assign _879 = _873[5:5];
    assign _878 = _873[4:4];
    assign _877 = _873[3:3];
    assign _876 = _873[2:2];
    assign _875 = _873[1:1];
    assign _752 = _143 == _292;
    assign _756 = _752 ? pin_in : _755;
    assign _72 = _756;
    always @(posedge clock) begin
        if (clear)
            _755 <= _216;
        else
            _755 <= _72;
    end
    assign _871 = _143 == _292;
    assign _872 = _871 ? pin_in : _755;
    assign _757 = _167 ? _77 : _124;
    assign _74 = _757;
    always @(posedge clock) begin
        if (clear)
            _124 <= _216;
        else
            _124 <= _74;
    end
    assign _758 = _173 ? _77 : _127;
    assign _75 = _758;
    always @(posedge clock) begin
        if (clear)
            _127 <= _216;
        else
            _127 <= _75;
    end
    assign _759 = _179 ? _77 : _130;
    assign _76 = _759;
    always @(posedge clock) begin
        if (clear)
            _130 <= _216;
        else
            _130 <= _76;
    end
    assign _193 = imem_data[7:0];
    assign _762 = 4'b0111;
    assign _763 = _190 == _762;
    assign _764 = _763 ? _193 : _761;
    assign _760 = _135 == _184;
    assign _765 = _760 ? _764 : _761;
    assign _77 = _765;
    assign _766 = _197 ? _77 : _133;
    assign _78 = _766;
    always @(posedge clock) begin
        if (clear)
            _133 <= _216;
        else
            _133 <= _78;
    end
    always @* begin
        case (_143)
        0:
            _761 <= _133;
        1:
            _761 <= _130;
        2:
            _761 <= _127;
        default:
            _761 <= _124;
        endcase
    end
    assign _869 = _761[7:7];
    assign _873 = _869 ? _872 : pin_in;
    assign _874 = _873[0:0];
    assign _536 = imem_data[11:9];
    always @* begin
        case (_536)
        0:
            _882 <= _874;
        1:
            _882 <= _875;
        2:
            _882 <= _876;
        3:
            _882 <= _877;
        4:
            _882 <= _878;
        5:
            _882 <= _879;
        6:
            _882 <= _880;
        default:
            _882 <= _881;
        endcase
    end
    assign _884 = { _882,
                    _883 };
    assign _582 = imem_data[8:8];
    assign _887 = _582 ? _886 : _884;
    assign _868 = imem_data[7:7];
    assign _907 = _868 ? _906 : _887;
    assign _866 = host_in_valid ? host_in : _235;
    always @* begin
        case (_280)
        0:
            _861 <= port_in0;
        1:
            _861 <= port_in1;
        2:
            _861 <= port_in2;
        default:
            _861 <= port_in3;
        endcase
    end
    assign _284 = port_in_valid[3:3];
    assign _283 = port_in_valid[2:2];
    assign _282 = port_in_valid[1:1];
    assign _281 = port_in_valid[0:0];
    assign _280 = _278[1:0];
    always @* begin
        case (_280)
        0:
            _285 <= _281;
        1:
            _285 <= _282;
        2:
            _285 <= _283;
        default:
            _285 <= _284;
        endcase
    end
    assign _862 = _285 ? _861 : _235;
    assign _774 = _770 ? _235 : _773;
    assign _86 = _774;
    always @(posedge clock) begin
        if (clear)
            _773 <= _216;
        else
            _773 <= _86;
    end
    assign _782 = _778 ? _235 : _781;
    assign _87 = _782;
    always @(posedge clock) begin
        if (clear)
            _781 <= _216;
        else
            _781 <= _87;
    end
    assign _790 = _786 ? _235 : _789;
    assign _88 = _790;
    always @(posedge clock) begin
        if (clear)
            _789 <= _216;
        else
            _789 <= _88;
    end
    assign _798 = _794 ? _235 : _797;
    assign _89 = _798;
    always @(posedge clock) begin
        if (clear)
            _797 <= _216;
        else
            _797 <= _89;
    end
    assign _858 = _278[1:0];
    always @* begin
        case (_858)
        0:
            _859 <= _797;
        1:
            _859 <= _789;
        2:
            _859 <= _781;
        default:
            _859 <= _773;
        endcase
    end
    assign _835 = _831[3:3];
    assign _834 = _831[2:2];
    assign _833 = _831[1:1];
    assign _791 = _278[1:0];
    assign _793 = _791 == _292;
    assign _794 = _93 & _793;
    assign _806 = _794 ? vdd : _805;
    assign _799 = _278[1:0];
    assign _801 = _799 == _292;
    assign _802 = _94 & _801;
    assign _807 = _802 ? gnd : _806;
    assign _90 = _807;
    always @(posedge clock) begin
        if (clear)
            _805 <= _164;
        else
            _805 <= _90;
    end
    assign _783 = _278[1:0];
    assign _785 = _783 == _290;
    assign _786 = _93 & _785;
    assign _815 = _786 ? vdd : _814;
    assign _808 = _278[1:0];
    assign _810 = _808 == _290;
    assign _811 = _94 & _810;
    assign _816 = _811 ? gnd : _815;
    assign _91 = _816;
    always @(posedge clock) begin
        if (clear)
            _814 <= _164;
        else
            _814 <= _91;
    end
    assign _775 = _278[1:0];
    assign _777 = _775 == _288;
    assign _778 = _93 & _777;
    assign _824 = _778 ? vdd : _823;
    assign _817 = _278[1:0];
    assign _819 = _817 == _288;
    assign _820 = _94 & _819;
    assign _825 = _820 ? gnd : _824;
    assign _92 = _825;
    always @(posedge clock) begin
        if (clear)
            _823 <= _164;
        else
            _823 <= _92;
    end
    assign _767 = _278[1:0];
    assign _769 = _767 == _286;
    assign _837 = _836 ? gnd : vdd;
    assign _838 = _279 ? gnd : _837;
    assign _839 = _277 ? gnd : _838;
    assign _826 = _135 == _274;
    assign _840 = _826 ? _839 : gnd;
    assign _93 = _840;
    assign _770 = _93 & _769;
    assign _850 = _770 ? vdd : _830;
    assign _846 = _278[1:0];
    assign _848 = _846 == _286;
    assign _842 = _836 ? vdd : gnd;
    assign _843 = _279 ? gnd : _842;
    assign _844 = _277 ? _843 : gnd;
    assign _841 = _135 == _274;
    assign _845 = _841 ? _844 : gnd;
    assign _94 = _845;
    assign _849 = _94 & _848;
    assign _851 = _849 ? gnd : _850;
    assign _95 = _851;
    always @(posedge clock) begin
        if (clear)
            _830 <= _164;
        else
            _830 <= _95;
    end
    assign _831 = { _830,
                    _823,
                    _814,
                    _805 };
    assign _832 = _831[0:0];
    assign _827 = _278[1:0];
    always @* begin
        case (_827)
        0:
            _836 <= _832;
        1:
            _836 <= _833;
        2:
            _836 <= _834;
        default:
            _836 <= _835;
        endcase
    end
    assign _860 = _836 ? _859 : _235;
    assign _278 = imem_data[10:8];
    assign _279 = _278[2:2];
    assign _863 = _279 ? _862 : _860;
    assign _277 = imem_data[11:11];
    assign _864 = _277 ? _863 : _235;
    assign _857 = _135 == _274;
    assign _865 = _857 ? _864 : _235;
    assign _856 = _135 == _330;
    assign _867 = _856 ? _866 : _865;
    assign _709 = 4'b1000;
    assign _855 = _135 == _709;
    assign _908 = _855 ? _907 : _867;
    assign _854 = _135 == _762;
    assign _936 = _854 ? _935 : _908;
    assign _852 = 4'b0100;
    assign _853 = _135 == _852;
    assign _937 = _853 ? _193 : _936;
    assign _96 = _937;
    assign _947 = _197 ? _96 : _225;
    assign _938 = _98 ? _143 : _735;
    assign _97 = _938;
    always @(posedge clock) begin
        if (clear)
            _735 <= _292;
        else
            _735 <= _97;
    end
    assign _945 = _735 == _292;
    assign _940 = _190 == _852;
    assign _941 = _940 ? vdd : gnd;
    assign gnd = 1'b0;
    assign _939 = _135 == _184;
    assign _942 = _939 ? _941 : gnd;
    assign _98 = _942;
    assign _943 = _98 ? vdd : gnd;
    assign _99 = _943;
    always @(posedge clock) begin
        if (clear)
            _732 <= _164;
        else
            _732 <= _99;
    end
    assign _946 = _732 & _945;
    assign _948 = _946 ? bank_rdata : _947;
    assign _100 = _948;
    always @(posedge clock) begin
        if (clear)
            _225 <= _216;
        else
            _225 <= _100;
    end
    always @* begin
        case (_143)
        0:
            _235 <= _225;
        1:
            _235 <= _228;
        2:
            _235 <= _231;
        default:
            _235 <= _234;
        endcase
    end
    assign _1002 = _235 == _193;
    assign _1005 = _1002 ? _1004 : _997;
    assign _1001 = _190 == _136;
    assign _1006 = _1001 ? _1005 : _997;
    assign _190 = imem_data[11:8];
    assign _999 = _190 == _276;
    assign _1010 = _999 ? _1009 : _1006;
    assign _996 = 8'b00000001;
    assign _957 = boot_pc[31:24];
    assign _167 = _143 == _286;
    assign _955 = _167 ? _107 : _954;
    assign _956 = _951 ? ctl_pc : _955;
    assign _958 = clear ? _957 : _956;
    assign _101 = _958;
    always @(posedge clock) begin
        _954 <= _101;
    end
    assign _967 = boot_pc[23:16];
    assign _173 = _143 == _288;
    assign _965 = _173 ? _107 : _964;
    assign _966 = _961 ? ctl_pc : _965;
    assign _968 = clear ? _967 : _966;
    assign _102 = _968;
    always @(posedge clock) begin
        _964 <= _102;
    end
    assign _977 = boot_pc[15:8];
    assign _179 = _143 == _290;
    assign _975 = _179 ? _107 : _974;
    assign _976 = _971 ? ctl_pc : _975;
    assign _978 = clear ? _977 : _976;
    assign _105 = _978;
    always @(posedge clock) begin
        _974 <= _105;
    end
    always @* begin
        case (_143)
        0:
            _995 <= _994;
        1:
            _995 <= _974;
        2:
            _995 <= _964;
        default:
            _995 <= _954;
        endcase
    end
    assign _997 = _995 + _996;
    assign _184 = 4'b1111;
    assign _991 = _135 == _184;
    assign _1011 = _991 ? _1010 : _997;
    assign _989 = 4'b1110;
    assign _990 = _135 == _989;
    assign _1059 = _990 ? _1058 : _1011;
    assign _274 = 4'b1101;
    assign _988 = _135 == _274;
    assign _1071 = _988 ? _1070 : _1059;
    assign _330 = 4'b1100;
    assign _987 = _135 == _330;
    assign _1073 = _987 ? _1072 : _1071;
    assign _985 = 4'b1010;
    assign _986 = _135 == _985;
    assign _1078 = _986 ? _1077 : _1073;
    assign _983 = 4'b1001;
    assign _984 = _135 == _983;
    assign _1079 = _984 ? _1056 : _1078;
    assign _982 = _135 == _261;
    assign _1083 = _982 ? _1082 : _1079;
    assign _135 = imem_data[15:12];
    assign _980 = _135 == _237;
    assign _1087 = _980 ? _1086 : _1083;
    assign _107 = _1087;
    assign _197 = _143 == _292;
    assign _1091 = _197 ? _107 : _994;
    assign _1092 = _1090 ? ctl_pc : _1091;
    assign _1094 = clear ? _1093 : _1092;
    assign _108 = _1094;
    always @(posedge clock) begin
        _994 <= _108;
    end
    always @* begin
        case (_1122)
        0:
            _1127 <= _994;
        1:
            _1127 <= _974;
        2:
            _1127 <= _964;
        default:
            _1127 <= _954;
        endcase
    end
    assign _1128 = _1124 ? ctl_pc : _1127;
    assign _1099 = boot_page[7:6];
    assign _950 = ctl_thread == _286;
    assign _951 = ctl_valid & _950;
    assign _1098 = _951 ? ctl_page : _1097;
    assign _1100 = clear ? _1099 : _1098;
    assign _109 = _1100;
    always @(posedge clock) begin
        _1097 <= _109;
    end
    assign _1105 = boot_page[5:4];
    assign _960 = ctl_thread == _288;
    assign _961 = ctl_valid & _960;
    assign _1104 = _961 ? ctl_page : _1103;
    assign _1106 = clear ? _1105 : _1104;
    assign _110 = _1106;
    always @(posedge clock) begin
        _1103 <= _110;
    end
    assign _1111 = boot_page[3:2];
    assign _970 = ctl_thread == _290;
    assign _971 = ctl_valid & _970;
    assign _1110 = _971 ? ctl_page : _1109;
    assign _1112 = clear ? _1111 : _1110;
    assign _111 = _1112;
    always @(posedge clock) begin
        _1109 <= _111;
    end
    assign _1117 = boot_page[1:0];
    assign _1089 = ctl_thread == _292;
    assign _1090 = ctl_valid & _1089;
    assign _1116 = _1090 ? ctl_page : _1115;
    assign _1118 = clear ? _1117 : _1116;
    assign _114 = _1118;
    always @(posedge clock) begin
        _1115 <= _114;
    end
    always @* begin
        case (_1122)
        0:
            _1125 <= _1115;
        1:
            _1125 <= _1109;
        2:
            _1125 <= _1103;
        default:
            _1125 <= _1097;
        endcase
    end
    assign vdd = 1'b1;
    assign _1120 = _143 + _290;
    assign _116 = _1120;
    always @(posedge clock) begin
        if (clear)
            _143 <= _292;
        else
            _143 <= _116;
    end
    assign _1122 = _143 + _290;
    assign _1123 = ctl_thread == _1122;
    assign _1124 = ctl_valid & _1123;
    assign _1126 = _1124 ? ctl_page : _1125;
    assign _1129 = { _1126,
                     _1128 };
    assign _1133 = clear ? _1132 : _1129;
    assign imem_addr = _1133;
    assign pin_out = _355;
    assign pin_oe = _535;
    assign pin_sub = _530;
    assign host_out = _349;
    assign host_tag = _343;
    assign host_out_valid = _339;
    assign host_in_ready = _32;
    assign port_out_data = _325;
    assign port_out_valid = _321;
    assign port_in_ready = _26;
    assign bank_addr = _257;
    assign bank_we = _18;
    assign bank_re = _98;
    assign bank_wdata = _235;
    assign fine_out = _217;
    assign fine_valid = _165;
    assign cfg_out = _134;

endmodule
