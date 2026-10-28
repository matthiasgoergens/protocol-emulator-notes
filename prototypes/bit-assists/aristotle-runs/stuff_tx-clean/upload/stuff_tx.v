module stuff_tx (
    data_bit,
    clear,
    clock,
    cfg_value,
    cfg_either,
    data_valid,
    due,
    restart,
    cfg_run,
    out_bit,
    take,
    stuffed,
    underrun
);

    input data_bit;
    input clear;
    input clock;
    input cfg_value;
    input cfg_either;
    input data_valid;
    input due;
    input restart;
    input [3:0] cfg_run;
    output out_bit;
    output take;
    output stuffed;
    output underrun;

    wire _20;
    wire _18;
    wire _19;
    wire _21;
    wire _4;
    wire _28;
    wire _27;
    wire _29;
    wire [3:0] _58;
    wire [3:0] _51;
    wire _49;
    wire [2:0] _48;
    wire [3:0] _50;
    wire [3:0] _52;
    wire [3:0] _46;
    wire [3:0] _43;
    wire _44;
    wire [3:0] _47;
    wire vdd;
    wire _35;
    wire gnd;
    wire _31;
    wire _33;
    reg _37;
    wire _8;
    wire _39;
    wire _38;
    wire _40;
    wire _41;
    wire _42;
    wire [3:0] _53;
    wire _23;
    wire _24;
    wire _25;
    wire _22;
    wire _26;
    wire [3:0] _54;
    wire [3:0] _56;
    reg [3:0] _59;
    wire [3:0] _14;
    wire _63;
    wire _64;
    wire _61;
    wire _62;
    wire _65;
    wire _16;
    wire _30;
    assign _20 = ~ data_valid;
    assign _18 = ~ _16;
    assign _19 = due & _18;
    assign _21 = _19 & _20;
    assign _4 = _8;
    assign _28 = ~ _4;
    assign _27 = ~ cfg_value;
    assign _29 = cfg_either ? _28 : _27;
    assign _58 = 4'b0000;
    assign _51 = 4'b0001;
    assign _49 = _30 == cfg_value;
    assign _48 = 3'b000;
    assign _50 = { _48,
                   _49 };
    assign _52 = cfg_either ? _51 : _50;
    assign _46 = _14 + _51;
    assign _43 = 4'b1111;
    assign _44 = _14 == _43;
    assign _47 = _44 ? _14 : _46;
    assign vdd = 1'b1;
    assign _35 = 1'b0;
    assign gnd = 1'b0;
    assign _31 = _26 ? _30 : _8;
    assign _33 = restart ? gnd : _31;
    always @(posedge clock) begin
        if (clear)
            _37 <= _35;
        else
            _37 <= _33;
    end
    assign _8 = _37;
    assign _39 = _30 == _8;
    assign _38 = _30 == cfg_value;
    assign _40 = cfg_either ? _39 : _38;
    assign _41 = ~ _40;
    assign _42 = _22 | _41;
    assign _53 = _42 ? _52 : _47;
    assign _23 = ~ _16;
    assign _24 = due & _23;
    assign _25 = _24 & data_valid;
    assign _22 = due & _16;
    assign _26 = _22 | _25;
    assign _54 = _26 ? _53 : _14;
    assign _56 = restart ? _58 : _54;
    always @(posedge clock) begin
        if (clear)
            _59 <= _58;
        else
            _59 <= _56;
    end
    assign _14 = _59;
    assign _63 = _14 < cfg_run;
    assign _64 = ~ _63;
    assign _61 = cfg_run == _58;
    assign _62 = ~ _61;
    assign _65 = _62 & _64;
    assign _16 = _65;
    assign _30 = _16 ? _29 : data_bit;
    assign out_bit = _30;
    assign take = _25;
    assign stuffed = _22;
    assign underrun = _21;

endmodule
