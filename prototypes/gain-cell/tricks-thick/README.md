# Tricks on the thick-oxide side (2026-09-25)

What each trick buys the 3T gain cell, simulated with one method (`gc.py`, `life.py`): write from
the opposite value, hold with WBL at the opposite value (the worst case, unless stated), read a
32-cell column with the other 31 cells holding 1.0 V, and take the lifetime as the time until
the stored 1 falls, or the stored 0 rises, past the lowest level that still reads. Worst case over
tt/ff/ss at 27 and 85 °C. All figures are SPICE (ngspice 44.2, PSP 103) unless marked
**estimate**. The full table is `results/summary-vm70.txt` (`summary.py`).

| cell | inverter 10 ns | inverter 20 ns | latch 5 ns |
|---|---|---|---|
| today's cell (thin storage transistor) | fails (ss/27) | 9.0 ms | 15.6 ms |
| thin + 1 fF storage cap | 16 ms | 25 ms | 40 ms |
| thin + WWL at 2.2 V | 5.9 ms | 9.2 ms | 15 ms |
| all thick | fails | fails | fails |
| all thick + 0.5 fF RWL coupling | 71 ms | 17 ms | 127 ms |
| all thick + WWL 2.2 V | 112 ms | 143 ms | 152 ms |
| all thick + WWL 2.2 V + 1 fF storage cap | 296 ms | **368 ms** | 390 ms |
| ... + WBL idle at 0.6 V | 404 ms | 514 ms | 548 ms |

"Latch" is a StrongARM against a matched reference column, with 70 mV margin each side (4σ of
the measured offset, below).

## Findings

1. **The boosted write word line is the trick that matters, and only for a thick-oxide storage
   transistor.** A charge pump (`wwl.py`: cross-coupled doubler at 100 MHz, two thin-oxide
   flying capacitors of 10 µm², a 100 µm² thick-oxide reservoir) reaches VPP 2.31 V in about
   0.1 µs. A thick-oxide level shifter and inverter per row drive the word line to 2.25 V. The
   far-end cell of 32 then writes 1.06 V (thick storage transistor) or 1.02 V (thin), in every
   corner (`results/wwl-pump.txt`, `wwl-pump-lvMS.txt`). No node exceeds 2.33 V; the thin-oxide
   flying capacitors see at most 1.20 V gate to channel. With a 40 µm² reservoir the word line
   still reaches 2.17 V and writes 1.06 V (`wwl-pump-small.txt`). A WWL above about 2.0 V gains
   nothing: the falling edge kicks SN down by more (`ret-hv-wwl2.{0,2,4,8}.txt`).
   - With thin oxide the extra charge tunnels away within about a millisecond, since the gate
     current rises steeply with voltage: 9.0 → 9.2 ms.
   - With thick oxide everywhere: from unreadable to 143 ms.
2. **Thick oxide in the storage transistor means thick oxide in all three.** A thick storage and
   thin read transistor would need the 0.54 µm keep-out again on strip A. All thick is drawn and
   DRC-clean: 1.03 × 2.96 µm, 3.05 µm² per bit, 3.10 µm² with a strap every 32 columns
   (`../drc/v4-ARRAY_3T_allthick_L45n.log`, `../lvs/allthick/extracted.cir`). That is 7% more
   than today's 2.88 µm², and 1.13× the density of the SRAM bit cell.
3. **Extra storage capacitance scales the lifetime about linearly.** SN is only 0.5–0.9 fF
   (`results/csn-*.txt`). **Estimate:** interleaved Metal4/Metal5 fingers over a cell give about
   1 fF. The 2D finite-difference solve (`capfd.py`, `results/capfd.txt`) gives 0.24–0.26 fF per
   µm of minimum-pitch line. The stack comes from the process spec's section 2.16. To use it, WBL
   must move to Metal3, stacked over RBL, so that SN can reach Metal4. The cap is simulated as an
   ideal, non-leaking capacitor: 143 → 368 ms with pumped writes, 9 → 25 ms for today's cell.
   A MIM capacitor (1.5 fF/µm²) needs 1.14 µm width plus 0.6 µm Metal5 enclosure per cell, so
   it is coarser than the cell.
4. **A coupling cap from RWL to SN reads low levels, but it also lifts stored 0s.** 0.5 fF lifts
   SN by about 0.5–0.6 V during a read. Then the all-thick cell reads without a pump: 71 ms at
   10 ns. But the lifetime is set by the stored 0 rising (WBL at VDD) until its boosted level
   reads as a 1. At a 20 ns sense that gives only 17 ms. With WBL idling at 0 V the figure is
   252 ms, and 684 ms with pumped writes too. That holds only if a column's WBL is rarely held
   high, so it is not a worst case. At 1 fF, and for a thin storage transistor even at 0.25 fF,
   stored 0s read as 1s (`read-*-cc*.txt`).
