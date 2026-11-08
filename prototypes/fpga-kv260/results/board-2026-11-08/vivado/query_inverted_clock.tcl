# SPDX-License-Identifier: Apache-2.0
# Read-only query of the routed KV260 bench (8 Nov 2026): how Vivado built the chip's falling-edge
# flip-flops. Counts registers with an inverted clock pin and names what drives their clock nets
# (a BUFGCE means the inversion sits in the flip-flop, not in a LUT on the clock).
#   vivado -mode batch -source query_inverted_clock.tcl -tclargs build/kv260_bench.runs/impl_1/kv260_top_routed.dcp
open_checkpoint [lindex $argv 0]
set regs [get_cells -hier -filter {PRIMITIVE_GROUP == REGISTER}]
set inv [filter $regs {IS_C_INVERTED == 1}]
puts "QUERY registers: [llength $regs], with IS_C_INVERTED=1: [llength $inv]"
set nets [lsort -unique [get_nets -of_objects [get_pins -of_objects $inv -filter {REF_PIN_NAME == C}]]]
foreach n $nets {
  set drv [get_cells -of_objects [get_pins -leaf -of_objects $n -filter {DIRECTION == OUT}]]
  puts "QUERY inverted-clock net $n driven by [get_property REF_NAME $drv] ($drv)"
}
set lut_clk 0
foreach n [lsort -unique [get_nets -of_objects [get_pins -of_objects $regs -filter {REF_PIN_NAME == C}]]] {
  set drv [get_cells -of_objects [get_pins -leaf -of_objects $n -filter {DIRECTION == OUT}]]
  if {[string match LUT* [get_property REF_NAME $drv]]} { incr lut_clk; puts "QUERY LUT drives clock net $n" }
}
puts "QUERY clock nets driven by a LUT: $lut_clk"
