"""Regenerate the DDC traces, rendered artefacts, and independent checks.

Usage: uv run generate_ddc.py

The normal run is deterministic (ddc.ml seeds its random generator) and writes the four plain
text channel traces to out/. The planted-fault control runs for 0.35 s in out/ddc-fault/ so
the analysed interval contains every station programme.
"""
import os
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
NORMAL_SECONDS = "1.2"
FAULT_SECONDS = "0.35"
ANALYSE = ["uv", "run", "--with", "numpy", "--with", "matplotlib", "analyse_ddc.py"]


def run(command, env=None):
    print("+ " + shlex.join(command), flush=True)
    completed = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    print(completed.stdout, end="")
    return completed.stdout


def main():
    normal_dir = Path("out")
    fault_dir = Path("out/ddc-fault")
    normal_dir.mkdir(parents=True, exist_ok=True)
    fault_dir.mkdir(parents=True, exist_ok=True)

    run(["opam", "exec", "--switch=5.3.0", "--", "dune", "build"])
    normal_run = run(
        ["./_build/default/main.exe", "ddc", NORMAL_SECONDS, str(normal_dir)]
    )
    run(ANALYSE + [str(normal_dir), "results/ddc_check.txt"])

    fault_env = os.environ.copy()
    fault_env["UPE_FAULT"] = "negate"
    fault_run = run(
        ["./_build/default/main.exe", "ddc", FAULT_SECONDS, str(fault_dir)],
        env=fault_env,
    )
    run(
        ANALYSE
        + [str(fault_dir), "results/ddc_fault_check.txt", "--expect-fault"],
        env=fault_env,
    )

    expected = [normal_dir / f"ddc-ch{channel}.txt" for channel in range(4)]
    missing = [str(path) for path in expected if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise RuntimeError("missing DDC channel outputs: " + ", ".join(missing))

    run_log = "\n".join(
        [
            f"# normal: ./_build/default/main.exe ddc {NORMAL_SECONDS} {normal_dir}",
            normal_run.rstrip(),
            "# fault control: UPE_FAULT=negate "
            f"./_build/default/main.exe ddc {FAULT_SECONDS} {fault_dir}",
            fault_run.rstrip(),
        ]
    )
    (ROOT / "results/ddc.txt").write_text(run_log + "\n")


if __name__ == "__main__":
    sys.exit(main())
