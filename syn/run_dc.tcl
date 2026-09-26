set top_module fullchip
set rtlPath "../rtl"

# Target library
# ---------------------------------------------------------------------------
# Technology setup.  The standard-cell library is vendor IP and is NOT part of
# this repository.  Point PDK_ROOT at your own installation and set
# STDCELL_DB to the worst-case .db you are licensed to use.
#   export PDK_ROOT=/path/to/pdk
#   export STDCELL_DB=$PDK_ROOT/db/<your_worst_case_lib>.db
# ---------------------------------------------------------------------------
if {![info exists ::env(STDCELL_DB)]} {
    error "STDCELL_DB is not set - see README.md (Prerequisites)."
}
set target_library $::env(STDCELL_DB)

set link_library $target_library
set symbol_library {}
set wire_load_mode enclosed
set timing_use_enhanced_capacitance_modeling true

set search_path [concat $rtlPath $search_path]
set link_library [concat * $link_library ]

set synthetic_library {}
set link_path [concat  $link_library $synthetic_library]
set dont_use_cells 1
set dont_use_cell_list ""

remove_design -all
if {[file exists template]} {
	exec rm -rf template
}
exec mkdir template
if {![file exists log]} {
    exec mkdir log
}
if {![file exists gate]} {
	exec mkdir gate
}

sh date
sh echo hostname
sh echo uptime

#Compiler directives
set compile_effort   "high"
set compile_no_new_cells_at_top_level false
set hdlin_enable_vpp true
set hdlin_auto_save_templates false

define_design_lib WORK -path .template
set verilogout_single_bit false

# read RTL, from the single file list shared with the simulation and FPGA flows
set flist "${rtlPath}/filelist.txt"
if {![file exists $flist]} { error "missing $flist" }
set fh [open $flist r]
set rtl_files {}
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    lappend rtl_files $line
}
close $fh
foreach f $rtl_files {
    analyze -format verilog -lib WORK $f
}
echo "analyzed [llength $rtl_files] RTL files"




elaborate $top_module -lib WORK -update
current_design $top_module

# Link Design
link

# Default SDC Constraints
read_sdc "./constraints/${top_module}.sdc"
propagate_constraints

current_design $top_module

set_cost_priority {max_transition max_fanout max_delay max_capacitance}
set_fix_multiple_port_nets -all -buffer_constants
set_fix_hold [all_clocks]

set_driving_cell -lib_cell BUFFD8 -pin Z [all_inputs]
set_load [get_attribute "$target_library/BUFFD8/A" fanout_load] [all_outputs]
#foreach_in_collection p [all_outputs] {
#	set_load 0.050 $p
#}

#More compiler directives
set compile_effort   "low"
set_app_var ungroup_keep_original_design true
set_register_merging [get_designs $top_module] false
set compile_seqmap_propagate_constants false
set compile_seqmap_propagate_high_effort false
# More constraints and setup before compile
foreach_in_collection design [ get_designs "*" ] {
	current_design $design
	#feedthrough / outputs / constants
	set_fix_multiple_port_nets -all
}
current_design $top_module


# Compile
# Source user compile options
compile_ultra -no_autoungroup -timing_high_effort_script -exact_map

# Write Out Design - Hierarchical
current_design $top_module

change_names -rules verilog -hierarchy

write -format verilog -hier -output [format "%s%s" $top_module .out.v]

# Write Reports
redirect [format "%s%s" log/ $top_module _area.rep] { report_area }
redirect -append [format "%s%s%s" log/ $top_module _area.rep] { report_reference }
redirect [format "%s%s%s" log/ $top_module _power.rep] { report_power }
redirect [format "%s%s%s" log/ $top_module _timing.rep] \
  { report_timing -path full -max_paths 100 -nets -transition_time -capacitance -significant_digits 3 -nosplit}

set inFile  [open log/$top_module\_area.rep]
while { [gets $inFile line]>=0 } {
    if { [regexp {Total cell area:} $line] } {
        set AREA [lindex $line 3]
    }
}
close $inFile
set inFile  [open log/$top_module\_power.rep]
while { [gets $inFile line]>=0 } {
    if { [regexp {Total Dynamic Power} $line] } {
        set PWR [lindex $line 4]
    } elseif { [regexp {Cell Leakage Power} $line] } {  
        set LEAK [lindex $line 4] 
    }
}
close $inFile

# Fail on unmapped logic anywhere in the hierarchy, not just at the top. The
# previous form passed $top_module, so a black-boxed sub-block was never
# reported: sfp_row and async_gray_fifo were unresolved in the step5/step6 runs
# and their power reports were meaningless as a result.
set unmapped_designs [get_designs -quiet -filter "is_unmapped == true"]
if { [sizeof_collection $unmapped_designs] != 0 } {
	echo "****************************************************"
	echo "* ERROR: compile finished with unmapped logic:      *"
	foreach_in_collection d $unmapped_designs { echo "*   [get_object_name $d]" }
	echo "****************************************************"
	exit 1
}

# A tri net almost always means an unresolved reference; the power engine then
# applies its X-transition factor to everything the missing block drives.
set tri_nets [get_nets -quiet -hierarchical -filter "net_type == tri"]
if { [sizeof_collection $tri_nets] != 0 } {
	echo "ERROR: [sizeof_collection $tri_nets] tri nets -- unresolved reference."
	exit 1
}
# Done
sh date
sh uptime

# Done
echo "run.scr completed successfully"

