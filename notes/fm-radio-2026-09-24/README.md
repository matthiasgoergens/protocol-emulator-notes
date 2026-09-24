# Can the chip bit-bang FM broadcast? (2026-09-24)

**Short answer:** not with edges on the clock grid, but yes in simulation, if the chip can place pin edges to about a quarter of a clock.

**The trick.** Pins toggle at most at 33 MHz, and the FM band is 87.5–108 MHz. But a square wave has odd harmonics, so a 33.25 MHz pin (half the 66.5 MHz clock) has a third harmonic at 99.75 MHz. PiFM on the Raspberry Pi uses harmonics the same way. FM at the third harmonic needs one third of the deviation at the fundamental: 25 kHz for broadcast's 75 kHz.

**The measurement** (`fm_sim.py`, output in `fm_sim.txt`). A 1 kHz tone at full broadcast deviation, pin edges quantised to various grids, demodulated by a software FM receiver tuned to 99.75 MHz. SINAD comes from a least-squares fit of the tone.

| Edge placement | SINAD | Recovered tone (rms deviation; ideal 53 kHz) |
|---|---|---|
| ideal | 22.2 dB | 53.3 kHz |
| **clock grid (15 ns): what an NCO on a pin does today** | −22.8 dB | 0.7 kHz: the tone is lost |
| clock/2 (7.5 ns, e.g. both clock edges) | 19.2 dB | 17.7 kHz: distorted |
| **clock/4 (3.8 ns)** | 21.8 dB | 53.2 kHz: essentially ideal |
| clock/8 to clock/32 | 22.2 dB | 53.3 kHz |

The 22 dB ceiling applies to the ideal signal too. It is a simulation artefact (brick-wall FFT filters over a window that is not a whole number of periods), so the comparison between rows is what counts, not the absolute figure. Two earlier versions of the metric were wrong and are recorded in the script: a tone window narrower than one FFT bin, then counting window leakage as noise.

**Why the clock grid fails.** At 99.75 MHz, a one-clock (15 ns) error in an edge is one and a half carrier cycles. The NCO's edge quantisation becomes a phase error far larger than the modulation.

**What it would take on the chip.**
- **Sub-clock edge placement.** A 4-tap delay line or a 4-phase clock would do, which is the "sub-cycle timer" idea from the earlier notes. That is analogue-ish and sensitive to process, voltage and temperature, so it needs calibration, for example with a TDC on the same delay line. It would be genuinely unusual functionality for a protocol chip, and also useful for fine-grained protocol timing and glitching.
- **Or frequency-modulate the chip's clock from the RP2040.** The chip then only divides by two. That is the PiFM approach, but the RP2040 does the real work, so it is weaker as a chip demo.

**Not modelled:**
- delay-line jitter and mismatch;
- pad slew;
- the third harmonic being about 9.5 dB below the fundamental;
- the fundamental at 33 MHz radiating too.

**Legal:** radiating in the broadcast band is regulated (IMDA in Singapore). Keep any test to a cable or a shielded setup, at the lowest power.

**An easy relative: AM radio.** Medium-wave AM (530–1,700 kHz) is 40–125 clocks per carrier cycle, so an NCO plus duty-cycle or amplitude modulation from the streamer is comfortably on the clock grid. A chip that broadcasts to any AM radio is a cheap demo with existing primitives.
