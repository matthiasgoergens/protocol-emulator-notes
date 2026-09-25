"""Make a copy of IHP's KLayout DRC deck with relaxed rule values, for checking layouts against
"the rules as relaxed" rather than only against the stock rules.

  uv run mkdeck.py OUTDIR [--keep-sram-exemption] RULE=VALUE ...

RULE is a rule name as the deck outputs it (e.g. Gat.c, NW.c, TGO.b, Cnt.c). The value is changed
in the maximal deck (sg13g2_maximal.drc: the literal "<old>.um" inside that rule's block) and, for
rules the main deck reads from the JSON (Cnt.c, Cnt.c.digibnd, Gat.b, Act.b, Cnt.f, ...), in
sg13g2_tech_default.json. Unless --keep-sram-exemption is given, the SRAM marker layer is replaced
by an empty layer in the maximal deck, so shapes under 25/0 are checked like any others (with the
relaxed values): a layout then passes only if it keeps to the stated values everywhere.
Every change made is printed and written to OUTDIR/CHANGES.txt."""
import sys, os, re, json, shutil
STOCK = os.path.expanduser("~/.ciel/ihp-sg13g2/ihp-sg13g2/libs.tech/klayout/tech/drc")
out = sys.argv[1]
args = sys.argv[2:]
keep = "--keep-sram-exemption" in args
rules = dict(a.split("=") for a in args if "=" in a)
if os.path.exists(out):
    shutil.rmtree(out)
shutil.copytree(STOCK, out)
log = []
mpath = os.path.join(out, "rule_decks", "sg13g2_maximal.drc")
m = open(mpath).read()
if not keep:
    m, n = re.subn(r'^SRAM = source\.polygons\("25/0"\)', 'SRAM = polygon_layer   # emptied by mkdeck.py', m, flags=re.MULTILINE)
    assert n == 1
    log.append("maximal: SRAM marker exemption removed (SRAM = empty layer)")
for rule, val in rules.items():
    pat = re.compile(r'output\("%s", "([^"]*)= ([\d.]+)"\)' % re.escape(rule))
    hit = pat.search(m)
    if hit:
        old = hit.group(2)
        start = m.rfind("-> ", 0, hit.start())
        block = m[start:hit.start()]
        nb, k = re.subn(r"\b%s\.um\b" % re.escape(old if "." in old else old + ".0"), f"{val}.um", block)
        if k == 0:
            nb, k = re.subn(r"\b%s\.um\b" % re.escape(str(float(old))), f"{val}.um", block)
        if k == 0:
            # some rules check a derived layer computed earlier (e.g. TGO.b uses
            # ThickGateOx_Act_out_ThickGateOx_TGO_b_sep_tmp1 = ...ext_separation(..., 0.27.um, ...))
            tok = "_" + rule.replace(".", "_") + "_"
            lines = m.split("\n")
            for i, line in enumerate(lines):
                if tok in line.split("=")[0] and f"{old}.um" in line:
                    lines[i] = line.replace(f"{old}.um", f"{val}.um"); k += 1
            assert k > 0, f"{rule}: value {old} not found in its block or its derived layers"
            m = "\n".join(lines)
            log.append(f"maximal: {rule} {old} -> {val} in {k} derived-layer definition(s)")
        else:
            m = m[:start] + nb + m[hit.start():]
        m = m.replace(hit.group(0), f'output("{rule}", "{hit.group(1)}= {val} (relaxed from {old})")', 1)
        log.append(f"maximal: {rule} {old} -> {val} ({k} substitution(s))")
open(mpath, "w").write(m)
# the main deck reads its values from the pycell library's sg13g2_tech_mod.json, falling back to
# rule_decks/sg13g2_tech_default.json; relax both, and make run_drc.py use our copy of the former
tech = os.path.join(os.path.dirname(os.path.dirname(STOCK)), "python", "sg13g2_pycell_lib", "sg13g2_tech_mod.json")
for src, dst in ((tech, os.path.join(out, "tech_mod_relaxed.json")),
                 (os.path.join(out, "rule_decks", "sg13g2_tech_default.json"),) * 2):
    j = json.load(open(src))
    for rule, val in rules.items():
        key = rule.replace(".", "_")
        if key in j["drc_rules"]:
            log.append(f"json {os.path.basename(dst)}: {key} {j['drc_rules'][key]} -> {val}")
            j["drc_rules"][key] = float(val)
    json.dump(j, open(dst, "w"), indent=4)
rp = os.path.join(out, "run_drc.py")
r = open(rp).read()
r2 = r.replace('script_dir / "../../python/sg13g2_pycell_lib/sg13g2_tech_mod.json"', 'script_dir / "tech_mod_relaxed.json"')
assert r2 != r
open(rp, "w").write(r2)
open(os.path.join(out, "CHANGES.txt"), "w").write("\n".join(log) + "\n")
print("\n".join(log))
