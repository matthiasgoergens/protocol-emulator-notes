# SPDX-License-Identifier: Apache-2.0
# KV260 carrier: the Pmod connector and the fan enable, for ../rtl/kv260_top.v.
#
# Package pins from AMD's KV260 platform constraints (Xilinx/kv260-vitis, release-2021.1,
# platforms/vivado/kv260_ispMipiRx_vcu_DP/xdc/pin.xdc), which put a Digilent Pmod I2S2 on this
# connector: its transmit side (Pmod pins 1-4) on H12 E10 D10 C11 and its receive side (pins 7-10)
# on B10 E12 D11 B11. The mapping of package pin to Pmod pin number is read from that module's
# pinout; check it against the carrier schematic before wiring anything that could be damaged.
# The bank is 3.3 V (HDA bank).

set_property PACKAGE_PIN H12 [get_ports pmod1]
set_property PACKAGE_PIN E10 [get_ports pmod2]
set_property PACKAGE_PIN D10 [get_ports pmod3]
set_property PACKAGE_PIN C11 [get_ports pmod4]
set_property PACKAGE_PIN B10 [get_ports pmod7]
set_property PACKAGE_PIN E12 [get_ports pmod8]
set_property PACKAGE_PIN D11 [get_ports pmod9]
set_property PACKAGE_PIN B11 [get_ports pmod10]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod1 pmod2 pmod3 pmod4 pmod7 pmod8 pmod9 pmod10}]

# The I2C pins are open drain. These internal pull-ups only keep the lines defined with nothing
# attached; a real I2C device needs real pull-ups (about 2.2 kohm to 3.3 V), since the demo's bus
# runs near 1 MHz at a 60 MHz chip clock.
set_property PULLUP true [get_ports {pmod7 pmod8}]
set_property PULLDOWN true [get_ports pmod9]

# Fan enable, active low (same file, "Fan Speed Enable").
set_property PACKAGE_PIN A12 [get_ports fan_en_b]
set_property IOSTANDARD LVCMOS33 [get_ports fan_en_b]
set_property SLEW SLOW [get_ports fan_en_b]
set_property DRIVE 4 [get_ports fan_en_b]

# The pins are watched with a logic analyser and the inputs are asynchronous to the chip clock;
# none of them has a timing relation that the tools should try to meet.
set_false_path -to [get_ports {pmod1 pmod2 pmod3 pmod4 pmod7 pmod8 pmod10 fan_en_b}]
set_false_path -from [get_ports {pmod7 pmod8 pmod9}]
