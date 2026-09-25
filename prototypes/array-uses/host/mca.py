"""Static cycle counts for the host kernels (kernels.c) on one Cortex-M33 core.

Compiles kernels.c with clang for thumbv8m.main (Cortex-M33, DSP), finds each function's
innermost loop (the shortest span from a label to a branch back to it), and runs llvm-mca's
Cortex-M33 model on that span. Writes results/host_cycles.txt with the timed assembly, so a
reader can see exactly what was counted.

Model limits (stated in the output too): one core; single-cycle SRAM, no contention, no
interrupts; llvm-mca charges a taken branch as an ordinary instruction, while the M33 refills
its pipeline (I add 2 cycles per iteration as the pessimistic column); a loop body with an
if/else is timed as both arms executed, which over-counts.
"""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "results" / "host_cycles.txt"
ASM = Path("/var/tmp/array-uses/kernels.s")
CC = ["clang", "--target=thumbv8m.main-none-eabi", "-mcpu=cortex-m33", "-mthumb",
      "-mfloat-abi=soft", "-O2", "-fno-unroll-loops", "-S", "-o", str(ASM), str(HERE / "kernels.c")]
MCA = ["llvm-mca", "-mtriple=thumbv8m.main-none-eabi", "-mcpu=cortex-m33", "-iterations=1000"]

# per function: which loop to time when there are several ("inner" = shortest span)
PICK = {}


def functions(asm):
    cur, out = None, {}
    for line in asm.splitlines():
        m = re.match(r"^(k\w+):", line)
        if m:
            cur = m.group(1); out[cur] = []; continue
        if cur and line.strip().startswith(".Lfunc_end"):
            cur = None; continue
        if cur:
            out[cur].append(line)
    return out


def loops(body):
    labels = {}
    for i, l in enumerate(body):
        m = re.match(r"^(\.LBB\w+):", l)
        if m:
            labels[m.group(1)] = i
    spans = []
    for i, l in enumerate(body):
        m = re.match(r"^\s+(b\w*|cbn?z)\s+(?:\w+,\s*)?(\.LBB\w+)", l)
        if m and m.group(2) in labels and labels[m.group(2)] < i:
            spans.append((labels[m.group(2)], i))
    return spans


def instrs(lines):
    keep = []
    for l in lines:
        s = l.split("@")[0].rstrip()
        if not s.strip() or s.strip().startswith(".") or s.rstrip().endswith(":"):
            continue
        keep.append(s)
    return keep


def main():
    subprocess.run(CC, check=True)
    asm = ASM.read_text()
    res = []
    for name, body in functions(asm).items():
        sp = loops(body)
        if not sp:
            res.append((name, None, None, 0, "no loop found")); continue
        a, b = min(sp, key=lambda s: s[1] - s[0])
        code = instrs(body[a:b + 1])
        src = "\n".join(code) + "\n"
        tmp = Path(f"/var/tmp/array-uses/{name}.s"); tmp.write_text(src)
        r = subprocess.run(MCA + [str(tmp)], capture_output=True, text=True)
        m = re.search(r"Total Cycles:\s+(\d+)", r.stdout)
        cyc = int(m.group(1)) / 1000 if m else None
        res.append((name, cyc, cyc + 2 if cyc else None, len(code), src))
    lines = ["Host kernels: llvm-mca " + subprocess.run(["llvm-mca", "--version"], capture_output=True,
             text=True).stdout.split("\n")[1].strip() + ", -mcpu=cortex-m33, 1000 iterations of the innermost loop",
             "compiler: " + " ".join(CC), "",
             f"{'kernel':24} {'instr':>5} {'cyc/iter (mca)':>15} {'cyc/iter +2 branch':>19}"]
    for name, c, c2, n, _ in res:
        lines.append(f"{name:24} {n:5d} {c if c is not None else float('nan'):15.2f} {c2 if c2 is not None else float('nan'):19.2f}")
    lines += ["", "Timed assembly (the innermost loop of each function):", ""]
    for name, c, _, n, src in res:
        lines += [f"--- {name}", src]
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:4 + len(res)]))


if __name__ == "__main__":
    sys.exit(main())