5. **A sense amplifier buys speed, not lifetime, once writes are boosted.** At 5 ns the latch
   matches the inverter at 20 ns. For the unboosted thick cell it does not help: the written
   level lies where RBL hardly moves.
   - The latch's offset, by Monte Carlo on `mos_tt_mismatch` (`results/sa-offset-*.txt`):
     σ ≈ 32 mV with a 2/0.5 input pair and a 1/0.13 latch (3 of 40 seeds beyond ±60 mV, so an
     underestimate); 17.6 mV at 4/0.5 and 2/0.26 (n = 50); 13.4 mV at 4/1.0 and 2/0.5 (n = 40).
     The input pair alone predicts about 4 mV. The rest comes from the latch and precharge
     devices at the high input common mode (about 1.1 V).
   - **Estimate:** 30–40 µm² per column.
6. **WBL idling at VDD/2** cuts the rise of stored 0s and the loss of 1s: 143 → 202 ms, and
   368 → 514 ms with the metal cap. It needs a mid-level WBL driver and a VDD/2 source.
7. **Mismatch.**
   - The write transistor 4σ leakier (−108 mV; σ = 27 mV for W 0.15/L 0.45 from the PDK's
     7 mV·µm) changes nothing (`ret-hv-wwl2.2*-mw4sigma.txt`). It is not the leak path.
   - A storage transistor 4σ weaker (+76 mV) raises the lowest readable level at ss/85 °C from
     0.70 to 0.77 V. That shortens the best cell to about 290 ms, interpolated from
     `read-hv-hvMR-ms4sigma-ss85.txt` and `ret-hv-wwl2.2-csn1.txt`.

**The best cell:** all thick oxide, write word line pumped to about 2.2 V, and about 1 fF of
metal on SN.
- Area: 3.10 µm² per bit, plus periphery. **Estimate** for the periphery: the pump is about
  150 µm² per array; the row driver is 6 thick-oxide devices, about 25 µm² per row, or about
  0.8 µm² per bit at 32 columns.
- Lifetime: 368 ms worst case (ss/85 °C) with an inverter read at 20 ns, 296 ms at 10 ns, and
  about 290 ms with a 4σ-weak storage transistor. Today's cell gives 9 ms by the same method.

## Artefacts and surprises

- **Word line high at t = 0.** With WWL already at 2.8 V at t = 0, the operating point with
  `.ic` SN = 0 did not converge (gmin and source stepping failed). The transient then started
  from SN = 1.2 V and showed a 1 decaying to 0 within 1 ms, through nanoampere currents that
  alternated in sign: a numerical artefact. Starting with WWL low removes it. All runs in
  `results/` use that; the first batch is kept in `results/artefacts/`.
- **The retention runs first reported levels only down to 0.20 V.** `life.py` then took an
  unbracketed level as the whole hold time instead of a lower bound. Both are fixed, and the
  runs were redone.
- **Kickback.** A StrongARM with 4/0.5 inputs, clocked on the floating RBL against an ideal
  reference, kicks RBL down by 0.5 V and reads a stored 0 as a 1
  (`results/artefacts/sa-read-ideal-reference-kickback.txt`). With a matched reference column
  (same wire and 32 cells, precharged to the reference), the kick is common-mode. The
  transistor-level decisions then agree with `life.py`'s model at the checked points
  (`results/saread-fixed-*.txt`). One reference line cannot serve many latches, so the
  reference should be the other half-array's RBL (open bit line).
- **Thick-oxide flying capacitors do not start.** Their top plate reaches only VDD − VT, too
  little to invert them once the clock lifts the bottom plate (`results/wwl-hvfly-nostart-ss27.txt`).
- **Two things that differ from the parent README.** Today's cell measures 9.0 ms here against
  "≥ 3.1 ms" there. There, the levels stopped at 0.20 V and the unselected cells held 0.7 V
  instead of 1.0 V. Stored 0s are not safe for a thick storage transistor: with WBL at VDD they
  rise to 0.5–0.9 V within 1 s, and they set the limit once the 1 lasts that long.

## Open questions

- Is a thin-oxide MOS capacitor acceptable at 2.3 V gate to substrate, with 1.2 V gate to
  channel? If not, the flying capacitors need MIM or metal, about 10× the area.
- Do Tiny Tapeout IHP tiles allow Metal4/5 over the array and MIM? `results/tt-layers.txt`
  records only what the template uses.
- A drawn and extracted metal-finger cap, the WBL-on-Metal3 routing, the row driver and the pump.
- Monte Carlo of the leakage paths themselves (junction, GIDL); PSP's mismatch varies only the
  threshold and mobility.
