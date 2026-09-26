#-----------------------------------------------------------------------------
# clock_gating_setup.tcl -- tool-inferred integrated clock gating
#
# Source this immediately before `compile_ultra` in run_dc.tcl, and add
# -gate_clock to the compile_ultra line:
#
#     source ./clock_gating_setup.tcl
#     compile_ultra -gate_clock -no_autoungroup -timing_high_effort_script -exact_map
#
# WHY NOT HAND-ROLL IT
#   rtl/mac_col.v builds its gater in RTL:
#
#       always @(*) if (!clk) clk_en_latch = clk_en;
#       wire g_clk = clk & clk_en_latch;
#
#   That is functionally the right structure -- latch the enable on the low
#   phase, AND it with the clock -- but synthesis maps it to a general-purpose
#   data latch plus a general-purpose AND (LNQD1 + CKAN2D1 on this library),
#   not to the library's integrated clock-gating cell.  Consequences:
#
#     * report_power applies no clock-gating credit, because nothing in the
#       netlist is tagged as a clock gate.
#     * report_clock_gating shows nothing.
#     * No clock-gating setup/hold checks are generated on the enable, so a
#       late enable that glitches the gated clock is never flagged.
#     * CTS does not recognise g_clk as a clock-tree element.  Unless you also
#       declare `create_generated_clock` on the AND output, the downstream
#       clock is not a clock at all to the tools -- it is a high-fanout
#       combinational net, and its switching power is charged in full.
#
#   The enables this design needs are *already* in the RTL.  Every
#   `if (inst_q[0])` / default-assignment (`cnt_q <= cnt_q;`) in mac_col.v
#   makes DC infer an enable flop -- 132 EDFCNQD1 per column in both the gated
#   and ungated builds.  -gate_clock takes those existing per-flop enables and
#   factors them into one integrated clock gater per register bank, which is
#   strictly better: one gated clock pin instead of 132 enable muxes.
#
#   So the right move is to delete the hand-rolled gater from mac_col.v and let
#   the tool do it from the enable conditions already present.
#-----------------------------------------------------------------------------

# Latch-based, positive-edge integrated cell.  `integrated` is what makes DC
# pick the library's ICG macro rather than assembling a latch + AND.
set_clock_gating_style \
    -sequential_cell latch \
    -positive_edge_logic {integrated} \
    -negative_edge_logic {integrated} \
    -control_point before \
    -control_signal scan_enable \
    -minimum_bitwidth 4 \
    -max_fanout 32

# Observability/controllability for DFT.  Without a test-enable path an ICG
# holds the clock off in scan shift and the bank becomes untestable.
set_clock_gating_registers -include_instances [all_registers]

# Banks smaller than -minimum_bitwidth are left as enable flops; that is the
# correct trade, since an ICG's own power is not amortised over 1-3 flops.
