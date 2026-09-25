module ring_cell16 (
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
    input [15:0] nb4;
    input [15:0] nb3;
    input [15:0] nb2;
    input [15:0] nb1;
    input cfg_strobe;
    input clock;
    input [7:0] cfg_in;
    input do_step;
    input init_strobe;
    output [15:0] s;
    output [7:0] cfg_out;
    output [7:0] init_out;

    wire [7:0] _16;
    wire vdd;
    wire [15:0] _72;
    wire [7:0] _68;
    wire [15:0] _69;
    wire [15:0] _65;
    wire _63;
    wire [15:0] _64;
    wire [15:0] _60;
    wire [15:0] _59;
    wire _58;
    wire [15:0] _61;
    wire [15:0] _57;
    wire _55;
    wire _54;
    wire _56;
    wire [15:0] _62;
    wire _49;
    wire [15:0] _52;
    wire [15:0] _48;
    wire _46;
    wire _42;
    wire [16:0] _43;
    wire [15:0] _34;
    wire [2:0] _33;
    reg [15:0] _35;
    wire _36;
    wire [16:0] _37;
    wire [16:0] _38;
    wire [1:0] _31;
    wire _32;
    wire [16:0] _39;
    wire [2:0] _27;
    reg [15:0] _28;
    wire _29;
    wire [16:0] _30;
    wire [16:0] _40;
    wire [16:0] _44;
    wire _45;
    wire _47;
    wire [15:0] _53;
    wire [7:0] _24;
    reg [7:0] _19;
    reg [7:0] _22;
    reg [7:0] _25;
    wire [1:0] _26;
    reg [15:0] _66;
    wire [15:0] _67;
    wire [15:0] _70;
    reg [15:0] _74;
    wire [15:0] _14;
    assign _16 = _14[15:8];
    assign vdd = 1'b1;
    assign _72 = 16'b0000000000000000;
    assign _68 = _14[7:0];
    assign _69 = { _68,
                   init_in };
    assign _65 = _63 ? _28 : _35;
    assign _63 = _44[16:16];
    assign _64 = _63 ? _35 : _28;
    assign _60 = 16'b1000000000000000;
    assign _59 = 16'b0111111111111111;
    assign _58 = _44[16:16];
    assign _61 = _58 ? _60 : _59;
    assign _57 = _44[15:0];
    assign _55 = _44[15:15];
    assign _54 = _44[16:16];
    assign _56 = _54 ^ _55;
    assign _62 = _56 ? _61 : _57;
    assign _49 = _44[16:16];
    assign _52 = _49 ? _60 : _59;
    assign _48 = _44[15:0];
    assign _46 = _44[15:15];
    assign _42 = ~ _32;
    assign _43 = { _72,
                   _42 };
    assign _34 = { _22,
                   _19 };
    assign _33 = _25[7:5];
    always @* begin
        case (_33)
        0:
            _35 <= nb1;
        1:
            _35 <= nb2;
        2:
            _35 <= nb3;
        3:
            _35 <= nb4;
        default:
            _35 <= _34;
        endcase
    end
    assign _36 = _35[15:15];
    assign _37 = { _36,
                   _35 };
    assign _38 = ~ _37;
    assign _31 = 2'b00;
    assign _32 = _26 == _31;
    assign _39 = _32 ? _37 : _38;
    assign _27 = _25[4:2];
    always @* begin
        case (_27)
        0:
            _28 <= _14;
        1:
            _28 <= nb1;
        2:
            _28 <= nb2;
        3:
            _28 <= nb3;
        default:
            _28 <= nb4;
        endcase
    end
    assign _29 = _28[15:15];
    assign _30 = { _29,
                   _28 };
    assign _40 = _30 + _39;
    assign _44 = _40 + _43;
    assign _45 = _44[16:16];
    assign _47 = _45 ^ _46;
    assign _53 = _47 ? _52 : _48;
    assign _24 = 8'b00000000;
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
    assign _26 = _25[1:0];
    always @* begin
        case (_26)
        0:
            _66 <= _53;
        1:
            _66 <= _62;
        2:
            _66 <= _64;
        default:
            _66 <= _65;
        endcase
    end
    assign _67 = do_step ? _66 : _14;
    assign _70 = init_strobe ? _69 : _67;
    always @(posedge clock) begin
        if (clear)
            _74 <= _72;
        else
            _74 <= _70;
    end
    assign _14 = _74;
    assign s = _14;
    assign cfg_out = _25;
    assign init_out = _16;

endmodule
