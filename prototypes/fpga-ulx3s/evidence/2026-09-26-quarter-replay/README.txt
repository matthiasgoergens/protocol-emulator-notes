Quarter-clock replay validation, 2026-09-26
==========================================

Scope
-----

This is simulation evidence for the uncommitted quarter-clock replay work
under prototypes/fpga-ulx3s. No board was attached. All runner commands used
the board's real divider, 60 clocks per UART bit. The toolchain for Verilator
and vcd2fst was:

  /home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin

The concise result index is summary.txt.

Build and host syntax checks
----------------------------

From prototypes/fpga-ulx3s/ocaml:

  nice ionice opam exec --switch=5.3.0 -- dune build \
    > ../evidence/2026-09-26-quarter-replay/ocaml-dune-build.log 2>&1

From prototypes/fpga-ulx3s:

  nice ionice uv run python -m py_compile host/emu_runner.py \
    > evidence/2026-09-26-quarter-replay/host-py-compile.log 2>&1

Both exited 0. The logs are empty, as expected.

The three RTL models were built with the following commands:

  env PATH=/home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin:/usr/bin:/bin \
    nice ionice bash sim/build.sh 60 plain \
    > evidence/2026-09-26-quarter-replay/sim-build-plain-cpb60.log 2>&1
  env PATH=/home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin:/usr/bin:/bin \
    nice ionice bash sim/build.sh 60 mp \
    > evidence/2026-09-26-quarter-replay/sim-build-mp-cpb60.log 2>&1
  env PATH=/home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin:/usr/bin:/bin \
    nice ionice bash sim/build.sh 60 mp-fault \
    > evidence/2026-09-26-quarter-replay/sim-build-mp-fault-cpb60.log 2>&1

All three exited 0. Each build log ends with the path of its Vemu_sim.

End-to-end simulation
---------------------

From prototypes/fpga-ulx3s:

  nice ionice uv run host/emu_runner.py --sim --cpb 60 --build plain \
    --controls --out evidence/2026-09-26-quarter-replay/plain-cpb60 \
    > evidence/2026-09-26-quarter-replay/plain-cpb60.log 2>&1
  nice ionice uv run host/emu_runner.py --sim --cpb 60 --build mp \
    --controls --out evidence/2026-09-26-quarter-replay/mp-cpb60 \
    > evidence/2026-09-26-quarter-replay/mp-cpb60.log 2>&1

Both exited 0 with "22 of 22 as expected": 18 normal tests passed and all 4
controls failed as intended. The controls flip one trace output, change one
instruction's immediate, run one SETP in the wrong sub-slot, and swap two
quarters in a recorded pin_sub nibble.

The quarter-specific measurements were:

  subslot_train, plain: 165 pin-1 edges; every spacing 17 quarters.
  subslot_train, mp: the same edges and 2,784 stage loopback quarters,
                     with 0 mismatches.
  quad_rx, plain: host bytes f0 f0 f0 f0.
  quad_rx, mp: host bytes 78 3c 1e 0f; 512 stage loopback quarters,
               with 0 mismatches.

The complete per-test checker output, traces, captures and summary.json are
in plain-cpb60/ and mp-cpb60/. The parent logs are plain-cpb60.log and
mp-cpb60.log.

Planted-fault control
---------------------

The focused negative-control command was:

  nice ionice uv run host/emu_runner.py --sim --cpb 60 --build mp-fault \
    --only subslot_train,quad_rx \
    --out evidence/2026-09-26-quarter-replay/mp-fault-cpb60 \
    > evidence/2026-09-26-quarter-replay/mp-fault-cpb60.log 2>&1

It exited 0 with "2 of 2 as expected". Both quad tests failed:
subslot_train had 41 loopback mismatches, while quad_rx had 2 loopback
mismatches and recovered 78 1e 1e 0f rather than 78 3c 1e 0f.

The first version of the planted fault dropped a sample only on pin 0, so the
pin-1 subslot_train correctly passed and the runner marked the control bad.
That run is preserved in mp-fault-before-fix/. The final fault drops quarter 2
on both staged pins, matching the runner's promise that every quad test fails.

VCD checks
----------

From prototypes/fpga-ulx3s:

  nice ionice ocaml/_build/default/fpga_tests.exe vcd \
    evidence/2026-09-26-quarter-replay/mp-cpb60/subslot_train.trace \
    --quarter-ps 4167 \
    > evidence/2026-09-26-quarter-replay/subslot_train-quarter.vcd
  nice ionice ocaml/_build/default/fpga_tests.exe vcd \
    evidence/2026-09-26-quarter-replay/mp-cpb60/quad_rx.trace \
    --quarter-ps 4167 \
    > evidence/2026-09-26-quarter-replay/quad_rx-quarter.vcd

Each VCD was independently parsed and converted to FST:

  /home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin/vcd2fst \
    evidence/2026-09-26-quarter-replay/subslot_train-quarter.vcd \
    evidence/2026-09-26-quarter-replay/subslot_train-quarter.fst \
    > evidence/2026-09-26-quarter-replay/subslot_train-vcd2fst.log 2>&1
  /home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin/vcd2fst \
    evidence/2026-09-26-quarter-replay/quad_rx-quarter.vcd \
    evidence/2026-09-26-quarter-replay/quad_rx-quarter.fst \
    > evidence/2026-09-26-quarter-replay/quad_rx-vcd2fst.log 2>&1

Both conversions exited 0 with empty logs. subslot_train spans 700 cycles and
ends at timestamp 11,667,600 ps; quad_rx spans 132 cycles and ends at
2,200,176 ps. These equal 4 * cycles * 4,167 ps.

Remaining caveats
-----------------

- This validates RTL simulation, not a rebuilt bitstream. The existing
  synthesis reports and bitstream predate the trace widening from 80 to 144
  bits, so their resource and timing figures do not describe this source.
- No physical four-phase pad timing or analogue behaviour was measured.
- The focused run used 60 clocks per UART bit. The older evidence directory
  also covers 8, but that run predates quarter replay.
