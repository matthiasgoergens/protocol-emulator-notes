# SPDX-License-Identifier: Apache-2.0
# Adapted from TinyTapeout/ttihp-verilog-template test/Makefile (Apache-2.0).
#
#   make              RTL simulation of ../src (Icarus, cocotb)
#   make GATES=yes    gate-level simulation of gate_level_netlist.v; needs PDK_ROOT and a netlist
#                     copied here from a LibreLane/tt-gds-action run (tt_submission/<top>.v)
# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = project.v deadline_sequencer_v2.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

ifeq ($(wildcard $(PWD)/gate_level_netlist.v),)
$(error GATES=yes but test/gate_level_netlist.v does not exist: there is no hardened netlist yet)
endif
ifndef PDK_ROOT
$(error GATES=yes needs PDK_ROOT)
endif

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DSIM
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_io/verilog/sg13cmos5l_io.v
# The user-defined primitives (ihp_dff_r, ihp_mux2, ...) that the cell models instantiate live in a file of
# their own; the template's Makefile does not list it, and a netlist with flip-flops then fails to elaborate.
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_udp.v
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

# The core's Verilog is generated from Hardcaml, never committed. regen.sh rewrites it only when its
# contents change, so running it on every make is cheap and never leaves a stale copy.
$(SRC_DIR)/deadline_sequencer_v2.v: FORCE
	../scripts/regen.sh $@
.PHONY: FORCE
FORCE:
