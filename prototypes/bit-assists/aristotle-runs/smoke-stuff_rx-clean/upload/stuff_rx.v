module stuff_rx (
    clear,
    clock,
    cfg_value,
    b,
    cfg_either,
    restart,
    cfg_run,
    valid,
    keep,
    err
);

    input clear;
    input clock;
    input cfg_value;
    input b;
    input cfg_either;
    input restart;
    input [3:0] cfg_run;
    input valid;
    output keep;
    output err;

    wire _22;
    wire _21;
    wire _23;
    wire _20;
    wire _24;
    wire [3:0] _53;
    wire [3:0] _46;
    wire _44;
    wire [2:0] _43;
    wire [3:0] _45;
    wire [3:0] _47;
    wire [3:0] _41;
    wire [3:0] _38;
    wire _39;
    wire [3:0] _42;
    wire vdd;
    wire _29;
    wire gnd;
    wire _25;
    wire _27;
    reg _31;
    wire _4;
    wire _34;
    wire _33;
    wire _35;
    wire _36;
    wire _8;
    wire _32;
    wire _37;
    wire [3:0] _48;
    wire [3:0] _49;
    wire [3:0] _51;
    reg [3:0] _54;
    wire [3:0] _10;
    wire _17;
    wire _18;
    wire _15;
    wire _16;
    wire _19;
    wire _55;
    wire _56;
    assign _22 = b == _4;
    assign _21 = b == cfg_value;
    assign _23 = cfg_either ? _22 : _21;
    assign _20 = valid & _19;
    assign _24 = _20 & _23;
    assign _53 = 4'b0000;
    assign _46 = 4'b0001;
    assign _44 = b == cfg_value;
    assign _43 = 3'b000;
    assign _45 = { _43,
                   _44 };
    assign _47 = cfg_either ? _46 : _45;
    assign _41 = _10 + _46;
    assign _38 = 4'b1111;
    assign _39 = _10 == _38;
    assign _42 = _39 ? _10 : _41;
    assign vdd = 1'b1;
    assign _29 = 1'b0;
    assign gnd = 1'b0;
    assign _25 = valid ? b : _4;
    assign _27 = restart ? gnd : _25;
    always @(posedge clock) begin
        if (clear)
            _31 <= _29;
        else
            _31 <= _27;
    end
    assign _4 = _31;
    assign _34 = b == _4;
    assign _33 = b == cfg_value;
    assign _35 = cfg_either ? _34 : _33;
    assign _36 = ~ _35;
    assign _8 = _19;
    assign _32 = valid & _8;
    assign _37 = _32 | _36;
    assign _48 = _37 ? _47 : _42;
    assign _49 = valid ? _48 : _10;
    assign _51 = restart ? _53 : _49;
    always @(posedge clock) begin
        if (clear)
            _54 <= _53;
        else
            _54 <= _51;
    end
    assign _10 = _54;
    assign _17 = _10 < cfg_run;
    assign _18 = ~ _17;
    assign _15 = cfg_run == _53;
    assign _16 = ~ _15;
    assign _19 = _16 & _18;
    assign _55 = ~ _19;
    assign _56 = valid & _55;
    assign keep = _56;
    assign err = _24;

endmodule
