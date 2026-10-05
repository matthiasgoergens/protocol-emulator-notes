Commands behind the logs here (2026-10-05, branch postlayout-roundtrip; GDS from
`./run_pnr.sh ../deadline-sequencer /var/tmp/postlayout-roundtrip/pnr seq15ns`, LibreLane 3.0.14,
IHP sg13g2 PDK at ~/.ciel/ihp-sg13g2; OCaml 5.3.0 switch, Hardcaml v0.17).
G = /var/tmp/postlayout-roundtrip/pnr/runs/seq15ns/final/gds/deadline_sequencer.gds,
M = the PDK's sg13g2_stdcell.v, L = sg13g2_stdcell_typ_1p20V_25C.lib.

- check.log: roundtrip_check.exe check $G deadline_sequencer ../deadline-sequencer/deadline_sequencer.v $M
- controls.log: roundtrip_check.exe controls $G deadline_sequencer ../deadline-sequencer/deadline_sequencer.v $M OUTDIR 10 1
- test_cells.log: test_cells.exe $M $L; test_cells_planted.log: the same with a21oi's or->and and tiehi 1'b1->1'b0
- check_foreign_layer.log: check on a copy of $G with a rectangle on layer 11/0 added by gdstk
- lockstep_full.log: seq_lockstep.exe $G $M 300 2000 (before the structural line and toggle count were added)
- lockstep_generic.log: seq_lockstep.exe $G $M 300 2000 --generic (clear pulsed 1 cycle in 64)
- lockstep_gds_controls.log: seq_lockstep.exe $G $M 20 2000 OUTDIR/*.gds (the 20 controls above)
- lockstep_swaps.log: seq_lockstep.exe $G $M 20 2000 --swaps 50 1
- lockstep_swaps_missed_300.log: seq_lockstep.exe $G $M 300 2000 --swaps 50 1 11 18 28 31 33
- lockstep_generic_swaps.log: seq_lockstep.exe $G $M 20 2000 --generic --swaps 50 1 11 18 28 31 33
- librelane_counts.txt / our_counts.txt: per-cell-type counts in LibreLane's final nl.v and in the extraction
- codex-review.md: the cross-model review's findings (codex, gpt-6-luna); findings 1-4 fixed, 5 answered in the README, 6 is roundtrip.sh
- test_via_overlap_before.log / test_via_overlap.log: test_via_overlap.exe /var/tmp/roundtrip-cmos5l/p3/viatest.gds,
  before and after via joins required positive overlap (2026-10-05, branch roundtrip-cmos5l); check.log was
  regenerated after the change (identical netlist; the extract line now counts touch-only via pairs)
