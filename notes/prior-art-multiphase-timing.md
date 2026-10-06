# Prior art for multiphase edge timing, DTC/TDC and the deadline sequencer

Written 2026-10-06. Scope: `prototypes/multiphase/` (four-phase output and input stage, planned DTC/TDC,
pin NCO) and the four-thread deadline sequencer. Every claim carries a source. Labels:

- **[R]** I read the paper, application note, datasheet or manual text myself (full text or the
  relevant pages, extracted with `pdftotext`; an abstract-only read is marked "abstract").
- **[S]** Search snippet, bibliographic record (Crossref/OpenAlex) or secondary source only. Treat
  the claim as unverified until someone reads the source.
- **[inference]** My own reasoning from sources; not stated by any of them.

Raw downloads are in `/var/tmp/pa/` (not committed; re-fetchable from the URLs below).

## 0. Corrections to the list I was given

| In the brief | Actual |
| --- | --- |
| Foley and Flynn, JSSC 2001, "DLL-based clock multiplier" | The paper is a **clock synthesizer** (x9) and a temperature-compensated oscillator: Foley and Flynn, "CMOS DLL-Based 2-V 3.2-ps Jitter 1-GHz Clock Synthesizer and Temperature-Compensated Tunable Oscillator", IEEE JSSC 36(3):417-423, March 2001, doi 10.1109/4.910480 [R]. It combines nine DLL phases with **AND-OR** logic (three clocks of 3x, then 9x), not XOR [R]. An earlier CICC 2000 version has a slightly different title (doi 10.1109/cicc.2000.852688) [S]. |
| XAPP224 "Data Recovery", XAPP523 "LVDS 4x oversampling" | XAPP224 v2.5 (11 July 2005), author **Nick Sawyer**, now marked "Not Recommended for New Designs" [R]. XAPP523 v1.1 (17 May 2017), "LVDS 4x Asynchronous Oversampling Using 7 Series FPGAs and Zynq-7000 AP SoCs", author **Marc Defossez** [R]. |
| Hybrid counter plus delay line DPWM: "Dancy and Chandrakasan; Peterchev, Xiao and Sanders" | Dancy and Chandrakasan, PESC 1997 (doi 10.1109/pesc.1997.616620) is a **tapped-delay-line** DPWM; the **combined delay-line plus counter** one is Dancy, Amirtharajah and Chandrakasan, IEEE TVLSI 8(3):252-263, 2000 (doi 10.1109/92.845892). I know this attribution only from Peterchev's own description of refs [6] and [7] [R of Peterchev; the Dancy papers themselves are [S]]. Peterchev, Xiao and Sanders (IEEE TPE 18(1):356-364, 2003, doi 10.1109/tpel.2002.807099) is a **ring-oscillator-multiplexer** DPWM (0.25 um test chip, 195 ps resolution), not a hybrid [R]. |
| "de Castro et al., IEEE TPE 2007?" for FPGA DPWM by clock phase shifting | Two papers. Huerta, de Castro, Garcia, Cobos, "FPGA-Based Digital Pulsewidth Modulator With Time Resolution Under 2 ns", IEEE TPE 23(6):3135-3141, 2008 (doi 10.1109/tpel.2008.2005370; APEC 2007 version doi 10.1109/apex.2007.357618) [S]. And de Castro and Todorovich, "High Resolution FPGA DPWM Based on Variable Clock Phase Shifting", IEEE TPE 25(5):1115-1119, 2010 (doi 10.1109/tpel.2009.2037818); its PESC 2008 version is "...under 100 ps" (doi 10.1109/pesc.2008.4592418) [S]. A 2021 survey table lists the 2010 paper as 19.5 ps on a Virtex 5 [R of Fernandez-Gomez et al.]. |
| Wu and Shi 2008, wave union | Correct: Wu and Shi, "The 10-ps Wave Union TDC: Improving FPGA TDC Resolution beyond Its Cell Delay", IEEE NSS Conference Record 2008, pp. 3440-3446, doi 10.1109/nssmic.2008.4775079 [R, open copy]. |
| Dudek et al., JSSC 2000 | Correct: Dudek, Szczepanski, Hatfield, "A High-Resolution CMOS Time-to-Digital Converter Utilizing a Vernier Delay Line", IEEE JSSC 35(2):240-247, Feb 2000, doi 10.1109/4.823449. 0.7 um CMOS, 128 stages, 30 ps resolution, DLL-stabilised [R, open copy]. |
| CERN HPTDC | It is a chip manual, not a paper: J. Christiansen, "HPTDC High Performance Time to Digital Converter", CERN/EP-MIC, manual version 2.2, March 2004 (record cds.cern.ch/record/1067476) [R]. |
| "Microchip high-resolution PWM" | Feature name is "High-Resolution PWM with Fine Edge Placement" (reference manual DS70005320, not read); dsPIC33CK datasheet DS70005349E says "up to 250 ps PWM resolution" [R datasheet]. |
| Edwards and Lee, PRET | "The Case for the Precision Timed (PRET) Machine", DAC 2007, **two pages** (pp. 264-265, doi 10.1145/1278480.1278545; also Berkeley TR UCB/EECS-2006-149) [S]. The deadline *instruction* first appears in Ip and Edwards, "A Processor Extension for Cycle-Accurate Real-Time Software", EUC 2006, LNCS 4096:449-458, doi 10.1007/11802167_46 [S metadata; Lickly et al. describe it, [R]]. |
| CDC 6600 "peripheral processors' barrel" | Right, but the primary source is J. E. Thornton, *Design of a Computer: The Control Data 6600* (Scott, Foresman, 1970), pp. 141-143 [R, scan at archive.computerhistory.org]. |

## 1. Edge combining: multiphase clocks into faster clocks or edges

**DLL clock multipliers with an "edge combiner".**

