The suite of ../2026-09-25-sim/ re-run after merging master into fpga-ulx3s (sub-slot sequencer,
prototypes/multiphase), with emu_core.v feeding pin_in4 (each pin's sample in all four quarters).
cpb60/, cpb8/: uv run host/emu_runner.py --sim --cpb {60,8} --controls -> "18 of 18 as expected"
each. Every .trace and .capture file is byte-identical to the pre-merge run (36 files per divider).
regen/: logs of regenerating the Verilog from master's sources in a scratch copy of the prototypes
(deadline-sequencer main.exe ALL PASS, usb-fs-device USB DEVICE PASS, multiphase main.exe ALL PASS,
streamer and sampler emit); all five generated files were byte-identical to master's committed ones.
