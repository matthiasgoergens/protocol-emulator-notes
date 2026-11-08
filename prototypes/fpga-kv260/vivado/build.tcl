# SPDX-License-Identifier: Apache-2.0
# Build the KV260 test bench: project, block design, bitstream.
#
#   vivado -mode batch -source vivado/build.tcl -tclargs OUT_DIR
#
# OUT_DIR (default ../build) receives the project, timing.rpt, utilization.rpt, methodology.rpt
# and kv260_bench.xsa; the bitstream and its .bin are in OUT_DIR/kv260_bench.runs/impl_1/.
#
# NOT YET RUN: written without access to Vivado. Expect to fix details on the first run, and
# please report what had to change. Needs the KV260 board files (Vivado: Tools > XHub Stores >
# Boards, "Kria KV260 Vision AI Starter Kit") and ../../tt/src/chip_tt.v (../README.md, "Running it
# on the board", step 1).
#
# The block design: the Zynq processor system with the board's preset (DDR, MIO), its pl_clk0 at
# 60 MHz, and M_AXI_HPM0_FPD (32 bits) through an AXI SmartConnect to kv260_core's register port,
# all on pl_clk0. kv260_core's pins are made external and kv260_top.v puts them on the Pmod.

set here [file dirname [file normalize [info script]]]
set root [file normalize $here/..]
set tt [file normalize $root/../../tt/src]
set out [expr {[llength $argv] ? [file normalize [lindex $argv 0]] : "$root/build"}]

if {![file exists $tt/chip_tt.v]} { error "missing $tt/chip_tt.v: see prototypes/fpga-kv260/README.md, Running it on the board, step 1" }

create_project kv260_bench $out -part xck26-sfvc784-2LV-c -force
set boards [get_board_parts -quiet -latest_file_version *kv260_som*]
if {$boards eq ""} { error "no KV260 board files: install them from XHub (Tools > XHub Stores > Boards)" }
set_property board_part [lindex $boards end] [current_project]

add_files [list \
  $root/rtl/kv260_top.v $root/rtl/kv260_core.v $root/rtl/fpga_axil.v $root/rtl/fpga_bench.v \
  $root/rtl/sram_fpga.v $tt/chip_project.v $tt/chip_tt.v]
add_files -fileset constrs_1 $root/constraints/kv260.xdc
update_compile_order -fileset sources_1

create_bd_design kv260_bd
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
set_property -dict [list \
  CONFIG.PSU__USE__M_AXI_GP0 {1} \
  CONFIG.PSU__USE__M_AXI_GP1 {0} \
  CONFIG.PSU__USE__M_AXI_GP2 {0} \
  CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
  CONFIG.PSU__FPGA_PL0_ENABLE {1} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {60} \
] $ps

create_bd_cell -type module -reference kv260_core kv260_core_0
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
  Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
  Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave {/kv260_core_0/s_axi} \
  ddr_seg {Auto} intc_ip {New AXI SmartConnect} master_apm {0}} \
  [get_bd_intf_pins kv260_core_0/s_axi]
# the whole bench must be on pl_clk0: check what the automation connected
set clk_net [get_bd_nets -of_objects [get_bd_pins kv260_core_0/s_axi_aclk]]
if {[lsearch [get_bd_pins -of_objects $clk_net] */pl_clk0] < 0} {
  error "kv260_core's clock is not pl_clk0: [get_bd_pins -of_objects $clk_net]"
}
foreach p {uo_out uio67_out uio67_oe uio67_in ui_ext heartbeat} {
  make_bd_pins_external -name $p [get_bd_pins kv260_core_0/$p]
}
assign_bd_address
validate_bd_design
save_bd_design

puts "pl_clk0: [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ $ps] MHz (want 60)"
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces zynq_ultra_ps_e_0/Data]] {
  puts "address: $seg at [get_property OFFSET $seg], range [get_property RANGE $seg]"
}

make_wrapper -files [get_files kv260_bd.bd] -top
add_files -norecurse [glob $out/kv260_bench.gen/sources_1/bd/kv260_bd/hdl/kv260_bd_wrapper.v]
set_property top kv260_top [current_fileset]
update_compile_order -fileset sources_1

# also a .bin of the bitstream (write_bitstream -bin_file)
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed" }

open_run impl_1
report_timing_summary -file $out/timing.rpt
report_utilization -file $out/utilization.rpt
report_methodology -file $out/methodology.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
puts "worst setup slack $wns ns, worst hold slack $whs ns"

set bit [glob $out/kv260_bench.runs/impl_1/kv260_top.bit]
write_hw_platform -fixed -force -include_bit $out/kv260_bench.xsa
puts "done: $bit (and kv260_top.bin next to it), $out/kv260_bench.xsa"
