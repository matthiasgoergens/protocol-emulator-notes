module multiphase_stage (
    pads,
    oe,
    ph3,
    ph2,
    ph1,
    clear,
    ph0,
    sub,
    pin,
    pin_oe,
    samples
);

    input [1:0] pads;
    input [1:0] oe;
    input ph3;
    input ph2;
    input ph1;
    input clear;
    input ph0;
    input [7:0] sub;
    output [1:0] pin;
    output [1:0] pin_oe;
    output [7:0] samples;

    wire _99;
    wire _91;
    reg _94;
    reg _97;
    reg _100;
    wire _81;
    reg _84;
    reg _87;
    reg _90;
    wire _71;
    reg _74;
    reg _77;
    reg _80;
    wire _61;
    reg _64;
    reg _67;
    reg _70;
    wire _51;
    reg _54;
    reg _57;
    reg _60;
    wire _41;
    reg _44;
    reg _47;
    reg _50;
    wire _31;
    reg _34;
    reg _37;
    reg _40;
    wire _20;
    reg _24;
    reg _27;
    reg _30;
    wire [7:0] _101;
    wire [1:0] _103;
    reg [1:0] _104;
    wire _106;
    wire _105;
    wire _107;
    reg _110;
    wire _5;
    wire _111;
    reg _114;
    wire _116;
    wire _115;
    wire _117;
    reg _120;
    wire _6;
    wire _121;
    reg _124;
    wire _126;
    wire _125;
    wire _127;
    reg _130;
    wire _7;
    wire _131;
    reg _134;
    wire _136;
    reg _139;
    wire _135;
    wire _140;
    wire _8;
    wire _141;
    reg _144;
    wire _188;
    wire _189;
    wire _190;
    wire _146;
    wire _145;
    wire _147;
    reg _150;
    wire _10;
    wire _151;
    reg _154;
    wire _156;
    wire _155;
    wire _157;
    reg _160;
    wire _12;
    wire _161;
    reg _164;
    wire _166;
    wire _165;
    wire _167;
    reg _170;
    wire _14;
    wire _171;
    reg _174;
    wire vdd;
    wire _176;
    reg _179;
    wire _175;
    wire _180;
    wire _18;
    wire _181;
    reg _184;
    wire _185;
    wire _186;
    wire _187;
    wire [1:0] _191;
    assign _99 = 1'b0;
    assign _91 = pads[0:0];
    always @(posedge ph0) begin
        if (clear)
            _94 <= _99;
        else
            _94 <= _91;
    end
    always @(posedge ph0) begin
        if (clear)
            _97 <= _99;
        else
            _97 <= _94;
    end
    always @(posedge ph0) begin
        if (clear)
            _100 <= _99;
        else
            _100 <= _97;
    end
    assign _81 = pads[0:0];
    always @(posedge ph1) begin
        if (clear)
            _84 <= _99;
        else
            _84 <= _81;
    end
    always @(posedge ph1) begin
        if (clear)
            _87 <= _99;
        else
            _87 <= _84;
    end
    always @(posedge ph0) begin
        if (clear)
            _90 <= _99;
        else
            _90 <= _87;
    end
    assign _71 = pads[0:0];
    always @(posedge ph2) begin
        if (clear)
            _74 <= _99;
        else
            _74 <= _71;
    end
    always @(posedge ph2) begin
        if (clear)
            _77 <= _99;
        else
            _77 <= _74;
    end
    always @(posedge ph0) begin
        if (clear)
            _80 <= _99;
        else
            _80 <= _77;
    end
    assign _61 = pads[0:0];
    always @(posedge ph3) begin
        if (clear)
            _64 <= _99;
        else
            _64 <= _61;
    end
    always @(posedge ph3) begin
        if (clear)
            _67 <= _99;
        else
            _67 <= _64;
    end
    always @(posedge ph0) begin
        if (clear)
            _70 <= _99;
        else
            _70 <= _67;
    end
    assign _51 = pads[1:1];
    always @(posedge ph0) begin
        if (clear)
            _54 <= _99;
        else
            _54 <= _51;
    end
    always @(posedge ph0) begin
        if (clear)
            _57 <= _99;
        else
            _57 <= _54;
    end
    always @(posedge ph0) begin
        if (clear)
            _60 <= _99;
        else
            _60 <= _57;
    end
    assign _41 = pads[1:1];
    always @(posedge ph1) begin
        if (clear)
            _44 <= _99;
        else
            _44 <= _41;
    end
    always @(posedge ph1) begin
        if (clear)
            _47 <= _99;
        else
            _47 <= _44;
    end
    always @(posedge ph0) begin
        if (clear)
            _50 <= _99;
        else
            _50 <= _47;
    end
    assign _31 = pads[1:1];
    always @(posedge ph2) begin
        if (clear)
            _34 <= _99;
        else
            _34 <= _31;
    end
    always @(posedge ph2) begin
        if (clear)
            _37 <= _99;
        else
            _37 <= _34;
    end
    always @(posedge ph0) begin
        if (clear)
            _40 <= _99;
        else
            _40 <= _37;
    end
    assign _20 = pads[1:1];
    always @(posedge ph3) begin
        if (clear)
            _24 <= _99;
        else
            _24 <= _20;
    end
    always @(posedge ph3) begin
        if (clear)
            _27 <= _99;
        else
            _27 <= _24;
    end
    always @(posedge ph0) begin
        if (clear)
            _30 <= _99;
        else
            _30 <= _27;
    end
    assign _101 = { _30,
                    _40,
                    _50,
                    _60,
                    _70,
                    _80,
                    _90,
                    _100 };
    assign _103 = 2'b00;
    always @(posedge ph0) begin
        if (clear)
            _104 <= _103;
        else
            _104 <= oe;
    end
    assign _106 = sub[2:2];
    assign _105 = sub[3:3];
    assign _107 = _105 ^ _106;
    always @(posedge ph0) begin
        if (clear)
            _110 <= _99;
        else
            _110 <= _107;
    end
    assign _5 = _114;
    assign _111 = _5 ^ _110;
    always @(posedge ph3) begin
        if (clear)
            _114 <= _99;
        else
            _114 <= _111;
    end
    assign _116 = sub[1:1];
    assign _115 = sub[2:2];
    assign _117 = _115 ^ _116;
    always @(posedge ph0) begin
        if (clear)
            _120 <= _99;
        else
            _120 <= _117;
    end
    assign _6 = _124;
    assign _121 = _6 ^ _120;
    always @(posedge ph2) begin
        if (clear)
            _124 <= _99;
        else
            _124 <= _121;
    end
    assign _126 = sub[0:0];
    assign _125 = sub[1:1];
    assign _127 = _125 ^ _126;
    always @(posedge ph0) begin
        if (clear)
            _130 <= _99;
        else
            _130 <= _127;
    end
    assign _7 = _134;
    assign _131 = _7 ^ _130;
    always @(posedge ph1) begin
        if (clear)
            _134 <= _99;
        else
            _134 <= _131;
    end
    assign _136 = sub[3:3];
    always @(posedge ph0) begin
        if (clear)
            _139 <= _99;
        else
            _139 <= _136;
    end
    assign _135 = sub[0:0];
    assign _140 = _135 ^ _139;
    assign _8 = _144;
    assign _141 = _8 ^ _140;
    always @(posedge ph0) begin
        if (clear)
            _144 <= _99;
        else
            _144 <= _141;
    end
    assign _188 = _144 ^ _134;
    assign _189 = _188 ^ _124;
    assign _190 = _189 ^ _114;
    assign _146 = sub[6:6];
    assign _145 = sub[7:7];
    assign _147 = _145 ^ _146;
    always @(posedge ph0) begin
        if (clear)
            _150 <= _99;
        else
            _150 <= _147;
    end
    assign _10 = _154;
    assign _151 = _10 ^ _150;
    always @(posedge ph3) begin
        if (clear)
            _154 <= _99;
        else
            _154 <= _151;
    end
    assign _156 = sub[5:5];
    assign _155 = sub[6:6];
    assign _157 = _155 ^ _156;
    always @(posedge ph0) begin
        if (clear)
            _160 <= _99;
        else
            _160 <= _157;
    end
    assign _12 = _164;
    assign _161 = _12 ^ _160;
    always @(posedge ph2) begin
        if (clear)
            _164 <= _99;
        else
            _164 <= _161;
    end
    assign _166 = sub[4:4];
    assign _165 = sub[5:5];
    assign _167 = _165 ^ _166;
    always @(posedge ph0) begin
        if (clear)
            _170 <= _99;
        else
            _170 <= _167;
    end
    assign _14 = _174;
    assign _171 = _14 ^ _170;
    always @(posedge ph1) begin
        if (clear)
            _174 <= _99;
        else
            _174 <= _171;
    end
    assign vdd = 1'b1;
    assign _176 = sub[7:7];
    always @(posedge ph0) begin
        if (clear)
            _179 <= _99;
        else
            _179 <= _176;
    end
    assign _175 = sub[4:4];
    assign _180 = _175 ^ _179;
    assign _18 = _184;
    assign _181 = _18 ^ _180;
    always @(posedge ph0) begin
        if (clear)
            _184 <= _99;
        else
            _184 <= _181;
    end
    assign _185 = _184 ^ _174;
    assign _186 = _185 ^ _164;
    assign _187 = _186 ^ _154;
    assign _191 = { _187,
                    _190 };
    assign pin = _191;
    assign pin_oe = _104;
    assign samples = _101;

endmodule
