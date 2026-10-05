"""List the rules of IHP's maximal DRC deck that exempt shapes under the SRAM marker (25/0).

The deck builds X_Nsram = X.ext_not(SRAM) and uses it in place of X in some rules; a rule that
only sees *_Nsram shapes is not checked under the marker. We print every output() whose block
(text since the previous output) mentions Nsram or SRAM, with the derived layers it uses.
"""
import re, sys
path = sys.argv[1]
text = open(path).read()
# derived layers defined from Nsram layers, transitively
defs = dict(re.findall(r"^(\w+)\s*=\s*(.+)$", text, re.MULTILINE))
tainted = {k for k, v in defs.items() if "Nsram" in k or "SRAM" in v}
changed = True
while changed:
    changed = False
    for k, v in defs.items():
        if k not in tainted and any(re.search(r"\b%s\b" % re.escape(t), v) for t in tainted):
            tainted.add(k); changed = True
prev = 0
for m in re.finditer(r'output\("([^"]+)",\s*"([^"]*)"\)', text):
    block = text[prev:m.start()]
    prev = m.end()
    used = sorted({t for t in tainted if re.search(r"\b%s\b" % re.escape(t), block)})
    if used:
        print(f"{m.group(1):20s} {m.group(2)}\n    via: {', '.join(used)}")
