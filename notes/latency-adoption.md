# Adopting hardcaml-latency in the video pipelines (2026-10-05)

This follows the decision in `backlog.md` ("`hardcaml-latency`: decided 2026-10-05"). The
library's `src/` is vendored unmodified at f59e57a (`vendor/hardcaml_latency/SOURCE.md`).
`tools/latency-ci/` is our own helper for running the lint as a regression test. Each
prototype is a separate dune project, so it reaches both through symlinks: `src` for the
library and `latency_ci` for the helper. The library's own `src/` frame filter is the reason
the first symlink has to be called `src`. See the limits below.

## 1. The lint over every video pipeline

The raw outputs are in `latency-adoption-raw/`. They were produced by probe code on 7cf2f05
plus the uncommitted probes. `retro.txt` and the first `platformer.txt` predate the helper's
own location lookup, so they have no source lines. Each design was run with default settings
and with `hold_registers`, which treats every register with a non-constant enable as holding
a value.

| Design (circuit) | Defaults | `hold_registers` | Classification |
| --- | --- | --- | --- |
| retro-console (`Console.circuit`) | 66 | 5 | **False positive (66):** the 54-byte line packet shifts through enabled registers and is latched once a line, so each sprite cell's parameters reach the pixel at a different register count. They are constant for the line. **Deliberate offset (5):** the 17-stage sprite pipeline is launched early (`hcount = vis_start - nspr - 2`) instead of the syncs being delayed by registers. The library's own experiment showed that an off-by-one launch gives the same 5 findings, so the lint cannot tell this offset from a bug. |
| platformer chip (`Video.circuit`, normal and lean PE-X) | 630 / 267 | 3 / 3 | **False positive (627 / 264):** all measured from `cfg_in`. They come from the byte-wide configuration chain through the 18 PE-Xs, which is static while the chip runs. **Deliberate history (1):** `video.ml:35`, `go = prev_go &: ~:line_go_n`, the falling-edge detector of the line event. **False positive, loop convention (2):** `video.ml:77`, the output port's `Always` block, where `hold` and `idx` are counters loaded from the array stream. The outport alone and the 18-PE row alone each lint clean (0 findings), so the findings come only from their composition. The loop is entered by the stream's tag and by a signal the lint places 20 cycles earlier, and its loop convention gives one loop register one latency. I did not trace the exact second entry path. Evidence that nothing is misaligned: the chip lockstep (`main.exe check`) still reports 0 of 61,440 pixels different, and its output is identical to the committed `results/check.txt` apart from timings (`prototypes/platformer/results/latency-check-after-adopt.txt`). |
| hdmi-ulx3s pattern (`Hdmi.pixel_circuit`, before and after the rewrite) | 0 | – | Clean. |
| hdmi-ulx3s demo (console through the frame buffer) | 95 | 1 | **False positive (90):** measured from the packet ROM instance. This is the console's packet chain again. **5** are measured from the writer's sub-pixel counter and disappear with `hold_registers`; I did not trace them one by one. **Deliberate history (1):** `console_hdmi.ml:74`, `first = pvalid &: ~:prev_valid`, the rising edge of pixel-valid. |
| hdmi-ulx3s serialiser (bit clock) | 1 | – | **Deliberate history:** `serialiser.ml:40`, the synchronised toggle XORed with its previous value to detect a new pixel. |
| multi-proto sequencer with mailboxes (`Sequencer_mb`, p7 d2, as `ethtv` and `cantv` use it) | 0 | 0 | Clean. Ethernet-to-TV and CAN-to-TV draw in firmware. Their pin stage (`video.ml`) is an OCaml model, not Hardcaml, so it cannot be linted. |
| multi-proto base sequencer (`../deadline-sequencer`) | 52 | 52 | **False positive:** a four-thread barrel processor. Each thread's PC, accumulator, counter and deadline are registers written under a thread select, and the instruction input meets state written by earlier instructions. That is history by design, and the lint is not a meaningful check for a processor. It is left out of the regression test. |
| multi-proto 10BASE-T receiver (`Eth_rx`, `Eth_rx_fixed`) | 1 each | 1 each | **Deliberate history:** `rx_q <>: rx_prev`, the transition detector. |
| unified-pe array (`upe_array`) and one PE (`upe_v1`) | 183 / 2 | 0 / 0 | **False positive:** measured from the configuration and initialisation chains and from the mailbox-loaded feed registers (`fixed_d*`, `fixed_v*`), all held while a configuration runs. The video uses (sprites, tiles) are configurations, so they are invisible to a structural lint. |
| video-nco (`pin_nco`) | – | – | **Not linted:** Verilog and Python, no Hardcaml circuit. |

**Real bugs: none.** Every finding is a deliberate offset, deliberate history (four edge or
transition detectors), or a false positive from enabled configuration or packet registers,
the processor structure, or the loop convention.

