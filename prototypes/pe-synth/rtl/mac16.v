module mac16 (
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
    output [31:0] acc;
    output [15:0] a_out;
    output [15:0] b_out;

    wire [15:0] _12;
    reg [15:0] _14;
    wire vdd;
    reg [15:0] _17;
    wire [31:0] _19;
    wire [31:0] _21;
    wire [31:0] _22;
    wire [31:0] _23;
    wire [31:0] _9;
    reg [31:0] _20;
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
    assign _19 = 32'b00000000000000000000000000000000;
    assign _21 = $signed(a_in) * $signed(b_in);
    assign _22 = _20 + _21;
    assign _23 = first ? _21 : _22;
    assign _9 = _23;
    always @(posedge clock) begin
        if (clear)
            _20 <= _19;
        else
            if (en)
                _20 <= _9;
    end
    assign acc = _20;
    assign a_out = _17;
    assign b_out = _14;

endmodule