- A DLL delay line of M taps spans exactly one reference period; the tap outputs are phases of the
  reference, and an *edge combiner* merges their edges into a clock at N times the frequency. With
  only rising edges used, the line needs M = 2N cells. Using falling edges as well makes the output
  depend on the reference duty cycle, "which might form a problem" [R: van de Beek, Klumperink,
  Vaucher, Nauta, "Analysis of Random Jitter in a Clock Multiplying DLL Architecture", Univ. of Twente
  conference paper, 2001 (the PDF does not name the venue; it starts at page 281), open copy
  https://ris.utwente.nl/ws/files/201856076/Beek2001analysis.pdf]. Foley and Flynn (above) is the
  cited exemplar there. **Our lanes use only rising edges of four phases, which is exactly this
  duty-cycle-immune variant.** [R]
- The same group shows jitter from delay-cell mismatch: "relative time deviations are highest in the
  middle of the delay line and proportional to the square root of the frequency multiplication
  factor" [R abstract: van de Beek et al., "Jitter in DLL-Based Clock Multipliers caused by Delay
  Cell Mismatch", 13th ProRISC Workshop, Veldhoven, Nov 2002,
  https://research.utwente.nl/en/publications/jitter-in-dllbased-clock-multipliers-caused-by-delay-cell-mismatch(9f5ed190-75c2-43a5-95b2-f06b09c95201).html].
- Foley and Flynn solve **false lock** (locking to 2T, 3T ... instead of T) with a self-correcting
  DLL (lock-detect from the tap states) [R]. Relevant if our four phases ever come from an on-chip
  DLL rather than an external PLL.
- Spur analysis of edge combiners: Casha, Grech, Badets, Morche, Micallef, "Analysis of the Spur
  Characteristics of Edge-Combining DLL-Based Frequency Multipliers", IEEE TCAS-II 56(2):132-136,
  2009, doi 10.1109/tcsii.2008.2011605. Abstract (as relayed by a search result): estimates the
  effect of in-lock error and delay-stage mismatch on spur level [S]. The open copy at
  um.edu.mt/library/oar returned an HTML gate for me, so not read. Also Guo, Wang, Kwasniewski,
  CCECE 2013, doi 10.1109/ccece.2013.6567802 [S], and Hassani and Saeedi, Analog ICSP 82(3), 2015,
  doi 10.1007/s10470-015-0495-1 (static phase offset) [S].
- Chien and Gray, "A 900-MHz Local Oscillator Using a DLL-Based Frequency Multiplier Technique for
  PCS Applications", IEEE JSSC 35(12):1996-1999, 2000, doi 10.1109/4.890315 [S]. XOR-based edge
  combiners with phase blending appear in later DLL-multiplier papers [S: search snippet only; I
  did not find a primary XOR-combiner paper I could read].

**FPGA "double-edge flip-flop" from two single-edge flip-flops.**

- FPGAs have no dual-edge flip-flop; the standard workaround is one posedge and one negedge
  flip-flop plus combining logic. The HDLBits exercise "Dualedge" states this and warns that "a
  larger combinational circuit that emulates this behaviour might [glitch]" [R: https://hdlbits.01xz.net/wiki/Dualedge;
  I did not see the reference solution, so the XOR form is [S]].
- ASIC literature on dual-edge-triggered flip-flops: Hossain, Wronski, Albicki, "Low Power Design
  Using Double Edge Triggered Flip-Flops", IEEE TVLSI 2(2):261-265, 1994, doi 10.1109/92.285754 [S];
  Gago, Escano, Hidalgo, "Reduced Implementation of D-Type DET Flip-Flops", IEEE JSSC 28(3):400-402,
  1993, doi 10.1109/4.210012 [S]; Llopis and Sachdev, ISLPED 1996, doi 10.1109/lpe.1996.547536 [S].
  I did not read these; whether any uses the toggle-and-XOR form is unchecked.
- Patents on FPGA memory elements triggered on both edges exist (US 5,844,844) [S: scanned PDF, no
  text layer].

**Assessment [inference].** Edge combining from rising edges of multiple phases is old and
well-studied in clock multipliers. As a *data-edge* generator (a per-pin toggle lane per phase,
XORed, with the lane chosen by a sub-slot field from a sequencer) I found no direct precedent, but
the absence of a hit is weak evidence.

## 2. Multiphase oversampling receivers and phase selection

- **XAPP224** (Sawyer, v2.5, 2005) [R]. Closest published match to our input stage. Four
  flip-flops sample the data: rising and falling edge of CLK and of CLK90, giving "four data sample
  points, each separated by 90 degrees ... In the case of a 420 MHz system clock, this logic is
  effectively running at 1680 MHz". The four samples are re-registered "to remove any metastability
  issues and to move them into the same time domain" in two or three stages. Data rates: 160 Mb/s
  (Virtex-E), 320 Mb/s (Spartan-3), 420 Mb/s (Virtex-II). "The absolute delay [pad to flip-flops]
  is irrelevant; only the skew is important", enforced with a MAXSKEW of 500 ps on that net. The
  metastability argument: if the load on a metastable flip-flop is one, the following flip-flop
  resolves it. The design is a "partial solution": no clock is recovered, the local oscillator
  differs by a few ppm and the circuit "hunts" for the phase.
- **XAPP523** (Defossez, v1.1, 2017) [R]. 1.25 Gb/s, local clock within +-100 ppm of the data rate.
  625 MHz CLK and CLK90 (both edges: four sample points per clock) plus a second copy of the data
  delayed by an IDELAY of 200 ps (4 taps of 52 ps at a 310 MHz IDELAYCTRL reference): eight sample
  points per 1.6 ns clock, i.e. four per 800 ps bit. A data recovery unit compares neighbouring
  samples with XOR to locate an edge, picks the sample farthest from it, and tracks edge drift with
  a state machine; when the edge crosses a word boundary it produces a **bit skip or repeat** (5 or
  7 bits instead of 6). Jitter budget: the starting requirement is 0.500 UI, sampling-phase error
  adds 0.125 UI (0.625 UI), leaving 0.375 UI for everything else. The sampling-phase error comprises
  MMCM jitter, **CLK0-to-CLK90 phase error**, **MMCM duty-cycle distortion**, IDELAY accuracy and
  pattern-dependent jitter, and master/slave path offset. A **clock-alignment calibration** measures
  the phase between two clock trees by looping an OSERDES pattern back into an ISERDES and
  phase-shifting the MMCM output until they match.
