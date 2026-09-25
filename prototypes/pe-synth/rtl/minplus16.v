module minplus16 (
    en,
    clear,
    clock,
    b_in,
    a_in,
    first,
    acc,
    a_out,
    b_out
);

    input en;
    input clear;
    input clock;
    input [15:0] b_in;
    input [15:0] a_in;
    input first;
    output [15:0] acc;
    output [15:0] a_out;
    output [15:0] b_out;

    wire [15:0] _12;
    reg [15:0] _14;
    wire vdd;
    reg [15:0] _17;
    wire [15:0] _24;
    wire [15:0] _23;
    wire [16:0] _20;
    wire gnd;
    wire [16:0] _19;
    wire [16:0] _21;
    wire _22;
    wire [15:0] _25;
    wire _29;
    wire [15:0] _30;
    wire [15:0] _31;
    wire [15:0] _9;
    reg [15:0] _28;
    assign _12 = 16'b0000000000000000;
    always @(posedge clock) begin
        if (clear)
            _14 <= _12;
        else
            _14 <= b_in;
    end
    assign vdd = 1'b1;
    always @(posedge clock) begin
        if (clear)
            _17 <= _12;
        else
            _17 <= a_in;
    end
    assign _24 = 16'b1111111111111111;
    assign _23 = _21[15:0];
    assign _20 = { gnd,
                   b_in };
    assign gnd = 1'b0;
    assign _19 = { gnd,
                   a_in };
    assign _21 = _19 + _20;
    assign _22 = _21[16:16];
    assign _25 = _22 ? _24 : _23;
    assign _29 = _25 < _28;
    assign _30 = _29 ? _25 : _28;
    assign _31 = first ? _25 : _30;
    assign _9 = _31;
    always @(posedge clock) begin
        if (clear)
            _28 <= _12;
        else
            if (en)
                _28 <= _9;
    end
    assign acc = _28;
    assign a_out = _17;
    assign b_out = _14;

endmodule
