# Transient simulations of the IHP sg13g2_io pad cells for 100 Mbit/s Ethernet (ngspice 44.2 +
# PSP 103 via OSDI, in the spice-retention container). The host only writes netlists and starts
# containers; analysis is in analyse.py.
#
# Pads as Tiny Tapeout wires them on TTIHP 26a (tt_ihp_wrapper.v of tinytapeout-ihp-26a-foundry-
# submission): uo_out = sg13g2_IOPadOut30mA, uio = sg13g2_IOPadInOut30mA, ui_in = sg13g2_IOPadIn.
# IOVDD 3.3 V, core 1.2 V (the shuttle's Datasheet.md).
#
# The netlists include no supply inductance (ideal VDD/IOVDD/VSS) and no pad-metal or ESD-layout
# parasitics beyond what sg13g2_io.spi has, so ground bounce from several pins switching together
# is NOT modelled. Package + board are modelled as a bond wire (2 nH) and a lumped capacitance.
#
# usage: padsim.py <case> <corner> <temp> <rundir>
#   cases:
#     toggle    square waves at several toggle rates, one pad per rate, 4/16/30 mA, 10 pF each
#     eye_cap5  / eye_cap10   PRBS7 at 125 Mbaud into 5 / 10 pF (30 mA pad)
#     eye_sfp   two 30 mA pads in antiphase -> 150 ohm series each -> 50 ohm lines -> SFP input
#               (AC-coupled, 100 ohm differential)
#     eye_tx    two 30 mA pads, MLT-3 by pin pair -> 82 ohm series each, 250 ohm across the
#               primary -> 1:1 transformer -> 100 ohm line -> 100 ohm termination
#     in_dc     DC transfer of IOPadIn (pad swept 0..IOVDD), threshold per corner
#     in_ac     IOPadIn fed a 62.5 MHz square / small sine around its threshold (see below)
import os, random, subprocess, sys

PDK = "/pdk"
MODELS = f"{PDK}/libs.tech/ngspice/models"
CORNERS = {  # name: (mos, dio, res, vdd, iovdd)
    "tt": ("mos_tt", "dio_tt", "res_typ", 1.20, 3.3),
    "ss": ("mos_ss", "dio_ss", "res_wcs", 1.08, 3.0),
    "ff": ("mos_ff", "dio_ff", "res_bcs", 1.32, 3.6),
}
UI = 8e-9          # 125 Mbaud
TEDGE = 80e-12     # core-side edge time into c2p

def head(corner, temp):
    mos, dio, res, vdd, iovdd = CORNERS[corner]
    return f"""* pad test {corner} {temp}C
.lib {MODELS}/cornerMOSlv.lib {mos}
.lib {MODELS}/cornerMOShv.lib {mos}
.lib {MODELS}/cornerDIO.lib {dio}
.lib {MODELS}/cornerRES.lib {res}
.include /work/io.spi
.global sub!
.temp {temp}
vsub sub! 0 0
vvdd vdd 0 {vdd}
viovdd iovdd 0 {iovdd}
vvss vss 0 0
viovss iovss 0 0
.options method=gear reltol=1e-3 itl4=200
""", vdd, iovdd

def pwl_bits(bits, vdd, ui=UI, t0=2e-9):
    """PWL for a bit sequence, each bit held for one UI, edges TEDGE."""
    pts = [(0.0, bits[0] * vdd)]
    for i in range(1, len(bits)):
        if bits[i] != bits[i - 1]:
            t = t0 + i * ui
            pts.append((t, bits[i - 1] * vdd))
            pts.append((t + TEDGE, bits[i] * vdd))
    pts.append((t0 + len(bits) * ui + 1e-9, bits[-1] * vdd))
    return " ".join(f"{t:.4e} {v:.4g}" for t, v in pts)

def prbs7(n, seed=0x7F):
    s, out = seed, []
    for _ in range(n):
        b = ((s >> 6) ^ (s >> 5)) & 1
        s = ((s << 1) | b) & 0x7F
        out.append(b)
    return out

