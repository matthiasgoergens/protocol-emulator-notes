module systolic_matcher (
    clear,
    x,
    cfg_shift,
    clock,
    cfg_in,
    y,
    hit
);

    input clear;
    input x;
    input cfg_shift;
    input clock;
    input cfg_in;
    output [4:0] y;
    output hit;

    wire _344;
    reg _327;
    reg _330;
    reg _333;
    reg _336;
    reg _339;
    wire [4:0] _340;
    wire _341;
    wire _342;
    reg _345;
    wire [4:0] _323;
    reg _317;
    reg _311;
    reg _314;
    wire _318;
    reg _308;
    wire _319;
    wire [3:0] _305;
    wire [4:0] _320;
    reg _297;
    reg _291;
    reg _294;
    wire _298;
    reg _288;
    wire _299;
    wire [4:0] _300;
    reg _277;
    reg _271;
    reg _274;
    wire _278;
    reg _268;
    wire _279;
    wire [4:0] _280;
    reg _257;
    reg _251;
    reg _254;
    wire _258;
    reg _248;
    wire _259;
    wire [4:0] _260;
    reg _237;
    reg _231;
    reg _234;
    wire _238;
    reg _228;
    wire _239;
    wire [4:0] _240;
    reg _217;
    reg _211;
    reg _214;
    wire _218;
    reg _208;
    wire _219;
    wire [4:0] _220;
    reg _197;
    reg _191;
    reg _194;
    wire _198;
    reg _188;
    wire _199;
    wire [4:0] _200;
    reg _177;
    reg _171;
    reg _174;
    wire _178;
    reg _168;
    wire _179;
    wire [4:0] _180;
    reg _157;
    reg _151;
    reg _154;
    wire _158;
    reg _148;
    wire _159;
    wire [4:0] _160;
    reg _137;
    reg _131;
    reg _134;
    wire _138;
    reg _128;
    wire _139;
    wire [4:0] _140;
    reg _117;
    reg _111;
    reg _114;
    wire _118;
    reg _108;
    wire _119;
    wire [4:0] _120;
    reg _97;
    reg _91;
    reg _94;
    wire _98;
    reg _88;
    wire _99;
    wire [4:0] _100;
    reg _77;
    reg _71;
    reg _74;
    wire _78;
    reg _68;
    wire _79;
    wire [4:0] _80;
    reg _57;
    reg _51;
    reg _54;
    wire _58;
    reg _48;
    wire _59;
    wire [4:0] _60;
    reg _37;
    reg _31;
    reg _34;
    wire _38;
    reg _28;
    wire _39;
    wire [4:0] _40;
    reg _18;
    wire vdd;
    reg _15;
    wire _19;
    reg _11;
    wire _20;
    wire [4:0] _21;
    reg [4:0] _24;
    wire [4:0] _41;
    reg [4:0] _44;
    wire [4:0] _61;
    reg [4:0] _64;
    wire [4:0] _81;
    reg [4:0] _84;
    wire [4:0] _101;
    reg [4:0] _104;
    wire [4:0] _121;
    reg [4:0] _124;
    wire [4:0] _141;
    reg [4:0] _144;
    wire [4:0] _161;
    reg [4:0] _164;
    wire [4:0] _181;
    reg [4:0] _184;
    wire [4:0] _201;
    reg [4:0] _204;
    wire [4:0] _221;
    reg [4:0] _224;
    wire [4:0] _241;
    reg [4:0] _244;
    wire [4:0] _261;
    reg [4:0] _264;
    wire [4:0] _281;
    reg [4:0] _284;
    wire [4:0] _301;
    reg [4:0] _304;
    wire [4:0] _321;
    reg [4:0] _324;
    assign _344 = 1'b0;
    always @(posedge clock) begin
        if (cfg_shift)
            _327 <= _317;
    end
    always @(posedge clock) begin
        if (cfg_shift)
            _330 <= _327;
    end
    always @(posedge clock) begin
        if (cfg_shift)
            _333 <= _330;
    end
    always @(posedge clock) begin
        if (cfg_shift)
            _336 <= _333;
    end
    always @(posedge clock) begin
        if (cfg_shift)
            _339 <= _336;
    end
    assign _340 = { _339,
                    _336,
                    _333,
                    _330,
                    _327 };
    assign _341 = _324 < _340;
    assign _342 = ~ _341;
    always @(posedge clock) begin
        if (clear)
            _345 <= _344;
        else
            _345 <= _342;
    end
    assign _323 = 5'b00000;
    always @(posedge clock) begin
        if (cfg_shift)
            _317 <= _308;
    end
    always @(posedge clock) begin
        if (clear)
            _311 <= _344;
        else
            _311 <= _294;
    end
    always @(posedge clock) begin
        if (clear)
            _314 <= _344;
        else
            _314 <= _311;
    end
    assign _318 = _314 == _317;
    always @(posedge clock) begin
        if (cfg_shift)
            _308 <= _297;
    end
    assign _319 = _308 & _318;
    assign _305 = 4'b0000;
    assign _320 = { _305,
                    _319 };
    always @(posedge clock) begin
        if (cfg_shift)
            _297 <= _288;
    end
    always @(posedge clock) begin
        if (clear)
            _291 <= _344;
        else
            _291 <= _274;
    end
    always @(posedge clock) begin
        if (clear)
            _294 <= _344;
        else
            _294 <= _291;
    end
    assign _298 = _294 == _297;
    always @(posedge clock) begin
        if (cfg_shift)
            _288 <= _277;
    end
    assign _299 = _288 & _298;
    assign _300 = { _305,
                    _299 };
    always @(posedge clock) begin
        if (cfg_shift)
            _277 <= _268;
    end
    always @(posedge clock) begin
        if (clear)
            _271 <= _344;
        else
            _271 <= _254;
    end
    always @(posedge clock) begin
        if (clear)
            _274 <= _344;
        else
            _274 <= _271;
    end
    assign _278 = _274 == _277;
    always @(posedge clock) begin
        if (cfg_shift)
            _268 <= _257;
    end
    assign _279 = _268 & _278;
    assign _280 = { _305,
                    _279 };
    always @(posedge clock) begin
        if (cfg_shift)
            _257 <= _248;
    end
    always @(posedge clock) begin
        if (clear)
            _251 <= _344;
        else
            _251 <= _234;
    end
    always @(posedge clock) begin
        if (clear)
            _254 <= _344;
        else
            _254 <= _251;
    end
    assign _258 = _254 == _257;
    always @(posedge clock) begin
        if (cfg_shift)
            _248 <= _237;
    end
    assign _259 = _248 & _258;
    assign _260 = { _305,
                    _259 };
    always @(posedge clock) begin
        if (cfg_shift)
            _237 <= _228;
    end
    always @(posedge clock) begin
        if (clear)
            _231 <= _344;
        else
            _231 <= _214;
    end
    always @(posedge clock) begin
        if (clear)
            _234 <= _344;
        else
            _234 <= _231;
    end
    assign _238 = _234 == _237;
    always @(posedge clock) begin
        if (cfg_shift)
            _228 <= _217;
    end
    assign _239 = _228 & _238;
    assign _240 = { _305,
                    _239 };
    always @(posedge clock) begin
        if (cfg_shift)
            _217 <= _208;
    end
    always @(posedge clock) begin
        if (clear)
            _211 <= _344;
        else
            _211 <= _194;
    end
    always @(posedge clock) begin
        if (clear)
            _214 <= _344;
        else
            _214 <= _211;
    end
    assign _218 = _214 == _217;
    always @(posedge clock) begin
        if (cfg_shift)
            _208 <= _197;
    end
    assign _219 = _208 & _218;
    assign _220 = { _305,
                    _219 };
    always @(posedge clock) begin
        if (cfg_shift)
            _197 <= _188;
    end
    always @(posedge clock) begin
        if (clear)
            _191 <= _344;
        else
            _191 <= _174;
    end
    always @(posedge clock) begin
        if (clear)
            _194 <= _344;
        else
            _194 <= _191;
    end
    assign _198 = _194 == _197;
    always @(posedge clock) begin
        if (cfg_shift)
            _188 <= _177;
    end
    assign _199 = _188 & _198;
    assign _200 = { _305,
                    _199 };
    always @(posedge clock) begin
        if (cfg_shift)
            _177 <= _168;
    end
    always @(posedge clock) begin
        if (clear)
            _171 <= _344;
        else
            _171 <= _154;
    end
    always @(posedge clock) begin
        if (clear)
            _174 <= _344;
        else
            _174 <= _171;
    end
    assign _178 = _174 == _177;
    always @(posedge clock) begin
        if (cfg_shift)
            _168 <= _157;
    end
    assign _179 = _168 & _178;
    assign _180 = { _305,
                    _179 };
    always @(posedge clock) begin
        if (cfg_shift)
            _157 <= _148;
    end
    always @(posedge clock) begin
        if (clear)
            _151 <= _344;
        else
            _151 <= _134;
    end
    always @(posedge clock) begin
        if (clear)
            _154 <= _344;
        else
            _154 <= _151;
    end
    assign _158 = _154 == _157;
    always @(posedge clock) begin
        if (cfg_shift)
            _148 <= _137;
    end
    assign _159 = _148 & _158;
    assign _160 = { _305,
                    _159 };
    always @(posedge clock) begin
        if (cfg_shift)
            _137 <= _128;
    end
    always @(posedge clock) begin
        if (clear)
            _131 <= _344;
        else
            _131 <= _114;
    end
    always @(posedge clock) begin
        if (clear)
            _134 <= _344;
        else
            _134 <= _131;
    end
    assign _138 = _134 == _137;
    always @(posedge clock) begin
        if (cfg_shift)
            _128 <= _117;
    end
    assign _139 = _128 & _138;
    assign _140 = { _305,
                    _139 };
    always @(posedge clock) begin
        if (cfg_shift)
            _117 <= _108;
    end
    always @(posedge clock) begin
        if (clear)
            _111 <= _344;
        else
            _111 <= _94;
    end
    always @(posedge clock) begin
        if (clear)
            _114 <= _344;
        else
            _114 <= _111;
    end
    assign _118 = _114 == _117;
    always @(posedge clock) begin
        if (cfg_shift)
            _108 <= _97;
    end
    assign _119 = _108 & _118;
    assign _120 = { _305,
                    _119 };
    always @(posedge clock) begin
        if (cfg_shift)
            _97 <= _88;
    end
    always @(posedge clock) begin
        if (clear)
            _91 <= _344;
        else
            _91 <= _74;
    end
    always @(posedge clock) begin
        if (clear)
            _94 <= _344;
        else
            _94 <= _91;
    end
    assign _98 = _94 == _97;
    always @(posedge clock) begin
        if (cfg_shift)
            _88 <= _77;
    end
    assign _99 = _88 & _98;
    assign _100 = { _305,
                    _99 };
    always @(posedge clock) begin
        if (cfg_shift)
            _77 <= _68;
    end
    always @(posedge clock) begin
        if (clear)
            _71 <= _344;
        else
            _71 <= _54;
    end
    always @(posedge clock) begin
        if (clear)
            _74 <= _344;
        else
            _74 <= _71;
    end
    assign _78 = _74 == _77;
    always @(posedge clock) begin
        if (cfg_shift)
            _68 <= _57;
    end
    assign _79 = _68 & _78;
    assign _80 = { _305,
                   _79 };
    always @(posedge clock) begin
        if (cfg_shift)
            _57 <= _48;
    end
    always @(posedge clock) begin
        if (clear)
            _51 <= _344;
        else
            _51 <= _34;
    end
    always @(posedge clock) begin
        if (clear)
            _54 <= _344;
        else
            _54 <= _51;
    end
    assign _58 = _54 == _57;
    always @(posedge clock) begin
        if (cfg_shift)
            _48 <= _37;
    end
    assign _59 = _48 & _58;
    assign _60 = { _305,
                   _59 };
    always @(posedge clock) begin
        if (cfg_shift)
            _37 <= _28;
    end
    always @(posedge clock) begin
        if (clear)
            _31 <= _344;
        else
            _31 <= _15;
    end
    always @(posedge clock) begin
        if (clear)
            _34 <= _344;
        else
            _34 <= _31;
    end
    assign _38 = _34 == _37;
    always @(posedge clock) begin
        if (cfg_shift)
            _28 <= _18;
    end
    assign _39 = _28 & _38;
    assign _40 = { _305,
                   _39 };
    always @(posedge clock) begin
        if (cfg_shift)
            _18 <= _11;
    end
    assign vdd = 1'b1;
    always @(posedge clock) begin
        if (clear)
            _15 <= _344;
        else
            _15 <= x;
    end
    assign _19 = _15 == _18;
    always @(posedge clock) begin
        if (cfg_shift)
            _11 <= cfg_in;
    end
    assign _20 = _11 & _19;
    assign _21 = { _305,
                   _20 };
    always @(posedge clock) begin
        if (clear)
            _24 <= _323;
        else
            _24 <= _21;
    end
    assign _41 = _24 + _40;
    always @(posedge clock) begin
        if (clear)
            _44 <= _323;
        else
            _44 <= _41;
    end
    assign _61 = _44 + _60;
    always @(posedge clock) begin
        if (clear)
            _64 <= _323;
        else
            _64 <= _61;
    end
    assign _81 = _64 + _80;
    always @(posedge clock) begin
        if (clear)
            _84 <= _323;
        else
            _84 <= _81;
    end
    assign _101 = _84 + _100;
    always @(posedge clock) begin
        if (clear)
            _104 <= _323;
        else
            _104 <= _101;
    end
    assign _121 = _104 + _120;
    always @(posedge clock) begin
        if (clear)
            _124 <= _323;
        else
            _124 <= _121;
    end
    assign _141 = _124 + _140;
    always @(posedge clock) begin
        if (clear)
            _144 <= _323;
        else
            _144 <= _141;
    end
    assign _161 = _144 + _160;
    always @(posedge clock) begin
        if (clear)
            _164 <= _323;
        else
            _164 <= _161;
    end
    assign _181 = _164 + _180;
    always @(posedge clock) begin
        if (clear)
            _184 <= _323;
        else
            _184 <= _181;
    end
    assign _201 = _184 + _200;
    always @(posedge clock) begin
        if (clear)
            _204 <= _323;
        else
            _204 <= _201;
    end
    assign _221 = _204 + _220;
    always @(posedge clock) begin
        if (clear)
            _224 <= _323;
        else
            _224 <= _221;
    end
    assign _241 = _224 + _240;
    always @(posedge clock) begin
        if (clear)
            _244 <= _323;
        else
            _244 <= _241;
    end
    assign _261 = _244 + _260;
    always @(posedge clock) begin
        if (clear)
            _264 <= _323;
        else
            _264 <= _261;
    end
    assign _281 = _264 + _280;
    always @(posedge clock) begin
        if (clear)
            _284 <= _323;
        else
            _284 <= _281;
    end
    assign _301 = _284 + _300;
    always @(posedge clock) begin
        if (clear)
            _304 <= _323;
        else
            _304 <= _301;
    end
    assign _321 = _304 + _320;
    always @(posedge clock) begin
        if (clear)
            _324 <= _323;
        else
            _324 <= _321;
    end
    assign y = _324;
    assign hit = _345;

endmodule