## 2. Pipelines rewritten with `Delayed`

**HDMI pixel path** (`prototypes/hdmi-ulx3s/hw/`, commit 8085f91):

- **Raster counters.** These are one `Delayed.reg_fb` and the time origin (latency 1).
- **Test pattern.** It is now a functor over `Comb.S`, built at `Delayed`, so `x` and `y`
  are checked against each other.
- **Demo source.** The frame-buffer reader is `Delayed`, with the Verilog RAM wrapped by
  `lift ~latency:1`.
- **TMDS encoder.** It is wrapped by `lift ~latency:1`. That checks `de`, the pixel and the
  control bits against each other.
- **Syncs.** They are delayed by `Delayed.align`, not by a declared integer, so a source
  with a different register count needs no change in `hdmi.ml`.

Evidence that the rewrite behaves exactly as before:

- **Cyclesim** (`test/test_latency.ml`, against frozen copies in `test/reference/`): 0 of
  1,375 cycles differ over 5 small frames, and 0 of 421,000 over a whole 640x480 frame plus
  1,000 cycles. The comparison covers every output. The end-to-end "latency" mutant is also
  identical to the original mutant. Since 2026-10-05 the small mode also checks that the
  comparison itself sees the fault: the rewritten mutant against the original good design
  differs on 555 of 1,375 cycles (and the original mutant against the rewritten good design on
  555), so a rewrite that introduced the mutant's fault would fail even there
  (`results/latency/small-mode-mutant-detected.txt`).
- **Verilog under iverilog** (`test/rtl-compare/run.sh`, `results/latency/rtl-compare-*.txt`,
  run at 8085f91): old `rtl/gen` against new, side by side. The pattern gives 0 of 900,000
  cycles different. The demo gives 0 of 2,500,000, which includes 3.5 frames after the
  console has filled the frame buffer. The comparison has two checks of its own. The
  latency mutant against the old pattern differs on 359,985 cycles. In the second half of
  each run, NEW's `word_b` changes 311,510 times for the pattern and 540,768 times for the
  demo.
- The rewrite is not a constant shift: all latencies are the same as before.

`results/latency/test_latency.txt` shows what the construction-time check reports when the
syncs are one register short:

```
Latency mismatch in [tmds] at hw/hdmi.ml:80:
    arg 0    latency 1       (hw/video_timing.ml:67)
    arg 1    latency 2       (hw/hdmi.ml:49)
    ...
```

**Not rewritten:** platformer and retro-console.

- **platformer.** Its pixel path is aligned by in-band step tokens in the array stream
  and by a counter constant (`start = 641`), not by registers. The feeder and the output
  port are `Always` state machines. A `Delayed` version would need `of_signal` at almost
  every boundary, so it would assert latencies rather than check them.
- **retro-console.** The library's `checker/designs/console_aligned.ml` already shows the
  re-alignment. It moves the output 17 clocks later, and its effect on the
  subcarrier-to-burst phase has not been measured.

## 3. Regression tests

`dune test` in each prototype now runs the lint and diffs its uid-free output with a
committed `latency.expected`. A reviewed change is accepted with `dune promote`. The helper
fails the test if the lint checked no node at all.

| Prototype | Entry point | Planted control (must be caught) |
| --- | --- | --- |
| hdmi-ulx3s | `test/test_latency.exe` | The syncs and blank one register short. `Delayed` refuses to build it, for the pattern and for the demo. The lint is tested against the original plain design with the same plant, and gives 6 new findings. |
| retro-console | `main.exe latency` | One register removed from the pixel-valid (blank) lane at sprite cell 8: 28 new findings. |
| platformer | `main.exe latency` | The sequencer's sync and blank levels one register later than the burst gate from the same pins: 6 new findings. No register exists on that path to remove, so this plant adds one. |
| multi-proto | `latency_lint.exe` | None. The hardware has no sync path; the video timing is in firmware. The test pins a blind spot instead (below). |
| unified-pe/verify | `main.exe latency` | None. A configuration decides which lanes carry pixel and valid. |

The default design is unchanged by the plant hooks:

- **retro-console.** `retro_console.v` is byte-identical to the one built at 7cf2f05.
- **platformer.** The chip lockstep output is unchanged.

**Live regression check.** With `plant_sync_short` defaulted to true in `hw/hdmi.ml`,
`dune test` fails with the mismatch above and exit status 1
(`results/latency/regression-demo-dune-test.txt`). The same exception stops `emit.exe`, so
`build.sh` and `e2e/run.sh` cannot produce misaligned Verilog either.

## 4. What the wrapper and the lint could not handle

