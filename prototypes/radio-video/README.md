# Two demos: FM radio with RDS on a TV, and advert detection from a TV signal

A feasibility study with working models for two "fun but real" demonstrations for the Tiny Tapeout
chip (IHP SG13G2, core clock about 60 MHz, digital pins only). Both are configurations of the
chip's generic blocks, not new special hardware:

- the four-thread deadline sequencer (`../deadline-sequencer`);
- the pin primitives, including the four-phase input and output stage (`../multiphase`: four
  one-bit samples per clock per pin, 240 MS/s);
- a systolic array of one generic programmable PE (`../pe-synth`, `../semiring-ring`,
  `../systolic-storage`), for which this study proposes a small set of extensions;
- generic assists: the programmable CRC, bit stuffing, the systolic matcher (`../systolic-matcher`);
- memory (latches, SRAM macros, gain cells: `../gain-cell`, `../../notes/gain-cell-compiler.md`).

Everything here is a model, run on a heavily loaded host: Python for the signal chains, a
Verilog PE with a lockstep check and Yosys synthesis for the extension area. No SPICE and no
silicon. Every number below points to a file in `results/` or `pe-ext/`.

RESULTS_PLACEHOLDER
