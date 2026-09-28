"""Random lockstep check of pe16x.v against a Python model of the documented semantics, through
iverilog. FAULT=1 plants a model error (the EMA shift one place short) to show the check can fail.
Usage: python3 check.py [cycles]   -> prints mismatches / comparisons."""
import os, random, subprocess, sys, pathlib

HERE = pathlib.Path(__file__).parent
N = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
FAULT = os.environ.get("FAULT") == "1"
random.seed(1)


def sx(v, w=16):
    v &= (1 << w) - 1
    return v - (1 << w) if v >> (w - 1) else v


def model_step(st, cfg, nb, ext, en):
    s, pipe, hist = st
    b = cfg
    op, wrap, ema, xsel, lut_en = b[0] & 3, b[0] >> 2 & 1, b[0] >> 3 & 1, b[0] >> 4 & 7, b[0] >> 7
    ysel, sh = b[1] & 7, b[1] >> 3 & 15
    k = sx(b[2] << 8 | b[3])
    lneg, lupd = b[6] << 8 | b[7], b[8] << 8 | b[9]
    x = [s, nb[0], nb[1], nb[2], nb[3], pipe, 0, 0][xsel]
    y0 = [nb[0], nb[1], nb[2], nb[3], k, s, pipe, 0][ysel]
    bit = lambda v, i: (v >> i) & 1
    src = [bit(nb[0], 15), bit(nb[1], 15), bit(nb[2], 15), bit(nb[3], 15), bit(nb[0], 14), bit(nb[0], 13),
           bit(nb[0], 12), bit(s, 15), bit(s, 14), ext & 1, ext >> 1 & 1, ext >> 2 & 1, hist & 1, hist >> 1 & 1, 0, 1]
    sels = [b[4] & 15, b[4] >> 4, b[5] & 15, b[5] >> 4]
    lin = sum(src[sel] << i for i, sel in enumerate(sels))
    neg = lut_en and (lneg >> lin & 1)
    upd = (not lut_en) or (lupd >> lin & 1)
    shift = sh - 1 if (FAULT and ema and sh > 0) else sh
    if ema:
        shv = (x - s) >> shift
    else:
        shv = y0 >> sh
    yv = -shv if neg else shv
    if ema:
        tot = s + shv
    elif op == 1:
        tot = x - yv
    else:
        tot = x + yv
    arith = sx(tot) if wrap else max(-32768, min(32767, tot))
    if ema:
        nxt = arith
    elif op in (2, 3):
        ys = min(yv, 32767)
        lt = x < yv
        nxt = (ys if lt else x) if op == 2 else (x if lt else ys)
    else:
        nxt = arith
    if en:
        return (nxt if upd else s, x, lin & 3)
    return st


def main():
    stim = []
    exp = []
    st = (0, 0, 0)
    cfg = None
    for c in range(N):
        if c % 16 == 0:
            cfg = [random.randrange(256) for _ in range(10)]
            if random.random() < 0.5:
                cfg[0] &= 0x7F               # half the time the plain cell (no LUT)
        nb = [sx(random.randrange(1 << 16)) for _ in range(4)]
        ext = random.randrange(8)
        en = 1 if random.random() < 0.8 else 0
        st = model_step(st, cfg, nb, ext, en)
        stim.append((cfg, nb, ext, en))
        exp.append(st[0])
    # testbench: load the configuration through the chain every 16 cycles (10 strobed cycles with
    # en = 0, which leave the state alone), then run the 16 cycles
    lines = []
    for c, (cfg, nb, ext, en) in enumerate(stim):
        if c % 16 == 0:
            for byte in cfg:                 # first byte in ends in cfg[0]
                lines.append(f"1 {byte:02x} 0 0000 0000 0000 0000 0 0")
        lines.append("0 00 %d %04x %04x %04x %04x %d 1" % (en, nb[0] & 0xFFFF, nb[1] & 0xFFFF, nb[2] & 0xFFFF,
                                                         nb[3] & 0xFFFF, ext, ))
    tmp = pathlib.Path("/var/tmp/radio-video/pe-ext")
    tmp.mkdir(parents=True, exist_ok=True)
    (tmp / "stim.txt").write_text("\n".join(lines) + "\n")
    tb = r'''
module tb;
  reg clk = 0, rst = 1, cs = 0, en = 0; reg [7:0] ci = 0; reg [15:0] n1, n2, n3, n4; reg [2:0] ext;
  wire [7:0] co; wire signed [15:0] s;
  pe16x dut(.clk(clk), .rst(rst), .cfg_strobe(cs), .cfg_in(ci), .cfg_out(co), .en(en),
            .nb1(n1), .nb2(n2), .nb3(n3), .nb4(n4), .ext(ext), .s_out(s));
  integer f, r, a, b, c, e, g, h, i, j, q, cnt;
  initial begin
    f = $fopen("STIM", "r"); n1 = 0; n2 = 0; n3 = 0; n4 = 0; ext = 0;
    #1 clk = 1; #1 clk = 0; rst = 0;
    while (!$feof(f)) begin
      r = $fscanf(f, "%d %h %d %h %h %h %h %d %d\n", a, b, c, e, g, h, i, j, q);
      if (r != 9) break;
      if (r == 9) begin
        cs = a; ci = b; en = c; n1 = e; n2 = g; n3 = h; n4 = i; ext = j;
        #1 clk = 1; #1 clk = 0;
        if (q) $display("%0d", s);
      end
    end
    $finish;
  end
endmodule
'''.replace("STIM", str(tmp / "stim.txt"))
    (tmp / "tb.v").write_text(tb)
    subprocess.run(["iverilog", "-g2012", "-o", str(tmp / "sim"), str(tmp / "tb.v"), str(HERE / "pe16x.v")], check=True)
    out = subprocess.run(["vvp", "-n", str(tmp / "sim")], capture_output=True, text=True, check=True).stdout.splitlines()
    got = [int(v) for v in out if v.lstrip("-").isdigit()]
    bad = sum(1 for g, e in zip(got, exp) if g != e) + abs(len(got) - len(exp))
    print(f"pe16x lockstep{' (FAULT=1)' if FAULT else ''}: {bad} mismatches / {len(exp)} cycles (got {len(got)} outputs)")


if __name__ == "__main__":
    main()
