"""Check the reduced, checked-in evidence without replaying raw SPICE.

The raw ngspice waveforms and external PDK/model inputs are documented in README.md. This script
checks only the committed NPZ/CSV/text artefacts and the deterministic Python pad fixture; it is a
consistency check, not an independent SPICE or silicon validation.
"""
from pathlib import Path
import math

import numpy as np

from padmodel import Pad, VT_SPICE


HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"
DATA = HERE / "ocaml" / "data"


def close(a, b, *, rtol=2e-6, atol=1e-15):
    return np.allclose(np.asarray(a), np.asarray(b), rtol=rtol, atol=atol)


def read_fit_params():
    params = {}
    for line in (RESULTS / "padmodel-fit.txt").read_text().splitlines():
        if line.startswith("param "):
            _, key, value = line.split()
            params[key] = float(value)
    return params


def read_csv_params():
    return {key: float(value) for key, value in
            (line.split(",") for line in (DATA / "pad_params.csv").read_text().splitlines())}


def check_parameters(pad):
    fit = read_fit_params()
    csv = read_csv_params()
    expected = {"C_a": pad.C_a, "C_m": pad.C_m, "tau_in": pad.tau_in,
                "v_lv": pad.v_lv, "d_lv": pad.d_lv, "vt": VT_SPICE}
    assert set(fit) == {"C_a", "C_m", "tau_in"}
    assert set(csv) == set(expected)
    for key, value in expected.items():
        assert math.isclose(csv[key], value, rel_tol=5e-5, abs_tol=1e-15), (key, csv[key], value)
    for key in fit:
        assert math.isclose(fit[key], csv[key], rel_tol=5e-5, abs_tol=1e-15), (key, fit[key], csv[key])


def check_pad_iv():
    with np.load(RESULTS / "pad-iv.npz") as z:
        assert set(z.files) == {"vin", "va", "tt", "ss", "ff"}
        vin, va = z["vin"], z["va"]
        assert vin.shape == (241,) and va.shape == (121,)
        assert np.all(np.diff(vin) > 0) and np.all(np.diff(va) > 0)
        for corner in ("tt", "ss", "ff"):
            current = z[corner]
            assert current.shape == (121, 241) and np.isfinite(current).all()
        table = np.genfromtxt(DATA / "pad_iv_tt.csv", delimiter=",")
        assert table.shape == (122, 242)
        assert close(table[0, 1:], vin, rtol=5e-5, atol=5e-5)
        assert close(table[1:, 0], va, rtol=5e-5, atol=5e-5)
        assert close(table[1:, 1:], z["tt"], rtol=5e-6, atol=1e-12)


def check_kick_tables():
    rows = [line.split(",") for line in (DATA / "kick_r500.csv").read_text().splitlines() if line]
    deltas = np.array([float(row[1]) for row in rows if row[0] == "D"])
    delays = np.array([float(row[2]) for row in rows if row[0] == "D"])
    positions = np.array([float(row[1]) for row in rows if row[0] == "W"])
    weights = np.array([float(row[2]) for row in rows if row[0] == "W"])
    with np.load(RESULTS / "kick.npz") as z:
        assert close(deltas, z["r500_deltas"], rtol=0, atol=5.1e-6)
        assert close(delays, z["r500_delay"], rtol=2e-6, atol=1e-15)
        assert close(positions, z["r500_pos"], rtol=2e-6, atol=1e-15)
        assert close(weights, z["r500_w"], rtol=2e-6, atol=1e-15)
        assert np.isfinite(z["r500_delay"]).all() and np.isfinite(z["r500_w"]).all()


def check_python_fixture(pad):
    rows = [line.split(",") for line in (DATA / "padcheck.csv").read_text().splitlines() if line]
    dt = 2e-12
    t = np.arange(0, 8e-9, dt)
    errors = []
    for offset_text, expected_text in rows:
        offset = float(offset_text)
        expected = float(expected_text)
        v = VT_SPICE - 0.25 + offset + 0.5 * np.clip((t - 3e-9) / 500e-12, 0, 1)
        core = pad.run(v[None, :], dt)[0]
        indices = np.flatnonzero(core)
        assert indices.size > 0
        errors.append(abs(t[indices[0]] - expected))
    assert max(errors) <= 2.01e-12
    return max(errors)


def check_required_results():
    for name in ("rx.txt", "rx-quick.txt", "infer.txt", "infer-quick.txt", "cs-quick.txt",
                 "padmodel-fit.txt", "padmodel-validate.txt"):
        assert (RESULTS / name).is_file(), name


def main():
    pad = Pad()
    report = [
        "# validate_artifacts.py: checked-in artefact consistency",
        "# Scope: reduced checked-in evidence only; raw SPICE replay is unavailable (see README.md).",
        "# This is not an independent SPICE or silicon validation.",
    ]
    checks = [
        ("required result files", check_required_results),
        ("fitted parameters and OCaml CSV agreement", lambda: check_parameters(pad)),
        ("pad IV NPZ/CSV grids and currents", check_pad_iv),
        ("kick NPZ/CSV aperture tables", check_kick_tables),
    ]
    for name, check in checks:
        check()
        report.append(f"PASS {name}")
    worst = check_python_fixture(pad)
    report.append(f"PASS Python padcheck fixture (worst difference {worst * 1e12:.1f} ps)")
    report.append(f"RESULT PASS ({len(checks) + 1} checks)")
    text = "\n".join(report) + "\n"
    print(text, end="")
    (RESULTS / "validation.txt").write_text(text)


if __name__ == "__main__":
    main()
