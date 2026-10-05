module retro_console (
    strobe,
    din,
    clear,
    clock,
    luma,
    chroma,
    chroma_oe,
    chroma2_oe,
    line_start,
    pix_col,
    pix_valid,
    hcount,
    vcount
);

    input strobe;
    input [7:0] din;
    input clear;
    input clock;
    output [3:0] luma;
    output chroma;
    output chroma_oe;
    output chroma2_oe;
    output line_start;
    output [7:0] pix_col;
    output pix_valid;
    output [11:0] hcount;
    output [8:0] vcount;

    wire _819;
    reg _820;
    wire [3:0] _814;
    wire _815;
    wire _816;
    wire _817;
    wire _831;
    reg _834;
    wire [4:0] _878;
    wire [4:0] _875;
    wire [4:0] _876;
    wire [3:0] _868;
    wire [3:0] _867;
    wire [3:0] _869;
    wire [4:0] _870;
    wire [4:0] _866;
    wire [4:0] _871;
    wire _873;
    wire _874;
    wire [4:0] _877;
    wire _879;
    wire [4:0] _862;
    wire [3:0] _853;
    wire [3:0] _854;
    wire [3:0] _850;
    wire [3:0] _851;
    wire [3:0] _848;
    wire [3:0] _849;
    wire [3:0] _813;
    wire [3:0] _846;
    wire _847;
    wire [3:0] _852;
    wire _845;
    wire [3:0] _855;
    wire [4:0] _856;
    wire [3:0] _841;
    wire _839;
    wire [3:0] _843;
    wire [3:0] _8;
    reg [3:0] _837;
    wire [4:0] _844;
    wire [4:0] _857;
    wire _859;
    wire _860;
    wire [4:0] _863;
    wire _865;
    wire [11:0] _828;
    wire _829;
    wire [11:0] _824;
    wire _825;
    wire _826;
    wire _823;
    wire _827;
    wire _830;
    wire _880;
    reg _883;
    wire [3:0] _981;
    wire [7:0] _811;
    reg [7:0] _808;
    reg [7:0] _801;
    reg [7:0] _794;
    reg [7:0] _787;
    reg [7:0] _780;
    reg [7:0] _773;
    reg [7:0] _766;
    reg [7:0] _759;
    reg [7:0] _752;
    reg [7:0] _745;
    reg [7:0] _738;
    reg [7:0] _731;
    reg [7:0] _724;
    reg [7:0] _717;
    reg [7:0] _710;
    reg [7:0] _703;
    reg [7:0] _696;
    reg [7:0] _687;
    reg [7:0] _690;
    reg [7:0] _693;
    wire [15:0] _657;
    reg [7:0] _913;
    reg [7:0] _910;
    wire [15:0] _914;
    reg [7:0] _903;
    reg [7:0] _900;
    wire [15:0] _904;
    wire [15:0] _905;
    wire [15:0] _906;
    wire [15:0] _907;
    wire [15:0] _915;
    wire [15:0] _10;
    reg [15:0] _658;
    wire _659;
    reg [7:0] _684;
    reg [7:0] _931;
    reg [7:0] _681;
    reg [7:0] _928;
    wire [15:0] _932;
    reg [7:0] _678;
    reg [7:0] _921;
    reg [7:0] _663;
    reg [7:0] _666;
    reg [7:0] _669;
    reg [7:0] _672;
    reg [7:0] _675;
    reg [7:0] _918;
    wire [15:0] _922;
    wire [15:0] _923;
    wire [15:0] _924;
    wire [15:0] _925;
    wire [15:0] _933;
    wire [15:0] _11;
    reg [15:0] _654;
    wire _655;
    wire _660;
    wire [7:0] _697;
    reg [7:0] _700;
    wire _649;
    wire _648;
    wire _647;
    wire _646;
    wire _645;
    wire _644;
    wire _643;
    reg [7:0] _641;
    wire _642;
    wire [2:0] _638;
    reg _650;
    wire [8:0] _635;
    reg [7:0] _623;
    reg [7:0] _626;
    reg [7:0] _629;
    reg [7:0] _632;
    wire [8:0] _633;
    wire [8:0] _620;
    wire [8:0] _634;
    wire _636;
    wire _637;
    wire _651;
    wire [7:0] _704;
    reg [7:0] _707;
    wire _617;
    wire _616;
    wire _615;
    wire _614;
    wire _613;
    wire _612;
    wire _611;
    reg [7:0] _609;
    wire _610;
    wire [2:0] _606;
    reg _618;
    reg [7:0] _591;
    reg [7:0] _594;
    reg [7:0] _597;
    reg [7:0] _600;
    wire [8:0] _601;
    wire [8:0] _588;
    wire [8:0] _602;
    wire _604;
    wire _605;
    wire _619;
    wire [7:0] _711;
    reg [7:0] _714;
    wire _585;
    wire _584;
    wire _583;
    wire _582;
    wire _581;
    wire _580;
    wire _579;
    reg [7:0] _577;
    wire _578;
    wire [2:0] _574;
    reg _586;
    reg [7:0] _559;
    reg [7:0] _562;
    reg [7:0] _565;
    reg [7:0] _568;
    wire [8:0] _569;
    wire [8:0] _556;
    wire [8:0] _570;
    wire _572;
    wire _573;
    wire _587;
    wire [7:0] _718;
    reg [7:0] _721;
    wire _553;
    wire _552;
    wire _551;
    wire _550;
    wire _549;
    wire _548;
    wire _547;
    reg [7:0] _545;
    wire _546;
    wire [2:0] _542;
    reg _554;
    reg [7:0] _527;
    reg [7:0] _530;
    reg [7:0] _533;
    reg [7:0] _536;
    wire [8:0] _537;
    wire [8:0] _524;
    wire [8:0] _538;
    wire _540;
    wire _541;
    wire _555;
    wire [7:0] _725;
    reg [7:0] _728;
    wire _521;
    wire _520;
    wire _519;
    wire _518;
    wire _517;
    wire _516;
    wire _515;
    reg [7:0] _513;
    wire _514;
    wire [2:0] _510;
    reg _522;
    reg [7:0] _495;
    reg [7:0] _498;
    reg [7:0] _501;
    reg [7:0] _504;
    wire [8:0] _505;
    wire [8:0] _492;
    wire [8:0] _506;
    wire _508;
    wire _509;
    wire _523;
    wire [7:0] _732;
    reg [7:0] _735;
    wire _489;
    wire _488;
    wire _487;
    wire _486;
    wire _485;
    wire _484;
    wire _483;
    reg [7:0] _481;
    wire _482;
    wire [2:0] _478;
    reg _490;
    reg [7:0] _463;
    reg [7:0] _466;
    reg [7:0] _469;
    reg [7:0] _472;
    wire [8:0] _473;
    wire [8:0] _460;
    wire [8:0] _474;
    wire _476;
    wire _477;
    wire _491;
    wire [7:0] _739;
    reg [7:0] _742;
    wire _457;
    wire _456;
    wire _455;
    wire _454;
    wire _453;
    wire _452;
    wire _451;
    reg [7:0] _449;
    wire _450;
    wire [2:0] _446;
    reg _458;
    reg [7:0] _431;
    reg [7:0] _434;
    reg [7:0] _437;
    reg [7:0] _440;
    wire [8:0] _441;
    wire [8:0] _428;
    wire [8:0] _442;
    wire _444;
    wire _445;
    wire _459;
    wire [7:0] _746;
    reg [7:0] _749;
    wire _425;
    wire _424;
    wire _423;
    wire _422;
    wire _421;
    wire _420;
    wire _419;
    reg [7:0] _417;
    wire _418;
    wire [2:0] _414;
    reg _426;
    reg [7:0] _399;
    reg [7:0] _402;
    reg [7:0] _405;
    reg [7:0] _408;
    wire [8:0] _409;
    wire [8:0] _396;
    wire [8:0] _410;
    wire _412;
    wire _413;
    wire _427;
    wire [7:0] _753;
    reg [7:0] _756;
    wire _393;
    wire _392;
    wire _391;
    wire _390;
    wire _389;
    wire _388;
    wire _387;
    reg [7:0] _385;
    wire _386;
    wire [2:0] _382;
    reg _394;
    reg [7:0] _367;
    reg [7:0] _370;
    reg [7:0] _373;
    reg [7:0] _376;
    wire [8:0] _377;
    wire [8:0] _364;
    wire [8:0] _378;
    wire _380;
    wire _381;
    wire _395;
    wire [7:0] _760;
    reg [7:0] _763;
    wire _361;
    wire _360;
    wire _359;
    wire _358;
    wire _357;
    wire _356;
    wire _355;
    reg [7:0] _353;
    wire _354;
    wire [2:0] _350;
    reg _362;
    reg [7:0] _335;
    reg [7:0] _338;
    reg [7:0] _341;
    reg [7:0] _344;
    wire [8:0] _345;
    wire [8:0] _332;
    wire [8:0] _346;
    wire _348;
    wire _349;
    wire _363;
    wire [7:0] _767;
    reg [7:0] _770;
    wire _329;
    wire _328;
    wire _327;
    wire _326;
    wire _325;
    wire _324;
    wire _323;
    reg [7:0] _321;
    wire _322;
    wire [2:0] _318;
    reg _330;
    reg [7:0] _303;
    reg [7:0] _306;
    reg [7:0] _309;
    reg [7:0] _312;
    wire [8:0] _313;
    wire [8:0] _300;
    wire [8:0] _314;
    wire _316;
    wire _317;
    wire _331;
    wire [7:0] _774;
    reg [7:0] _777;
    wire _297;
    wire _296;
    wire _295;
    wire _294;
    wire _293;
    wire _292;
    wire _291;
    reg [7:0] _289;
    wire _290;
    wire [2:0] _286;
    reg _298;
    reg [7:0] _271;
    reg [7:0] _274;
    reg [7:0] _277;
    reg [7:0] _280;
    wire [8:0] _281;
    wire [8:0] _268;
    wire [8:0] _282;
    wire _284;
    wire _285;
    wire _299;
    wire [7:0] _781;
    reg [7:0] _784;
    wire _265;
    wire _264;
    wire _263;
    wire _262;
    wire _261;
    wire _260;
    wire _259;
    reg [7:0] _257;
    wire _258;
    wire [2:0] _254;
    reg _266;
    reg [7:0] _239;
    reg [7:0] _242;
    reg [7:0] _245;
    reg [7:0] _248;
    wire [8:0] _249;
    wire [8:0] _236;
    wire [8:0] _250;
    wire _252;
    wire _253;
    wire _267;
    wire [7:0] _788;
    reg [7:0] _791;
    wire _233;
    wire _232;
    wire _231;
    wire _230;
    wire _229;
    wire _228;
    wire _227;
    reg [7:0] _225;
    wire _226;
    wire [2:0] _222;
    reg _234;
    reg [7:0] _207;
    reg [7:0] _210;
    reg [7:0] _213;
    reg [7:0] _216;
    wire [8:0] _217;
    wire [8:0] _204;
    wire [8:0] _218;
    wire _220;
    wire _221;
    wire _235;
    wire [7:0] _795;
    reg [7:0] _798;
    wire _201;
    wire _200;
    wire _199;
    wire _198;
    wire _197;
    wire _196;
    wire _195;
    reg [7:0] _193;
    wire _194;
    wire [2:0] _190;
    reg _202;
    reg [7:0] _175;
    reg [7:0] _178;
    reg [7:0] _181;
    reg [7:0] _184;
    wire [8:0] _185;
    wire [8:0] _172;
    wire [8:0] _186;
    wire _188;
    wire _189;
    wire _203;
    wire [7:0] _802;
    reg [7:0] _805;
    wire _169;
    wire _168;
    wire _167;
    wire _166;
    wire _165;
    wire _164;
    wire _163;
    reg [7:0] _161;
    wire _162;
    wire [2:0] _158;
    reg _170;
    wire [11:0] _150;
    wire _151;
    reg [7:0] _141;
    reg [7:0] _144;
    reg [7:0] _147;
    reg [7:0] _152;
    wire [8:0] _153;
    wire [7:0] _89;
    reg [7:0] _92;
    reg [7:0] _95;
    reg [7:0] _98;
    reg [7:0] _101;
    reg [7:0] _104;
    reg [7:0] _107;
    reg [7:0] _110;
    reg [7:0] _113;
    reg [7:0] _116;
    reg [7:0] _119;
    reg [7:0] _122;
    reg [7:0] _125;
    reg [7:0] _128;
    reg [7:0] _131;
    reg [7:0] _134;
    reg [7:0] _137;
    wire [8:0] _138;
    wire [8:0] _154;
    wire _156;
    wire _157;
    wire _171;
    wire [7:0] _809;
    reg [7:0] _812;
    wire [3:0] _979;
    wire _980;
    wire [3:0] _982;
    wire [3:0] _984;
    wire gnd;
    wire [8:0] _947;
    wire [8:0] _87;
    wire [8:0] _934;
    wire [8:0] _935;
    wire [8:0] _936;
    wire [8:0] _937;
    wire [8:0] _939;
    wire [8:0] _14;
    reg [8:0] _88;
    wire _948;
    wire _949;
    wire [3:0] _896;
    wire [3:0] _941;
    wire [3:0] _943;
    wire [3:0] _944;
    wire [3:0] _946;
    wire [3:0] _15;
    reg [3:0] _895;
    wire _897;
    wire _950;
    wire _951;
    wire [11:0] _890;
    wire _891;
    wire [8:0] _887;
    wire _888;
    wire [8:0] _884;
    wire _885;
    wire _886;
    wire _889;
    wire _892;
    wire _952;
    wire _16;
    reg _33;
    reg _36;
    reg _39;
    reg _42;
    reg _45;
    reg _48;
    reg _51;
    reg _54;
    reg _57;
    reg _60;
    reg _63;
    reg _66;
    reg _69;
    reg _72;
    reg _75;
    reg _78;
    reg _81;
    reg _84;
    wire [3:0] _985;
    wire [11:0] _972;
    wire _973;
    wire [11:0] _969;
    wire _970;
    wire _971;
    wire _974;
    wire [11:0] _967;
    wire _968;
    wire _975;
    wire [11:0] _965;
    wire _966;
    wire [8:0] _821;
    wire [11:0] _28;
    wire vdd;
    wire [11:0] _955;
    wire [11:0] _956;
    wire _954;
    wire [11:0] _958;
    wire [11:0] _17;
    reg [11:0] _27;
    wire _29;
    wire [8:0] _962;
    wire [8:0] _959;
    wire _960;
    wire [8:0] _964;
    wire [8:0] _20;
    reg [8:0] _30;
    wire _822;
    wire _976;
    wire [3:0] _987;
    reg [3:0] _990;
    assign _819 = 1'b0;
    always @(posedge clock) begin
        if (clear)
            _820 <= _819;
        else
            _820 <= _817;
    end
    assign _814 = 4'b0000;
    assign _815 = _813 == _814;
    assign _816 = ~ _815;
    assign _817 = _84 & _816;
    assign _831 = _830 | _817;
    always @(posedge clock) begin
        if (clear)
            _834 <= _819;
        else
            _834 <= _831;
    end
    assign _878 = 5'b00110;
    assign _875 = 5'b01100;
    assign _876 = _871 - _875;
    assign _868 = 4'b0111;
    assign _867 = 4'b0100;
    assign _869 = _845 ? _868 : _867;
    assign _870 = { gnd,
                    _869 };
    assign _866 = { gnd,
                    _837 };
    assign _871 = _866 + _870;
    assign _873 = _871 < _875;
    assign _874 = ~ _873;
    assign _877 = _874 ? _876 : _871;
    assign _879 = _877 < _878;
    assign _862 = _857 - _875;
    assign _853 = 4'b1011;
    assign _854 = _853 - _852;
    assign _850 = 4'b1101;
    assign _851 = _813 - _850;
    assign _848 = 4'b0001;
    assign _849 = _813 - _848;
    assign _813 = _812[7:4];
    assign _846 = 4'b1100;
    assign _847 = _846 < _813;
    assign _852 = _847 ? _851 : _849;
    assign _845 = _30[0:0];
    assign _855 = _845 ? _854 : _852;
    assign _856 = { gnd,
                    _855 };
    assign _841 = _837 + _848;
    assign _839 = _837 == _853;
    assign _843 = _839 ? _814 : _841;
    assign _8 = _843;
    always @(posedge clock) begin
        if (clear)
            _837 <= _814;
        else
            _837 <= _8;
    end
    assign _844 = { gnd,
                    _837 };
    assign _857 = _844 + _856;
    assign _859 = _857 < _875;
    assign _860 = ~ _859;
    assign _863 = _860 ? _862 : _857;
    assign _865 = _863 < _878;
    assign _828 = 12'b000110100010;
    assign _829 = _27 < _828;
    assign _824 = 12'b000100101010;
    assign _825 = _27 < _824;
    assign _826 = ~ _825;
    assign _823 = ~ _822;
    assign _827 = _823 & _826;
    assign _830 = _827 & _829;
    assign _880 = _830 ? _879 : _865;
    always @(posedge clock) begin
        if (clear)
            _883 <= _819;
        else
            _883 <= _880;
    end
    assign _981 = 4'b1010;
    assign _811 = 8'b00000000;
    always @(posedge clock) begin
        if (clear)
            _808 <= _811;
        else
            if (_151)
                _808 <= _141;
    end
    always @(posedge clock) begin
        if (clear)
            _801 <= _811;
        else
            if (_151)
                _801 <= _175;
    end
    always @(posedge clock) begin
        if (clear)
            _794 <= _811;
        else
            if (_151)
                _794 <= _207;
    end
    always @(posedge clock) begin
        if (clear)
            _787 <= _811;
        else
            if (_151)
                _787 <= _239;
    end
    always @(posedge clock) begin
        if (clear)
            _780 <= _811;
        else
            if (_151)
                _780 <= _271;
    end
    always @(posedge clock) begin
        if (clear)
            _773 <= _811;
        else
            if (_151)
                _773 <= _303;
    end
    always @(posedge clock) begin
        if (clear)
            _766 <= _811;
        else
            if (_151)
                _766 <= _335;
    end
    always @(posedge clock) begin
        if (clear)
            _759 <= _811;
        else
            if (_151)
                _759 <= _367;
    end
    always @(posedge clock) begin
        if (clear)
            _752 <= _811;
        else
            if (_151)
                _752 <= _399;
    end
    always @(posedge clock) begin
        if (clear)
            _745 <= _811;
        else
            if (_151)
                _745 <= _431;
    end
    always @(posedge clock) begin
        if (clear)
            _738 <= _811;
        else
            if (_151)
                _738 <= _463;
    end
    always @(posedge clock) begin
        if (clear)
            _731 <= _811;
        else
            if (_151)
                _731 <= _495;
    end
    always @(posedge clock) begin
        if (clear)
            _724 <= _811;
        else
            if (_151)
                _724 <= _527;
    end
    always @(posedge clock) begin
        if (clear)
            _717 <= _811;
        else
            if (_151)
                _717 <= _559;
    end
    always @(posedge clock) begin
        if (clear)
            _710 <= _811;
        else
            if (_151)
                _710 <= _591;
    end
    always @(posedge clock) begin
        if (clear)
            _703 <= _811;
        else
            if (_151)
                _703 <= _623;
    end
    always @(posedge clock) begin
        if (clear)
            _696 <= _811;
        else
            if (_151)
                _696 <= _687;
    end
    always @(posedge clock) begin
        if (clear)
            _687 <= _811;
        else
            if (strobe)
                _687 <= _684;
    end
    always @(posedge clock) begin
        if (clear)
            _690 <= _811;
        else
            if (strobe)
                _690 <= _687;
    end
    always @(posedge clock) begin
        if (clear)
            _693 <= _811;
        else
            if (_151)
                _693 <= _690;
    end
    assign _657 = 16'b0000000000000000;
    always @(posedge clock) begin
        if (clear)
            _913 <= _811;
        else
            if (_151)
                _913 <= _672;
    end
    always @(posedge clock) begin
        if (clear)
            _910 <= _811;
        else
            if (_151)
                _910 <= _669;
    end
    assign _914 = { _910,
                    _913 };
    always @(posedge clock) begin
        if (clear)
            _903 <= _811;
        else
            if (_151)
                _903 <= _666;
    end
    always @(posedge clock) begin
        if (clear)
            _900 <= _811;
        else
            if (_151)
                _900 <= _663;
    end
    assign _904 = { _900,
                    _903 };
    assign _905 = _658 + _904;
    assign _906 = _897 ? _905 : _658;
    assign _907 = _33 ? _906 : _658;
    assign _915 = _892 ? _914 : _907;
    assign _10 = _915;
    always @(posedge clock) begin
        if (clear)
            _658 <= _657;
        else
            _658 <= _10;
    end
    assign _659 = _658[12:12];
    always @(posedge clock) begin
        if (clear)
            _684 <= _811;
        else
            if (strobe)
                _684 <= _681;
    end
    always @(posedge clock) begin
        if (clear)
            _931 <= _811;
        else
            if (_151)
                _931 <= _684;
    end
    always @(posedge clock) begin
        if (clear)
            _681 <= _811;
        else
            if (strobe)
                _681 <= _678;
    end
    always @(posedge clock) begin
        if (clear)
            _928 <= _811;
        else
            if (_151)
                _928 <= _681;
    end
    assign _932 = { _928,
                    _931 };
    always @(posedge clock) begin
        if (clear)
            _678 <= _811;
        else
            if (strobe)
                _678 <= _675;
    end
    always @(posedge clock) begin
        if (clear)
            _921 <= _811;
        else
            if (_151)
                _921 <= _678;
    end
    always @(posedge clock) begin
        if (clear)
            _663 <= _811;
        else
            if (strobe)
                _663 <= _629;
    end
    always @(posedge clock) begin
        if (clear)
            _666 <= _811;
        else
            if (strobe)
                _666 <= _663;
    end
    always @(posedge clock) begin
        if (clear)
            _669 <= _811;
        else
            if (strobe)
                _669 <= _666;
    end
    always @(posedge clock) begin
        if (clear)
            _672 <= _811;
        else
            if (strobe)
                _672 <= _669;
    end
    always @(posedge clock) begin
        if (clear)
            _675 <= _811;
        else
            if (strobe)
                _675 <= _672;
    end
    always @(posedge clock) begin
        if (clear)
            _918 <= _811;
        else
            if (_151)
                _918 <= _675;
    end
    assign _922 = { _918,
                    _921 };
    assign _923 = _654 + _922;
    assign _924 = _897 ? _923 : _654;
    assign _925 = _33 ? _924 : _654;
    assign _933 = _892 ? _932 : _925;
    assign _11 = _933;
    always @(posedge clock) begin
        if (clear)
            _654 <= _657;
        else
            _654 <= _11;
    end
    assign _655 = _654[12:12];
    assign _660 = _655 ^ _659;
    assign _697 = _660 ? _696 : _693;
    always @(posedge clock) begin
        if (clear)
            _700 <= _811;
        else
            _700 <= _697;
    end
    assign _649 = _641[0:0];
    assign _648 = _641[1:1];
    assign _647 = _641[2:2];
    assign _646 = _641[3:3];
    assign _645 = _641[4:4];
    assign _644 = _641[5:5];
    assign _643 = _641[6:6];
    always @(posedge clock) begin
        if (clear)
            _641 <= _811;
        else
            if (_151)
                _641 <= _626;
    end
    assign _642 = _641[7:7];
    assign _638 = _634[3:1];
    always @* begin
        case (_638)
        0:
            _650 <= _642;
        1:
            _650 <= _643;
        2:
            _650 <= _644;
        3:
            _650 <= _645;
        4:
            _650 <= _646;
        5:
            _650 <= _647;
        6:
            _650 <= _648;
        default:
            _650 <= _649;
        endcase
    end
    assign _635 = 9'b000010000;
    always @(posedge clock) begin
        if (clear)
            _623 <= _811;
        else
            if (strobe)
                _623 <= _597;
    end
    always @(posedge clock) begin
        if (clear)
            _626 <= _811;
        else
            if (strobe)
                _626 <= _623;
    end
    always @(posedge clock) begin
        if (clear)
            _629 <= _811;
        else
            if (strobe)
                _629 <= _626;
    end
    always @(posedge clock) begin
        if (clear)
            _632 <= _811;
        else
            if (_151)
                _632 <= _629;
    end
    assign _633 = { gnd,
                    _632 };
    assign _620 = { gnd,
                    _92 };
    assign _634 = _620 - _633;
    assign _636 = _634 < _635;
    assign _637 = _36 & _636;
    assign _651 = _637 & _650;
    assign _704 = _651 ? _703 : _700;
    always @(posedge clock) begin
        if (clear)
            _707 <= _811;
        else
            _707 <= _704;
    end
    assign _617 = _609[0:0];
    assign _616 = _609[1:1];
    assign _615 = _609[2:2];
    assign _614 = _609[3:3];
    assign _613 = _609[4:4];
    assign _612 = _609[5:5];
    assign _611 = _609[6:6];
    always @(posedge clock) begin
        if (clear)
            _609 <= _811;
        else
            if (_151)
                _609 <= _594;
    end
    assign _610 = _609[7:7];
    assign _606 = _602[3:1];
    always @* begin
        case (_606)
        0:
            _618 <= _610;
        1:
            _618 <= _611;
        2:
            _618 <= _612;
        3:
            _618 <= _613;
        4:
            _618 <= _614;
        5:
            _618 <= _615;
        6:
            _618 <= _616;
        default:
            _618 <= _617;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _591 <= _811;
        else
            if (strobe)
                _591 <= _565;
    end
    always @(posedge clock) begin
        if (clear)
            _594 <= _811;
        else
            if (strobe)
                _594 <= _591;
    end
    always @(posedge clock) begin
        if (clear)
            _597 <= _811;
        else
            if (strobe)
                _597 <= _594;
    end
    always @(posedge clock) begin
        if (clear)
            _600 <= _811;
        else
            if (_151)
                _600 <= _597;
    end
    assign _601 = { gnd,
                    _600 };
    assign _588 = { gnd,
                    _95 };
    assign _602 = _588 - _601;
    assign _604 = _602 < _635;
    assign _605 = _39 & _604;
    assign _619 = _605 & _618;
    assign _711 = _619 ? _710 : _707;
    always @(posedge clock) begin
        if (clear)
            _714 <= _811;
        else
            _714 <= _711;
    end
    assign _585 = _577[0:0];
    assign _584 = _577[1:1];
    assign _583 = _577[2:2];
    assign _582 = _577[3:3];
    assign _581 = _577[4:4];
    assign _580 = _577[5:5];
    assign _579 = _577[6:6];
    always @(posedge clock) begin
        if (clear)
            _577 <= _811;
        else
            if (_151)
                _577 <= _562;
    end
    assign _578 = _577[7:7];
    assign _574 = _570[3:1];
    always @* begin
        case (_574)
        0:
            _586 <= _578;
        1:
            _586 <= _579;
        2:
            _586 <= _580;
        3:
            _586 <= _581;
        4:
            _586 <= _582;
        5:
            _586 <= _583;
        6:
            _586 <= _584;
        default:
            _586 <= _585;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _559 <= _811;
        else
            if (strobe)
                _559 <= _533;
    end
    always @(posedge clock) begin
        if (clear)
            _562 <= _811;
        else
            if (strobe)
                _562 <= _559;
    end
    always @(posedge clock) begin
        if (clear)
            _565 <= _811;
        else
            if (strobe)
                _565 <= _562;
    end
    always @(posedge clock) begin
        if (clear)
            _568 <= _811;
        else
            if (_151)
                _568 <= _565;
    end
    assign _569 = { gnd,
                    _568 };
    assign _556 = { gnd,
                    _98 };
    assign _570 = _556 - _569;
    assign _572 = _570 < _635;
    assign _573 = _42 & _572;
    assign _587 = _573 & _586;
    assign _718 = _587 ? _717 : _714;
    always @(posedge clock) begin
        if (clear)
            _721 <= _811;
        else
            _721 <= _718;
    end
    assign _553 = _545[0:0];
    assign _552 = _545[1:1];
    assign _551 = _545[2:2];
    assign _550 = _545[3:3];
    assign _549 = _545[4:4];
    assign _548 = _545[5:5];
    assign _547 = _545[6:6];
    always @(posedge clock) begin
        if (clear)
            _545 <= _811;
        else
            if (_151)
                _545 <= _530;
    end
    assign _546 = _545[7:7];
    assign _542 = _538[3:1];
    always @* begin
        case (_542)
        0:
            _554 <= _546;
        1:
            _554 <= _547;
        2:
            _554 <= _548;
        3:
            _554 <= _549;
        4:
            _554 <= _550;
        5:
            _554 <= _551;
        6:
            _554 <= _552;
        default:
            _554 <= _553;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _527 <= _811;
        else
            if (strobe)
                _527 <= _501;
    end
    always @(posedge clock) begin
        if (clear)
            _530 <= _811;
        else
            if (strobe)
                _530 <= _527;
    end
    always @(posedge clock) begin
        if (clear)
            _533 <= _811;
        else
            if (strobe)
                _533 <= _530;
    end
    always @(posedge clock) begin
        if (clear)
            _536 <= _811;
        else
            if (_151)
                _536 <= _533;
    end
    assign _537 = { gnd,
                    _536 };
    assign _524 = { gnd,
                    _101 };
    assign _538 = _524 - _537;
    assign _540 = _538 < _635;
    assign _541 = _45 & _540;
    assign _555 = _541 & _554;
    assign _725 = _555 ? _724 : _721;
    always @(posedge clock) begin
        if (clear)
            _728 <= _811;
        else
            _728 <= _725;
    end
    assign _521 = _513[0:0];
    assign _520 = _513[1:1];
    assign _519 = _513[2:2];
    assign _518 = _513[3:3];
    assign _517 = _513[4:4];
    assign _516 = _513[5:5];
    assign _515 = _513[6:6];
    always @(posedge clock) begin
        if (clear)
            _513 <= _811;
        else
            if (_151)
                _513 <= _498;
    end
    assign _514 = _513[7:7];
    assign _510 = _506[3:1];
    always @* begin
        case (_510)
        0:
            _522 <= _514;
        1:
            _522 <= _515;
        2:
            _522 <= _516;
        3:
            _522 <= _517;
        4:
            _522 <= _518;
        5:
            _522 <= _519;
        6:
            _522 <= _520;
        default:
            _522 <= _521;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _495 <= _811;
        else
            if (strobe)
                _495 <= _469;
    end
    always @(posedge clock) begin
        if (clear)
            _498 <= _811;
        else
            if (strobe)
                _498 <= _495;
    end
    always @(posedge clock) begin
        if (clear)
            _501 <= _811;
        else
            if (strobe)
                _501 <= _498;
    end
    always @(posedge clock) begin
        if (clear)
            _504 <= _811;
        else
            if (_151)
                _504 <= _501;
    end
    assign _505 = { gnd,
                    _504 };
    assign _492 = { gnd,
                    _104 };
    assign _506 = _492 - _505;
    assign _508 = _506 < _635;
    assign _509 = _48 & _508;
    assign _523 = _509 & _522;
    assign _732 = _523 ? _731 : _728;
    always @(posedge clock) begin
        if (clear)
            _735 <= _811;
        else
            _735 <= _732;
    end
    assign _489 = _481[0:0];
    assign _488 = _481[1:1];
    assign _487 = _481[2:2];
    assign _486 = _481[3:3];
    assign _485 = _481[4:4];
    assign _484 = _481[5:5];
    assign _483 = _481[6:6];
    always @(posedge clock) begin
        if (clear)
            _481 <= _811;
        else
            if (_151)
                _481 <= _466;
    end
    assign _482 = _481[7:7];
    assign _478 = _474[3:1];
    always @* begin
        case (_478)
        0:
            _490 <= _482;
        1:
            _490 <= _483;
        2:
            _490 <= _484;
        3:
            _490 <= _485;
        4:
            _490 <= _486;
        5:
            _490 <= _487;
        6:
            _490 <= _488;
        default:
            _490 <= _489;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _463 <= _811;
        else
            if (strobe)
                _463 <= _437;
    end
    always @(posedge clock) begin
        if (clear)
            _466 <= _811;
        else
            if (strobe)
                _466 <= _463;
    end
    always @(posedge clock) begin
        if (clear)
            _469 <= _811;
        else
            if (strobe)
                _469 <= _466;
    end
    always @(posedge clock) begin
        if (clear)
            _472 <= _811;
        else
            if (_151)
                _472 <= _469;
    end
    assign _473 = { gnd,
                    _472 };
    assign _460 = { gnd,
                    _107 };
    assign _474 = _460 - _473;
    assign _476 = _474 < _635;
    assign _477 = _51 & _476;
    assign _491 = _477 & _490;
    assign _739 = _491 ? _738 : _735;
    always @(posedge clock) begin
        if (clear)
            _742 <= _811;
        else
            _742 <= _739;
    end
    assign _457 = _449[0:0];
    assign _456 = _449[1:1];
    assign _455 = _449[2:2];
    assign _454 = _449[3:3];
    assign _453 = _449[4:4];
    assign _452 = _449[5:5];
    assign _451 = _449[6:6];
    always @(posedge clock) begin
        if (clear)
            _449 <= _811;
        else
            if (_151)
                _449 <= _434;
    end
    assign _450 = _449[7:7];
    assign _446 = _442[3:1];
    always @* begin
        case (_446)
        0:
            _458 <= _450;
        1:
            _458 <= _451;
        2:
            _458 <= _452;
        3:
            _458 <= _453;
        4:
            _458 <= _454;
        5:
            _458 <= _455;
        6:
            _458 <= _456;
        default:
            _458 <= _457;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _431 <= _811;
        else
            if (strobe)
                _431 <= _405;
    end
    always @(posedge clock) begin
        if (clear)
            _434 <= _811;
        else
            if (strobe)
                _434 <= _431;
    end
    always @(posedge clock) begin
        if (clear)
            _437 <= _811;
        else
            if (strobe)
                _437 <= _434;
    end
    always @(posedge clock) begin
        if (clear)
            _440 <= _811;
        else
            if (_151)
                _440 <= _437;
    end
    assign _441 = { gnd,
                    _440 };
    assign _428 = { gnd,
                    _110 };
    assign _442 = _428 - _441;
    assign _444 = _442 < _635;
    assign _445 = _54 & _444;
    assign _459 = _445 & _458;
    assign _746 = _459 ? _745 : _742;
    always @(posedge clock) begin
        if (clear)
            _749 <= _811;
        else
            _749 <= _746;
    end
    assign _425 = _417[0:0];
    assign _424 = _417[1:1];
    assign _423 = _417[2:2];
    assign _422 = _417[3:3];
    assign _421 = _417[4:4];
    assign _420 = _417[5:5];
    assign _419 = _417[6:6];
    always @(posedge clock) begin
        if (clear)
            _417 <= _811;
        else
            if (_151)
                _417 <= _402;
    end
    assign _418 = _417[7:7];
    assign _414 = _410[3:1];
    always @* begin
        case (_414)
        0:
            _426 <= _418;
        1:
            _426 <= _419;
        2:
            _426 <= _420;
        3:
            _426 <= _421;
        4:
            _426 <= _422;
        5:
            _426 <= _423;
        6:
            _426 <= _424;
        default:
            _426 <= _425;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _399 <= _811;
        else
            if (strobe)
                _399 <= _373;
    end
    always @(posedge clock) begin
        if (clear)
            _402 <= _811;
        else
            if (strobe)
                _402 <= _399;
    end
    always @(posedge clock) begin
        if (clear)
            _405 <= _811;
        else
            if (strobe)
                _405 <= _402;
    end
    always @(posedge clock) begin
        if (clear)
            _408 <= _811;
        else
            if (_151)
                _408 <= _405;
    end
    assign _409 = { gnd,
                    _408 };
    assign _396 = { gnd,
                    _113 };
    assign _410 = _396 - _409;
    assign _412 = _410 < _635;
    assign _413 = _57 & _412;
    assign _427 = _413 & _426;
    assign _753 = _427 ? _752 : _749;
    always @(posedge clock) begin
        if (clear)
            _756 <= _811;
        else
            _756 <= _753;
    end
    assign _393 = _385[0:0];
    assign _392 = _385[1:1];
    assign _391 = _385[2:2];
    assign _390 = _385[3:3];
    assign _389 = _385[4:4];
    assign _388 = _385[5:5];
    assign _387 = _385[6:6];
    always @(posedge clock) begin
        if (clear)
            _385 <= _811;
        else
            if (_151)
                _385 <= _370;
    end
    assign _386 = _385[7:7];
    assign _382 = _378[3:1];
    always @* begin
        case (_382)
        0:
            _394 <= _386;
        1:
            _394 <= _387;
        2:
            _394 <= _388;
        3:
            _394 <= _389;
        4:
            _394 <= _390;
        5:
            _394 <= _391;
        6:
            _394 <= _392;
        default:
            _394 <= _393;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _367 <= _811;
        else
            if (strobe)
                _367 <= _341;
    end
    always @(posedge clock) begin
        if (clear)
            _370 <= _811;
        else
            if (strobe)
                _370 <= _367;
    end
    always @(posedge clock) begin
        if (clear)
            _373 <= _811;
        else
            if (strobe)
                _373 <= _370;
    end
    always @(posedge clock) begin
        if (clear)
            _376 <= _811;
        else
            if (_151)
                _376 <= _373;
    end
    assign _377 = { gnd,
                    _376 };
    assign _364 = { gnd,
                    _116 };
    assign _378 = _364 - _377;
    assign _380 = _378 < _635;
    assign _381 = _60 & _380;
    assign _395 = _381 & _394;
    assign _760 = _395 ? _759 : _756;
    always @(posedge clock) begin
        if (clear)
            _763 <= _811;
        else
            _763 <= _760;
    end
    assign _361 = _353[0:0];
    assign _360 = _353[1:1];
    assign _359 = _353[2:2];
    assign _358 = _353[3:3];
    assign _357 = _353[4:4];
    assign _356 = _353[5:5];
    assign _355 = _353[6:6];
    always @(posedge clock) begin
        if (clear)
            _353 <= _811;
        else
            if (_151)
                _353 <= _338;
    end
    assign _354 = _353[7:7];
    assign _350 = _346[3:1];
    always @* begin
        case (_350)
        0:
            _362 <= _354;
        1:
            _362 <= _355;
        2:
            _362 <= _356;
        3:
            _362 <= _357;
        4:
            _362 <= _358;
        5:
            _362 <= _359;
        6:
            _362 <= _360;
        default:
            _362 <= _361;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _335 <= _811;
        else
            if (strobe)
                _335 <= _309;
    end
    always @(posedge clock) begin
        if (clear)
            _338 <= _811;
        else
            if (strobe)
                _338 <= _335;
    end
    always @(posedge clock) begin
        if (clear)
            _341 <= _811;
        else
            if (strobe)
                _341 <= _338;
    end
    always @(posedge clock) begin
        if (clear)
            _344 <= _811;
        else
            if (_151)
                _344 <= _341;
    end
    assign _345 = { gnd,
                    _344 };
    assign _332 = { gnd,
                    _119 };
    assign _346 = _332 - _345;
    assign _348 = _346 < _635;
    assign _349 = _63 & _348;
    assign _363 = _349 & _362;
    assign _767 = _363 ? _766 : _763;
    always @(posedge clock) begin
        if (clear)
            _770 <= _811;
        else
            _770 <= _767;
    end
    assign _329 = _321[0:0];
    assign _328 = _321[1:1];
    assign _327 = _321[2:2];
    assign _326 = _321[3:3];
    assign _325 = _321[4:4];
    assign _324 = _321[5:5];
    assign _323 = _321[6:6];
    always @(posedge clock) begin
        if (clear)
            _321 <= _811;
        else
            if (_151)
                _321 <= _306;
    end
    assign _322 = _321[7:7];
    assign _318 = _314[3:1];
    always @* begin
        case (_318)
        0:
            _330 <= _322;
        1:
            _330 <= _323;
        2:
            _330 <= _324;
        3:
            _330 <= _325;
        4:
            _330 <= _326;
        5:
            _330 <= _327;
        6:
            _330 <= _328;
        default:
            _330 <= _329;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _303 <= _811;
        else
            if (strobe)
                _303 <= _277;
    end
    always @(posedge clock) begin
        if (clear)
            _306 <= _811;
        else
            if (strobe)
                _306 <= _303;
    end
    always @(posedge clock) begin
        if (clear)
            _309 <= _811;
        else
            if (strobe)
                _309 <= _306;
    end
    always @(posedge clock) begin
        if (clear)
            _312 <= _811;
        else
            if (_151)
                _312 <= _309;
    end
    assign _313 = { gnd,
                    _312 };
    assign _300 = { gnd,
                    _122 };
    assign _314 = _300 - _313;
    assign _316 = _314 < _635;
    assign _317 = _66 & _316;
    assign _331 = _317 & _330;
    assign _774 = _331 ? _773 : _770;
    always @(posedge clock) begin
        if (clear)
            _777 <= _811;
        else
            _777 <= _774;
    end
    assign _297 = _289[0:0];
    assign _296 = _289[1:1];
    assign _295 = _289[2:2];
    assign _294 = _289[3:3];
    assign _293 = _289[4:4];
    assign _292 = _289[5:5];
    assign _291 = _289[6:6];
    always @(posedge clock) begin
        if (clear)
            _289 <= _811;
        else
            if (_151)
                _289 <= _274;
    end
    assign _290 = _289[7:7];
    assign _286 = _282[3:1];
    always @* begin
        case (_286)
        0:
            _298 <= _290;
        1:
            _298 <= _291;
        2:
            _298 <= _292;
        3:
            _298 <= _293;
        4:
            _298 <= _294;
        5:
            _298 <= _295;
        6:
            _298 <= _296;
        default:
            _298 <= _297;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _271 <= _811;
        else
            if (strobe)
                _271 <= _245;
    end
    always @(posedge clock) begin
        if (clear)
            _274 <= _811;
        else
            if (strobe)
                _274 <= _271;
    end
    always @(posedge clock) begin
        if (clear)
            _277 <= _811;
        else
            if (strobe)
                _277 <= _274;
    end
    always @(posedge clock) begin
        if (clear)
            _280 <= _811;
        else
            if (_151)
                _280 <= _277;
    end
    assign _281 = { gnd,
                    _280 };
    assign _268 = { gnd,
                    _125 };
    assign _282 = _268 - _281;
    assign _284 = _282 < _635;
    assign _285 = _69 & _284;
    assign _299 = _285 & _298;
    assign _781 = _299 ? _780 : _777;
    always @(posedge clock) begin
        if (clear)
            _784 <= _811;
        else
            _784 <= _781;
    end
    assign _265 = _257[0:0];
    assign _264 = _257[1:1];
    assign _263 = _257[2:2];
    assign _262 = _257[3:3];
    assign _261 = _257[4:4];
    assign _260 = _257[5:5];
    assign _259 = _257[6:6];
    always @(posedge clock) begin
        if (clear)
            _257 <= _811;
        else
            if (_151)
                _257 <= _242;
    end
    assign _258 = _257[7:7];
    assign _254 = _250[3:1];
    always @* begin
        case (_254)
        0:
            _266 <= _258;
        1:
            _266 <= _259;
        2:
            _266 <= _260;
        3:
            _266 <= _261;
        4:
            _266 <= _262;
        5:
            _266 <= _263;
        6:
            _266 <= _264;
        default:
            _266 <= _265;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _239 <= _811;
        else
            if (strobe)
                _239 <= _213;
    end
    always @(posedge clock) begin
        if (clear)
            _242 <= _811;
        else
            if (strobe)
                _242 <= _239;
    end
    always @(posedge clock) begin
        if (clear)
            _245 <= _811;
        else
            if (strobe)
                _245 <= _242;
    end
    always @(posedge clock) begin
        if (clear)
            _248 <= _811;
        else
            if (_151)
                _248 <= _245;
    end
    assign _249 = { gnd,
                    _248 };
    assign _236 = { gnd,
                    _128 };
    assign _250 = _236 - _249;
    assign _252 = _250 < _635;
    assign _253 = _72 & _252;
    assign _267 = _253 & _266;
    assign _788 = _267 ? _787 : _784;
    always @(posedge clock) begin
        if (clear)
            _791 <= _811;
        else
            _791 <= _788;
    end
    assign _233 = _225[0:0];
    assign _232 = _225[1:1];
    assign _231 = _225[2:2];
    assign _230 = _225[3:3];
    assign _229 = _225[4:4];
    assign _228 = _225[5:5];
    assign _227 = _225[6:6];
    always @(posedge clock) begin
        if (clear)
            _225 <= _811;
        else
            if (_151)
                _225 <= _210;
    end
    assign _226 = _225[7:7];
    assign _222 = _218[3:1];
    always @* begin
        case (_222)
        0:
            _234 <= _226;
        1:
            _234 <= _227;
        2:
            _234 <= _228;
        3:
            _234 <= _229;
        4:
            _234 <= _230;
        5:
            _234 <= _231;
        6:
            _234 <= _232;
        default:
            _234 <= _233;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _207 <= _811;
        else
            if (strobe)
                _207 <= _181;
    end
    always @(posedge clock) begin
        if (clear)
            _210 <= _811;
        else
            if (strobe)
                _210 <= _207;
    end
    always @(posedge clock) begin
        if (clear)
            _213 <= _811;
        else
            if (strobe)
                _213 <= _210;
    end
    always @(posedge clock) begin
        if (clear)
            _216 <= _811;
        else
            if (_151)
                _216 <= _213;
    end
    assign _217 = { gnd,
                    _216 };
    assign _204 = { gnd,
                    _131 };
    assign _218 = _204 - _217;
    assign _220 = _218 < _635;
    assign _221 = _75 & _220;
    assign _235 = _221 & _234;
    assign _795 = _235 ? _794 : _791;
    always @(posedge clock) begin
        if (clear)
            _798 <= _811;
        else
            _798 <= _795;
    end
    assign _201 = _193[0:0];
    assign _200 = _193[1:1];
    assign _199 = _193[2:2];
    assign _198 = _193[3:3];
    assign _197 = _193[4:4];
    assign _196 = _193[5:5];
    assign _195 = _193[6:6];
    always @(posedge clock) begin
        if (clear)
            _193 <= _811;
        else
            if (_151)
                _193 <= _178;
    end
    assign _194 = _193[7:7];
    assign _190 = _186[3:1];
    always @* begin
        case (_190)
        0:
            _202 <= _194;
        1:
            _202 <= _195;
        2:
            _202 <= _196;
        3:
            _202 <= _197;
        4:
            _202 <= _198;
        5:
            _202 <= _199;
        6:
            _202 <= _200;
        default:
            _202 <= _201;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _175 <= _811;
        else
            if (strobe)
                _175 <= _147;
    end
    always @(posedge clock) begin
        if (clear)
            _178 <= _811;
        else
            if (strobe)
                _178 <= _175;
    end
    always @(posedge clock) begin
        if (clear)
            _181 <= _811;
        else
            if (strobe)
                _181 <= _178;
    end
    always @(posedge clock) begin
        if (clear)
            _184 <= _811;
        else
            if (_151)
                _184 <= _181;
    end
    assign _185 = { gnd,
                    _184 };
    assign _172 = { gnd,
                    _134 };
    assign _186 = _172 - _185;
    assign _188 = _186 < _635;
    assign _189 = _78 & _188;
    assign _203 = _189 & _202;
    assign _802 = _203 ? _801 : _798;
    always @(posedge clock) begin
        if (clear)
            _805 <= _811;
        else
            _805 <= _802;
    end
    assign _169 = _161[0:0];
    assign _168 = _161[1:1];
    assign _167 = _161[2:2];
    assign _166 = _161[3:3];
    assign _165 = _161[4:4];
    assign _164 = _161[5:5];
    assign _163 = _161[6:6];
    always @(posedge clock) begin
        if (clear)
            _161 <= _811;
        else
            if (_151)
                _161 <= _144;
    end
    assign _162 = _161[7:7];
    assign _158 = _154[3:1];
    always @* begin
        case (_158)
        0:
            _170 <= _162;
        1:
            _170 <= _163;
        2:
            _170 <= _164;
        3:
            _170 <= _165;
        4:
            _170 <= _166;
        5:
            _170 <= _167;
        6:
            _170 <= _168;
        default:
            _170 <= _169;
        endcase
    end
    assign _150 = 12'b000000000000;
    assign _151 = _27 == _150;
    always @(posedge clock) begin
        if (clear)
            _141 <= _811;
        else
            if (strobe)
                _141 <= din;
    end
    always @(posedge clock) begin
        if (clear)
            _144 <= _811;
        else
            if (strobe)
                _144 <= _141;
    end
    always @(posedge clock) begin
        if (clear)
            _147 <= _811;
        else
            if (strobe)
                _147 <= _144;
    end
    always @(posedge clock) begin
        if (clear)
            _152 <= _811;
        else
            if (_151)
                _152 <= _147;
    end
    assign _153 = { gnd,
                    _152 };
    assign _89 = _88[7:0];
    always @(posedge clock) begin
        if (clear)
            _92 <= _811;
        else
            _92 <= _89;
    end
    always @(posedge clock) begin
        if (clear)
            _95 <= _811;
        else
            _95 <= _92;
    end
    always @(posedge clock) begin
        if (clear)
            _98 <= _811;
        else
            _98 <= _95;
    end
    always @(posedge clock) begin
        if (clear)
            _101 <= _811;
        else
            _101 <= _98;
    end
    always @(posedge clock) begin
        if (clear)
            _104 <= _811;
        else
            _104 <= _101;
    end
    always @(posedge clock) begin
        if (clear)
            _107 <= _811;
        else
            _107 <= _104;
    end
    always @(posedge clock) begin
        if (clear)
            _110 <= _811;
        else
            _110 <= _107;
    end
    always @(posedge clock) begin
        if (clear)
            _113 <= _811;
        else
            _113 <= _110;
    end
    always @(posedge clock) begin
        if (clear)
            _116 <= _811;
        else
            _116 <= _113;
    end
    always @(posedge clock) begin
        if (clear)
            _119 <= _811;
        else
            _119 <= _116;
    end
    always @(posedge clock) begin
        if (clear)
            _122 <= _811;
        else
            _122 <= _119;
    end
    always @(posedge clock) begin
        if (clear)
            _125 <= _811;
        else
            _125 <= _122;
    end
    always @(posedge clock) begin
        if (clear)
            _128 <= _811;
        else
            _128 <= _125;
    end
    always @(posedge clock) begin
        if (clear)
            _131 <= _811;
        else
            _131 <= _128;
    end
    always @(posedge clock) begin
        if (clear)
            _134 <= _811;
        else
            _134 <= _131;
    end
    always @(posedge clock) begin
        if (clear)
            _137 <= _811;
        else
            _137 <= _134;
    end
    assign _138 = { gnd,
                    _137 };
    assign _154 = _138 - _153;
    assign _156 = _154 < _635;
    assign _157 = _81 & _156;
    assign _171 = _157 & _170;
    assign _809 = _171 ? _808 : _805;
    always @(posedge clock) begin
        if (clear)
            _812 <= _811;
        else
            _812 <= _809;
    end
    assign _979 = _812[3:0];
    assign _980 = _981 < _979;
    assign _982 = _980 ? _981 : _979;
    assign _984 = _982 + _867;
    assign gnd = 1'b0;
    assign _947 = 9'b011111111;
    assign _87 = 9'b000000000;
    assign _934 = 9'b000000001;
    assign _935 = _88 + _934;
    assign _936 = _897 ? _935 : _88;
    assign _937 = _33 ? _936 : _88;
    assign _939 = _892 ? _87 : _937;
    assign _14 = _939;
    always @(posedge clock) begin
        if (clear)
            _88 <= _87;
        else
            _88 <= _14;
    end
    assign _948 = _88 == _947;
    assign _949 = _948 ? gnd : _33;
    assign _896 = 4'b1001;
    assign _941 = _895 + _848;
    assign _943 = _897 ? _814 : _941;
    assign _944 = _33 ? _943 : _895;
    assign _946 = _892 ? _814 : _944;
    assign _15 = _946;
    always @(posedge clock) begin
        if (clear)
            _895 <= _814;
        else
            _895 <= _15;
    end
    assign _897 = _895 == _896;
    assign _950 = _897 ? _949 : _33;
    assign _951 = _33 ? _950 : _33;
    assign _890 = 12'b001010000100;
    assign _891 = _27 == _890;
    assign _887 = 9'b100011000;
    assign _888 = _30 < _887;
    assign _884 = 9'b000101000;
    assign _885 = _30 < _884;
    assign _886 = ~ _885;
    assign _889 = _886 & _888;
    assign _892 = _889 & _891;
    assign _952 = _892 ? vdd : _951;
    assign _16 = _952;
    always @(posedge clock) begin
        if (clear)
            _33 <= _819;
        else
            _33 <= _16;
    end
    always @(posedge clock) begin
        if (clear)
            _36 <= _819;
        else
            _36 <= _33;
    end
    always @(posedge clock) begin
        if (clear)
            _39 <= _819;
        else
            _39 <= _36;
    end
    always @(posedge clock) begin
        if (clear)
            _42 <= _819;
        else
            _42 <= _39;
    end
    always @(posedge clock) begin
        if (clear)
            _45 <= _819;
        else
            _45 <= _42;
    end
    always @(posedge clock) begin
        if (clear)
            _48 <= _819;
        else
            _48 <= _45;
    end
    always @(posedge clock) begin
        if (clear)
            _51 <= _819;
        else
            _51 <= _48;
    end
    always @(posedge clock) begin
        if (clear)
            _54 <= _819;
        else
            _54 <= _51;
    end
    always @(posedge clock) begin
        if (clear)
            _57 <= _819;
        else
            _57 <= _54;
    end
    always @(posedge clock) begin
        if (clear)
            _60 <= _819;
        else
            _60 <= _57;
    end
    always @(posedge clock) begin
        if (clear)
            _63 <= _819;
        else
            _63 <= _60;
    end
    always @(posedge clock) begin
        if (clear)
            _66 <= _819;
        else
            _66 <= _63;
    end
    always @(posedge clock) begin
        if (clear)
            _69 <= _819;
        else
            _69 <= _66;
    end
    always @(posedge clock) begin
        if (clear)
            _72 <= _819;
        else
            _72 <= _69;
    end
    always @(posedge clock) begin
        if (clear)
            _75 <= _819;
        else
            _75 <= _72;
    end
    always @(posedge clock) begin
        if (clear)
            _78 <= _819;
        else
            _78 <= _75;
    end
    always @(posedge clock) begin
        if (clear)
            _81 <= _819;
        else
            _81 <= _78;
    end
    always @(posedge clock) begin
        if (clear)
            _84 <= _819;
        else
            _84 <= _81;
    end
    assign _985 = _84 ? _984 : _867;
    assign _972 = 12'b110001010011;
    assign _973 = _27 < _972;
    assign _969 = 12'b011010100110;
    assign _970 = _27 < _969;
    assign _971 = ~ _970;
    assign _974 = _971 & _973;
    assign _967 = 12'b010110101100;
    assign _968 = _27 < _967;
    assign _975 = _968 | _974;
    assign _965 = 12'b000011111010;
    assign _966 = _27 < _965;
    assign _821 = 9'b000000011;
    assign _28 = 12'b110101001100;
    assign vdd = 1'b1;
    assign _955 = 12'b000000000001;
    assign _956 = _27 + _955;
    assign _954 = _27 == _28;
    assign _958 = _954 ? _150 : _956;
    assign _17 = _958;
    always @(posedge clock) begin
        if (clear)
            _27 <= _150;
        else
            _27 <= _17;
    end
    assign _29 = _27 == _28;
    assign _962 = _30 + _934;
    assign _959 = 9'b100110111;
    assign _960 = _30 == _959;
    assign _964 = _960 ? _87 : _962;
    assign _20 = _964;
    always @(posedge clock) begin
        if (clear)
            _30 <= _87;
        else
            if (_29)
                _30 <= _20;
    end
    assign _822 = _30 < _821;
    assign _976 = _822 ? _975 : _966;
    assign _987 = _976 ? _814 : _985;
    always @(posedge clock) begin
        if (clear)
            _990 <= _814;
        else
            _990 <= _987;
    end
    assign luma = _990;
    assign chroma = _883;
    assign chroma_oe = _834;
    assign chroma2_oe = _820;
    assign line_start = _151;
    assign pix_col = _812;
    assign pix_valid = _84;
    assign hcount = _27;
    assign vcount = _30;

endmodule
