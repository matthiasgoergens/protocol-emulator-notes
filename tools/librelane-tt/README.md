# tools/librelane-tt: LibreLane as Tiny Tapeout runs it for sg13cmos5l

A pinned, local copy of the place-and-route environment that Tiny Tapeout's GDS action uses for
the IHP `sg13cmos5l` shuttle. Rootless podman only: nothing is installed on the host, and the
shared `~/.ciel` is not used.

    tools/librelane-tt/build.sh      # builds localhost/librelane-tt:3.1.0.dev3, writes versions.txt

Users: `prototypes/postlayout-roundtrip/run_pnr.sh` (the default for `ihp-sg13cmos5l`) and
`tt/scripts/harden.sh`.

## What Tiny Tapeout's action does

TinyTapeout/tt-gds-action, branch `ihp-cmos5l`, commit 3412659 (read 2026-10-05):

- **LibreLane:** `pip install librelane==3.1.0.dev3` (the `librelane-version` input's default) into
  Python 3.11 from `actions/setup-python`, then `tt/tt_tool.py --harden --ihp`, which runs
  `python -m librelane --dockerized --pdk ihp-sg13cmos5l --manual-pdk ...`. With `--dockerized`,
  LibreLane runs itself again inside `ghcr.io/librelane/librelane:<its own version>` (unless
  `LIBRELANE_IMAGE_OVERRIDE` says otherwise), so **every EDA tool comes from that image**; the
  action installs no Magic, KLayout, OpenROAD or Yosys of its own.
- **Magic, KLayout, OpenROAD, Yosys:** therefore the image's: Magic 8.3.674, KLayout 0.30.9,
  OpenROAD 2026-02-17 (`openroad -version` prints dcf36133), Yosys 0.66, Netgen 1.5.320 (all in
  `versions.txt`, all from the image's Nix store). The host-side `klayout==0.29.12` Python wheel in
  tt-support-tools' `requirements.txt` is used only for the PNG render and the precheck, not for
  the GDS.
- **PDK:** `install_sg13cmos5l.sh` makes a shallow git checkout of IHP-Open-PDK at
  2bbec755dc67ca3db0261c3d6163e15735d66710 (dev branch, 2026-09-08) into `$PDK_ROOT` and writes
  `ihp-sg13cmos5l/SOURCES`; ciel is not used, and ciel 3.0's releases do not carry this revision.
- **tt-support-tools:** branch `ihp-sg13cmos5l` (the action's `tools-ref` default), commit d66cf17
  on 2026-10-05.

## The pin here

`Containerfile` is `FROM ghcr.io/librelane/librelane@sha256:f454022a...` — the x86_64 manifest
of tag `3.1.0.dev3` (the multi-arch index is sha256:d109140b...), so a re-pushed tag cannot change
what is built. The build fails unless the image reports LibreLane 3.1.0.dev3 and Magic 8.3.674.
The PDK is the checkout `install_sg13cmos5l.sh` makes, at `/var/tmp/roundtrip-cmos5l/pdk`, mounted
read-only by `run_pnr.sh`.

Note the dates: 3.1.0.dev3 reached PyPI on 2026-08-13, between 3.0.9 (08-12) and 3.0.10 (08-15),
so 3.0.14 (09-06) is *newer* than it, on the 3.0 branch, and still has the older Magic. A newer
version number on the 3.0 branch does not bring the 3.1 branch's tools.

## Why LibreLane 3.0.14 cannot finish a sg13cmos5l run

The IHP-Open-PDK 2bbec755 techfile `ihp-sg13cmos5l/libs.tech/magic/ihp-sg13cmos5l.tech` says
`requires magic-8.3.657` (line 34). The 3.0.14 image has Magic 8.3.623 (KLayout 0.30.7, Yosys
0.62, the same OpenROAD commit). Magic rejects the techfile's version section ("Magic version
8.3.657 is required by this techfile, but this version of magic is 8.3.623"), carries on with an
incomplete technology, cannot read the routed DEF ("DEF read, Line 67 (Error): No cut layer") and
then spins at 100% CPU with an empty log: 13 minutes in `Magic.StreamOut` and 7 in
`Magic.WriteLEF` before the run was stopped (4 and 8 s for the same block on `sg13g2`). Switching
off Magic's stream-out does not help, because `Odb.CheckDesignAntennaProperties` needs Magic's LEF.
Every step before Magic completes, including KLayout's stream-out, so the earlier round trip used
the GDS of step 56 (`prototypes/postlayout-roundtrip/README.md`, "Port to SG13CMOS5L").

With this image the same block runs to the end: 67 steps in 197 s, exit 0, Magic stream-out and
LEF in 7.2 s each. Results: `prototypes/postlayout-roundtrip/README.md`, "The same block with
LibreLane 3.1.0.dev3".

The Tiny Tapeout harness in `tt/` also hardens end to end through `tt/scripts/harden.sh`
(`tt_tool.py --create-user-config --ihp` and `--harden --ihp`, the 6x4 tile, its DEF template):
exit 0 after 1,763 s, 9,621 cells, routing DRC 0, Magic DRC 0, LVS 0, antenna 0, worst setup
slack +10.39 ns and hold +0.12 ns at 20 ns; Magic DRC took 17 minutes and detailed routing 10.
`pdk.json` there records LibreLane 3.1.0.dev3 and IHP-Open-PDK 2bbec755, as the action's would
(`results/tt-harden/`; the run itself is in `/var/tmp/librelane-tt/tt-harden-1/`).

## Where this still differs from the action

- **Container engine.** The action uses the GitHub runner's docker and pulls by tag; here rootless
  podman runs the digest-pinned image. `run_pnr.sh` calls `librelane` inside the image directly,
  as `--dockerized` itself does after re-launching; `tt/scripts/harden.sh` goes through
  `tt_tool.py` and `python -m librelane --dockerized` exactly as the action does, with
  `LIBRELANE_CONTAINER_ENGINE` and `LIBRELANE_IMAGE_OVERRIDE` pointing at podman and this image.
- **Mounts.** `--dockerized` mounts `$HOME` and `PDK_ROOT` read-write into the container.
  `harden.sh` sets HOME to its scratch directory for that call, so only the stage and the PDK are
  visible; the PDK is still mounted writable there, as in the action (`run_pnr.sh` mounts it
  read-only).
- **Provenance fields.** `commit_id.json` names a throwaway repository (`harden.sh` stages a copy
  of `tt/` and commits it), and `workflow_url` is null outside GitHub Actions.
- **Flow configuration.** `run_pnr.sh` runs our block's own `librelane.json` (no Tiny Tapeout
  tile, DEF template or pin order, and KLayout XOR, DRC and LVS switched off); only `harden.sh`
  uses the Tiny Tapeout configuration (`tt_tool.py --create-user-config`).
- **Precheck.** `tt/scripts/precheck.sh` runs tt-support-tools' `precheck/precheck.py` (d66cf17) as the
  action's precheck step does, but in a project-local uv venv (Python 3.11, `precheck/requirements.txt`)
  with a `klayout` shim that runs the image's KLayout 0.30.9 under podman. The action takes KLayout
  and Magic from a pinned nixpkgs (`precheck/default.nix`; `tool-versions.json` says KLayout 0.30.4,
  Magic 8.3.568), through `nix-shell`; on the sg13cmos5l path only KLayout is used. Results:
  `results/tt-precheck/`.
- **Not reproduced:** the action's apt packages (`librsvg2-bin`, `pngquant`, `ghdl-llvm`; PNG
  render and VHDL only), the precheck's Nix environment, and the GitHub artefact uploads.
- **Moving targets.** The action's branch and tt-support-tools' branch are not pinned upstream;
  the commits above are what they were on 2026-10-05. The PDK revision is pinned by the action.
