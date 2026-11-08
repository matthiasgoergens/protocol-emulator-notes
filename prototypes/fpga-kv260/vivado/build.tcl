# SPDX-License-Identifier: Apache-2.0
# Build the KV260 test bench: project, block design, bitstream.
#
#   vivado -mode batch -source vivado/build.tcl -tclargs OUT_DIR [DEFINES...]
#
# OUT_DIR (default ../build) receives the project, timing.rpt, utilization.rpt, methodology.rpt
# and kv260_bench.xsa; the bitstream and its .bin are in OUT_DIR/kv260_bench.runs/impl_1/.
# DEFINES are Verilog defines for the sources, e.g. I2C_INTERNAL (../rtl/kv260_top.v).
#
# Run with Vivado 2026.1 on 2026-11-08 (../results/board-2026-11-08/): three changes were needed
# on the first run, each commented where it is made below. Needs the KV260 board files (Vivado:
# Tools > XHub Stores > Boards, "Kria KV260 Vision AI Starter Kit") and ../../tt/src/chip_tt.v
# (../README.md, "Running it on the board", step 1).
#
# The block design: the Zynq processor system with the board's preset (DDR, MIO), its pl_clk0 at
# 100 MHz; an MMCM (clk_wiz_0) making the 60 MHz bench clock from it; and M_AXI_HPM0_FPD (32 bits)
# through an AXI SmartConnect to kv260_core's register port, all on the MMCM's clock.
# kv260_core's pins are made external and kv260_top.v puts them on the Pmod.

set here [file dirname [file normalize [info script]]]
set root [file normalize $here/..]
set tt [file normalize $root/../../tt/src]
set out [expr {[llength $argv] ? [file normalize [lindex $argv 0]] : "$root/build"}]

if {![file exists $tt/chip_tt.v]} { error "missing $tt/chip_tt.v: see prototypes/fpga-kv260/README.md, Running it on the board, step 1" }

create_project kv260_bench $out -part xck26-sfvc784-2LV-c -force
set boards [get_board_parts -quiet -latest_file_version *kv260_som*]
if {$boards eq ""} { error "no KV260 board files: install them from XHub (Tools > XHub Stores > Boards)" }
set_property board_part [lindex $boards end] [current_project]

# First board build (2026-11-08, Vivado 2026.1): Vivado reads the sources as one compilation unit,
# so the `default_nettype none of the files read before chip_tt.v reaches it, and the generated
# ports, which have no net type, fail ([Synth 8-6735], [Synth 8-9844]). Read a copy that restores
# the default first; tt/src/chip_tt.v itself is unchanged.
set chip_v $out/chip_tt_nettype_wire.v
set fi [open $tt/chip_tt.v r]
set fo [open $chip_v w]
puts $fo "`default_nettype wire"
fcopy $fi $fo
close $fi
close $fo
add_files [list \
  $root/rtl/kv260_top.v $root/rtl/kv260_core.v $root/rtl/fpga_axil.v $root/rtl/fpga_bench.v \
  $root/rtl/sram_fpga.v $tt/chip_project.v $chip_v]
add_files -fileset constrs_1 $root/constraints/kv260.xdc
# optional Verilog defines after OUT_DIR, e.g. I2C_INTERNAL (rtl/kv260_top.v)
if {[llength $argv] > 1} {
  set_property verilog_define [lrange $argv 1 end] [current_fileset]
  puts "verilog defines: [lrange $argv 1 end]"
}
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
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] $ps

# First board build (2026-11-08): asked for 60 MHz, the PS made 58.822941 MHz (its PLL / 17),
# outside kv260_run.py's 1 %. pl_clk0 now runs at 100 MHz, the rate other Kria apps' overlays set,
# and an MMCM makes the 60 MHz bench clock. The PS's AXI port, the SmartConnect and kv260_core all
# run on the MMCM's clock, so the bench is still one clock domain; wired by hand rather than by
# the AXI automation, so that no part lands on pl_clk0.
set pl0 [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ $ps]
set wiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_0]
set_property -dict [list \
  CONFIG.PRIM_SOURCE {Global_buffer} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {60.000} \
  CONFIG.USE_LOCKED {true} \
  CONFIG.USE_RESET {true} \
  CONFIG.RESET_TYPE {ACTIVE_LOW} \
  CONFIG.RESET_PORT {resetn} \
] $wiz
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_bench]
set sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect axi_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $sc
create_bd_cell -type module -reference kv260_core kv260_core_0
connect_bd_net [get_bd_pins $ps/pl_clk0] [get_bd_pins $wiz/clk_in1]
connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins $wiz/resetn] [get_bd_pins $rst/ext_reset_in]
connect_bd_net [get_bd_pins $wiz/locked] [get_bd_pins $rst/dcm_locked]
connect_bd_net [get_bd_pins $wiz/clk_out1] [get_bd_pins $ps/maxihpm0_fpd_aclk] [get_bd_pins $sc/aclk] \
  [get_bd_pins kv260_core_0/s_axi_aclk] [get_bd_pins $rst/slowest_sync_clk]
connect_bd_net [get_bd_pins $rst/interconnect_aresetn] [get_bd_pins $sc/aresetn]
connect_bd_net [get_bd_pins $rst/peripheral_aresetn] [get_bd_pins kv260_core_0/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_FPD] [get_bd_intf_pins $sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $sc/M00_AXI] [get_bd_intf_pins kv260_core_0/s_axi]
foreach p {uo_out uio67_out uio67_oe uio67_in ui_ext heartbeat} {
  make_bd_pins_external -name $p [get_bd_pins kv260_core_0/$p]
}
assign_bd_address
validate_bd_design
save_bd_design

puts "pl_clk0: [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ $ps] MHz (want 100: the overlay sets it; the MMCM makes 60)"
puts "bench clock: [get_property CONFIG.FREQ_HZ [get_bd_pins $wiz/clk_out1]] Hz (want 60 MHz within 1 %)"
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
