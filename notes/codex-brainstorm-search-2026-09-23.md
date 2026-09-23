My priority would be **controllable effect families, composable primitives, and a diversity archive that preserves surprises**. “Amazing” can guide selection imperfectly; it should not be the single objective deciding which discoveries survive.

I read the requested files except the absent wave-engine README; I read its implementation and game instead. These are proposed experiments, not demonstrated capabilities.

For every search, evaluate animated, PAL-decoded output, including gamepad trajectories. Preserve fine luminance detail while judging chroma through its narrower bandwidth. Optimise a small CPU-side parameter-to-packet function, rather than unrestricted prerecorded movies. Finalists must survive exact integer simulation, decoder variations, packet deadlines, and synthesis/routing costs.

1. **First: inverse design with the ten-wave engine.**

   Search phases, horizontal frequencies, signed shift amplitudes, palettes, and their dependence on line, time and 2–4 controls. Fit target families: rippling water, rotating interference lattices, perspective floors, broad tunnel bands. The hardware permits different frequencies on every line, considerably more than ten global plane waves.

   Start with sparse sinusoidal fitting, then optimise decoded animation error, temporal continuity and control response; quantise and refine using the actual sine table, shifts and palette clamp. [Mallat–Zhang matching pursuit](https://www.di.ens.fr/~mallat/papiers/MallatPursuit93.pdf) supplies a useful initialisation principle.

   This directly targets recognisable demo choreography. A player controls centre, rotation, speed or wavelength; the existing cancellation game supplies another interaction. Failure modes: ten waves cannot represent arbitrary scenes, palette clipping hides interference, and independently fitted lines shimmer. Fit neighbouring lines and frames jointly, and constrain RP2040 computation/table size.

2. **Expand MAP-Elites into an archive of playable behaviours, with a learned critic.**

   Search programs, palettes and seed-generating functions; periodically mutate wiring in an outer search. Archive by decoded spatial scale, symmetry, motion type, persistence and response to controls. Distinguish geometric motion from palette cycling so both survive.

   Train an ensemble preference predictor on occasional pairwise judgements of short clips, including your favourites, noise, stripes and deliberately broken variants. Between judging sessions, automatically select using predicted preference, novelty and uncertainty in separate archive channels. Evaluate held-out clips and control trajectories; retain an unguided exploration fraction. [Human-preference learning](https://arxiv.org/abs/1706.03741) is the precedent, not evidence that aesthetic judgement is solved.

   Require each control to produce a detectable, bounded and repeatable change, with a usable neutral region. Measure whether separate controls actually change different visual properties. This could preserve unexpected melting/weaving effects while making them steerable. Risks: critic exploitation, novelty rewarded for noise, and familiar-looking effects monopolising the archive. Human curation becomes occasional rather than per-generation.

3. **Make composition the search language.**

   Search small expression graphs built from phase ramps, waves, XOR masks, palette maps and sprite overlays. Optimise visual quality/diversity subject to cell, wave-slot, packet and latency budgets. Give each component a contract: output range, reset policy, latency and exposed controls.

   A concrete composition is a wave background plus sixteen-cell sprite foreground, with CPU-controlled per-line phase warps and palette choreography. That can produce water beneath a readable ship, or a rotating patterned floor beneath enemies. Combining the current prototypes needs an explicit pixel interface and an area measurement; it is not already available.

   Wave contributions compose before palette conversion if sufficient headroom prevents clipping. Network components need isolated state and explicit boundary links, which may require a topology change. Arbitrary neighbouring programs do not compose automatically. [DreamCoder](https://arxiv.org/abs/2006.08381) is relevant prior art for discovering reusable program libraries. The risk is restricting invention too much; retain raw-network mutations too.

4. **Use GF(2) algebra to find reachable periodic modes and impulse responses.**

   Here, XOR is followed by ordinary addition of `ks`; use `ks=0` for a clean linear sublanguage. Each bit plane then follows the same 64-state binary matrix. Low seed bits cannot influence the displayed top nibble in this sublanguage.

   For candidate links/taps, compute the exact seed-to-visible-samples map, reachable subspaces, observable subspaces and periods. Search for reachable states in \(\ker(A^L-I)\) for desired recurrence lengths, where \(A\) advances one network step. Include actual line resets, seed injection and pixel sampling.

   **\(\ker(A)\) contains states erased after one step; it is not inherently an interesting visual repertoire.** More useful are periodic subspaces and impulse responses producing coarse travelling masks. XOR superposition gives exact composition before the palette. Controls choose combinations of reachable modes; smooth motion still needs deliberate phase sequencing. [Martin–Odlyzko–Wolfram](https://content.wolfram.com/sw-publications/2020/07/algebraic-properties-cellular-automata.pdf) supplies the linear-cellular-automata precedent.

   Also explore add/subtract-only programs: between seed injections, these are affine systems over \(\mathbb Z/256\mathbb Z\), potentially closer to ramps and phase arithmetic.

   Risks: inaccessible modes, binary-looking patterns, and long periods that merely look random. Score decoded appearance, not period length alone.

5. **Use differentiation locally, starting with waves and structured network motifs.**

   Optimise wave parameters directly; for the network, relax opcode/link choices into soft selections and model arithmetic with differentiable bit-level gates or a learned surrogate. Optimise target-clip loss, perceptual features and control response, with penalties on wire length and soft-choice ambiguity. Quantise frequently and repair discrete candidates with mutation or a solver.

   [Differentiable logic-gate networks](https://arxiv.org/abs/2210.08277) establish a relevant technique; they do not establish trainability of this recurrent byte machine. [Differentiable quality diversity](https://arxiv.org/abs/2106.03894) suggests using gradients to populate different behaviours rather than polish one winner.

   Potential payoff: coherent morphs and interference patterns with learned control directions. Hazards: carry/wrap discontinuities, long recurrent horizons, soft circuits doing things no discrete circuit can do, and exploiting the surrogate. Begin with line-reset programs and short motifs; always judge hard execution.

6. **SAT/SMT plus CEGIS: synthesise useful mechanisms.**

   Search opcodes, constants, permitted links and seed encodings with exact 8-bit semantics. Specify a delayed mask, a chosen periodic output, a reversible phase change, or independence of one component from another’s controls. Minimise cells/links after finding a solution.

   [CEGIS](https://people.csail.mit.edu/asolar/SynthesisCourse2020/Lecture10.htm) alternates synthesis on examples with counterexamples to the required contract. Use it to grow the component library and superoptimise known effects. Specify control behaviour across its allowed domain, giving games dependable building blocks for raster tricks.

   The solver supplies mechanisms from which impressive scenes can be assembled; it has no native concept of visual quality. Whole-field unrolling becomes enormous. Start with small motifs, use algebra for XOR regions, and distinguish bounded guarantees from indefinite ones. Under-specified targets produce technically correct but visually useless solutions.

7. **ILP/MILP: choose and pack the hardware repertoire.**

   Use binary variables for physical links, component placement and supported effect families; integer variables for schedules and resources. Constrain fan-in, wire budget, register/configuration storage, throughput and the wave engine’s ten slots per pixel. Maximise weighted coverage of effect families while minimising routed cost estimates.

   Precompute legal motif mappings where possible: ILP then selects compatible mappings and shared links. Compare a ring, structured shortcuts and mixed random links, keeping some effect families unseen during selection. Inspect routed finalists rather than trusting graph connectivity or an expander gap.

   This could make several strong, controllable effects coexist on one chip. Control contracts come from selected motifs. It cannot discover beauty directly, and linear cost models can badly underestimate routing. This is a proposed application of standard scheduling/mapping methods, not a known demonstrated result for this design.

8. **Later: Koopman models to tame a discovered nonlinear effect.**

   Fit a controlled linear predictor in observable features such as band position, dominant frequencies and colour occupancy. Search seed commands that track joystick-requested feature trajectories; compile a small controller or lookup table for the RP2040. [Korda–Mezić](https://arxiv.org/abs/1611.03537) provides the control precedent.

   The objective is prediction and tracking error, preserving an already striking organic effect. This is speculative here: finite-state switching and wraparound may defeat a compact model, and hidden state makes control history-dependent. Train within one useful operating region and reject models that fail fresh trajectories.

I would start by fitting three wave-effect families, seeding the PAL-aware archive with those and the existing favourites, and extracting one composable motif from each successful family. That creates useful targets for algebra and solvers before committing to a topology.
---

## Triage (written after reading the above, 2026-09-23)

- Checked at source: the claim that in the XOR-only sublanguage with zero
  constants each bit plane evolves independently, so low seed bits cannot
  reach the displayed top nibble, follows from `Model.run_field`: XOR never
  moves information between bit positions. Correct. Addition carries only
  upward, so add/subtract programs mix low bits into high ones.
- Correct and important: the kernel of the step matrix is not the
  interesting object; periodic subspaces (kernel of A^L - I), impulse
  responses and reachable/observable subspaces are.
- Correct and under-used by us so far: the wave engine takes a new phase
  step on every line, so it can draw curved and chirped waves, not only ten
  global plane waves.
- Adopted as the plan: (1) inverse design on the wave engine first, where
  the maths is closest to classic demo effects; (2) a PAL-decoded archive
  with a learned preference critic, trained on occasional pairwise
  judgements, used alongside novelty and uncertainty, never alone;
  (3) composition as the search language, with explicit contracts per
  block; GF(2) analysis, SAT/CEGIS and ILP as tools for particular jobs
  (mechanisms, contracts, hardware packing), not as the source of beauty.
- Not adopted yet: differentiable relaxation of the network itself (carry
  and wrap discontinuities, long recurrent horizons), Koopman control
  (only once there is a discovered effect worth taming).
