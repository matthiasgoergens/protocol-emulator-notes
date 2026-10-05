# Template: liberty_file/sdc_file/corner_label/period_label are substituted
# by gen_sta_tcl.py into per-run copies of this file (OpenSTA's CLI does not
# forward extra argv to the script).
set liberty_file  {{LIBERTY_FILE}}
set sdc_file      {{SDC_FILE}}
set corner_label  {{CORNER_LABEL}}
set period_label  {{PERIOD_LABEL}}

read_liberty $liberty_file
read_verilog /var/tmp/multiphase/sta/multiphase_stage_synth.v
link_design multiphase_stage

read_sdc $sdc_file

puts "==================================================================="
puts "CORNER=$corner_label PERIOD=$period_label"
puts "==================================================================="

puts "\n--- report_checks -path_delay max (worst setup path, top 3) ---"
report_checks -path_delay max -group_count 3 -digits 4

puts "\n--- report_checks -path_delay min (worst hold path, top 3) ---"
report_checks -path_delay min -group_count 3 -digits 4

puts "\n--- worst slacks ---"
puts [format "WORST_SETUP_SLACK %.4f" [sta::worst_slack -max]]
puts [format "WORST_HOLD_SLACK %.4f" [sta::worst_slack -min]]

puts "\n--- per-lane clock-to-pin delays (clock-to-Q + XOR tree) ---"
# lane flop Q net name, phase, output port
set lanes {
    {_144 ph0 pin[0]}
    {_134 ph1 pin[0]}
    {_124 ph2 pin[0]}
    {_114 ph3 pin[0]}
    {_18  ph0 pin[1]}
    {_14  ph1 pin[1]}
    {_12  ph2 pin[1]}
    {_10  ph3 pin[1]}
}

foreach lane $lanes {
    set net [lindex $lane 0]
    set phase [lindex $lane 1]
    set port [lindex $lane 2]
    set qpins [get_pins -quiet -of_objects [get_nets $net] -filter "direction == output"]
    if {[llength $qpins] == 0} {
        puts "LANE $net ($phase -> $port): no driving pin found (net optimized away?)"
        continue
    }
    set qpin [lindex $qpins 0]
    set qpin_full [get_full_name $qpin]
    set inst [file dirname $qpin_full]
    set ckpin "$inst/CLK"
    puts "\nLANE net=$net phase=$phase port=$port inst=$inst"
    puts "  MAXRISE:"
    report_checks -from $ckpin -rise_to $port -path_delay max -digits 4 -format full_clock
    puts "  MAXFALL:"
    report_checks -from $ckpin -fall_to $port -path_delay max -digits 4 -format full_clock
    puts "  MINRISE:"
    report_checks -from $ckpin -rise_to $port -path_delay min -digits 4 -format full_clock
    puts "  MINFALL:"
    report_checks -from $ckpin -fall_to $port -path_delay min -digits 4 -format full_clock
}

exit
