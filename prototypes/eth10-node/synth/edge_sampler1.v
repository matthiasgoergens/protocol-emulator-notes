module edge_sampler1 (
    period,
    offset,
    invert,
    holdoff,
    timeout,
    clear,
    clock,
    samples,
    active,
    mode,
    bit,
    valid,
    burst_end,
    overrun,
    in_burst
);

    input [7:0] period;
    input [7:0] offset;
    input invert;
    input [9:0] holdoff;
    input [9:0] timeout;
    input clear;
    input clock;
    input samples;
    input active;
    input [1:0] mode;
    output bit;
    output valid;
    output burst_end;
    output overrun;
    output in_burst;

    wire _27;
    reg _28;
    wire _52;
    reg _55;
    wire [7:0] _60;
    wire [7:0] _57;
    wire [7:0] _65;
    wire _63;
    wire [7:0] _67;
    wire [7:0] _68;
    wire [7:0] _69;
    wire [7:0] _70;
    wire [7:0] _59;
    wire [7:0] _71;
    wire [7:0] _6;
    reg [7:0] _58;
    wire _61;
    wire _72;
    wire _73;
    wire _74;
    wire _75;
    reg _78;
    wire _90;
    wire _91;
    wire _92;
    wire gnd;
    wire _89;
    wire [9:0] _48;
    wire [9:0] _42;
    wire [9:0] _43;
    wire [9:0] _40;
    wire [9:0] _80;
    wire [9:0] _81;
    wire [9:0] _10;
    reg [9:0] _39;
    wire _41;
    wire [9:0] _44;
    wire _45;
    wire _46;
    wire _47;
    wire [9:0] _49;
    wire [9:0] _50;
    wire _51;
    wire _83;
    wire vdd;
    wire _82;
    wire _14;
    reg _33;
    wire _34;
    wire _35;
    wire _36;
    wire _84;
    wire _17;
    reg _24;
    wire _93;
    wire _18;
    reg _87;
    wire [1:0] _94;
    wire _95;
    wire _96;
    wire [1:0] _29;
    wire _30;
    wire _97;
    wire _98;
    reg _101;
    assign _27 = 1'b0;
    always @(posedge clock) begin
        if (clear)
            _28 <= _27;
        else
            _28 <= _27;
    end
    assign _52 = _24 & _51;
    always @(posedge clock) begin
        if (clear)
            _55 <= _27;
        else
            _55 <= _52;
    end
    assign _60 = 8'b00000001;
    assign _57 = 8'b00000000;
    assign _65 = _58 - _60;
    assign _63 = _58 == _57;
    assign _67 = _63 ? _57 : _65;
    assign _68 = _61 ? period : _67;
    assign _69 = _47 ? offset : _68;
    assign _70 = _30 ? _69 : _58;
    assign _59 = _36 ? offset : _58;
    assign _71 = _24 ? _70 : _59;
    assign _6 = _71;
    always @(posedge clock) begin
        if (clear)
            _58 <= _57;
        else
            _58 <= _6;
    end
    assign _61 = _58 == _60;
    assign _72 = ~ _47;
    assign _73 = _72 & _61;
    assign _74 = _30 ? _73 : _47;
    assign _75 = _24 & _74;
    always @(posedge clock) begin
        if (clear)
            _78 <= _27;
        else
            _78 <= _75;
    end
    assign _90 = _87 | _36;
    assign _91 = _47 ? gnd : _90;
    assign _92 = _30 ? _87 : _91;
    assign gnd = 1'b0;
    assign _89 = _36 ? gnd : _87;
    assign _48 = 10'b0000000000;
    assign _42 = 10'b0000000001;
    assign _43 = _39 + _42;
    assign _40 = 10'b1111111111;
    assign _80 = _36 ? _48 : _39;
    assign _81 = _24 ? _50 : _80;
    assign _10 = _81;
    always @(posedge clock) begin
        if (clear)
            _39 <= _48;
        else
            _39 <= _10;
    end
    assign _41 = _39 == _40;
    assign _44 = _41 ? _39 : _43;
    assign _45 = _44 < holdoff;
    assign _46 = ~ _45;
    assign _47 = _36 & _46;
    assign _49 = _47 ? _48 : _44;
    assign _50 = _30 ? _49 : _49;
    assign _51 = timeout < _50;
    assign _83 = ~ _51;
    assign vdd = 1'b1;
    assign _82 = active ? samples : _33;
    assign _14 = _82;
    always @(posedge clock) begin
        if (clear)
            _33 <= _27;
        else
            _33 <= _14;
    end
    assign _34 = samples == _33;
    assign _35 = ~ _34;
    assign _36 = active & _35;
    assign _84 = _24 ? _83 : _36;
    assign _17 = _84;
    always @(posedge clock) begin
        if (clear)
            _24 <= _27;
        else
            _24 <= _17;
    end
    assign _93 = _24 ? _92 : _89;
    assign _18 = _93;
    always @(posedge clock) begin
        if (clear)
            _87 <= _27;
        else
            _87 <= _18;
    end
    assign _94 = 2'b00;
    assign _95 = mode == _94;
    assign _96 = _95 ? samples : _87;
    assign _29 = 2'b10;
    assign _30 = mode == _29;
    assign _97 = _30 ? samples : _96;
    assign _98 = _97 ^ invert;
    always @(posedge clock) begin
        if (clear)
            _101 <= _27;
        else
            _101 <= _98;
    end
    assign bit = _101;
    assign valid = _78;
    assign burst_end = _55;
    assign overrun = _28;
    assign in_burst = _24;

endmodule
