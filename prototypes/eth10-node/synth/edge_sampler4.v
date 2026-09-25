module edge_sampler4 (
    invert,
    period,
    offset,
    holdoff,
    mode,
    timeout,
    clear,
    clock,
    samples,
    active,
    bit,
    valid,
    burst_end,
    overrun,
    in_burst
);

    input invert;
    input [7:0] period;
    input [7:0] offset;
    input [9:0] holdoff;
    input [1:0] mode;
    input [9:0] timeout;
    input clear;
    input clock;
    input [3:0] samples;
    input active;
    output bit;
    output valid;
    output burst_end;
    output overrun;
    output in_burst;

    wire _185;
    wire _182;
    wire _138;
    wire _95;
    wire _139;
    wire _183;
    reg _186;
    wire _196;
    wire _190;
    wire _188;
    wire _187;
    wire _189;
    wire _191;
    wire _197;
    reg _200;
    wire _164;
    wire _178;
    wire _179;
    wire _180;
    wire _201;
    reg _204;
    wire [1:0] _261;
    wire _262;
    wire _263;
    wire _264;
    wire _265;
    wire _257;
    wire _258;
    wire _259;
    wire _260;
    wire _266;
    wire _252;
    wire _253;
    wire _254;
    wire _255;
    wire _267;
    wire _220;
    wire _221;
    wire _222;
    wire _215;
    wire _216;
    wire _217;
    wire _210;
    wire _211;
    wire _212;
    wire _225;
    wire _226;
    wire _227;
    wire gnd;
    wire _224;
    wire _228;
    wire _6;
    reg _207;
    wire _209;
    wire _213;
    wire _214;
    wire _218;
    wire _219;
    wire _223;
    wire _247;
    wire _248;
    wire _249;
    wire _250;
    wire _120;
    wire _134;
    wire _135;
    wire _136;
    wire _69;
    wire _88;
    wire _89;
    wire _90;
    wire [7:0] _74;
    wire [7:0] _71;
    wire [7:0] _233;
    wire _231;
    wire [7:0] _235;
    wire _177;
    wire [7:0] _236;
    wire [7:0] _237;
    wire [7:0] _238;
    wire [7:0] _169;
    wire _167;
    wire [7:0] _171;
    wire _133;
    wire [7:0] _172;
    wire [7:0] _173;
    wire [7:0] _174;
    wire [7:0] _125;
    wire _123;
    wire [7:0] _127;
    wire _87;
    wire [7:0] _128;
    wire [7:0] _129;
    wire [7:0] _130;
    wire [7:0] _79;
    wire _77;
    wire [7:0] _81;
    wire [7:0] _82;
    wire [7:0] _83;
    wire [7:0] _84;
    wire [7:0] _73;
    wire [7:0] _85;
    wire [7:0] _121;
    wire [7:0] _131;
    wire [7:0] _165;
    wire [7:0] _175;
    wire [7:0] _229;
    wire [7:0] _239;
    wire [7:0] _9;
    reg [7:0] _72;
    wire _75;
    wire _91;
    wire _92;
    wire _93;
    wire _195;
    wire _244;
    wire _143;
    wire _144;
    wire _99;
    wire _100;
    wire [9:0] _45;
    wire [9:0] _39;
    wire [9:0] _40;
    wire [9:0] _37;
    wire [9:0] _159;
    wire _157;
    wire [9:0] _160;
    wire _161;
    wire _162;
    wire _163;
    wire [9:0] _193;
    wire [1:0] _146;
    wire _147;
    wire [9:0] _194;
    wire [9:0] _115;
    wire _113;
    wire [9:0] _116;
    wire _117;
    wire _118;
    wire _119;
    wire [9:0] _141;
    wire _103;
    wire [9:0] _142;
    wire [9:0] _64;
    wire _62;
    wire [9:0] _65;
    wire _66;
    wire _67;
    wire _68;
    wire [9:0] _97;
    wire _52;
    wire [9:0] _98;
    wire [9:0] _59;
    wire [9:0] _60;
    wire _55;
    wire _56;
    wire _57;
    wire [9:0] _110;
    wire [9:0] _111;
    wire _106;
    wire _107;
    wire _108;
    wire [9:0] _154;
    wire [9:0] _155;
    wire _150;
    wire _151;
    wire _152;
    wire [9:0] _241;
    wire [9:0] _242;
    wire [9:0] _11;
    reg [9:0] _36;
    wire _38;
    wire [9:0] _41;
    wire _42;
    wire _43;
    wire _44;
    wire [9:0] _46;
    wire _33;
    wire [9:0] _47;
    wire _48;
    wire _49;
    wire vdd;
    wire _148;
    wire _104;
    wire _53;
    wire _54;
    wire _105;
    wire _149;
    wire _243;
    wire _16;
    reg _28;
    wire _25;
    wire _29;
    wire _30;
    wire _31;
    wire _50;
    wire _101;
    wire _145;
    wire _245;
    wire _19;
    reg _24;
    wire _94;
    wire _137;
    wire _181;
    wire _268;
    reg _271;
    assign _185 = 1'b0;
    assign _182 = _180 & _181;
    assign _138 = _136 & _137;
    assign _95 = _90 & _94;
    assign _139 = _95 | _138;
    assign _183 = _139 | _182;
    always @(posedge clock) begin
        if (clear)
            _186 <= _185;
        else
            _186 <= _183;
    end
    assign _196 = _145 & _195;
    assign _190 = _101 & _143;
    assign _188 = _50 & _99;
    assign _187 = _24 & _48;
    assign _189 = _187 | _188;
    assign _191 = _189 | _190;
    assign _197 = _191 | _196;
    always @(posedge clock) begin
        if (clear)
            _200 <= _185;
        else
            _200 <= _197;
    end
    assign _164 = ~ _163;
    assign _178 = _164 & _177;
    assign _179 = _147 ? _178 : _163;
    assign _180 = _145 & _179;
    assign _201 = _181 | _180;
    always @(posedge clock) begin
        if (clear)
            _204 <= _185;
        else
            _204 <= _201;
    end
    assign _261 = 2'b00;
    assign _262 = mode == _261;
    assign _263 = _262 ? _25 : _207;
    assign _264 = _33 ? _25 : _263;
    assign _265 = _264 ^ invert;
    assign _257 = mode == _261;
    assign _258 = _257 ? _53 : _213;
    assign _259 = _52 ? _53 : _258;
    assign _260 = _259 ^ invert;
    assign _266 = _94 ? _265 : _260;
    assign _252 = mode == _261;
    assign _253 = _252 ? _104 : _218;
    assign _254 = _103 ? _104 : _253;
    assign _255 = _254 ^ invert;
    assign _267 = _137 ? _266 : _255;
    assign _220 = _218 | _108;
    assign _221 = _119 ? gnd : _220;
    assign _222 = _103 ? _218 : _221;
    assign _215 = _213 | _57;
    assign _216 = _68 ? gnd : _215;
    assign _217 = _52 ? _213 : _216;
    assign _210 = _207 | _31;
    assign _211 = _44 ? gnd : _210;
    assign _212 = _33 ? _207 : _211;
    assign _225 = _223 | _152;
    assign _226 = _163 ? gnd : _225;
    assign _227 = _147 ? _223 : _226;
    assign gnd = 1'b0;
    assign _224 = _152 ? gnd : _223;
    assign _228 = _145 ? _227 : _224;
    assign _6 = _228;
    always @(posedge clock) begin
        if (clear)
            _207 <= _185;
        else
            _207 <= _6;
    end
    assign _209 = _31 ? gnd : _207;
    assign _213 = _24 ? _212 : _209;
    assign _214 = _57 ? gnd : _213;
    assign _218 = _50 ? _217 : _214;
    assign _219 = _108 ? gnd : _218;
    assign _223 = _101 ? _222 : _219;
    assign _247 = mode == _261;
    assign _248 = _247 ? _148 : _223;
    assign _249 = _147 ? _148 : _248;
    assign _250 = _249 ^ invert;
    assign _120 = ~ _119;
    assign _134 = _120 & _133;
    assign _135 = _103 ? _134 : _119;
    assign _136 = _101 & _135;
    assign _69 = ~ _68;
    assign _88 = _69 & _87;
    assign _89 = _52 ? _88 : _68;
    assign _90 = _50 & _89;
    assign _74 = 8'b00000001;
    assign _71 = 8'b00000000;
    assign _233 = _175 - _74;
    assign _231 = _175 == _71;
    assign _235 = _231 ? _71 : _233;
    assign _177 = _175 == _74;
    assign _236 = _177 ? period : _235;
    assign _237 = _163 ? offset : _236;
    assign _238 = _147 ? _237 : _175;
    assign _169 = _131 - _74;
    assign _167 = _131 == _71;
    assign _171 = _167 ? _71 : _169;
    assign _133 = _131 == _74;
    assign _172 = _133 ? period : _171;
    assign _173 = _119 ? offset : _172;
    assign _174 = _103 ? _173 : _131;
    assign _125 = _85 - _74;
    assign _123 = _85 == _71;
    assign _127 = _123 ? _71 : _125;
    assign _87 = _85 == _74;
    assign _128 = _87 ? period : _127;
    assign _129 = _68 ? offset : _128;
    assign _130 = _52 ? _129 : _85;
    assign _79 = _72 - _74;
    assign _77 = _72 == _71;
    assign _81 = _77 ? _71 : _79;
    assign _82 = _75 ? period : _81;
    assign _83 = _44 ? offset : _82;
    assign _84 = _33 ? _83 : _72;
    assign _73 = _31 ? offset : _72;
    assign _85 = _24 ? _84 : _73;
    assign _121 = _57 ? offset : _85;
    assign _131 = _50 ? _130 : _121;
    assign _165 = _108 ? offset : _131;
    assign _175 = _101 ? _174 : _165;
    assign _229 = _152 ? offset : _175;
    assign _239 = _145 ? _238 : _229;
    assign _9 = _239;
    always @(posedge clock) begin
        if (clear)
            _72 <= _71;
        else
            _72 <= _9;
    end
    assign _75 = _72 == _74;
    assign _91 = ~ _44;
    assign _92 = _91 & _75;
    assign _93 = _33 ? _92 : _44;
    assign _195 = timeout < _194;
    assign _244 = ~ _195;
    assign _143 = timeout < _142;
    assign _144 = ~ _143;
    assign _99 = timeout < _98;
    assign _100 = ~ _99;
    assign _45 = 10'b0000000000;
    assign _39 = 10'b0000000001;
    assign _40 = _36 + _39;
    assign _37 = 10'b1111111111;
    assign _159 = _155 + _39;
    assign _157 = _155 == _37;
    assign _160 = _157 ? _155 : _159;
    assign _161 = _160 < holdoff;
    assign _162 = ~ _161;
    assign _163 = _152 & _162;
    assign _193 = _163 ? _45 : _160;
    assign _146 = 2'b10;
    assign _147 = mode == _146;
    assign _194 = _147 ? _193 : _193;
    assign _115 = _111 + _39;
    assign _113 = _111 == _37;
    assign _116 = _113 ? _111 : _115;
    assign _117 = _116 < holdoff;
    assign _118 = ~ _117;
    assign _119 = _108 & _118;
    assign _141 = _119 ? _45 : _116;
    assign _103 = mode == _146;
    assign _142 = _103 ? _141 : _141;
    assign _64 = _60 + _39;
    assign _62 = _60 == _37;
    assign _65 = _62 ? _60 : _64;
    assign _66 = _65 < holdoff;
    assign _67 = ~ _66;
    assign _68 = _57 & _67;
    assign _97 = _68 ? _45 : _65;
    assign _52 = mode == _146;
    assign _98 = _52 ? _97 : _97;
    assign _59 = _31 ? _45 : _36;
    assign _60 = _24 ? _47 : _59;
    assign _55 = _53 == _54;
    assign _56 = ~ _55;
    assign _57 = active & _56;
    assign _110 = _57 ? _45 : _60;
    assign _111 = _50 ? _98 : _110;
    assign _106 = _104 == _105;
    assign _107 = ~ _106;
    assign _108 = active & _107;
    assign _154 = _108 ? _45 : _111;
    assign _155 = _101 ? _142 : _154;
    assign _150 = _148 == _149;
    assign _151 = ~ _150;
    assign _152 = active & _151;
    assign _241 = _152 ? _45 : _155;
    assign _242 = _145 ? _194 : _241;
    assign _11 = _242;
    always @(posedge clock) begin
        if (clear)
            _36 <= _45;
        else
            _36 <= _11;
    end
    assign _38 = _36 == _37;
    assign _41 = _38 ? _36 : _40;
    assign _42 = _41 < holdoff;
    assign _43 = ~ _42;
    assign _44 = _31 & _43;
    assign _46 = _44 ? _45 : _41;
    assign _33 = mode == _146;
    assign _47 = _33 ? _46 : _46;
    assign _48 = timeout < _47;
    assign _49 = ~ _48;
    assign vdd = 1'b1;
    assign _148 = samples[3:3];
    assign _104 = samples[2:2];
    assign _53 = samples[1:1];
    assign _54 = active ? _25 : _28;
    assign _105 = active ? _53 : _54;
    assign _149 = active ? _104 : _105;
    assign _243 = active ? _148 : _149;
    assign _16 = _243;
    always @(posedge clock) begin
        if (clear)
            _28 <= _185;
        else
            _28 <= _16;
    end
    assign _25 = samples[0:0];
    assign _29 = _25 == _28;
    assign _30 = ~ _29;
    assign _31 = active & _30;
    assign _50 = _24 ? _49 : _31;
    assign _101 = _50 ? _100 : _57;
    assign _145 = _101 ? _144 : _108;
    assign _245 = _145 ? _244 : _152;
    assign _19 = _245;
    always @(posedge clock) begin
        if (clear)
            _24 <= _185;
        else
            _24 <= _19;
    end
    assign _94 = _24 & _93;
    assign _137 = _94 | _90;
    assign _181 = _137 | _136;
    assign _268 = _181 ? _267 : _250;
    always @(posedge clock) begin
        if (clear)
            _271 <= _185;
        else
            _271 <= _268;
    end
    assign bit = _271;
    assign valid = _204;
    assign burst_end = _200;
    assign overrun = _186;
    assign in_burst = _24;

endmodule
