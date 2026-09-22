# Demo: active noise cancelling with no converters on the chip

A demonstration that the same architecture, a deterministic core plus
systolic streaming datapaths plus one-bit interfaces, does signal
processing as well as protocols: cancel noise at a microphone using a
second microphone and a speaker, with every filter coefficient computed
on a workstation beforehand and the chip running alone afterwards.
Written 22 September 2026 from the design discussion; nothing here has
been built yet.

## Two versions

**Room quiet zone (build first).** Noise source, reference microphone,
target microphone and cancelling speaker in a line in a room. The
reference sits one to two metres closer to the source than the target, so
the chip hears the noise one to six milliseconds before it reaches the
target: hundreds of times the electronic latency, which makes decimation,
a modest sample rate and a long filter all affordable. Physics sets the
limits instead: a single speaker cancelling at a point makes a quiet zone
about a tenth of a wavelength across (17 cm at 200 Hz, 3 cm at 1 kHz), and
room reflections destroy the coherence between the microphones as
frequency rises. Expect 10 to 20 dB of reduction below about 300 Hz at
the target, less above, and slightly more noise elsewhere, which is the
honest signature of a real quiet zone. Steady or tonal noise (aircon, a
fan) cancels best; music from a laptop loses only its bass.

**In-ear (the fun one, and where the one-bit path matters).** The
topology of a commercial noise-cancelling headphone: an error microphone
inside the earcup facing the driver, a reference microphone outside, the
cancelling signal into the driver. Here the acoustic path from the outer
microphone to the eardrum is tens of microseconds, so the electronic path
must be shorter than that, which rules out ordinary codec and decimation
chains and is why dedicated cancelling chips keep part of the path
analogue. Cancellation will be strong below a few hundred hertz and fade
by a kilohertz; that is accepted.

## The one-bit path

A PDM MEMS microphone's output is already a sigma-delta encoding of the
sound, a one-bit stream at 1 to 3 MHz on a digital pin with a clock we
supply. Keep the signal one-bit until the last moment:

1. Baseline: invert the reference stream and send it to the output stage.
   Anti-noise with one bit period of latency, a third of a microsecond,
   gain set by the analogue stage. Every fancier filter must beat this.
2. Filter at the PDM rate: a FIR over the one-bit stream is the systolic
   correlator with signed multi-bit coefficients, since multiplying a
   one-bit sample is adding the coefficient or not. A thousand taps at
   3 MHz is a millisecond of impulse response with no decimation delay;
   the only latency is the filter's own group delay, which offline design
   makes minimum-phase.
3. Back to one bit through a second-order sigma-delta modulator, into a
   resistor-capacitor filter and a small class-D amplifier on the board.

The room version can instead decimate to a low rate and run a short
multi-bit filter; the in-ear version should not.

## Blocks on the chip

| Block | What | Rough area |
| --- | --- | --- |
| PDM-rate FIR, one bit in, signed coefficients | the correlator array, widened | a few thousand um2 per hundred taps |
| or: decimators plus one 16-bit MAC with coefficients in SRAM | room version | 10K + 15K um2 plus a 1024x16 macro |
| Feedback-path neutraliser | second small filter, speaker-to-reference path | as above, shorter |
| Sigma-delta modulator | adders | 5K um2 |
| Optional adaptation (filtered-x LMS) | a slow second array, supervised by the on-board microcontroller | one more tile |

Everything is a fixed-schedule stream with no branching. The chip has no
ADC or DAC and needs none: microphones are PDM, music if wanted is I2S,
output is one bit.

## What the host does, once

1. Play a chirp through the chip's output while recording the target and
   the reference: identifies the speaker-to-target path and the
   speaker-to-reference feedback path.
2. With the noise on and the chip silent, record both microphones:
   identifies the noise path from reference to target.
3. Compute the cancelling filter: least squares on the measured paths, or
   run the adaptive algorithm offline until it converges, or search if
   the objective is awkward. Co-design with the analogue stage: the RC
   filter, amplifier and driver are part of the model, and the modulator's
   noise can be shaped into what that stage rejects.
4. Load the coefficients. The chip then runs with no host.
5. Per unit, per room: the "happy coincidences" are the transfer
   functions, resonances and passive attenuation of that particular rig;
   measure each and let the search use them. This is the birth-certificate
   idea with acoustics in place of silicon variation. Geometry is part of
   the search too: a reference microphone farther from the ear buys time.

The fit of a cup on a head changes the paths, so a filter tuned in a jig
is approximate on a person; low frequencies are the robust part. If the
zone must follow a moving source, adaptation is the slow second filter.

## Verification

Two readouts from the target: the chip's own error microphone, and an
independent measurement microphone into a USB audio interface on the
laptop, taped within a few centimetres of the target. Compare spectra
with the chip's output toggled off and on. For the in-ear version, an
earphone with built-in microphones (the Roland CS-10EM binaural set) is
an off-the-shelf witness in the ear; its microphones are analogue, so it
is the witness, not the chip's input.

## Parts

- PDM microphones: Adafruit PDM MEMS breakout (about 15 x 10 mm, four
  wires) or the ICS4135X breakout from Pesky Products (10 x 8 mm); both
  fit inside an earcup next to the driver, none fits an ear canal. Bare
  dies are 3 to 4 mm on a flex; not a first step.
- Transducers: any cheap wired over-ear headphone, or a discarded
  noise-cancelling one for its cups and drivers; for the room, any speaker.
- Output stage: RC filter, a class-D amplifier module, wires.
- Witness: measurement microphone plus USB audio interface; CS-10EM for
  in-ear. A tube of ear-canal diameter with a microphone at the end is a
  free dummy ear for repeatable bench measurements.
- Vendor evaluation boards (ADAU1787, ams AS3415) are the competition's
  product, not a substrate for ours.

## Pitfalls

- The speaker-to-reference feedback path makes a first attempt howl:
  measure it in step 1 and neutralise it, or put distance between speaker
  and reference microphone.
- The zone is small: the witness must sit at the target.
- Non-stationary music cancels intermittently; use a fan for the numbers.
- Latency budget in the in-ear version: keep the PDM clock high, keep the
  path one-bit, and design the filter minimum-phase.

## Relation to the competition

Off-theme as a product, on-theme as a demonstration: PDM, I2S and
sigma-delta are protocols, the filter is the systolic datapath, and
nothing is added to the chip but a microphone and an amplifier. It also
runs on the FPGA before silicon, which is where it will be built.
