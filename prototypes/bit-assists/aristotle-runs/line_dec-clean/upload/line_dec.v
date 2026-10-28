module line_dec (
    cfg_toggle_on,
    cfg_invert,
    sym,
    clear,
    clock,
    cfg_mode,
    valid,
    out_valid,
    out_bit,
    err
);

    input cfg_toggle_on;
    input cfg_invert;
    input sym;
    input clear;
    input clock;
    input [1:0] cfg_mode;
    input valid;
    output out_valid;
    output out_bit;
    output err;

    wire _22;
    wire _17;
    wire _16;
    wire _18;
    wire _20;
    reg _24;
    wire _1;
    wire _27;
    wire _25;
    wire _26;
    wire _28;
    wire _37;
    wire _29;
    reg _32;
    wire _4;
    wire _35;
    wire _36;
    wire _38;
    wire _19;
    wire [1:0] _33;
    wire _34;
    wire _39;
    wire _40;
    wire vdd;
    wire _42;
    wire _41;
    wire _43;
    reg _46;
    wire _10;
    wire [1:0] _14;
    wire _15;
    wire _47;
    wire _48;
    wire _49;
    assign _22 = 1'b0;
    assign _17 = ~ _10;
    assign _16 = valid & _15;
    assign _18 = _16 & _17;
    assign _20 = _18 ? _19 : _1;
    always @(posedge clock) begin
        if (clear)
            _24 <= _22;
        else
            _24 <= _20;
    end
    assign _1 = _24;
    assign _27 = _1 == _19;
    assign _25 = valid & _15;
    assign _26 = _25 & _10;
    assign _28 = _26 & _27;
    assign _37 = ~ cfg_toggle_on;
    assign _29 = valid ? _19 : _4;
    always @(posedge clock) begin
        if (clear)
            _32 <= _22;
        else
            _32 <= _29;
    end
    assign _4 = _32;
    assign _35 = _19 == _4;
    assign _36 = ~ _35;
    assign _38 = _36 ? cfg_toggle_on : _37;
    assign _19 = sym ^ cfg_invert;
    assign _33 = 2'b01;
    assign _34 = cfg_mode == _33;
    assign _39 = _34 ? _38 : _19;
    assign _40 = _15 ? _19 : _39;
    assign vdd = 1'b1;
    assign _42 = ~ _10;
    assign _41 = valid & _15;
    assign _43 = _41 ? _42 : _10;
    always @(posedge clock) begin
        if (clear)
            _46 <= _22;
        else
            _46 <= _43;
    end
    assign _10 = _46;
    assign _14 = 2'b10;
    assign _15 = cfg_mode == _14;
    assign _47 = ~ _15;
    assign _48 = _47 | _10;
    assign _49 = valid & _48;
    assign out_valid = _49;
    assign out_bit = _40;
    assign err = _28;

endmodule
