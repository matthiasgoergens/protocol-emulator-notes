# Arrival time at each uo_out pad for paths launched on the rising and on the falling clock edge,
# max and min, per output transition.  Usage: openroad -exit edges.tcl with env CORNER, LIBS, ODB, SPEF, SDC.
read_db $::env(ODB)
foreach l [split $::env(LIBS) " "] { read_liberty $l }
read_sdc $::env(SDC)
read_spef $::env(SPEF)
set_propagated_clock [all_clocks]
set out [open $::env(OUT) w]
foreach p [get_ports uo_out*] {
  set pn [get_full_name $p]
  foreach launch {rise fall} {
    foreach tr {rise fall} {
      foreach pd {max min} {
        set paths [find_timing_paths -${launch}_from [get_clocks clk] -${tr}_to $p -path_delay $pd -group_path_count 1]
        if {[llength $paths] == 0} { puts $out "$pn launch=$launch out=$tr $pd none"; continue }
        set path [lindex $paths 0]
        puts $out [format "%s launch=%s out=%s %s arrival=%.3f" $pn $launch $tr $pd [expr [$path data_arrival_time] * 1e9]]
      }
    }
  }
}
close $out
# one full path per launch edge for uo_out[0], to see what launches it
report_checks -rise_from [get_clocks clk] -to [get_ports {uo_out[0]}] -path_delay max -format full_clock_expanded
report_checks -fall_from [get_clocks clk] -to [get_ports {uo_out[0]}] -path_delay max -format full_clock_expanded