- Applied use: Finogeev et al., "Development of a 100 ps TDC based on a Kintex 7 FPGA for the High
  Granular Neutron Time-of-Flight detector for the BM@N experiment", arXiv 2309.17235 (2023): the
  TDC board "is based on the standard LVDS 4x asynchronous oversampling" with 100 ps bins [R abstract].
  So 4x phase oversampling is a known way to make a TDC; our sampler word is a 4-bin TDC.
- **Blind oversampling CDR:** Yang, Farjad-Rad, Horowitz, "A 0.5-um CMOS 4.0-Gbit/s Serial Link
  Transceiver with Data Recovery Using Oversampling", IEEE JSSC 33(5):713-722, 1998, doi
  10.1109/4.668986 (VLSI Circuits 1997 version doi 10.1109/vlsic.1997.623812) [S]; Kim and Jeong,
  "Multi-Gigabit-Rate Clock and Data Recovery Based on Blind Oversampling", IEEE Communications
  Magazine 41(12):68-74, 2003, doi 10.1109/mcom.2003.1252801 [S]. Neither read; both closed access.
  Also a 2003 CICC paper on a phase-interpolator CDR: Kreienkamp et al., JSSC 40(3):736-743, 2005, doi
  10.1109/jssc.2005.843624 [S].

## 3. High-resolution digital PWM

The structure "coarse counter on the clock, fine delay for the sub-clock part" is the standard
architecture, and the sub-clock part is called a DTC in other literature. Our "slot plus quarter
plus tap" is the same split.

- **Architectures** [R: Peterchev et al. 2003, section V, https://power.eecs.berkeley.edu/publications/peterch_xiao_03.pdf].
  Counter-comparator needs a fast clock (mW-class power); tapped delay line replaces the fast clock
  by a line running at the switching frequency but needs "precise delay matching among the phases"
  in a multiphase converter, and mux area grows exponentially with bits; combined delay-line plus
  counter trades area against power but "the asymmetry of the delay line remains a problem for
  multiphase applications". Peterchev's ring-oscillator-MUX has a 128-stage differential ring (256
  symmetric taps), the PWM edge being the ring edge reaching a selected tap; 8 bits between two
  adjacent taps; the four phases tap the ring at offsets of 64. Test chip: 195 ps resolution
  [S: abstract as relayed by a search result; the figure is not in the body text I extracted]. Effective 10 bits from 7 bits of hardware plus 3 bits of digital dither.
- **Resolution versus limit cycling:** Peterchev and Sanders, "Quantization Resolution and Limit
  Cycling in Digitally Controlled PWM Converters", IEEE TPE 18(1):301-308, 2003, doi
  10.1109/tpel.2002.807092 [S]. Relevant principle: the modulator's step must be finer than the
  loop's other quantisation or the loop dithers.
- **Surveys:** Syed, Ahmed, Maksimovic, Alarcon, "Digital Pulse Width Modulator Architectures", PESC
  2004, doi 10.1109/pesc.2004.1354828 [S]. Fernandez-Gomez et al., "Design and Implementation of Two
  Hybrid High Frequency DPWMs Using Delay Blocks on FPGAs", IEEE TPE 2021, doi 10.1109/tpel.2021.3091306,
  open copy https://e-archivo.uc3m.es/bitstreams/a01b4f82-8ccf-45c0-a796-1252fb8abae3/download [R].
  Its comparison table (resolutions reported by others, all FPGA): 1.242 ns and 730-737 ps (hybrid
  with DLL, calibration and manual place-and-route needed); 19.5 ps at 6.25 MHz (fine clock phase
  shifting); 60 ps and 90 ps (Costinett et al.: "With 1 MUX, the DPWM is **not monotonic** and the
  resolution is 20 ps. When using 4 MUX, the DPWM is monotonic and the resolution is 90 ps");
  78 ps (IODELAY); 41.3 ps and 40.2 ps (carry chains). It also records the common caveats:
  duty-cycle update needing more than one clock, calibration after place-and-route, "nonlinearity
  in the on-time step due to duty-cycle variation" (DCM-based). The paper's own result: 76.8 ps
  measured on a buck converter.
- **FPGA clock phase shifting:** de Castro and Todorovich (above) [S]; Costinett, Rodriguez,
  Maksimovic, "Simple Digital Pulse Width Modulator Under 100 ps Resolution Using General-Purpose
  FPGAs", IEEE TPE 28(10):4466-4472, 2013, doi 10.1109/tpel.2012.2233218 [S].
- **TI C2000 HRPWM** (TMS320x280x/2801x/2804x HRPWM Reference Guide, SPRU924F, Oct 2011) [R]. The
  micro edge positioner (MEP) places an edge in "one of 255 (8 bits) discrete time steps"; "time step
  accuracy ... on the order of 150 ps"; examples use 180 ps. Duty is the concatenation
  [CMPA:CMPAHR] (CMPAHR an 8-bit fraction); CMPAHR = frac(duty x period) x MEP_ScaleFactor, where the scale factor is the MEP
  steps per SYSCLK. "The MEP scale factor varies with the system clock and DSP operating
  conditions"; TI supplies the **scale factor optimiser (SFO)** software, which "uses the built in
  diagnostics in each HRPWM", "varies slowly over a limited range so [it] can be run very slowly in a
  background loop". **Limits:** the MEP is not active for the first 3 SYSCLK cycles after a period
  starts (6 while SFO diagnostics run), so "precision edge control is not available all the way down
  to 0% duty"; regular PWM still works down to 0. Newer parts are quoted at ~60 ps [S via
  Fernandez-Gomez et al.].
- **Microchip** (dsPIC33CK256MP508 datasheet, DS70005349E, 2017-2018) [R]: "up to 250 ps PWM
  resolution", status bits HRRDY ("high-resolution circuitry is ready") and HRERR; "Duty cycle
  values less than 0x0008 should not be used (0x0020 in High-Resolution mode)". Same shape of
  limitation as TI's: fine placement has a minimum pulse width.

## 4. Time-to-digital converters

