# Rewrite the chip's generated Verilog (chip_tt.v) for the whole-chip power-up proof: each IHP SRAM
# macro instance becomes ports of the module, so the harness can give both copies one shared memory.
#
#   stub_sram.py chip_tt.v chip_pu.v [state]
#
# Per macro N (in order of appearance) the module gains
#   output [AW-1:0]  pu_raddr_N   the address of the previous clock (the macro reads every clock:
#                                 A_MEN and A_REN are tied high)
#   input  [DW-1:0]  pu_dout_N    the read data, driven by the harness
#   output [..]      pu_in_N      {A_WEN, A_ADDR, A_DIN, A_BM}: what the macro would be given now
# and the module is renamed chip_pu.  With "state", it also gains
#   output [..]      pu_state     every other register, concatenated
#   output [..]      pu_held      every register loaded under an enable and never cleared
# for the proof's inductive helper (chip_powerup.sv, STATE_EQ and HELD_EQ).  Nothing else changes.
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
with_state = sys.argv[3:] == ["state"]
s = open(src).read()
assert s.count("module chip_tt (") == 1
s = s.replace("module chip_tt (", "module chip_pu (", 1)

inst = re.compile(r"RM_IHPSG13_1P_(\d+)x(\d+)_c2_bm_bist\s+(\w+)\s*\((.*?)\);", re.S)
ports, decls, n = [], [], 0


def stub(m):
    global n
    words, width, name, body = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
    conn = dict(re.findall(r"\.(\w+)\(([^()]*(?:\[[^\]]*\])?)\)", body))
    for need in ("A_CLK", "A_MEN", "A_REN", "A_WEN", "A_ADDR", "A_DIN", "A_BM", "A_DOUT"):
        assert need in conn, (name, need)
    # the proof's memory model reads every clock; refuse an instance where that is not so
    assert conn["A_MEN"] == "vdd" and conn["A_REN"] == "vdd" and conn["A_CLK"] == "clk", conn
    # and nothing else steers it: the delay trim fixed, the BIST mux off
    assert conn["A_DLY"] == "vdd" and conn["A_BIST_EN"] == "gnd", conn
    aw = (words - 1).bit_length()
    n += 1
    ports.extend([f"pu_raddr_{n}", f"pu_dout_{n}", f"pu_in_{n}"])
    decls.append(
        f"    output [{aw - 1}:0] pu_raddr_{n};\n"
        f"    input [{width - 1}:0] pu_dout_{n};\n"
        f"    output [{1 + aw + 2 * width - 1}:0] pu_in_{n};\n"
    )
    return (
        f"/* {name}: stubbed by stub_sram.py */\n"
        f"    reg [{aw - 1}:0] pu_raddr_q_{n};\n"
        f"    always @(posedge clk) pu_raddr_q_{n} <= {conn['A_ADDR']};\n"
        f"    assign pu_raddr_{n} = pu_raddr_q_{n};\n"
        f"    assign {conn['A_DOUT']} = pu_dout_{n};\n"
        f"    assign pu_in_{n} = {{{conn['A_WEN']}, {conn['A_ADDR']}, {conn['A_DIN']}, {conn['A_BM']}}}"
    )


s, count = inst.subn(lambda m: stub(m) + ";", s)
assert count == 2, count
if with_state:
    width = {m.group(4): int(m.group(2)) - int(m.group(3)) + 1 if m.group(1) else 1
             for m in re.finditer(r"^\s*reg\s*(\[(\d+):(\d+)\])?\s*(\w+)\s*;", s, re.M)}
    # loaded under an enable and never cleared: they hold their power-up value until written.
    # Other registers are cleared at reset, through "if (reset_sync)", "if (reset_sync | x)" or a
    # mux on D, or (the reset synchroniser, input stages) follow the inputs; pu_state takes them
    # all and bmc_state checks that reset makes them equal.
    resets = {"reset_sync"} | set(re.findall(r"assign (\w+) = reset_sync \|", s))
    held = [r for c, r in re.findall(r"always @\(posedge \w+\) begin\s*if \((\w+)\)\s*(\w+) <=", s)
            if c not in resets and not re.search(r"if \(" + c + r"\)\s*" + r + r" <= [^;]+;\s*else", s)]
    regs = [r for r in dict.fromkeys(re.findall(r"^\s*(\w+) <=", s, re.M))
            if r not in held and not r.startswith("pu_raddr_q_")]
    for port, rs in (("pu_state", regs), ("pu_held", held)):
        assert rs and all(r in width for r in rs)
        bits = sum(width[r] for r in rs)
        ports.append(port)
        decls.append(f"    output [{bits - 1}:0] {port};\n")
        s = s.replace("endmodule", f"    assign {port} = {{{', '.join(rs)}}};\nendmodule", 1)
        print(f"{port}: {len(rs)} registers, {bits} bits", file=sys.stderr)
header_end = s.index(");", s.index("module chip_pu ("))
s = s[:header_end] + "".join(f",\n    {p}" for p in ports) + "\n" + s[header_end:]
first_decl = s.index("    input rst_n;")
s = s[:first_decl] + "".join(decls) + s[first_decl:]
open(dst, "w").write(s)
print(" ".join(f"{p}" for p in ports))