def nrzi(bits):
    lvl, out = 0, []
    for b in bits:
        lvl ^= b
        out.append(lvl)
    return out

def pkg(name, pad, node, c):
    # bond wire (2 nH, 1 ohm incl. skin loss) + package + PCB lumped
    return (f"lb{name} {pad} {node}_b 2n\nrb{name} {node}_b {node} 1\n"
            f"c{name} {node} 0 {c}\n")

def mlt3_pins(bits):
    """MLT-3 from a bit stream (1 = step to the next level in 0,+,0,-), as two pins A, B where the
    line level is A - B and exactly one pin toggles per step: + = (1,0), - = (0,1), and the zero
    level alternates between (0,0) and (1,1)."""
    seq = [0, 1, 0, -1]
    k, a, b = 0, 0, 0
    A, B, L = [], [], []
    for bit in bits:
        if bit:
            k = (k + 1) % 4
            lvl = seq[k]
            # exactly one pin changes
            if lvl == 1: a, b = 1, 0
            elif lvl == -1: a, b = 0, 1
            else:
                # leaving + (1,0): drop a -> (0,0); leaving - (0,1): raise a -> (1,1)
                if a == 1 and b == 0: a = 0
                else: a = 1
        A.append(a); B.append(b); L.append(a - b)
    return A, B, L

def scrambled(n, seed=1):
    random.seed(seed)
    return [random.getrandbits(1) for _ in range(n)]

def threshold(corner, temp):
    """The IOPadIn DC switching point (pad voltage where p2c crosses VDD/2) from the in_dc run."""
    vdd = CORNERS[corner][3]
    rows = [l.split() for l in open(f"/var/tmp/fast-eth/pads/in_dc-{corner}-{temp}/out.dat")][1:]
    prev = None
    for r in rows:
        v, o = float(r[1]), float(r[2])
        if prev is not None and prev[1] >= vdd / 2 > o or prev is not None and prev[1] < vdd / 2 <= o:
            return v
        prev = (v, o)
    raise SystemExit("no threshold crossing")

