#-----------------------------------------------------------------------------
# run_power_saif.tcl -- activity-annotated power analysis
#
# WHY THIS EXISTS
#   run_dc.tcl ends with a bare `report_power`.  With no annotated switching
#   activity, DC falls back to a vectorless estimate: it assumes a default
#   toggle probability on every primary input and every sequential cell output
#   and propagates that statistically ("PWR-6: Propagating switching activity
#   (low effort zero delay simulation)", followed by PWR-414/PWR-415).
#
#   That estimate cannot see data-dependent power savings.  Clock gating,
#   operand isolation and the SFP skip path all work by making *specific*
#   nets stop toggling under *specific* data conditions.  A vectorless engine
#   assumes the gating condition is a coin flip, so it charges you for every
#   comparator and every gater it added and credits you with nothing.  The
#   result is that a correctly gated design reports *more* power than the
#   ungated one.
#
#   This script annotates real activity from a simulation SAIF before calling
#   report_power, which is the only way to observe the savings.
#
# USAGE
#   1. Generate a SAIF from the RTL or gate-level sim: build the testbench with
#      -DSAIF_DUMP under a simulator implementing $toggle_* (see sim/gen_saif.md).
#   2. dc_shell-xg-t -f run_power_saif.tcl | tee log/power_saif.log
#-----------------------------------------------------------------------------

set top_module fullchip
set saif_file  "../sim/build_gated/fullchip.saif"
# Instance path of the DUT inside the testbench, as it appears in the SAIF.
set dut_inst   "fullchip_tb/fullchip_instance"

if {![info exists ::env(STDCELL_DB)]} {
    error "STDCELL_DB is not set - see README.md (Prerequisites)."
}
set target_library $::env(STDCELL_DB)
set link_library [concat * $target_library]

#-----------------------------------------------------------------------------
# Read the mapped netlist produced by run_dc.tcl
#-----------------------------------------------------------------------------
read_file -format verilog ${top_module}.out.v
current_design $top_module
link

# Fail loudly if anything is a black box.  A black box has unresolved outputs,
# so DC applies its default X-transition factor to every net the block drives.
# On this design that is 320 bits of sfp_out plus the two 24-bit inter-core sum
# buses -- enough unannotated high-fanout switching to dominate the report and
# make the numbers meaningless.  The check in run_dc.tcl only inspects
# $top_module, so it stays silent while sub-blocks are unmapped.
set bad [get_designs -quiet -filter "is_unmapped == true"]
if {[sizeof_collection $bad] != 0} {
    echo "ERROR: unmapped designs present -- power numbers will be invalid:"
    foreach_in_collection d $bad { echo "   [get_object_name $d]" }
    error "Resolve black boxes before running power analysis."
}
set tris [get_nets -quiet -hierarchical -filter "net_type == tri"]
if {[sizeof_collection $tris] != 0} {
    echo "WARNING: [sizeof_collection $tris] tri nets -- usually a symptom of an\
          unresolved reference. Expect inflated switching power."
}

read_sdc "./constraints/${top_module}.sdc"

#-----------------------------------------------------------------------------
# Annotate activity
#-----------------------------------------------------------------------------
if {![file exists $saif_file]} {
    error "SAIF not found: $saif_file  (run the sim first)"
}

reset_switching_activity
read_saif -input $saif_file -instance_name $dut_inst -auto_map_names -verbose

# report_saif tells you what fraction of the design actually got annotated.
# Anything less than ~100% on registers and nets means the remainder is still
# being estimated, and the "measured" savings are diluted by that fraction.
redirect log/${top_module}_saif.rep {
    report_saif -hier -missing -flat
}

#-----------------------------------------------------------------------------
# Power
#-----------------------------------------------------------------------------
set power_enable_analysis true
set power_analysis_mode time_based

redirect log/${top_module}_power_saif.rep {
    report_power -analysis_effort high -verbose
}
redirect log/${top_module}_power_hier.rep {
    report_power -hierarchy -levels 3 -analysis_effort high
}

# Where the clock-gating credit shows up, if the gaters are ones DC recognises.
redirect log/${top_module}_clock_gating.rep {
    report_clock_gating -verbose
    report_clock_gating -gating_elements
}

# If a SAIF is unavailable, this is the fallback. 0.872 is measured, not
# assumed: it is the mean fraction of cycles the mac_col register enables are
# low on the reference workload (sim/vcd_activity.py --duty .col_en). It is the
# field Innovus reports as "Default icg ratio: N.A." when left unset.
#   set_default_switching_activity -input_activity 0.2 -clock_gating_ratio 0.872

echo "run_power_saif.tcl completed"
exit
