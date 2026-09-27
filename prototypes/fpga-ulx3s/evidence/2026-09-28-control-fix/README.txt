Focused negative-control selection, 2026-09-28
=============================================

Question
--------

A focused quarter replay

  --only subslot_train,quad_rx --controls

originally selected `subslot_train` as the generic trace and imem control after
`--only` had removed `uart_loop`.  `subslot_train` has no LDD n>1, so setup of
the imem mutation raised StopIteration after the two normal tests and the trace
control had run.  That abort hid whether the remaining controls worked.

The fix keeps the unfiltered manifest for the generic controls and requires
`uart_loop`, while quarter controls remain tied to selected tests eligible for
their mutations.  Mutation construction failures are infrastructure errors,
not negative controls that happened to fail.

Commands
--------

  nice ionice uv run --with pytest pytest -q host/test_emu_runner.py
  nice ionice uv run python -m unittest host.test_emu_runner

  nice ionice opam exec --switch=5.3.0 -- dune build
  nice ionice uv run python -m py_compile host/emu_runner.py host/test_emu_runner.py
  env PATH=/home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin:/usr/bin:/bin \
    nice ionice bash sim/build.sh 60 plain
  env PATH=/home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin:/usr/bin:/bin \
    nice ionice bash sim/build.sh 60 mp
  env PATH=/home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin:/usr/bin:/bin \
    nice ionice bash sim/build.sh 60 mp-fault

  nice ionice uv run host/emu_runner.py --sim --cpb 60 --build plain \
    --only subslot_train,quad_rx --controls \
    --out /tmp/fpga-quarter-control-fixed-plain
  nice ionice uv run host/emu_runner.py --sim --cpb 60 --build mp \
    --only subslot_train,quad_rx --controls \
    --out /tmp/fpga-quarter-control-fixed-mp

  nice ionice uv run host/emu_runner.py --sim --cpb 60 --build plain \
    --controls --out evidence/2026-09-28-control-fix/plain-cpb60
  nice ionice uv run host/emu_runner.py --sim --cpb 60 --build mp \
    --controls --out evidence/2026-09-28-control-fix/mp-cpb60
  nice ionice uv run host/emu_runner.py --sim --cpb 60 --build mp-fault \
    --controls --out evidence/2026-09-28-control-fix/mp-fault-cpb60

  nice ionice ocaml/_build/default/fpga_tests.exe vcd \
    evidence/2026-09-28-control-fix/mp-cpb60/subslot_train.trace \
    --quarter-ps 4167 \
    > evidence/2026-09-28-control-fix/subslot_train-quarter.vcd
  nice ionice ocaml/_build/default/fpga_tests.exe vcd \
    evidence/2026-09-28-control-fix/mp-cpb60/quad_rx.trace \
    --quarter-ps 4167 \
    > evidence/2026-09-28-control-fix/quad_rx-quarter.vcd
  /home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin/vcd2fst \
    evidence/2026-09-28-control-fix/subslot_train-quarter.vcd \
    evidence/2026-09-28-control-fix/subslot_train-quarter.fst
  /home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin/vcd2fst \
    evidence/2026-09-28-control-fix/quad_rx-quarter.vcd \
    evidence/2026-09-28-control-fix/quad_rx-quarter.fst

Results
-------

- The five unit tests pass under both pytest and unittest.
- Each focused run reports 6 of 6 as expected: both quarter tests pass and
  the uart_loop trace/imem plus subslot_train q/swap controls fail as required.
- Each full run reports 22 of 22 as expected.  Plain and four-phase pass all
  18 functional tests and all 4 controls fail as required.
- In the planted-fault build, `subslot_train` and `quad_rx` fail as required
  while the other 16 functional tests pass; all 4 controls also fail as
  required.  `quad_rx` reports 78 1e 1e 0f instead of 78 3c 1e 0f.
- Every summary has zero skipped entries and zero infrastructure errors.
- The OCaml build, Python compilation and all three Verilator builds exit 0.
  Their empty or build-only logs are ocaml-dune-build.log, host-py-compile.log
  and sim-build-*-cpb60.log.
- Both quarter VCDs convert to non-empty FST files.  Their final timestamps
  are 11,667,600 ps and 2,200,176 ps, exactly 4 * cycles * 4,167 ps.

Raw per-test traces, captures, checker reports, simulator logs and summaries
are in plain-cpb60/, mp-cpb60/ and mp-fault-cpb60/.
