# Four-phase clock SDC, core period = 15.0 ns (66.6667 MHz)
# ph0 is the reference; ph1/ph2/ph3 are related (not asynchronous) clocks
# generated from the same source, shifted by a quarter, half and
# three-quarter period. Ideal clocks (no CTS).
create_clock -name ph0 -period 15.0 -waveform {0 7.500000} [get_ports ph0]
create_clock -name ph1 -period 15.0 -waveform {3.750000 11.250000} [get_ports ph1]
create_clock -name ph2 -period 15.0 -waveform {7.500000 15.000000} [get_ports ph2]
create_clock -name ph3 -period 15.0 -waveform {11.250000 18.750000} [get_ports ph3]

set_clock_uncertainty 0.0 [get_clocks {ph0 ph1 ph2 ph3}]

# sub/oe come from an upstream register clocked by ph0
set_input_delay -clock ph0 1.0 [get_ports sub*]
set_input_delay -clock ph0 1.0 [get_ports oe*]
set_input_delay -clock ph0 1.0 [get_ports pads*]
set_input_delay -clock ph0 1.0 [get_ports clear]

# pin drives an external pad; pads are a separate small load
set_output_delay -clock ph0 0.0 [get_ports pin*]
set_output_delay -clock ph0 0.0 [get_ports pin_oe*]
set_output_delay -clock ph0 0.0 [get_ports samples*]

set_load 0.005 [get_ports pin*]
set_load 0.005 [get_ports pin_oe*]
set_load 0.002 [get_ports samples*]

set_input_transition 0.05 [get_ports ph0]
set_input_transition 0.05 [get_ports ph1]
set_input_transition 0.05 [get_ports ph2]
set_input_transition 0.05 [get_ports ph3]
set_input_transition 0.1 [get_ports sub*]
set_input_transition 0.1 [get_ports oe*]
set_input_transition 0.1 [get_ports pads*]
set_input_transition 0.1 [get_ports clear]
