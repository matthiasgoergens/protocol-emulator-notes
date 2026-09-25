module crc_prog (
    check,
    mask,
    top,
    poly,
    value,
    msb_first,
    skip_n,
    clear,
    clock,
    frame,
    stb,
    init,
    en,
    ok
);

    input [15:0] check;
    input [15:0] mask;
    input [3:0] top;
    input [15:0] poly;
    input value;
    input msb_first;
    input [4:0] skip_n;
    input clear;
    input clock;
    input frame;
    input stb;
    input [15:0] init;
    input en;
    output ok;

    wire [15:0] _76;
    wire _65;
    wire _64;
    wire _63;
    wire _62;
    wire _61;
    wire _60;
    wire _59;
    wire _58;
    wire _57;
    wire _56;
    wire _55;
    wire _54;
    wire _53;
    wire _52;
    wire _51;
    wire _50;
    reg _66;
    wire _67;
    wire [15:0] _69;
    wire _48;
    wire [14:0] _47;
    wire [15:0] _49;
    wire [15:0] _70;
    wire [15:0] _71;
    wire _42;
    wire _43;
    wire [15:0] _45;
    wire [14:0] _40;
    wire [15:0] _41;
    wire [15:0] _46;
    wire [15:0] _72;
    wire [4:0] _36;
    wire [4:0] _28;
    wire [4:0] _29;
    wire _25;
    wire _26;
    wire _27;
    wire [4:0] _30;
    wire [4:0] _31;
    reg [4:0] _34;
    wire [4:0] _8;
    wire _37;
    wire vdd;
    reg _21;
    wire _22;
    wire _17;
    wire _23;
    wire _35;
    wire _38;
    wire [15:0] _73;
    wire [15:0] _74;
    reg [15:0] _77;
    wire [15:0] _15;
    wire _78;
    assign _76 = 16'b0000000000000000;
    assign _65 = _15[15:15];
    assign _64 = _15[14:14];
    assign _63 = _15[13:13];
    assign _62 = _15[12:12];
    assign _61 = _15[11:11];
    assign _60 = _15[10:10];
    assign _59 = _15[9:9];
    assign _58 = _15[8:8];
    assign _57 = _15[7:7];
    assign _56 = _15[6:6];
    assign _55 = _15[5:5];
    assign _54 = _15[4:4];
    assign _53 = _15[3:3];
    assign _52 = _15[2:2];
    assign _51 = _15[1:1];
    assign _50 = _15[0:0];
    always @* begin
        case (top)
        0:
            _66 <= _50;
        1:
            _66 <= _51;
        2:
            _66 <= _52;
        3:
            _66 <= _53;
        4:
            _66 <= _54;
        5:
            _66 <= _55;
        6:
            _66 <= _56;
        7:
            _66 <= _57;
        8:
            _66 <= _58;
        9:
            _66 <= _59;
        10:
            _66 <= _60;
        11:
            _66 <= _61;
        12:
            _66 <= _62;
        13:
            _66 <= _63;
        14:
            _66 <= _64;
        default:
            _66 <= _65;
        endcase
    end
    assign _67 = _66 ^ value;
    assign _69 = _67 ? poly : _76;
    assign _48 = 1'b0;
    assign _47 = _15[14:0];
    assign _49 = { _47,
                   _48 };
    assign _70 = _49 ^ _69;
    assign _71 = _70 & mask;
    assign _42 = _15[0:0];
    assign _43 = _42 ^ value;
    assign _45 = _43 ? poly : _76;
    assign _40 = _15[15:1];
    assign _41 = { _48,
                   _40 };
    assign _46 = _41 ^ _45;
    assign _72 = msb_first ? _71 : _46;
    assign _36 = 5'b00000;
    assign _28 = 5'b00001;
    assign _29 = _8 - _28;
    assign _25 = _8 == _36;
    assign _26 = ~ _25;
    assign _27 = _23 & _26;
    assign _30 = _27 ? _29 : _8;
    assign _31 = en ? _30 : skip_n;
    always @(posedge clock) begin
        if (clear)
            _34 <= _36;
        else
            _34 <= _31;
    end
    assign _8 = _34;
    assign _37 = _8 == _36;
    assign vdd = 1'b1;
    always @(posedge clock) begin
        if (clear)
            _21 <= _48;
        else
            _21 <= _17;
    end
    assign _22 = ~ _21;
    assign _17 = stb & frame;
    assign _23 = _17 & _22;
    assign _35 = en & _23;
    assign _38 = _35 & _37;
    assign _73 = _38 ? _72 : _15;
    assign _74 = en ? _73 : init;
    always @(posedge clock) begin
        if (clear)
            _77 <= _76;
        else
            _77 <= _74;
    end
    assign _15 = _77;
    assign _78 = _15 == check;
    assign ok = _78;

endmodule