- **Tapped delay line / Vernier.** Dudek et al. [R]: a single delay line is limited to "a few
  hundred picoseconds" resolution in contemporary CMOS; a Vernier line (two chains, delays differing
  by tau) gives resolution = the difference; limited by "mismatch of the transistors and noise" and
  line length. They stabilise the resolution with a **DLL** ("calibration against process
  variations and ambient conditions"), 128 stages, 30 ps, accuracy better than 1 LSB, 5 ps shown
  attainable. Dummy devices and matched layout for parasitics.
- **FPGA carry-chain TDCs.** Wu, Shi, Wang, "Firmware-only implementation of time-to-digital
  converter (TDC) in field-programmable gate array (FPGA)", IEEE NSS 2003, pp. 177-181, doi
  10.1109/nssmic.2003.1352025 (open copy https://www.osti.gov/biblio/817308) [S]. Wu and Shi 2008
  [R]: bin widths "are uneven and depend on temperature and power supply voltage, which must be
  calibrated as frequently as possible"; origins of DNL: logic-array-block boundaries give periodic
  "ultra-wide bins" (typical bin about 60 ps, ultra-wide as large as 165 ps on a Cyclone II),
  clock-distribution skew between flip-flops, and, with inverting delay cells, different widths for
  even and odd bins. **Wave union:** a launcher sends a pulse train (several transitions) down the
  chain so that one measurement yields several readings that subdivide the ultra-wide bins; 20 to 10 ps in low-cost FPGAs. **Auto
  calibration:** a code-density histogram of hits taken against an asynchronous source gives each
  bin's width as N x (clock period)/(total hits), e.g. 16384 hits across a 2500 ps clock period; a
  lookup table turns codes into bin-centre times. Later: Xie, Chen, Li, "Are wave union methods
  still suitable for 20 nm FPGA-based high-resolution (<2 ps) time-to-digital converters?",
  arXiv 2009.03591: bubbles and ultra-wide bins get worse on UltraScale; clock skew at clock-region
  boundaries is a main cause of nonlinearity [R abstract and introduction].
- **Multiphase-DLL TDC: CERN HPTDC** [R: manual v2.2]. 32 delay elements locked to a 40 MHz clock
  gives about 250 ps RMS; a 320 MHz PLL clock drives the DLL for 30-50 ps; in "very high
  resolution" mode the DLL phases are sampled four times from a precisely calibrated **R-C delay
  line** (about 25 ps steps), with a per-chip external calibration that "can be considered constant
  within reasonable variations of temperature and voltage (+-25 C, +-10% Vdd)". Measured
  (specification table in the manual): time resolution 265/86/64/58 ps in the four modes, **17 ps RMS in very-high mode
  after table correction**; INL +3.5/-5.0 bins (2.1 bins RMS) in very-high mode; temperature
  variation "maximum 100 ps change with 10 degrees change of IC temperature"; 150 ps crosstalk
  from 31 concurrent channels. The INL has "a fixed pattern ... caused by 40 MHz cross talk from the
  logic part of the chip to the time measurement part ... power supply and substrate coupling";
  because the interferer is the TDC's own time reference "the integral non linearity [has] a stable
  shape between chips and can therefore be compensated for by a simple look up table using the LSB
  bits". The DNL has a peak at tap 27 plus multiples of 32, the DLL wrap-around cell.
- **Nutt interpolation and equivalent-time sampling.** R. Nutt, "Digital Time Intervalometer",
  Rev. Sci. Instrum. 39(9):1342-1345, 1968, doi 10.1063/1.1683667 [S]: coarse counter plus separate
  interpolators for the fractions before the first and after the last counted clock; reported 200 ps
  resolution for intervals up to 1 ms (per search snippets and review chapters, not read). Random
  interleaved (equivalent-time) sampling in oscilloscopes uses a TDC to time each sample against the
  trigger [S: Teledyne LeCroy whitepaper, https://cdn.teledynelecroy.com/files/whitepapers/wp_ris_102203.pdf]. Our shmoo is *sequential* equivalent-time sampling (step a delay
  and repeat); a free-running TDC would give the *random* variant without stepping.
- **On-chip self-measurement of skew and delay.**
  - Code-density calibration (Wu and Shi) is the lowest-cost route [R].
  - Gutnik and Chandrakasan, "On-Chip Picosecond Time Measurement", Symp. VLSI Circuits 2000, pp.
    52-53, doi 10.1109/vlsic.2000.852849: an array of 64 arbiters in 0.35 um with temporal
    resolution better than 2 ps, calibrated using additive noise [S abstract].
  - Abaskharoun and Roberts, "Circuits for On-Chip Sub-Nanosecond Signal Capture and
    Characterization", CICC 2001, pp. 251-254, doi 10.1109/cicc.2001.929766 [S].
  - Tabatabaei and Ivanov, "Embedded Timing Analysis: A SoC Infrastructure", IEEE Design & Test of
    Computers 19(3):22-34, 2002, doi 10.1109/mdt.2002.1003786 [S].
  - XAPP523's clock-alignment loop (loop an output pattern into the sampler and phase-shift to
    match) measures phase between two clock trees with the I/O flip-flops themselves [R].
  - TI SFO and HPTDC both use the device's own diagnostics [R].

## 5. DTCs and phase interpolators in SerDes

- DTC and phase interpolator (PI) literature is mostly analogue or mixed-signal and aimed at
  fractional-N PLLs and CDRs: Staszewski et al., "All-Digital PLL and Transmitter for Mobile
  Phones", IEEE JSSC 40(12):2469-2482, 2005, doi 10.1109/jssc.2005.857417 [S]; Tasca, Zanuso, Marzin,
  Levantino, "A 2.9-4.0 GHz Fractional-N Digital PLL With Bang-Bang Phase Detector and 560-fs rms
  Integrated Jitter at 4.5 mW", IEEE JSSC 46(12):2745-2758, 2011, doi 10.1109/jssc.2011.2162917 [S];
  Kreienkamp et al. (above) [S]; Sidiropoulos and Horowitz, "A Semidigital Dual Delay-Locked Loop",
  IEEE JSSC 32(11):1683-1692, 1997, doi 10.1109/4.641688 [S]; Razavi, "The Design of a Phase
  Interpolator", IEEE Solid-State Circuits Magazine 15(4):6-10, 2023, doi 10.1109/mssc.2023.3315653 [S].
- Search results repeatedly state that DTC nonlinearity (INL) is what produces fractional spurs in
  DTC-based PLLs and that gain/INL are calibrated with LMS-type loops [S: search snippets only; I did not read any of
  these]. Note the structural parallel: a DTC whose code is a *deterministic* function of time (our
  NCO feeds the DTC) turns INL into **periodic** error, hence spurs rather than noise.
- Open-source synthesizable DTC/PI: Kim, Myers, Herbst, Lim, Horowitz, "Open-Source Synthesizable
  Analog Blocks for High-Speed Link Designs: 20-GS/s 5b ENOB ADC and 5-GHz Phase Interpolator",
  arXiv 2009.09077 (2020): built from digital standard cells and digital place-and-route; the PI uses
  a delay chain generating 32 phases with arbiters to find the number of delays per clock and mux
  and phase-blender selection, and notes that automated PnR "jeopardises" matching when path-delay
  mismatch exceeds the unit delay of the chain [R abstract and excerpts]. This is the nearest
  "synthesised DTC with on-chip calibration" precedent I found.
- On-chip, measured: Dehmeshki et al., "A Sub-Picosecond Digitally-Controlled Phase Delay",
  arXiv 2111.13548 (2021): 66 cells, TSMC 65 nm, 200 fs precision with 12 ps range [R abstract].

## 6. Known failure modes and mitigations

| Failure | What the sources say | Mitigation in the sources |
| --- | --- | --- |
| **Phase mismatch gives fixed-pattern timing error and spurs** | Timing skew dT between interleaved channels adds dT x dx/dt; in the spectrum it produces a copy at k x f_clk offset by the input, and offsets make a tone at f_clk and 3 f_clk [R: Razavi, "Problem of Timing Mismatch in Interleaved ADCs", CICC 2012, http://www.seas.ucla.edu/brweb/papers/Conferences/BRCICC12.pdf]. Also Kurosawa et al., IEEE TCAS-I 48(3):261-271, 2001, doi 10.1109/81.915383 (open copy http://www.hit.bme.hu/people/papay/edu/Conv/pdf/Kurosawa.pdf) [S]; Black and Hodges, IEEE JSSC 15(6):1022-1029, 1980, doi 10.1109/jssc.1980.1051512 [S]; Jenq, IEEE Trans. Instr. Meas. 37(2):245-251, 1988, doi 10.1109/19.6060 [S]. For edge combiners: spur level set by in-lock error and delay-stage mismatch [S: Casha et al.]; HPTDC's INL is a fixed pattern locked to its own clock [R]. | Calibrate the skew (Razavi surveys detection and correction schemes: digital filter, zero-crossing, background); layout symmetry; ring/tap symmetry (Peterchev, "symmetric structure") [R]. |
| **XOR glitches when lanes toggle near-simultaneously** | HDLBits notes that combinational emulation of a dual-edge flip-flop "might" glitch [R]. Beyond that I found no source on XOR-combiner glitching specifically. Our own analysis (README "Glitches in the XOR combiner") argues by construction (one lane per phase, quarter apart) and says neither simulation can see it. | Static check of minimum pulse width: OpenSTA `report_check_types -min_pulse_width` and `set_min_pulse_width` exist [R: https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/doc/Commands.md] but check clock pins, not the XOR output; a post-layout transient simulation or a delay-annotated gate-level run is needed [inference]. |
| **Duty-cycle error** | Using falling edges makes combined timing depend on the reference duty cycle [R: Beek 2001]; XAPP523 lists MMCM duty-cycle distortion in the sampling-phase error [R]; Fernandez-Gomez table lists "nonlinearity in the on-time step due to duty-cycle variation" for a DCM DPWM [R]. | Rising-edge-only (our design). Duty-cycle correctors if phases are derived from one clock's two edges: e.g. Kim et al., "A 500MHz DLL with second order duty cycle corrector for low jitter", CICC 2005, doi 10.1109/cicc.2005.1568671 [S]; quadrature clock correctors, Chae et al., IEEE TVLSI 27(4):978-982, 2019, doi 10.1109/tvlsi.2018.2883730 [S]. |
| **Metastability in multiphase samplers** | XAPP224: each of four samplers followed by another flip-flop; "no problem as long as the load on the potentially metastable flip-flop is one" [R]. Ginosar, "Metastability and Synchronizers: A Tutorial", IEEE Design & Test 28(5):23-35, 2011, doi 10.1109/mdt.2011.113 (open copy https://webee.technion.ac.il/people/ran/papers/MetastabilitySynchronizersTutorialIEEEDT2011.pdf): MTBF = e^(S/tau)/(T_W f_C f_D); example 28 nm: tau = 10 ps, T_W = 20 ps; tau is "several times larger" with process variation and "may increase by several orders of magnitude" at low supply and extreme temperatures; a missed resolution time S "has made quite a few synchronizers fail unexpectedly" [R]. The 7-series XAPP523 does not discuss it beyond the ISERDES. | Two-flop per phase (ours); compute MTBF with measured tau and T_W; our README: "No MTBF was computed." |
| **Calibration against PVT** | Tap delay spans 2.4x across our own liberty corners (README). TI SFO [R], Dudek's DLL [R], IDELAYCTRL continuously recalibrating from a reference clock (UG471, as relayed [S]; XAPP523 uses 310 MHz giving 52 ps taps [R]), Wu and Shi semi-continuous auto-calibration [R], HPTDC one-off per-chip calibration of an R-C line, "constant within +-25 C, +-10% Vdd" [R]. | Count taps per clock, repeat slowly; histogram calibration for DNL; temperature drift 100 ps per 10 C in HPTDC means recalibrate on a temperature or time trigger. |
| **Power of multiphase clock distribution** | Dynamic power scales with phases x frequency; skew-adjust granularity costs power and area [S: search snippets about multiphase distribution in serial links, no primary source read]. Quarter-rate designs exist precisely to cut clock power [S: e.g. a 32 Gb/s quarter-rate PAM4 CDR, researchgate.net/publication/342852838]. Our own number: the stage costs ~500 um2 per output pin and ~750 per input pin (README), clock-tree power unmeasured. | Measure with the Tiny Tapeout power report or an external current measurement with the phases gated, not estimated. |
| **STA of multi-phase paths** | Our SDC declares four `create_clock -waveform` entries, same period, shifted by P/4, ideal clocks (README, `sta/sta_16p67.sdc`). OpenSTA documents `create_clock -waveform`, `set_clock_latency`, `set_propagated_clock`, `report_clock_skew` [R: Commands.md above]. XAPP224 bounds only *skew* from pad to the four flip-flops (MAXSKEW 500 ps) [R]. | After clock-tree synthesis, re-run with propagated clocks and read the real phase-to-phase insertion delay; add a pad-to-sampler skew check. |
| **Delay-line mismatch, ultra-wide bins, bubbles** | Wu and Shi, Xie et al., Dudek [R]. Costinett: a one-mux DPWM was non-monotonic [R via Fernandez-Gomez]. Dehmeshki and the arXiv 2009.09077 authors both stress layout matching [R abstracts]. | Wave union, sub-delay-line, thermometer-to-binary with bubble correction [R abstract: Xie et al.]; LUT correction [R]. |
| **Fine placement near the coarse edge** | TI and Microchip both disable or limit fine placement for short pulses [R]. | Document a minimum fine-pulse width; test it. |

## 7. Deterministic timed I/O and thread-interleaved processors

- **PRET machines** (Berkeley/Columbia/Saarland). Thread-interleaved pipeline, scratchpads instead
  of caches, "explicit timing control at the ISA level" [R: Lickly, Liu, Kim, Patel, Edwards, Lee,
  "Predictable Programming on a Precision Timed Architecture", CASES 2008, pp. 137-146, doi
  10.1145/1450095.1450117, https://ptolemy.berkeley.edu/projects/chess/pubs/475/cases025-lickly.pdf].
  It uses a six-stage thread-interleaved pipeline; the **deadline instruction** (a lower bound on
  execution time of a code segment, which makes execution time exactly repeatable) is credited to Ip
  and Edwards (2006), "first implemented ... in a very simple non-pipelined processor"; "Thread-
  interleaved pipelines date to at least 1987 [20], probably much earlier" [R]. PTARM: Liu, Reineke,
  Broman, Zimmer, Lee, ICCD 2012, pp. 87-93, doi 10.1109/iccd.2012.6378622: four hardware threads in
  a five-stage pipeline, "each thread cycle is equivalent to four processor cycles" [R,
  https://ptolemy.berkeley.edu/projects/chess/pubs/919/ptarm-iccd-2012-accepted-version.pdf].
  FlexPRET: Zimmer, Broman, Shaver, Lee, RTAS 2014, pp. 101-110, doi 10.1109/rtas.2014.6925994 [S].
  Abstract PRET machines: Lee, Reineke, Zimmer, RTSS 2017, doi 10.1109/rtss.2017.00041 [S]. **Our
  four-thread, one-instruction-per-clock deadline sequencer is closest to PTARM plus the deadline
  instruction.** [inference from the above]
- **XMOS xCORE (XS1).** Threads issued round-robin with a guarantee: "with n threads able to
  execute, each will get at least 1/n processor cycles"; threads are "virtual processors each with
  clock rate at least 1/n". **Timed ports:** a port has a timer; SETPT sets a port time so that
  "the movement of data between the pins and the transfer register" happens at that time; GETTS
  reads the timestamp at which an input condition was met [R: D. May, *The XMOS XS1 Architecture*,
  2009, Sections on scheduling and ports, https://docs.alexrp.com/xcore/xmos_xs1.pdf]. This is the
  closest commercial analogue to our "sub-slot comes with each pin write".
- **CDC 6600 peripheral processors** [R: Thornton 1970, pp. 141-143]: ten PPUs share one "slot" of
  arithmetic and logic, the "barrel"; "once every minor cycle, 100 nanoseconds, all information in
  the barrel is moved one position"; each PPU passes the slot once per major cycle (1000 ns); the
  ten-way sharing is chosen to fit the 1000 ns storage cycle against the 100 ns arithmetic. Also
  Thornton, "Parallel Operation in the Control Data 6600", AFIPS FJCC 1964, doi 10.1145/1464039.1464045 [S].
- **Time-triggered architecture:** Kopetz and Bauer, "The Time-Triggered Architecture", Proc. IEEE
  91(1):112-126, 2003, doi 10.1109/jproc.2002.805821 [S, not read].
- **TI PRU** (AM335x PRU-ICSS Reference Guide, SPRUHF8A, 2012-2013): "The PRU cores are programmed
  with a small, deterministic instruction set"; PRU-ICSS includes enhanced GPIO with serial,
  parallel and MII **capture** of the pins [R]. The 200 MHz clock and single-cycle execution are
  widely quoted; I read only the 200 MHz peripheral clocks, not the cycle-per-instruction statement, so that is [S].
- **Parallax Propeller P8X32A** [R: datasheet, sections 4.3-4.4]: eight cogs on one system clock, 20
  MIPS per cog at 80 MHz; hub access by "round robin" with the hub at half the system clock, "once
  every 16 System Clock cycles", hub instructions take 7 to 22 cycles depending on window alignment.
  Two counters per cog. Deterministic but not cycle-exact for hub access.
- **RP2040 PIO** (RP2040 Datasheet, RP-008371-DS) [R]. Every instruction takes "precisely one cycle,
  unless it explicitly stalls"; up to 31 delay cycles (section 3.2.2); the clock divider is 16-bit
  integer plus 8-bit fractional "with first-order delta-sigma for the fractional divider" (3.5.5),
  so a fractional divisor makes the state-machine clock jitter ("selectively extending some division periods"; the size, one system clock, is my [inference]); a "standard 2-flipflop
  synchroniser" on each GPIO input adds two cycles of latency, bypassable per pin for synchronous
  interfaces (3.5.6.3, INPUT_SYNC_BYPASS). **PIO's timing grid is the system clock; nothing places an
  edge between system clocks.** The datasheet publishes no input-to-output timing figures (a pico-feedback issue notes this [S]).
- **Same shuttle, same idea:** PESM v3 (github.com/grcheulishvili/PESM, created 2026-10-01) is a
  microcoded cycle-exact protocol emulator for the IHP SG13G2 Tiny Tapeout shuttle: 6x4 tiles, 50
  MHz, one instruction per clock, 64 x 16-bit instruction memory, with a 16.8 fractional tick divider
  [R: README]. A single thread, no sub-clock edge placement. Worth reading as a contemporary design on the same flow.
- **Open-silicon delay-line and TDC projects (Tiny Tapeout):** tt09-analog-tdc (13hihi31): tapped-delay-line
  TDC in sky130, 8 stages, "approximately 75 ps in post-layout simulations", a variable delay line to generate the stop signal; **no measured silicon result is stated** [R: https://tinytapeout.com/chips/tt09/tt_um_13hihi31_tdc];
  tt04 "Delay Line" (ashleyjr) [S]; tt-um-govardhana-adpll (ring-oscillator DCO, counter TDC, two-tile
  all-digital PLL, sky130) [S: github.com/SriKondapaturi/tt-um-govardhana-adpll]; "Ring Oscillator Meter" on IHP (mgpauly1458/ttihp26b-project) [S]. I found no Tiny Tapeout or IHP project with
  a multiphase XOR output stage or a four-phase sampler.

## 8. What this means for our design

Ranked by how much each lesson could change a decision. "Planted fault" means: inject this into the
model or RTL with a control run and confirm the check fails; the repo's existing habit (lane on the wrong
phase, OR instead of XOR) already follows this.

1. **Measure the inter-phase skew and the tap widths with the chip's own samplers, using a code-density
   histogram, before trusting any calibration.** Wu and Shi and HPTDC both build bin widths from a
   histogram of hits from an *asynchronous* source (N counts per bin times period over total hits).
   The input stage has four phase samplers, so an asynchronous edge source (an on-chip ring
   oscillator, or an external clock at a non-commensurate frequency) gives the relative width of the
   four quarter-intervals directly, which is the phase skew. [inference from Wu and Shi] Arithmetic
   (mine): to resolve a 50 ps phase error in a 4.17 ns quarter (a 0.3% change in occupancy) needs
   about 2 x 10^5 edges for one standard error of 0.1% (a 3-sigma detection) and 2 x 10^6 for 10 sigma; at 1 MHz of edges that is seconds. Do this on the sampler first
   (it costs nothing but an asynchronous source); it also checks the DTC (step the tap, read the
   sampler).
   - Measure: per-phase offset, per-tap width, DNL pattern periodicity.
   - Planted faults: phase 2 early by 300 ps; periodic DNL with period 16 or 32 taps; even/odd tap width asymmetry (Wu and Shi's inverting-cell effect).
   - Cite: Wu and Shi 2008; Christiansen HPTDC manual section "Time resolution measurements".

2. **Test for a clock-synchronous fixed-pattern INL.** HPTDC attributes its limit to INL from crosstalk: 58 ps raw against 17 ps after table correction
   (a factor of about 3.4), from crosstalk from its own 40 MHz core clock into the
   timing path, which was stable chip to chip and corrected by a LUT indexed by the low bits. Our
   DTC/TDC sits next to a 60 MHz sequencer, so expect the same shape: INL as a function of the
   position in the core clock period. Add a plant: a sinusoidal INL term locked to the core clock, amplitude 30 ps, and check that the
   histogram test of lesson 1 detects it, and that the LUT correction removes it.
   Cite: HPTDC manual, Design bugs and problems.

3. **Treat spurs as the FM transmitter's real risk and compute their frequencies before measuring.**
   The interleaving literature says static lane skew puts images of the signal at multiples of the
   lane rate, here f_clk. [inference: our lanes are a four-way interleaved edge generator] My
   arithmetic for the README's FM case (99.75 MHz carrier, 66.5 MHz clock): images at 99.75 +- k x
   66.5 MHz fall at 33.25 and 166.25 MHz and beyond, none inside the 88-108 MHz band, which is
   consistent with the README's measured small loss (31.5 to 28.5 dB SINAD* for 800 ps lane skew).
   What would matter instead: the DTC's INL (periodic because the NCO is deterministic), so test
   the NCO-through-DTC case with a swept INL pattern, as done for 5 ps walk and 2% scale error, but with a *periodic* INL of 20 to 50 ps and read the spur line, not SINAD.
   Cite: Razavi CICC 2012, Kurosawa 2001; Peterchev and Sanders 2003 (quantisation versus limit cycling).

4. **Plant XOR-combiner faults that the zero-delay simulations cannot see.** The README itself says
   both simulators are blind to glitches. Run the lane stage in a delay-annotated gate-level
   simulation (the Liberty numbers already exist) with: two lanes toggling within 100 ps of each
   other (DTC delays making edges coincide), lane p+1 earlier than p (reordering), and a
   runt-width sweep. The finding that matters is the minimum pulse the pad and XOR pass, which the
   README marks unverified. TI and Microchip both document a minimum duty below which fine
   placement is unavailable; document ours. Cite: HDLBits Dualedge (caveat), SPRU924F section 2.3.3, DS70005349E.

5. **Keep the rising-edge-only rule everywhere, and test the one place it can leak.** Beek et al. and
   XAPP523 say duty cycle only matters when falling edges are used. Our lanes avoid it, but the
   README's "both clock edges" source, the PLL phase generation, and any DLL that derives the 90 and
   270 degree phases from the 0 and 180 degree ones would reintroduce it. Plant a 40/60 duty on the
   source clock; with rising-edge phases from a DLL the error should not change. If phases come from
   the clock's two edges, report what duty error costs. Cite: Beek 2001, XAPP523 jitter-tolerance table.

6. **Calibrate against PVT by counting taps per clock, but also bound the calibration's blind spots.**
   Everyone calibrates this way (Dudek DLL, TI SFO, IDELAYCTRL, Wu and Shi). Make explicit: (a) the
   line must cover at least one quarter, preferably one full clock, at the *fast* corner and still
   fit at slow (our liberty numbers: 42.6, 63.2, 101 ps per buffer: 2.4x); (b) calibration is
   background and slow (TI SFO: "very slowly in a background loop") but TI's diagnostics make the MEP
   unusable for 6 cycles, so decide where in the sequencer's schedule it runs; (c) HPTDC measured
   100 ps drift per 10 C of die temperature, so a thermal trigger beats a fixed schedule;
   (d) a DLL with harmonic lock (Foley and Flynn's false lock) must be detected, not assumed.
   Planted fault: lock at 2T; a calibration run at a shifted supply. Cite: SPRU924F 2.3, Foley and Flynn section II.

7. **Make the TDC readings robust to bubbles and wide bins, by design rather than by luck.**
   Thermometer codes from a delay line get bubbles; wave union and sub-delay-line are known fixes.
   For our four-sample word, the analogue is a *non-thermometer pattern* (for example 0101 across the
   phases): count it as a free health metric. It flags metastable resolution and gross skew. Plant: force one phase to be late by
   more than a quarter and check the counter. Cite: Xie, Chen, Li 2020; Wu and Shi; XAPP523 on edge comparison.

8. **Compute the synchroniser MTBF.** The README says none was computed; Ginosar's formula needs tau
   and T_W for the IHP flip-flop at the slow, low-voltage, hot corner, because tau can degrade by
   orders of magnitude there. Four samplers per pin multiply the number of near-aperture events by
   four relative to one sampler; the extra sampling is also what masks them, so evaluate rather than guess.
   Cite: Ginosar 2011; XAPP224 metastability section.

9. **Put real clock-tree skew into STA before silicon.** Ideal-clock STA cannot show inter-phase
   insertion-delay error, which the README correctly lists as the unknown. Run propagated-clock STA
   after CTS, extract each phase's latency (`report_clock_skew`), add a pad-to-sampler path-skew check as XAPP224 does (skew, not absolute delay), and re-run the
   lane-skew tolerance experiments with the extracted numbers (the stage tolerates about 3 ns, so a
   comfortable margin is expected, but state the measured value).

10. **Write-up positioning.** The honest claim is a *combination*: rising-edge edge-combining of
    four phases (Foley and Flynn; van de Beek et al.) used as a per-pin data-edge generator driven by a
    deterministic thread-interleaved sequencer with a deadline notion (Ip and Edwards; PTARM; XMOS timed
    ports), plus 4x phase oversampling (XAPP224/523) and a calibrated DTC/TDC (TI HRPWM, Dudek, HPTDC,
    Wu and Shi). Cite XAPP224 and XAPP523 for the input stage, Beek 2001 for the rising-edge rule,
    TI SPRU924F and Microchip DS70005349E for "coarse grid plus fine delay", Wu and Shi 2008 and the HPTDC
    manual for code-density calibration and fixed-pattern INL, PTARM and the XMOS XS1 manual for the sequencer lineage,
    and RP2040 PIO as the timing-grid comparison (PIO's grid is one system clock and its fractional
    divider jitters by design). Do not claim novelty of the combination beyond "I found no
    published precedent", which is weak.

## 9. What I could not verify, and why

- Dancy et al. 1997 and 2000, de Castro and Todorovich 2008 and 2010, Huerta et al., Costinett et al.:
  paywalled (IEEE), no open copy found; their content is known only through Peterchev (read) and the
  Fernandez-Gomez table (read).
- Foley and Flynn is read in full from an author-hosted copy
  (https://www.mpflynngroup.com/uploads/7/3/4/9/73490609/00910480.pdf); OpenAlex and Unpaywall report
  it closed, so check the copy's licence before redistributing it.
- Casha et al. spur analysis (open copy at um.edu.mt returned an HTML gate), Gutnik and Chandrakasan,
  Abaskharoun and Roberts, Tabatabaei and Ivanov, Kim and Jeong, Yang et al., Nutt, Hossain/Gago/Llopis,
  Kopetz and Bauer, Edwards and Lee, FlexPRET: metadata checked in Crossref, content not read.
- Microchip DS70005320, TI newer HRPWM step figures, Xilinx UG471 and DS182 numbers: not read.
- The XOR-combiner claim for DLL multipliers (as opposed to AND-OR) rests on a search snippet only.
- The DPWM "dither" and "limit cycle" principle is from Peterchev's own summary; the companion
  paper itself is [S].

## 10. Bibliography checked in Crossref (author, year, venue, DOI)

Entries marked in the text with doi were looked up in Crossref/OpenAlex on 2026-10-06; the label
says whether I read the paper. Open copies read: XAPP224
(https://docs.amd.com/api/khub/documents/PRa042GlRmr8Z~QWgM6qYA/content), XAPP523
(https://docs.amd.com/api/khub/documents/idLQiUc5PAanaw3lcdBzZg/content), SPRU924F
(https://www.ti.com/lit/pdf/spru924), DS70005349E
(https://ww1.microchip.com/downloads/en/DeviceDoc/dsPIC33CK256MP508-Family-Data-Sheet-DS70005349E.pdf),
Dudek (https://personalpages.manchester.ac.uk/staff/p.dudek/papers/dudek-jssc2000.pdf), Wu and Shi
(https://inspirehep.net/files/f5280a625c69285e1c00f24e1bfa1543), HPTDC
(http://www.oka.ihep.ru/Members/semenovv/iii/hptdc_manual_ver2-2.pdf), Peterchev et al.
(https://power.eecs.berkeley.edu/publications/peterch_xiao_03.pdf), Fernandez-Gomez et al., Ginosar,
Razavi, Lickly et al., PTARM, XMOS XS1 (URLs above), Thornton
(https://archive.computerhistory.org/resources/text/CDC/cdc.6600.thornton.design_of_a_computer_the_control_data_6600.1970.102630394.pdf),
RP2040 datasheet (https://pip.raspberrypi.com/documents/RP-008371-DS-rp2040-datasheet.pdf), P8X32A
datasheet (https://www.playingwithfusion.com/files/p8x32a_q44_datasheet.pdf), AM335x PRU-ICSS guide
(https://mythopoeic.org/BBB-PRU/am335xPruReferenceGuide.pdf, a community mirror of SPRUHF8A).
