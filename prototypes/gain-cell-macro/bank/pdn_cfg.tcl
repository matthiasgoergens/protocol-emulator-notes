# Power grid of the bank: LibreLane's own pdn_cfg.tcl for PDN_MULTILAYER = false (Metal1 rails
# and Metal4 vertical straps, pins on Metal4), without its default macro grid.
#
# with a macro grid of its own for the array. LibreLane's default macro grid joins a macro's
# Metal4 power pins to horizontal straps on PDN_HORIZONTAL_LAYER (TopMetal1), and a Tiny
# Tapeout tile may not use TopMetal1 (RT_MAX_LAYER Metal4). The array instead has its GND pins
# on two Metal3 bars along its bottom and top edges and no Metal4 except over its internal GND
# stripes, so the core's vertical Metal4 straps cross it; the grid below drops Via3 where a VGND
# strap crosses a bar. config.json sets the strap pitch and offset so no strap lands on an
# internal stripe.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

set_voltage_domain -name CORE -power $::env(VDD_NET) -ground $::env(GND_NET)

define_pdn_grid -name stdcell_grid -starts_with POWER -voltage_domain CORE \
    -pins "$::env(PDN_VERTICAL_LAYER)"

add_pdn_stripe -grid stdcell_grid -layer $::env(PDN_VERTICAL_LAYER) \
    -width $::env(PDN_VWIDTH) -pitch $::env(PDN_VPITCH) -offset $::env(PDN_VOFFSET) \
    -spacing $::env(PDN_VSPACING) -starts_with POWER -extend_to_core_ring

add_pdn_stripe -grid stdcell_grid -layer $::env(PDN_RAIL_LAYER) \
    -width $::env(PDN_RAIL_WIDTH) -followpins

add_pdn_connect -grid stdcell_grid -layers "$::env(PDN_RAIL_LAYER) $::env(PDN_VERTICAL_LAYER)"

define_pdn_grid -macro -instances array_i -name array_grid -starts_with POWER -halo "0 0"
add_pdn_connect -grid array_grid -layers "Metal3 $::env(PDN_VERTICAL_LAYER)"
