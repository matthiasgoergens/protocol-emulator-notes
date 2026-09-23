# PAL and NTSC colour composite video from digital pins

Composite colour video generated entirely on the host and played out as a
sigma-delta stream at 66 Msps on one, two or three pins through resistors
and a low-pass filter. The chip's job is only to play bits; everything
else, the picture, sync, colour burst, colour subcarrier and modulation,
is computed beforehand.

`tv.py` (run with `uv run tv.py`) does four things:

1. Encodes an original test card (75 % colour bars, a hue and brightness
   sweep, a grey ramp, text) into a PAL or NTSC composite field: sync and
   simplified vertical sync, colour burst, U and V band-limited to 1.3 MHz
   and quadrature-modulated onto the subcarrier, the PAL line-by-line V
   switch.
2. Reduces the composite signal to L output levels with the second-order
   sigma-delta modulator measured in the one-bit synthesiser: L = 2 is one
   pin, 4 is two pins, 8 is three pins through a resistor ladder.
3. Decodes it with a software TV written independently of the encoder's
   timing: reconstruction low-pass, a sync separator that slices a 1 MHz
   low-passed copy (as a TV does), per-line burst phase lock, chroma
   demodulation, the PAL delay line, YUV to RGB.
4. Measures in-band SNR of the reconstructed composite and the PSNR of the
   decoded picture against the picture decoded from the ideal composite.

## Results (`out/results.json`, pictures in `out/`)

| Standard | Pins | In-band SNR | Picture PSNR vs ideal | Bytes per field |
| --- | --- | --- | --- | --- |
| PAL | 1 | 12.6 dB | 24.2 dB | 165 KB |
| PAL | 2 | 28.8 dB | 40.4 dB | 329 KB |
| PAL | 3 | 37.5 dB | 48.8 dB | 494 KB |
| NTSC | 1 | 18.1 dB | 25.3 dB | 137 KB |
| NTSC | 2 | 33.7 dB | 40.7 dB | 275 KB |
| NTSC | 3 | 42.3 dB | 49.1 dB | 412 KB |

For scale, the ideal composite itself decodes to 26.9 dB (PAL) and 25.2 dB
(NTSC) PSNR against the source picture: that is the format's own bandwidth
loss plus my simple resampling, and it is the ceiling everything else is
measured under.

Reading: one pin gives a recognisable colour picture with clearly visible
noise (`out/PAL_L2.png`). Two pins give a picture indistinguishable from
the ideal composite by eye (`out/NTSC_L4.png`), since its error is 13 dB
below the format's own loss. At 66 Msps the oversampling ratio over a
5 MHz video band is only about 6, which is why one bit struggles here
while it reached 68 dB for audio. A higher-order modulator designed
offline, or a look-ahead search over the bits, should narrow the gap for
one pin; that is untested.

Pad limits: the streams have 43 to 47 million transitions per second, the
equivalent of a 22 to 24 MHz square wave, inside the 33 MHz output limit.
Storage: a PAL field is 165 KB at one pin, so the demo board's 8 MB PSRAM
holds about 50 fields, one second, of precomputed video; playing it needs
8 MB/s per pin.

## Not done

The chip-side player (it only has to shift bits out of memory), the real
analogue filter and a real TV, interlace and exact vertical sync timing,
and RF modulation onto a TV channel through the sample-rate image.
