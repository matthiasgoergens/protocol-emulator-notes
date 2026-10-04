module hdmi_serial_sdr (
    word_r,
    word_g,
    word_b,
    clear,
    clock,
    toggle,
    lane0,
    lane1,
    lane2,
    lane3,
    armed,
    slip,
    led_1hz
);

    input [9:0] word_r;
    input [9:0] word_g;
    input [9:0] word_b;
    input clear;
    input clock;
    input toggle;
    output lane0;
    output lane1;
    output lane2;
    output lane3;
    output armed;
    output slip;
    output led_1hz;

    wire _35;
    wire [26:0] _23;
    wire [26:0] _30;
    wire [26:0] _25;
    wire [26:0] _26;
    wire [26:0] _28;
    reg [26:0] _32;
    wire [26:0] _1;
    wire _24;
    wire _33;
    reg _36;
    wire _2;
    wire [3:0] _53;
    wire _54;
    wire [3:0] _50;
    wire _51;
    wire _52;
    wire _55;
    wire _56;
    wire _47;
    wire _57;
    wire _58;
    reg _61;
    wire _4;
    wire [9:0] _73;
    wire [9:0] _69;
    wire [8:0] _67;
    wire [9:0] _68;
    wire [9:0] _70;
    reg [9:0] _74;
    wire [9:0] _7;
    wire _75;
    wire [8:0] _77;
    wire [9:0] _78;
    wire [9:0] _79;
    reg [9:0] _82;
    wire [9:0] _10;
    wire _83;
    wire [8:0] _85;
    wire [9:0] _86;
    wire [9:0] _87;
    reg [9:0] _90;
    wire [9:0] _13;
    wire _91;
    wire gnd;
    wire [8:0] _108;
    wire [9:0] _109;
    wire [3:0] _48;
    wire [3:0] _94;
    wire [3:0] _95;
    wire [3:0] _97;
    wire _92;
    wire _93;
    wire [3:0] _99;
    reg [3:0] _102;
    wire [3:0] _16;
    wire _49;
    reg _45;
    wire vdd;
    reg _39;
    reg _42;
    wire _46;
    wire _103;
    reg _106;
    wire _20;
    wire _62;
    reg _65;
    wire [9:0] _110;
    reg [9:0] _113;
    wire [9:0] _21;
    wire _114;
    assign _35 = 1'b0;
    assign _23 = 27'b111011100110101100100111111;
    assign _30 = 27'b000000000000000000000000000;
    assign _25 = 27'b000000000000000000000000001;
    assign _26 = _1 + _25;
    assign _28 = _24 ? _30 : _26;
    always @(posedge clock) begin
        if (clear)
            _32 <= _30;
        else
            _32 <= _28;
    end
    assign _1 = _32;
    assign _24 = _1 == _23;
    assign _33 = _2 ^ _24;
    always @(posedge clock) begin
        if (clear)
            _36 <= _35;
        else
            _36 <= _33;
    end
    assign _2 = _36;
    assign _53 = 4'b0000;
    assign _54 = _16 == _53;
    assign _50 = 4'b1000;
    assign _51 = _16 == _50;
    assign _52 = _49 | _51;
    assign _55 = _52 | _54;
    assign _56 = ~ _55;
    assign _47 = _20 & _46;
    assign _57 = _47 & _56;
    assign _58 = _4 | _57;
    always @(posedge clock) begin
        if (clear)
            _61 <= _35;
        else
            _61 <= _58;
    end
    assign _4 = _61;
    assign _73 = 10'b0000000000;
    assign _69 = 10'b0000011111;
    assign _67 = _7[9:1];
    assign _68 = { _35,
                   _67 };
    assign _70 = _65 ? _69 : _68;
    always @(posedge clock) begin
        if (gnd)
            _74 <= _73;
        else
            _74 <= _70;
    end
    assign _7 = _74;
    assign _75 = _7[0:0];
    assign _77 = _10[9:1];
    assign _78 = { _35,
                   _77 };
    assign _79 = _65 ? word_r : _78;
    always @(posedge clock) begin
        if (gnd)
            _82 <= _73;
        else
            _82 <= _79;
    end
    assign _10 = _82;
    assign _83 = _10[0:0];
    assign _85 = _13[9:1];
    assign _86 = { _35,
                   _85 };
    assign _87 = _65 ? word_g : _86;
    always @(posedge clock) begin
        if (gnd)
            _90 <= _73;
        else
            _90 <= _87;
    end
    assign _13 = _90;
    assign _91 = _13[0:0];
    assign gnd = 1'b0;
    assign _108 = _21[9:1];
    assign _109 = { _35,
                    _108 };
    assign _48 = 4'b1001;
    assign _94 = 4'b0001;
    assign _95 = _16 + _94;
    assign _97 = _49 ? _53 : _95;
    assign _92 = ~ _20;
    assign _93 = _92 & _46;
    assign _99 = _93 ? _53 : _97;
    always @(posedge clock) begin
        if (clear)
            _102 <= _53;
        else
            _102 <= _99;
    end
    assign _16 = _102;
    assign _49 = _16 == _48;
    always @(posedge clock) begin
        if (clear)
            _45 <= _35;
        else
            _45 <= _42;
    end
    assign vdd = 1'b1;
    always @(posedge clock) begin
        if (clear)
            _39 <= _35;
        else
            _39 <= toggle;
    end
    always @(posedge clock) begin
        if (clear)
            _42 <= _35;
        else
            _42 <= _39;
    end
    assign _46 = _42 ^ _45;
    assign _103 = _20 | _46;
    always @(posedge clock) begin
        if (clear)
            _106 <= _35;
        else
            _106 <= _103;
    end
    assign _20 = _106;
    assign _62 = _20 ? _49 : _46;
    always @(posedge clock) begin
        if (clear)
            _65 <= _35;
        else
            _65 <= _62;
    end
    assign _110 = _65 ? word_b : _109;
    always @(posedge clock) begin
        if (gnd)
            _113 <= _73;
        else
            _113 <= _110;
    end
    assign _21 = _113;
    assign _114 = _21[0:0];
    assign lane0 = _114;
    assign lane1 = _91;
    assign lane2 = _83;
    assign lane3 = _75;
    assign armed = _20;
    assign slip = _4;
    assign led_1hz = _2;

endmodule
