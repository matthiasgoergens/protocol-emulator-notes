module pe16 (
    en,
    clear,
    nbr_in,
    cfg_strobe,
    clock,
    cfg_in,
    out,
    pipe_out,
    cfg_out
);

    input en;
    input clear;
    input [15:0] nbr_in;
    input cfg_strobe;
    input clock;
    input [7:0] cfg_in;
    output [15:0] out;
    output [15:0] pipe_out;
    output [7:0] cfg_out;

    wire [15:0] _66;
    wire [15:0] _63;
    wire _61;
    wire [15:0] _62;
    wire [15:0] _58;
    wire [15:0] _57;
    wire _56;
    wire [15:0] _59;
    wire [15:0] _55;
    wire _53;
    wire _52;
    wire _54;
    wire [15:0] _60;
    wire _47;
    wire [15:0] _50;
    wire [15:0] _46;
    wire _44;
    wire _40;
    wire [16:0] _41;
    wire [15:0] _32;
    wire _31;
    wire [15:0] _33;
    wire _34;
    wire [16:0] _35;
    wire [16:0] _36;
    wire [1:0] _29;
    wire _30;
    wire [16:0] _37;
    wire _25;
    wire [15:0] _26;
    wire _27;
    wire [16:0] _28;
    wire [16:0] _38;
    wire [16:0] _42;
    wire _43;
    wire _45;
    wire [15:0] _51;
    wire [1:0] _24;
    reg [15:0] _64;
    reg [15:0] _67;
    wire [15:0] _4;
    wire vdd;
    reg [15:0] _23;
    wire [7:0] _18;
    reg [7:0] _13;
    reg [7:0] _16;
    reg [7:0] _19;
    wire _68;
    wire [15:0] _69;
    assign _66 = 16'b0000000000000000;
    assign _63 = _61 ? _26 : _33;
    assign _61 = _42[16:16];
    assign _62 = _61 ? _33 : _26;
    assign _58 = 16'b1000000000000000;
    assign _57 = 16'b0111111111111111;
    assign _56 = _42[16:16];
    assign _59 = _56 ? _58 : _57;
    assign _55 = _42[15:0];
    assign _53 = _42[15:15];
    assign _52 = _42[16:16];
    assign _54 = _52 ^ _53;
    assign _60 = _54 ? _59 : _55;
    assign _47 = _42[16:16];
    assign _50 = _47 ? _58 : _57;
    assign _46 = _42[15:0];
    assign _44 = _42[15:15];
    assign _40 = ~ _30;
    assign _41 = { _66,
                   _40 };
    assign _32 = { _16,
                   _13 };
    assign _31 = _19[2:2];
    assign _33 = _31 ? _32 : _4;
    assign _34 = _33[15:15];
    assign _35 = { _34,
                   _33 };
    assign _36 = ~ _35;
    assign _29 = 2'b00;
    assign _30 = _24 == _29;
    assign _37 = _30 ? _35 : _36;
    assign _25 = _19[3:3];
    assign _26 = _25 ? _4 : nbr_in;
    assign _27 = _26[15:15];
    assign _28 = { _27,
                   _26 };
    assign _38 = _28 + _37;
    assign _42 = _38 + _41;
    assign _43 = _42[16:16];
    assign _45 = _43 ^ _44;
    assign _51 = _45 ? _50 : _46;
    assign _24 = _19[1:0];
    always @* begin
        case (_24)
        0:
            _64 <= _51;
        1:
            _64 <= _60;
        2:
            _64 <= _62;
        default:
            _64 <= _63;
        endcase
    end
    always @(posedge clock) begin
        if (clear)
            _67 <= _66;
        else
            if (en)
                _67 <= _64;
    end
    assign _4 = _67;
    assign vdd = 1'b1;
    always @(posedge clock) begin
        if (clear)
            _23 <= _66;
        else
            _23 <= nbr_in;
    end
    assign _18 = 8'b00000000;
    always @(posedge clock) begin
        if (cfg_strobe)
            _13 <= cfg_in;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _16 <= _13;
    end
    always @(posedge clock) begin
        if (cfg_strobe)
            _19 <= _16;
    end
    assign _68 = _19[4:4];
    assign _69 = _68 ? _4 : _23;
    assign out = _69;
    assign pipe_out = _23;
    assign cfg_out = _19;

endmodule
