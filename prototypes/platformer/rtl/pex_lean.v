module pex_lean (
    clear,
    data_in,
    cfg_strobe,
    clock,
    cfg_in,
    tag_in,
    tag_out,
    data_out,
    s,
    cfg_out
);

    input clear;
    input [15:0] data_in;
    input cfg_strobe;
    input clock;
    input [7:0] cfg_in;
    input [2:0] tag_in;
    output [2:0] tag_out;
    output [15:0] data_out;
    output [15:0] s;
    output [7:0] cfg_out;

    wire [15:0] _151;
    wire [7:0] _146;
    wire [7:0] _147;
    wire [2:0] _58;
    wire _59;
    wire [15:0] _60;
    wire [15:0] _61;
    wire [15:0] _3;
    reg [15:0] _54;
    wire [7:0] _144;
    wire [7:0] _145;
    wire [15:0] _148;
    wire [7:0] _139;
    wire [7:0] _137;
    wire [7:0] _136;
    wire [7:0] _138;
    wire _140;
    wire _141;
    wire _142;
    wire [7:0] _129;
    wire [7:0] _128;
    wire [7:0] _130;
    wire [31:0] _65;
    wire [15:0] _112;
    wire [31:0] _113;
    wire [15:0] _109;
    wire [31:0] _110;
    wire [2:0] _107;
    wire _108;
    wire [31:0] _111;
    wire [2:0] _105;
    wire _106;
    wire [31:0] _114;
    wire [29:0] _100;
    wire [1:0] _99;
    wire [31:0] _101;
    wire [29:0] _96;
    wire [31:0] _98;
    wire [31:0] _102;
    wire _91;
    wire [31:0] _103;
    wire [31:0] _104;
    wire [31:0] _115;
    wire [31:0] _4;
    reg [31:0] _66;
    wire [1:0] _126;
    wire [5:0] _125;
    wire [7:0] _127;
    wire [8:0] _93;
    wire [8:0] _118;
    wire [2:0] _116;
    wire _117;
    wire [8:0] _119;
    wire [8:0] _120;
    wire [8:0] _5;
    reg [8:0] _94;
    wire _95;
    wire [7:0] _131;
    wire _133;
    wire _134;
    wire _121;
    wire _122;
    wire _123;
    wire _124;
    wire _135;
    wire _143;
    wire [15:0] _149;
    wire [15:0] _6;
    reg [15:0] _152;
    wire _48;
    wire _229;
    wire _223;
    wire gnd;
    wire [15:0] _86;
    wire [15:0] _85;
    wire [15:0] _84;
    wire [15:0] _83;
    wire [15:0] _82;
    wire [15:0] _81;
    wire [15:0] _80;
    wire [15:0] _79;
    wire [15:0] _78;
    wire [15:0] _77;
    wire [15:0] _76;
    wire [15:0] _75;
    wire [15:0] _74;
    wire [15:0] _73;
    wire [15:0] _72;
    wire [3:0] _70;
    reg [15:0] _87;
    wire [2:0] _208;
    wire vdd;
    wire [2:0] _159;
    wire [2:0] _155;
    wire _156;
    wire _157;
    wire [2:0] _160;
    wire [1:0] _153;
    wire _154;
    wire [2:0] _162;
    wire [2:0] _163;
    wire [2:0] _9;
    reg [2:0] _57;
    wire _209;
    wire [15:0] _210;
    wire [15:0] _204;
    wire _202;
    wire [15:0] _203;
    wire [15:0] _199;
    wire _197;
    wire [15:0] _200;
    wire [15:0] _196;
    wire _194;
    wire _193;
    wire _195;
    wire [15:0] _201;
    wire _188;
    wire [15:0] _191;
    wire [15:0] _187;
    wire _185;
    wire _181;
    wire [16:0] _182;
    wire [15:0] _173;
    wire _172;
    wire [15:0] _174;
    wire _175;
    wire [16:0] _176;
    wire [16:0] _177;
    wire _171;
    wire [16:0] _178;
    wire _166;
    wire [15:0] _167;
    wire _168;
    wire [16:0] _169;
    wire [16:0] _179;
    wire [16:0] _183;
    wire _184;
    wire _186;
    wire [15:0] _192;
    wire [1:0] _165;
    reg [15:0] _205;
    wire _164;
    wire [15:0] _206;
    wire [15:0] _207;
    wire [15:0] _211;
    wire [15:0] _10;
    reg [15:0] _38;
    wire [11:0] _68;
    wire [3:0] _67;
    wire [15:0] _69;
    wire [15:0] _88;
    wire _90;
    wire _217;
    wire _218;
    wire _11;
    reg _214;
    wire _221;
    wire _222;
    wire _224;
    wire _215;
    wire _219;
    wire _220;
    wire _225;
    wire _226;
    wire _227;
    wire [1:0] _62;
    wire _63;
    wire _228;
    wire _230;
    wire _13;
    reg _49;
    wire _50;
    wire _45;
    reg [7:0] _22;
    reg [7:0] _25;
    reg [7:0] _28;
    reg [7:0] _31;
    reg [7:0] _34;
    wire _42;
    wire _41;
    wire _43;
    wire [1:0] _39;
    wire _40;
    wire _44;
    wire _46;
    wire _51;
    wire [2:0] _232;
    wire [2:0] _18;
    reg [2:0] _235;
    assign _151 = 16'b0000000000000000;
    assign _146 = _54[7:0];
    assign _147 = _146 | _131;
    assign _58 = 3'b000;
    assign _59 = _57 == _58;
    assign _60 = _59 ? data_in : _54;
    assign _61 = _51 ? _60 : _54;
    assign _3 = _61;
    always @(posedge clock) begin
        if (clear)
            _54 <= _151;
        else
            _54 <= _3;
    end
    assign _144 = _54[15:8];
    assign _145 = _136 | _144;
    assign _148 = { _145,
                    _147 };
    assign _139 = 8'b00000000;
    assign _137 = _94[7:0];
    assign _136 = data_in[15:8];
    assign _138 = _136 & _137;
    assign _140 = _138 == _139;
    assign _141 = ~ _140;
    assign _142 = ~ _141;
    assign _129 = 8'b00000011;
    assign _128 = _66[7:0];
    assign _130 = _128 & _129;
    assign _65 = 32'b00000000000000000000000000000000;
    assign _112 = _66[15:0];
    assign _113 = { data_in,
                    _112 };
    assign _109 = _66[31:16];
    assign _110 = { _109,
                    data_in };
    assign _107 = 3'b010;
    assign _108 = _57 == _107;
    assign _111 = _108 ? _110 : _104;
    assign _105 = 3'b001;
    assign _106 = _57 == _105;
    assign _114 = _106 ? _113 : _111;
    assign _100 = _66[31:2];
    assign _99 = 2'b00;
    assign _101 = { _99,
                    _100 };
    assign _96 = _66[29:0];
    assign _98 = { _96,
                   _99 };
    assign _102 = _95 ? _101 : _98;
    assign _91 = _49 & _90;
    assign _103 = _91 ? _102 : _66;
    assign _104 = _63 ? _103 : _66;
    assign _115 = _51 ? _114 : _104;
    assign _4 = _115;
    always @(posedge clock) begin
        if (clear)
            _66 <= _65;
        else
            _66 <= _4;
    end
    assign _126 = _66[31:30];
    assign _125 = 6'b000000;
    assign _127 = { _125,
                    _126 };
    assign _93 = 9'b000000000;
    assign _118 = data_in[8:0];
    assign _116 = 3'b100;
    assign _117 = _57 == _116;
    assign _119 = _117 ? _118 : _94;
    assign _120 = _51 ? _119 : _94;
    assign _5 = _120;
    always @(posedge clock) begin
        if (clear)
            _94 <= _93;
        else
            _94 <= _5;
    end
    assign _95 = _94[8:8];
    assign _131 = _95 ? _130 : _127;
    assign _133 = _131 == _139;
    assign _134 = ~ _133;
    assign _121 = _22[4:4];
    assign _122 = _63 & _121;
    assign _123 = _122 & _49;
    assign _124 = _123 & _90;
    assign _135 = _124 & _134;
    assign _143 = _135 & _142;
    assign _149 = _143 ? _148 : data_in;
    assign _6 = _149;
    always @(posedge clock) begin
        if (clear)
            _152 <= _151;
        else
            _152 <= _6;
    end
    assign _48 = 1'b0;
    assign _229 = _154 ? vdd : _228;
    assign _223 = ~ _90;
    assign gnd = 1'b0;
    assign _86 = 16'b0111111111111111;
    assign _85 = 16'b0011111111111111;
    assign _84 = 16'b0001111111111111;
    assign _83 = 16'b0000111111111111;
    assign _82 = 16'b0000011111111111;
    assign _81 = 16'b0000001111111111;
    assign _80 = 16'b0000000111111111;
    assign _79 = 16'b0000000011111111;
    assign _78 = 16'b0000000001111111;
    assign _77 = 16'b0000000000111111;
    assign _76 = 16'b0000000000011111;
    assign _75 = 16'b0000000000001111;
    assign _74 = 16'b0000000000000111;
    assign _73 = 16'b0000000000000011;
    assign _72 = 16'b0000000000000001;
    assign _70 = _22[3:0];
    always @* begin
        case (_70)
        0:
            _87 <= _151;
        1:
            _87 <= _72;
        2:
            _87 <= _73;
        3:
            _87 <= _74;
        4:
            _87 <= _75;
        5:
            _87 <= _76;
        6:
            _87 <= _77;
        7:
            _87 <= _78;
        8:
            _87 <= _79;
        9:
            _87 <= _80;
        10:
            _87 <= _81;
        11:
            _87 <= _82;
        12:
            _87 <= _83;
        13:
            _87 <= _84;
        14:
            _87 <= _85;
        default:
            _87 <= _86;
        endcase
    end
    assign _208 = 3'b011;
    assign vdd = 1'b1;
    assign _159 = _57 + _105;
    assign _155 = 3'b111;
    assign _156 = _57 == _155;
    assign _157 = ~ _156;
    assign _160 = _157 ? _159 : _57;
    assign _153 = 2'b11;
    assign _154 = _39 == _153;
    assign _162 = _154 ? _58 : _160;
    assign _163 = _51 ? _162 : _57;
    assign _9 = _163;
    always @(posedge clock) begin
        if (clear)
            _57 <= _58;
        else
            _57 <= _9;
    end
    assign _209 = _57 == _208;
    assign _210 = _209 ? data_in : _207;
    assign _204 = _202 ? _167 : _174;
    assign _202 = _183[16:16];
    assign _203 = _202 ? _174 : _167;
    assign _199 = 16'b1000000000000000;
    assign _197 = _183[16:16];
    assign _200 = _197 ? _199 : _86;
    assign _196 = _183[15:0];
    assign _194 = _183[15:15];
    assign _193 = _183[16:16];
    assign _195 = _193 ^ _194;
    assign _201 = _195 ? _200 : _196;
    assign _188 = _183[16:16];
    assign _191 = _188 ? _199 : _86;
    assign _187 = _183[15:0];
    assign _185 = _183[15:15];
    assign _181 = ~ _171;
    assign _182 = { _151,
                    _181 };
    assign _173 = { _31,
                    _28 };
    assign _172 = _34[2:2];
    assign _174 = _172 ? _173 : _38;
    assign _175 = _174[15:15];
    assign _176 = { _175,
                    _174 };
    assign _177 = ~ _176;
    assign _171 = _165 == _99;
    assign _178 = _171 ? _176 : _177;
    assign _166 = _34[3:3];
    assign _167 = _166 ? _38 : data_in;
    assign _168 = _167[15:15];
    assign _169 = { _168,
                    _167 };
    assign _179 = _169 + _178;
    assign _183 = _179 + _182;
    assign _184 = _183[16:16];
    assign _186 = _184 ^ _185;
    assign _192 = _186 ? _191 : _187;
    assign _165 = _34[1:0];
    always @* begin
        case (_165)
        0:
            _205 <= _192;
        1:
            _205 <= _201;
        2:
            _205 <= _203;
        default:
            _205 <= _204;
        endcase
    end
    assign _164 = _34[4:4];
    assign _206 = _164 ? _205 : _38;
    assign _207 = _63 ? _206 : _38;
    assign _211 = _51 ? _210 : _207;
    assign _10 = _211;
    always @(posedge clock) begin
        if (clear)
            _38 <= _151;
        else
            _38 <= _10;
    end
    assign _68 = _38[15:4];
    assign _67 = 4'b0000;
    assign _69 = { _67,
                   _68 };
    assign _88 = _69 & _87;
    assign _90 = _88 == _151;
    assign _217 = _215 ? gnd : _90;
    assign _218 = _63 ? _217 : _214;
    assign _11 = _218;
    always @(posedge clock) begin
        if (clear)
            _214 <= _48;
        else
            _214 <= _11;
    end
    assign _221 = _25[6:6];
    assign _222 = _221 & _214;
    assign _224 = _222 & _223;
    assign _215 = data_in[15:15];
    assign _219 = _25[7:7];
    assign _220 = _219 & _215;
    assign _225 = _220 | _224;
    assign _226 = _49 & _225;
    assign _227 = _226 ? gnd : _49;
    assign _62 = 2'b01;
    assign _63 = _39 == _62;
    assign _228 = _63 ? _227 : _49;
    assign _230 = _51 ? _229 : _228;
    assign _13 = _230;
    always @(posedge clock) begin
        if (clear)
            _49 <= _48;
        else
            _49 <= _13;
    end
    assign _50 = ~ _49;
    assign _45 = _34[5:5];
    always @(posedge clock) begin
        if (cfg_strobe)
            _22 <= cfg_in;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _25 <= _22;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _28 <= _25;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _31 <= _28;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _34 <= _31;
    end
    assign _42 = _34[6:6];
    assign _41 = tag_in[2:2];
    assign _43 = _41 == _42;
    assign _39 = tag_in[1:0];
    assign _40 = _39[1:1];
    assign _44 = _40 & _43;
    assign _46 = _44 & _45;
    assign _51 = _46 & _50;
    assign _232 = _51 ? _58 : tag_in;
    assign _18 = _232;
    always @(posedge clock) begin
        if (clear)
            _235 <= _58;
        else
            _235 <= _18;
    end
    assign tag_out = _235;
    assign data_out = _152;
    assign s = _38;
    assign cfg_out = _34;

endmodule