1. **Coupled feedback registers.** `reg_fb` is for one register. Two counters updated on
   the same edge (h, and v, which reads h's wrap) come out at different latencies if each
   is its own `reg_fb`. The only way out was to concatenate them into one register.
2. **`Always`.** State machines (platformer feeder and output port, retro-console pixel
   walker, every sequencer) are written with `Always` on `Signal.t`. `Delayed` has no
   counterpart, so they stay plain or are wrapped with `of_signal`.
3. **Several time bases in one clock domain.** The HDMI demo has two beams, the console's
   and the raster's, which meet only in the frame buffer. `Delayed` has one time origin per
   circuit. The writer had to stay unchecked, and the RAM was lifted as a read-only
   one-register function, with its write side closed over as plain signals.
4. **Memories.** `lift` handles a RAM's read side only. The write side is not checked by
   either tool.
5. **Multiple clocks.** The pixel and bit clock domains are separate circuits here, so
   nothing went wrong. But the lint counts every register as one cycle whatever its clock,
   and `Delayed` has no clock domain.
6. **Enables.** `hold_registers` is all or nothing. It was needed on four designs, to
   silence configuration and packet chains, and it also hides any enabled pipeline stage.
   That is why the unified-PE array could not get a planted control.
7. **History.** Four edge or transition detectors are reported as findings, and the lint
   has no way to mark one as intended. They are accepted through the expected file.
8. **Counter-constant alignment.** This is invisible to both tools (retro-console,
   platformer).
9. **Inputs sampled together outside the chip** (`rx` and `rx_active`) have no common
   source in the circuit, so a misalignment between them is not reported. The multi-proto
   test pins that as a known blind spot.
10. **Processors.** These are not pipelines. The base sequencer gives 52 findings that mean
    nothing.
11. **Source locations.** `Delayed` and the lint pick the design's frame by skipping files
    under `src/` and requiring a `/` in the path. Vendored under any directory name other
    than `src`, every `Delayed` error named `hardcaml_latency/delayed.ml:29`. For designs at
    their dune project's root (retro-console, platformer, multi-proto, unified-pe), the
    lint gave no location at all. `tools/latency-ci` looks locations up again itself. Tail
    calls still lose frames: `< @ console.ml:113` names the circuit wrapper, not the
    comparison.
12. **Unnamed `lift` arguments.** The errors say `arg 0` to `arg 3`, not `de`, `d`, `c0` and
    `c1`.
13. **Brittle finding text.** The text carries source lines, so an edit above a finding
    changes the expected file. Reviewing that with `dune promote` is the price paid. It
    happened during this work: adding the plant hook to `retro-console/console.ml` moved
    lines in a file that `hdmi-ulx3s/demo` uses through a symlink, so the HDMI test failed
    until it was promoted. The finding was the same; only its line numbers had moved.

## Proposed improvements to hardcaml-latency (not implemented there)

1. Identify the library's own frames by its compiled file names, such as `__FILE__` of
   `delayed.ml` and `latency_lint.ml`, instead of a `src/` prefix. Accept frames without a
   `/`, and exclude the standard library by module name, as `tools/latency-ci/latency_ci.ml`
   does.
2. Expose the creation site per uid, or the `Signal.t` itself, in `Latency_lint.finding`, so
   that tools can key findings on signal names rather than parse text. Prefer
   `Signal.names` when present, so that expected files survive line moves.
3. Add a `reg_fb` over an `Interface` or a list of widths: several registers updated
   together, with one shared latency.
4. Add a `Delayed.Always`, or `Variable`s carrying a latency, so that state machines can be
   checked without unwrapping.
5. Add named time origins: a latency relative to a named beam or counter. Mixing two
   origins would be an error except through a declared crossing (a RAM, a FIFO). This is
   the HDMI demo's console-to-raster frame buffer.
6. Add `Delayed.ram`, Érdi's `delayedRam`, with both ports checked, each against its own
   origin.
7. Let `lift` take named arguments, and add `lift_n` for several outputs, for example
   `Tmds.create`'s word and disparity.
8. Add a history annotation (`Delayed.history ~n x`, and a signal attribute the lint
   honours) for edge detectors and similar `x(t)` against `x(t-1)` uses.
9. Make `hold_registers` per register, as an attribute or a name predicate, instead of
   global. Add a mode that treats a common pipeline enable as transparent.
10. Add a declared counter offset (`of_counter_offset ~cycles`). The lint would accept the
    declared offset, and a simulation test would check it. Without this, early-launch
    designs cannot be checked at all.
11. Add input groups the lint treats as one source: inputs sampled together outside the
    circuit.
12. Make the lint aware of clock domains: no edges across domains, and labels per domain.
    Combine it with `Clocked_signal` on Hardcaml master.
13. Add a scoped lint between named start and end points, the generalisation of
    `Signal_graph.count_regs_between`. Then processors and mixed designs can be checked
    where it means something.
14. Add an allow-list API (`check_circuit ~accept`), so that accepted findings live next to
    the design with their reasons.
