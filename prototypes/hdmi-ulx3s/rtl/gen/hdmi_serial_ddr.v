module hdmi_serial_ddr (
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
    output [1:0] lane0;
    output [1:0] lane1;
    output [1:0] lane2;
    output [1:0] lane3;
    output armed;
    output slip;
    output led_1hz;

    wire _38;
    wire [25:0] _23;
    wire [25:0] _34;
    wire [25:0] _29;
    wire [25:0] _30;
    wire [25:0] _32;
    reg [25:0] _35;
    wire [25:0] _1;
    wire _24;
    reg _28;
    wire _36;
    reg _39;
    wire _2;
    wire [2:0] _56;
    wire _57;
    wire [2:0] _53;
    wire _54;
    wire _55;
    wire _58;
    wire _59;
    wire _50;
    wire _60;
    wire _61;
    reg _64;
    wire _4;
    wire [9:0] _76;
    wire [9:0] _72;
    wire [7:0] _70;
    wire [1:0] _69;
    wire [9:0] _71;
    wire [9:0] _73;
    reg [9:0] _77;
    wire [9:0] _7;
    wire [1:0] _78;
    wire [7:0] _80;
    wire [9:0] _81;
    wire [9:0] _82;
    reg [9:0] _85;
    wire [9:0] _10;
    wire [1:0] _86;
    wire [7:0] _88;
    wire [9:0] _89;
    wire [9:0] _90;
    reg [9:0] _93;
    wire [9:0] _13;
    wire [1:0] _94;
    wire gnd;
    wire [7:0] _111;
    wire [9:0] _112;
    wire [2:0] _51;
    wire [2:0] _97;
    wire [2:0] _98;
    wire [2:0] _100;
    wire _95;
    wire _96;
    wire [2:0] _102;
    reg [2:0] _105;
    wire [2:0] _16;
    wire _52;
    reg _48;
    wire vdd;
    reg _42;
    reg _45;
    wire _49;
    wire _106;
    reg _109;
    wire _20;
    wire _65;
    reg _68;
    wire [9:0] _113;
    reg [9:0] _116;
    wire [9:0] _21;
    wire [1:0] _117;
    assign _38 = 1'b0;
    assign _23 = 26'b11101110011010110010011110;
    assign _34 = 26'b00000000000000000000000000;
    assign _29 = 26'b00000000000000000000000001;
    assign _30 = _1 + _29;
    assign _32 = _28 ? _34 : _30;
    always @(posedge clock) begin
        if (clear)
            _35 <= _34;
        else
            _35 <= _32;
    end
    assign _1 = _35;
    assign _24 = _1 == _23;
    always @(posedge clock) begin
        if (clear)
            _28 <= _38;
        else
            _28 <= _24;
    end
    assign _36 = _2 ^ _28;
    always @(posedge clock) begin
        if (clear)
            _39 <= _38;
        else
            _39 <= _36;
    end
    assign _2 = _39;
    assign _56 = 3'b000;
    assign _57 = _16 == _56;
    assign _53 = 3'b011;
    assign _54 = _16 == _53;
    assign _55 = _52 | _54;
    assign _58 = _55 | _57;
    assign _59 = ~ _58;
    assign _50 = _20 & _49;
    assign _60 = _50 & _59;
    assign _61 = _4 | _60;
    always @(posedge clock) begin
        if (clear)
            _64 <= _38;
        else
            _64 <= _61;
    end
    assign _4 = _64;
    assign _76 = 10'b0000000000;
    assign _72 = 10'b0000011111;
    assign _70 = _7[9:2];
    assign _69 = 2'b00;
    assign _71 = { _69,
                   _70 };
    assign _73 = _68 ? _72 : _71;
    always @(posedge clock) begin
        if (gnd)
            _77 <= _76;
        else
            _77 <= _73;
    end
    assign _7 = _77;
    assign _78 = _7[1:0];
    assign _80 = _10[9:2];
    assign _81 = { _69,
                   _80 };
    assign _82 = _68 ? word_r : _81;
    always @(posedge clock) begin
        if (gnd)
            _85 <= _76;
        else
            _85 <= _82;
    end
    assign _10 = _85;
    assign _86 = _10[1:0];
    assign _88 = _13[9:2];
    assign _89 = { _69,
                   _88 };
    assign _90 = _68 ? word_g : _89;
    always @(posedge clock) begin
        if (gnd)
            _93 <= _76;
        else
            _93 <= _90;
    end
    assign _13 = _93;
    assign _94 = _13[1:0];
    assign gnd = 1'b0;
    assign _111 = _21[9:2];
    assign _112 = { _69,
                    _111 };
    assign _51 = 3'b100;
    assign _97 = 3'b001;
    assign _98 = _16 + _97;
    assign _100 = _52 ? _56 : _98;
    assign _95 = ~ _20;
    assign _96 = _95 & _49;
    assign _102 = _96 ? _56 : _100;
    always @(posedge clock) begin
        if (clear)
            _105 <= _56;
        else
            _105 <= _102;
    end
    assign _16 = _105;
    assign _52 = _16 == _51;
    always @(posedge clock) begin
        if (clear)
            _48 <= _38;
        else
            _48 <= _45;
    end
    assign vdd = 1'b1;
    always @(posedge clock) begin
        if (clear)
            _42 <= _38;
        else
            _42 <= toggle;
    end
    always @(posedge clock) begin
        if (clear)
            _45 <= _38;
        else
            _45 <= _42;
    end
    assign _49 = _45 ^ _48;
    assign _106 = _20 | _49;
    always @(posedge clock) begin
        if (clear)
            _109 <= _38;
        else
            _109 <= _106;
    end
    assign _20 = _109;
    assign _65 = _20 ? _52 : _49;
    always @(posedge clock) begin
        if (clear)
            _68 <= _38;
        else
            _68 <= _65;
    end
    assign _113 = _68 ? word_b : _112;
    always @(posedge clock) begin
        if (gnd)
            _116 <= _76;
        else
            _116 <= _113;
    end
    assign _21 = _116;
    assign _117 = _21[1:0];
    assign lane0 = _117;
    assign lane1 = _94;
    assign lane2 = _86;
    assign lane3 = _78;
    assign armed = _20;
    assign slip = _4;
    assign led_1hz = _2;

endmodule
