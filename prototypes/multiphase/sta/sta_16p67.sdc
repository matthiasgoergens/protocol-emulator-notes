# Four-phase clock SDC, core period = 16.67 ns (59.9880 MHz)
# ph0 is the reference; ph1/ph2/ph3 are related (not asynchronous) clocks
# generated from the same source, shifted by a quarter, half and
# three-quarter period. Ideal clocks (no CTS).
create_clock -name ph0 -period 16.67 -waveform {0 8.335000} [get_ports ph0]
create_clock -name ph1 -period 16.67 -waveform {4.167500 12.502500} [get_ports ph1]
create_clock -name ph2 -period 16.67 -waveform {8.335000 16.670000} [get_ports ph2]
create_clock -name ph3 -period 16.67 -waveform {12.502500 20.837500} [get_ports ph3]

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
