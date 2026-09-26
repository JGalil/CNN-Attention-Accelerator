#
#Load design
set desdir 		"$::env(DESIGN_DATA)"
set libdir 		"$::env(PDK_ROOT)"
set design 		"fullchip"
set netlist 		"./netlist/$design.out.v"
set sdc 		"./constraints/$design.sdc"
set best_timing_lib 	"$libdir/lib/$::env(STDCELL_LIB_BC).lib"
set worst_timing_lib 	"$libdir/lib/$::env(STDCELL_LIB_WC).lib"
set lef 		"$libdir/lef/$::env(STDCELL_LEF).lef"
set best_captbl 	"$libdir/captbl/$::env(CAPTBL_BEST)"
set worst_captbl 	"$libdir/captbl/$::env(CAPTBL_WORST)"

# default settings
set init_pwr_net "VDD"
set init_gnd_net "VSS"

# default settings
set init_verilog "$netlist"
set init_design_netlisttype "Verilog"
set init_design_settop 1
set init_top_cell "$design"
set init_lef_file "$lef ./subckt/sram_w16.lef"

# MCMM setup
create_library_set -name WC_LIB -timing "$worst_timing_lib ./subckt/sram_w16_WC.lib"
create_library_set -name BC_LIB -timing "$best_timing_lib ./subckt/sram_w16_BC.lib"
create_rc_corner -name Cmax -cap_table $worst_captbl -T 125
create_rc_corner -name Cmin -cap_table $best_captbl -T -40
create_delay_corner -name WC -library_set WC_LIB -rc_corner Cmax
create_delay_corner -name BC -library_set BC_LIB -rc_corner Cmin
create_constraint_mode -name CON -sdc_file [list $sdc]
create_analysis_view -name WC_VIEW -delay_corner WC -constraint_mode CON
create_analysis_view -name BC_VIEW -delay_corner BC -constraint_mode CON
init_design -setup {WC_VIEW} -hold {BC_VIEW}

set_interactive_constraint_modes {CON}
setDesignMode -process 65

