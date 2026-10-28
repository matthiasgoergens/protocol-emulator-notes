module line_enc (
    cfg_invert,
    cfg_toggle_on,
    bit,
    clear,
    clock,
    tick,
    restart,
    cfg_mode,
    need_bit,
    line,
    sym
);

    input cfg_invert;
    input cfg_toggle_on;
    input bit;
    input clear;
    input clock;
    input tick;
    input restart;
    input [1:0] cfg_mode;
    output need_bit;
    output line;
    output sym;

    wire _43;
    wire _27;
    wire _26;
    wire _28;
    wire _29;
    wire _31;
    reg _35;
    wire _3;
    wire _22;
    wire _23;
    wire _19;
    wire _36;
    wire _37;
    wire _38;
    reg _41;
    wire _5;
    wire _20;
    wire [1:0] _17;
    wire _18;
    wire _21;
    wire _24;
    wire _25;
    reg _44;
    wire vdd;
    wire gnd;
    wire _46;
    wire _45;
    wire _47;
    wire _48;
    reg _51;
    wire _12;
    wire _53;
    wire [1:0] _15;
    wire _16;
    wire _52;
    wire _54;
    assign _43 = 1'b0;
    assign _27 = ~ _12;
    assign _26 = tick & _16;
    assign _28 = _26 & _27;
    assign _29 = _28 ? bit : _3;
    assign _31 = restart ? gnd : _29;
    always @(posedge clock) begin
        if (clear)
            _35 <= _43;
        else
            _35 <= _31;
    end
    assign _3 = _35;
    assign _22 = ~ bit;
    assign _23 = _12 ? _3 : _22;
    assign _19 = bit == cfg_toggle_on;
    assign _36 = tick & _18;
    assign _37 = _36 ? _20 : _5;
    assign _38 = restart ? gnd : _37;
    always @(posedge clock) begin
        if (clear)
            _41 <= _43;
        else
            _41 <= _38;
    end
    assign _5 = _41;
    assign _20 = _5 ^ _19;
    assign _17 = 2'b01;
    assign _18 = cfg_mode == _17;
    assign _21 = _18 ? _20 : bit;
    assign _24 = _16 ? _23 : _21;
    assign _25 = _24 ^ cfg_invert;
    always @(posedge clock) begin
        if (clear)
            _44 <= _43;
        else
            if (tick)
                _44 <= _25;
    end
    assign vdd = 1'b1;
    assign gnd = 1'b0;
    assign _46 = ~ _12;
    assign _45 = tick & _16;
    assign _47 = _45 ? _46 : _12;
    assign _48 = restart ? gnd : _47;
    always @(posedge clock) begin
        if (clear)
            _51 <= _43;
        else
            _51 <= _48;
    end
    assign _12 = _51;
    assign _53 = ~ _12;
    assign _15 = 2'b10;
    assign _16 = cfg_mode == _15;
    assign _52 = ~ _16;
    assign _54 = _52 | _53;
    assign need_bit = _54;
    assign line = _44;
    assign sym = _25;

endmodule