def netlist(case, corner, temp):
    h, vdd, iovdd = head(corner, temp)
    body, save, tstop, tstep = "", [], None, "10p"
    if case == "toggle":
        rates = [62.5e6, 100e6, 125e6, 166.7e6, 250e6, 333e6]   # toggles/s = 2 x square freq
        tstop = 120e-9
        for drv in ("4mA", "16mA", "30mA"):
            for j, r in enumerate(rates):
                period = 2.0 / r
                n = f"{drv}_{j}"
                body += (f"vc{n} c{n} 0 pulse(0 {vdd} 2n {TEDGE} {TEDGE} {period/2 - TEDGE:.4e} {period:.4e})\n"
                         f"x{n} vss vdd iovss iovdd c{n} p{n} sg13g2_IOPadOut{drv}\n" + pkg(n, f"p{n}", f"o{n}", "10p"))
                save += [f"o{n}"]
        tstep = "5p"
    elif case in ("eye_cap5", "eye_cap10"):
        c = "5p" if case == "eye_cap5" else "10p"
        bits = nrzi(prbs7(140))
        tstop = 2e-9 + 140 * UI
        body += (f"vc c 0 pwl({pwl_bits(bits, vdd)})\n"
                 f"xp vss vdd iovss iovdd c p sg13g2_IOPadOut30mA\n" + pkg("o", "p", "o", c))
        save += ["c", "p", "o"]
    elif case == "eye_sfp":
        bits = nrzi(prbs7(140))
        nbits = [1 - b for b in bits]
        tstop = 2e-9 + 140 * UI
        body += (f"vcp cp 0 pwl({pwl_bits(bits, vdd)})\nvcn cn 0 pwl({pwl_bits(nbits, vdd)})\n"
                 f"xpp vss vdd iovss iovdd cp pp sg13g2_IOPadOut30mA\n"
                 f"xpn vss vdd iovss iovdd cn pn sg13g2_IOPadOut30mA\n"
                 + pkg("p", "pp", "op", "5p") + pkg("n", "pn", "on", "5p") +
                 # series resistors at the chip, 50 ohm lines (8 cm), SFP: AC caps then 100 ohm diff
                 "rsp op lp 150\nrsn on ln 150\n"
                 "tlp lp 0 sp0 0 z0=50 td=0.5n\ntln ln 0 sn0 0 z0=50 td=0.5n\n"
                 "cap sp0 sp 100n\ncan sn0 sn 100n\nrt sp sn 100\nrbp sp 0 10k\nrbn sn 0 10k\n"
                 "cs sp0 0 1p\ncsn sn0 0 1p\n")
        save += ["op", "on", "sp", "sn"]
    elif case == "eye_tx":
        A, B, L = mlt3_pins(scrambled(160))
        tstop = 2e-9 + 160 * UI
        body += (f"vca ca 0 pwl({pwl_bits(A, vdd)})\nvcb cb 0 pwl({pwl_bits(B, vdd)})\n"
                 f"xpa vss vdd iovss iovdd ca pa sg13g2_IOPadOut30mA\n"
                 f"xpb vss vdd iovss iovdd cb pb sg13g2_IOPadOut30mA\n"
                 + pkg("a", "pa", "oa", "5p") + pkg("b", "pb", "ob", "5p") +
                 "rsa oa pria 82\nrsb ob prib 82\nrp pria prib 250\n"
                 # 1:1 magnetics: 350 uH OCL, ~0.3 uH leakage, 10 pF winding capacitance each side
                 "l1 pria prib 350u\nl2 seca secb 350u\nk1 l1 l2 0.99957\n"
                 "cw1 pria prib 5p\ncw2 seca secb 5p\nrref secb 0 1meg\n"
                 # 1 m of 100 ohm twisted pair (lossless here; loss is in the channel model), 100 ohm
                 "tl seca secb la lb z0=100 td=5n\nrl la lb 100\nrlr lb 0 1meg\n")
        save += ["oa", "ob", "pria", "prib", "seca", "secb", "la", "lb"]
    elif case == "in_dc":
        body += (f"vpad pad 0 0\nxi vss vdd iovss iovdd p2c pad sg13g2_IOPadIn\ncl p2c 0 5f\n")
        ctl = f"dc vpad 0 {iovdd} 0.002\nwrdata /work/out.dat v(pad) v(p2c)\n"
        return h + body + control(ctl)
    elif case.startswith("in_ac") or case == "in_full":
        # in_ac_<amp_mV>_<offset_mV>: a sine of the given peak amplitude at 62.5 MHz (the
        # fundamental of 125 Mbaud 1010) centred <offset> above this corner's DC threshold (read
        # from the in_dc run), through 50 ohm, 3 pF board + package and the 2 nH bond wire.
        # in_full: a full-swing 0..IOVDD 62.5 MHz square wave (1 ns edges) the same way.
        if case == "in_full":
            src = f"pulse(0 {iovdd} 2n 1n 1n 7n 16n)"
        else:
            _, _, amp, off = case.split("_")
            thr = threshold(corner, temp)
            src = f"sin({thr + float(off)/1000:.4f} {float(amp)/1000} 62.5meg)"
        body += (f"vs s 0 {src}\nrs s pb 50\n"
                 "cpb pb 0 3p\nlb pb pad 2n\n"
                 f"xi vss vdd iovss iovdd p2c pad sg13g2_IOPadIn\ncl p2c 0 10f\n")
        save += ["s", "pad", "p2c"]
        tstop = 200e-9
        tstep = "10p"
    else:
        raise SystemExit(f"unknown case {case}")
    ctl = (f"tran {tstep} {tstop:.4e}\n"
           f"wrdata /work/out.dat {' '.join('v(' + s + ')' for s in save)}\n")
    return h + body + control(ctl)

