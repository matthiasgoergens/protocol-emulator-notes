Mutation check of the flash_interlock control: rtl/emu_core.v with prefix_ok forced to 1
(sed on a copy in /var/tmp/fpga-ulx3s/mutant), Verilator at 8 clocks per bit, runner run_test called
directly. The control must FAIL here, and does: the simulated flash received 0x06.
