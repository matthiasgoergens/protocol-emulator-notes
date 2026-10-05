#!/usr/bin/env python3
"""Instantiate sta_run.tcl (a template) for each corner x period combination."""

LIB_DIR = "/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib"
CORNERS = {
    "fast": f"{LIB_DIR}/sg13g2_stdcell_fast_1p32V_m40C.lib",
    "typ":  f"{LIB_DIR}/sg13g2_stdcell_typ_1p20V_25C.lib",
    "slow": f"{LIB_DIR}/sg13g2_stdcell_slow_1p08V_125C.lib",
}
PERIODS = {
    "15p0":  "/var/tmp/multiphase/sta/sta_15p0.sdc",
    "16p67": "/var/tmp/multiphase/sta/sta_16p67.sdc",
    "18p8":  "/var/tmp/multiphase/sta/sta_18p8.sdc",
}

with open("/var/tmp/multiphase/sta/sta_run.tcl") as f:
    template = f.read()

for corner, lib in CORNERS.items():
    for period, sdc in PERIODS.items():
        out = template
        out = out.replace("{{LIBERTY_FILE}}", lib)
        out = out.replace("{{SDC_FILE}}", sdc)
        out = out.replace("{{CORNER_LABEL}}", corner)
        out = out.replace("{{PERIOD_LABEL}}", period)
        fname = f"/var/tmp/multiphase/sta/sta_{corner}_{period}.tcl"
        with open(fname, "w") as g:
            g.write(out)
        print("wrote", fname)
