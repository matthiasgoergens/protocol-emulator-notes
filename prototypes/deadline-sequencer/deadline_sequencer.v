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
    wire gnd;
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
    wire _95;
    wire [1:0] _96;
    wire [3:0] _97;
    wire [7:0] _98;
    wire [7:0] _99;
    wire [7:0] _93;
    wire [7:0] _94;
    wire [7:0] _100;
    wire _88;
    wire [7:0] _101;
    wire [7:0] _8;
    reg [7:0] _91;
    wire _194;
    wire [1:0] _195;
    wire [3:0] _196;
    wire [7:0] _197;
    wire [7:0] _198;
    wire [7:0] _92;
    wire [7:0] _192;
    wire [7:0] _193;
    wire [7:0] _199;
    wire _188;
    wire [2:0] _186;
    wire _187;
    wire _189;
    wire _184;
    wire [2:0] _182;
    wire _183;
    wire _185;
    wire _180;
    wire [2:0] _178;
    wire _179;
    wire _181;
    wire _176;
    wire [2:0] _174;
    wire _175;
    wire _177;
    wire _172;
    wire [2:0] _170;
    wire _171;
    wire _173;
    wire _168;
    wire [2:0] _166;
    wire _167;
    wire _169;
    wire _164;
    wire [2:0] _162;
    wire _163;
    wire _165;
    wire _159;
    wire [7:0] _104;
    wire [7:0] _10;
    reg [7:0] _84;
    wire [7:0] _107;
    wire [7:0] _11;
    reg [7:0] _81;
    wire [7:0] _110;
    wire [7:0] _12;
    reg [7:0] _78;
    wire [7:0] _145;
    wire [6:0] _140;
    wire [7:0] _142;
    wire [6:0] _138;
    wire [7:0] _139;
    wire [7:0] _143;
    wire [6:0] _133;
    wire [7:0] _134;
    wire [6:0] _131;
    wire [7:0] _132;
    wire [7:0] _135;
    wire [7:0] _118;
    wire _117;
    wire [7:0] _119;
    wire _116;
    wire [7:0] _136;
    wire _114;
    wire [7:0] _144;
    wire [3:0] _111;
    wire _112;
    wire [7:0] _146;
    wire [7:0] _14;
    wire [7:0] _149;
    wire [7:0] _15;
    reg [7:0] _75;
    reg [7:0] _85;
    wire _158;
    wire _160;
    wire _157;
    wire [2:0] _155;
    wire _156;
    wire _161;
    wire [7:0] _190;
    wire _151;
    wire [7:0] _191;
    wire [3:0] _87;
    wire _150;
    wire [7:0] _200;
    wire [7:0] _16;
    reg [7:0] _154;
    wire [5:0] _51;
    wire [11:0] _287;
    wire _288;
    wire [5:0] _289;
    wire _120;
    wire _129;
    wire _128;
    wire _127;
    wire _126;
    wire _125;
    wire _124;
    wire _123;
    wire _122;
    wire [2:0] _121;
    reg _130;
    wire _286;
    wire [5:0] _290;
    wire [11:0] _204;
    wire [11:0] _19;
    reg [11:0] _203;
    wire [11:0] _208;
    wire [11:0] _20;
    reg [11:0] _207;
    wire [11:0] _212;
    wire [11:0] _21;
    reg [11:0] _211;
    wire [11:0] _221;
    wire [11:0] _222;
    wire _220;
    wire [11:0] _223;
    wire [3:0] _213;
    wire _214;
    wire [11:0] _225;
    wire [11:0] _22;
    wire [11:0] _226;
    wire [11:0] _23;
    reg [11:0] _217;
    reg [11:0] _218;
    wire _283;
    wire [5:0] _284;
    wire [5:0] _278;
    wire [11:0] _230;
    wire [11:0] _24;
    reg [11:0] _229;
    wire [11:0] _234;
    wire [11:0] _25;
    reg [11:0] _233;
    wire [11:0] _238;
    wire [11:0] _26;
    reg [11:0] _237;
    wire [11:0] _224;
    wire [11:0] _251;
    wire [11:0] _248;
    wire [3:0] _115;
    wire _242;
    wire [11:0] _249;
    wire [3:0] _113;
    wire _241;
    wire [11:0] _252;
    wire [3:0] _239;
    wire _240;
    wire [11:0] _253;
    wire [11:0] _27;
    wire [11:0] _254;
    wire [11:0] _28;
    reg [11:0] _245;
    reg [11:0] _246;
    wire _276;
    wire _277;
    wire [5:0] _279;
    wire [5:0] _273;
    wire [5:0] _270;
    wire [1:0] _102;
    wire _103;
    wire [5:0] _255;
    wire [5:0] _30;
    reg [5:0] _43;
    wire [1:0] _105;
    wire _106;
    wire [5:0] _256;
    wire [5:0] _31;
    reg [5:0] _46;
    wire [1:0] _108;
    wire _109;
    wire [5:0] _257;
    wire [5:0] _32;
    reg [5:0] _49;
    reg [5:0] _269;
    wire [5:0] _271;
    wire [3:0] _267;
    wire _268;
    wire [5:0] _272;
    wire [3:0] _55;
    wire _266;
    wire [5:0] _274;
    wire [3:0] _264;
    wire _265;
    wire [5:0] _280;
    wire [3:0] _262;
    wire _263;
    wire [5:0] _281;
    wire [3:0] _260;
    wire _261;
    wire [5:0] _285;
    wire [3:0] _258;
    wire [3:0] _54;
    wire _259;
    wire [5:0] _291;
    wire [5:0] _34;
    wire [1:0] _147;
    wire _148;
    wire [5:0] _292;
    wire [5:0] _35;
    reg [5:0] _52;
    reg [5:0] _297;
    wire vdd;
    wire [1:0] _294;
    wire [1:0] _38;
    reg [1:0] _72;
    wire [1:0] _296;
    wire [7:0] _298;
    assign _53 = { _43,
                   _46,
                   _49,
                   _52 };
    assign _58 = host_in_valid ? vdd : gnd;
    assign _56 = _54 == _55;
    assign _59 = _56 ? _58 : gnd;
    assign _2 = _59;
    assign _64 = 1'b0;
    assign gnd = 1'b0;
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
    assign _95 = imem_data[2:2];
    assign _96 = { _95,
                   _95 };
    assign _97 = { _96,
                   _96 };
    assign _98 = { _97,
                   _97 };
    assign _99 = _92 & _98;
    assign _93 = ~ _92;
    assign _94 = _91 & _93;
    assign _100 = _94 | _99;
    assign _88 = _54 == _87;
    assign _101 = _88 ? _100 : _91;
    assign _8 = _101;
    always @(posedge clock) begin
        if (clear)
            _91 <= _68;
        else
            _91 <= _8;
    end
    assign _194 = imem_data[3:3];
    assign _195 = { _194,
                    _194 };
    assign _196 = { _195,
                    _195 };
    assign _197 = { _196,
                    _196 };
    assign _198 = _92 & _197;
    assign _92 = imem_data[11:4];
    assign _192 = ~ _92;
    assign _193 = _154 & _192;
    assign _199 = _193 | _198;
    assign _188 = _154[0:0];
    assign _186 = 3'b000;
    assign _187 = _121 == _186;
    assign _189 = _187 ? _160 : _188;
    assign _184 = _154[1:1];
    assign _182 = 3'b001;
    assign _183 = _121 == _182;
    assign _185 = _183 ? _160 : _184;
    assign _180 = _154[2:2];
    assign _178 = 3'b010;
    assign _179 = _121 == _178;
    assign _181 = _179 ? _160 : _180;
    assign _176 = _154[3:3];
    assign _174 = 3'b011;
    assign _175 = _121 == _174;
    assign _177 = _175 ? _160 : _176;
    assign _172 = _154[4:4];
    assign _170 = 3'b100;
    assign _171 = _121 == _170;
    assign _173 = _171 ? _160 : _172;
    assign _168 = _154[5:5];
    assign _166 = 3'b101;
    assign _167 = _121 == _166;
    assign _169 = _167 ? _160 : _168;
    assign _164 = _154[6:6];
    assign _162 = 3'b110;
    assign _163 = _121 == _162;
    assign _165 = _163 ? _160 : _164;
    assign _159 = _85[7:7];
    assign _104 = _103 ? _14 : _84;
    assign _10 = _104;
    always @(posedge clock) begin
        if (clear)
            _84 <= _68;
        else
            _84 <= _10;
    end
    assign _107 = _106 ? _14 : _81;
    assign _11 = _107;
    always @(posedge clock) begin
        if (clear)
            _81 <= _68;
        else
            _81 <= _11;
    end
    assign _110 = _109 ? _14 : _78;
    assign _12 = _110;
    always @(posedge clock) begin
        if (clear)
            _78 <= _68;
        else
            _78 <= _12;
    end
    assign _145 = imem_data[7:0];
    assign _140 = _85[6:0];
    assign _142 = { _140,
                    _64 };
    assign _138 = _85[7:1];
    assign _139 = { _64,
                    _138 };
    assign _143 = _120 ? _142 : _139;
    assign _133 = _85[6:0];
    assign _134 = { _133,
                    _130 };
    assign _131 = _85[7:1];
    assign _132 = { _130,
                    _131 };
    assign _135 = _120 ? _134 : _132;
    assign _118 = host_in_valid ? host_in : _85;
    assign _117 = _54 == _55;
    assign _119 = _117 ? _118 : _85;
    assign _116 = _54 == _115;
    assign _136 = _116 ? _135 : _119;
    assign _114 = _54 == _113;
    assign _144 = _114 ? _143 : _136;
    assign _111 = 4'b0100;
    assign _112 = _54 == _111;
    assign _146 = _112 ? _145 : _144;
    assign _14 = _146;
    assign _149 = _148 ? _14 : _75;
    assign _15 = _149;
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
    assign _158 = _85[0:0];
    assign _160 = _120 ? _159 : _158;
    assign _157 = _154[7:7];
    assign _155 = 3'b111;
    assign _156 = _121 == _155;
    assign _161 = _156 ? _160 : _157;
    assign _190 = { _161,
                    _165,
                    _169,
                    _173,
                    _177,
                    _181,
                    _185,
                    _189 };
    assign _151 = _54 == _113;
    assign _191 = _151 ? _190 : _154;
    assign _87 = 4'b0001;
    assign _150 = _54 == _87;
    assign _200 = _150 ? _199 : _191;
    assign _16 = _200;
    always @(posedge clock) begin
        if (clear)
            _154 <= _68;
        else
            _154 <= _16;
    end
    assign _51 = 6'b000000;
    assign _287 = 12'b000000000000;
    assign _288 = _218 == _287;
    assign _289 = _288 ? _278 : _269;
    assign _120 = imem_data[8:8];
    assign _129 = pin_in[7:7];
    assign _128 = pin_in[6:6];
    assign _127 = pin_in[5:5];
    assign _126 = pin_in[4:4];
    assign _125 = pin_in[3:3];
    assign _124 = pin_in[2:2];
    assign _123 = pin_in[1:1];
    assign _122 = pin_in[0:0];
    assign _121 = imem_data[11:9];
    always @* begin
        case (_121)
        0:
            _130 <= _122;
        1:
            _130 <= _123;
        2:
            _130 <= _124;
        3:
            _130 <= _125;
        4:
            _130 <= _126;
        5:
            _130 <= _127;
        6:
            _130 <= _128;
        default:
            _130 <= _129;
        endcase
    end
    assign _286 = _130 == _120;
    assign _290 = _286 ? _271 : _289;
    assign _204 = _103 ? _22 : _203;
    assign _19 = _204;
    always @(posedge clock) begin
        if (clear)
            _203 <= _287;
        else
            _203 <= _19;
    end
    assign _208 = _106 ? _22 : _207;
    assign _20 = _208;
    always @(posedge clock) begin
        if (clear)
            _207 <= _287;
        else
            _207 <= _20;
    end
    assign _212 = _109 ? _22 : _211;
    assign _21 = _212;
    always @(posedge clock) begin
        if (clear)
            _211 <= _287;
        else
            _211 <= _21;
    end
    assign _221 = 12'b000000000001;
    assign _222 = _218 - _221;
    assign _220 = _218 == _287;
    assign _223 = _220 ? _218 : _222;
    assign _213 = 4'b0011;
    assign _214 = _54 == _213;
    assign _225 = _214 ? _224 : _223;
    assign _22 = _225;
    assign _226 = _148 ? _22 : _217;
    assign _23 = _226;
    always @(posedge clock) begin
        if (clear)
            _217 <= _287;
        else
            _217 <= _23;
    end
    always @* begin
        case (_72)
        0:
            _218 <= _217;
        1:
            _218 <= _211;
        2:
            _218 <= _207;
        default:
            _218 <= _203;
        endcase
    end
    assign _283 = _218 == _287;
    assign _284 = _283 ? _271 : _269;
    assign _278 = imem_data[5:0];
    assign _230 = _103 ? _27 : _229;
    assign _24 = _230;
    always @(posedge clock) begin
        if (clear)
            _229 <= _287;
        else
            _229 <= _24;
    end
    assign _234 = _106 ? _27 : _233;
    assign _25 = _234;
    always @(posedge clock) begin
        if (clear)
            _233 <= _287;
        else
            _233 <= _25;
    end
    assign _238 = _109 ? _27 : _237;
    assign _26 = _238;
    always @(posedge clock) begin
        if (clear)
            _237 <= _287;
        else
            _237 <= _26;
    end
    assign _224 = imem_data[11:0];
    assign _251 = _246 - _221;
    assign _248 = _246 - _221;
    assign _115 = 4'b1000;
    assign _242 = _54 == _115;
    assign _249 = _242 ? _248 : _246;
    assign _113 = 4'b0111;
    assign _241 = _54 == _113;
    assign _252 = _241 ? _251 : _249;
    assign _239 = 4'b0010;
    assign _240 = _54 == _239;
    assign _253 = _240 ? _224 : _252;
    assign _27 = _253;
    assign _254 = _148 ? _27 : _245;
    assign _28 = _254;
    always @(posedge clock) begin
        if (clear)
            _245 <= _287;
        else
            _245 <= _28;
    end
    always @* begin
        case (_72)
        0:
            _246 <= _245;
        1:
            _246 <= _237;
        2:
            _246 <= _233;
        default:
            _246 <= _229;
        endcase
    end
    assign _276 = _246 == _287;
    assign _277 = ~ _276;
    assign _279 = _277 ? _278 : _271;
    assign _273 = host_in_valid ? _271 : _269;
    assign _270 = 6'b000001;
    assign _102 = 2'b11;
    assign _103 = _72 == _102;
    assign _255 = _103 ? _34 : _43;
    assign _30 = _255;
    always @(posedge clock) begin
        if (clear)
            _43 <= _51;
        else
            _43 <= _30;
    end
    assign _105 = 2'b10;
    assign _106 = _72 == _105;
    assign _256 = _106 ? _34 : _46;
    assign _31 = _256;
    always @(posedge clock) begin
        if (clear)
            _46 <= _51;
        else
            _46 <= _31;
    end
    assign _108 = 2'b01;
    assign _109 = _72 == _108;
    assign _257 = _109 ? _34 : _49;
    assign _32 = _257;
    always @(posedge clock) begin
        if (clear)
            _49 <= _51;
        else
            _49 <= _32;
    end
    always @* begin
        case (_72)
        0:
            _269 <= _52;
        1:
            _269 <= _49;
        2:
            _269 <= _46;
        default:
            _269 <= _43;
        endcase
    end
    assign _271 = _269 + _270;
    assign _267 = 4'b1101;
    assign _268 = _54 == _267;
    assign _272 = _268 ? _269 : _271;
    assign _55 = 4'b1100;
    assign _266 = _54 == _55;
    assign _274 = _266 ? _273 : _272;
    assign _264 = 4'b1010;
    assign _265 = _54 == _264;
    assign _280 = _265 ? _279 : _274;
    assign _262 = 4'b1001;
    assign _263 = _54 == _262;
    assign _281 = _263 ? _278 : _280;
    assign _260 = 4'b0110;
    assign _261 = _54 == _260;
    assign _285 = _261 ? _284 : _281;
    assign _258 = 4'b0101;
    assign _54 = imem_data[15:12];
    assign _259 = _54 == _258;
    assign _291 = _259 ? _290 : _285;
    assign _34 = _291;
    assign _147 = 2'b00;
    assign _148 = _72 == _147;
    assign _292 = _148 ? _34 : _52;
    assign _35 = _292;
    always @(posedge clock) begin
        if (clear)
            _52 <= _51;
        else
            _52 <= _35;
    end
    always @* begin
        case (_296)
        0:
            _297 <= _52;
        1:
            _297 <= _49;
        2:
            _297 <= _46;
        default:
            _297 <= _43;
        endcase
    end
    assign vdd = 1'b1;
    assign _294 = _72 + _108;
    assign _38 = _294;
    always @(posedge clock) begin
        if (clear)
            _72 <= _147;
        else
            _72 <= _38;
    end
    assign _296 = _72 + _108;
    assign _298 = { _296,
                    _297 };
    assign imem_addr = _298;
    assign pin_out = _154;
    assign pin_oe = _91;
    assign host_out = _69;
    assign host_out_valid = _65;
    assign host_in_ready = _2;
    assign pcs = _53;

endmodule
