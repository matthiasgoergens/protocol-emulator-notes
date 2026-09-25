module ring_cell24 (
    clear,
    init_in,
    nb4,
    nb3,
    nb2,
    nb1,
    cfg_strobe,
    clock,
    cfg_in,
    do_step,
    init_strobe,
    s,
    cfg_out,
    init_out
);

    input clear;
    input [7:0] init_in;
    input [23:0] nb4;
    input [23:0] nb3;
    input [23:0] nb2;
    input [23:0] nb1;
    input cfg_strobe;
    input clock;
    input [7:0] cfg_in;
    input do_step;
    input init_strobe;
    output [23:0] s;
    output [7:0] cfg_out;
    output [7:0] init_out;

    wire [7:0] _16;
    wire vdd;
    wire [23:0] _75;
    wire [15:0] _71;
    wire [23:0] _72;
    wire [23:0] _68;
    wire _66;
    wire [23:0] _67;
    wire [23:0] _63;
    wire [23:0] _62;
    wire _61;
    wire [23:0] _64;
    wire [23:0] _60;
    wire _58;
    wire _57;
    wire _59;
    wire [23:0] _65;
    wire _52;
    wire [23:0] _55;
    wire [23:0] _51;
    wire _49;
    wire _45;
    wire [24:0] _46;
    wire [23:0] _37;
    wire [2:0] _36;
    reg [23:0] _38;
    wire _39;
    wire [24:0] _40;
    wire [24:0] _41;
    wire [1:0] _34;
    wire _35;
    wire [24:0] _42;
    wire [2:0] _30;
    reg [23:0] _31;
    wire _32;
    wire [24:0] _33;
    wire [24:0] _43;
    wire [24:0] _47;
    wire _48;
    wire _50;
    wire [23:0] _56;
    wire [7:0] _27;
    reg [7:0] _19;
    reg [7:0] _22;
    reg [7:0] _25;
    reg [7:0] _28;
    wire [1:0] _29;
    reg [23:0] _69;
    wire [23:0] _70;
    wire [23:0] _73;
    reg [23:0] _77;
    wire [23:0] _14;
    assign _16 = _14[23:16];
    assign vdd = 1'b1;
    assign _75 = 24'b000000000000000000000000;
    assign _71 = _14[15:0];
    assign _72 = { _71,
                   init_in };
    assign _68 = _66 ? _31 : _38;
    assign _66 = _47[24:24];
    assign _67 = _66 ? _38 : _31;
    assign _63 = 24'b100000000000000000000000;
    assign _62 = 24'b011111111111111111111111;
    assign _61 = _47[24:24];
    assign _64 = _61 ? _63 : _62;
    assign _60 = _47[23:0];
    assign _58 = _47[23:23];
    assign _57 = _47[24:24];
    assign _59 = _57 ^ _58;
    assign _65 = _59 ? _64 : _60;
    assign _52 = _47[24:24];
    assign _55 = _52 ? _63 : _62;
    assign _51 = _47[23:0];
    assign _49 = _47[23:23];
    assign _45 = ~ _35;
    assign _46 = { _75,
                   _45 };
    assign _37 = { _25,
                   _22,
                   _19 };
    assign _36 = _28[7:5];
    always @* begin
        case (_36)
        0:
            _38 <= nb1;
        1:
            _38 <= nb2;
        2:
            _38 <= nb3;
        3:
            _38 <= nb4;
        default:
            _38 <= _37;
        endcase
    end
    assign _39 = _38[23:23];
    assign _40 = { _39,
                   _38 };
    assign _41 = ~ _40;
    assign _34 = 2'b00;
    assign _35 = _29 == _34;
    assign _42 = _35 ? _40 : _41;
    assign _30 = _28[4:2];
    always @* begin
        case (_30)
        0:
            _31 <= _14;
        1:
            _31 <= nb1;
        2:
            _31 <= nb2;
        3:
            _31 <= nb3;
        default:
            _31 <= nb4;
        endcase
    end
    assign _32 = _31[23:23];
    assign _33 = { _32,
                   _31 };
    assign _43 = _33 + _42;
    assign _47 = _43 + _46;
    assign _48 = _47[24:24];
    assign _50 = _48 ^ _49;
    assign _56 = _50 ? _55 : _51;
    assign _27 = 8'b00000000;
    always @(posedge clock) begin
        if (cfg_strobe)
            _19 <= cfg_in;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _22 <= _19;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _25 <= _22;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _28 <= _25;
    end
    assign _29 = _28[1:0];
    always @* begin
        case (_29)
        0:
            _69 <= _56;
        1:
            _69 <= _65;
        2:
            _69 <= _67;
        default:
            _69 <= _68;
        endcase
    end
    assign _70 = do_step ? _69 : _14;
    assign _73 = init_strobe ? _72 : _70;
    always @(posedge clock) begin
        if (clear)
            _77 <= _75;
        else
            _77 <= _73;
    end
    assign _14 = _77;
    assign s = _14;
    assign cfg_out = _28;
    assign init_out = _16;

endmodule