DIODES_FX = """
.model darea_fx D (tnom=27 is=2.315E-019 n=1.009 rs=2.193E+005 cj0=9.371E-016 m=0.3036 vj=0.696 fc=0.5 xti=5.039)
.model dperim_fx D (tnom=27 is=3.851E-021 n=1.022 rs=1.688E+006 cj0=1.821E-017 m=0.01923 vj=0.598 xti=3)
.model dparea_fx D (tnom=27 is=8.569E-020 n=1.003 rs=1.728E+005 cj0=8.252E-016 m=0.3171 vj=0.6628 fc=0.5 xti=4.56)
.model dpperim_fx D (tnom=27 is=1.186E-020 n=1.006 rs=1.577E+006 cj0=3.657E-017 m=0.1512 vj=0.5241 xti=4.118)
.subckt dantenna_fx 1 2 l=780n w=780n
D1 1 2 darea_fx area={l*w/1p}
D2 1 2 dperim_fx area={(l+w)/0.5u}
.ends dantenna_fx
.subckt dpantenna_fx 1 2 l=780n w=780n
D1 1 2 dparea_fx area={l*w/1p}
D2 1 2 dpperim_fx area={(l+w)/0.5u}
.ends dpantenna_fx
"""

def control(ctl):
    return f""".control
pre_osdi /work/osdi/psp103.osdi
pre_osdi /work/osdi/r3_cmc.osdi
set wr_singlescale
set wr_vecnames
option numdgt=7
{ctl}quit
.endc
.end
"""

if __name__ == "__main__":
    case, corner, temp, rundir = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    os.makedirs(rundir + "/osdi", exist_ok=True)
    subprocess.run(["cp", "--no-clobber", "/var/tmp/fast-eth/osdi/psp103.osdi", "/var/tmp/fast-eth/osdi/r3_cmc.osdi", rundir + "/osdi/"], check=True)
    # The PDK netlist with the clamp-gate antenna diodes (XDGATE, 0.64 x 0.48 um dantenna /
    # dpantenna, a fraction of a femtofarad) commented out: with them, every transient that
    # switches the output driver stops with "timestep too small" at the diode's internal node
    # (reproduced in isolation: level shifter + clamps fails, the same without XDGATE runs). The
    # large ESD diodes on the pad itself (sg13g2_DCNDiode / DCPDiode) are kept.
    spi = open(os.path.expanduser("~/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_io/spice/sg13g2_io.spi")).read()
    with open(rundir + "/io.spi", "w") as f:
        spi = spi.replace("\nXDGATE", "\n*XDGATE")
        # The pad ESD diodes use the same dantenna / dpantenna models, and fail the same way when
        # the pad passes through 0 V (reproduced: 1 us into a PRBS run, "trouble with node
        # viovss#branch" as the pad settles to 26 mV). Replace them with copies of the PDK model
        # cards keeping saturation current, emission coefficient, series resistance and junction
        # capacitance, and dropping the breakdown (bv, ibv, nbv, tcv), recombination (isr) and
        # high-injection (ik) terms, which only matter far outside a 0..IOVDD signal.
        spi = spi.replace(" dantenna ", " dantenna_fx ").replace(" dpantenna ", " dpantenna_fx ")
        f.write(spi + DIODES_FX)
    with open(rundir + "/tb.cir", "w") as f:
        f.write(netlist(case, corner, temp))
    if os.environ.get("NORUN"):
        sys.exit(0)
    with open(rundir + "/ngspice.log", "w") as log:
        r = subprocess.run(["nice", "ionice", "--class", "3", "podman", "run", "--rm",
                            "--volume", os.path.expanduser("~/.ciel/ihp-sg13g2/ihp-sg13g2") + ":/pdk:ro",
                            "--volume", rundir + ":/work", "--workdir", "/work",
                            "spice-retention:latest", "ngspice", "-b", "/work/tb.cir"],
                           stdout=log, stderr=subprocess.STDOUT)
    print(rundir, "exit", r.returncode)
