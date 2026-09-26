# Producing activity data for power analysis

The testbench already writes a full VCD (`$dumpvars(0, fullchip_tb)`), so the
raw activity has always been available — it was simply never fed back into
`report_power`. Two routes, depending on which tool you want to do the power
integration.

## Route A — SAIF into Design Compiler (fastest, what `run_power_saif.tcl` expects)

Add to `tb/fullchip_tb.v`, inside the existing stimulus `initial` block:

```verilog
initial begin
  // RTL-level toggle monitoring. For a gate-level netlist sim use
  // $set_gate_level_monitoring("on") instead, so glitches are counted.
  $set_gate_level_monitoring("rtl_on");
  $set_toggle_region(fullchip_tb.full_chip_instance);

  // Skip reset and the SRAM preload phase. Including them pollutes the
  // average with a burst of writes that the real workload does once.
  wait (reset == 0);
  repeat (200) @(posedge clk);

  $toggle_start();
  wait (done_condition);          // end of the last streamed Q vector
  $toggle_stop();

  $toggle_report("../sim/fullchip.saif", 1.0e-9, fullchip_tb.full_chip_instance);
end
```

Then:

```sh
xrun -f filelist +access+r          # produces fullchip.saif
cd ../syn && dc_shell-xg-t -f run_power_saif.tcl
```

Check `log/fullchip_saif.rep` first. If register/net annotation is not close to
100%, the unannotated remainder is still being estimated and any "savings" you
read off are diluted by that fraction.

## Route B — VCD into Innovus (post-route, includes the real clock tree)

This is the number worth quoting, because the clock tree is the thing clock
gating actually shuts off, and it does not exist until after CTS.

```tcl
# after route, in place of the bare report_power in reportDesign.tcl
read_activity_file -format VCD ../sim/fullchip_tb.vcd \
    -scope fullchip_tb/full_chip_instance \
    -start 200ns -end 5000ns -block $design

set_power_analysis_mode -method dynamic_vectorbased -disable_static false
report_power -hierarchy all -outfile ${design}.vcd.power.rpt
```

The existing flow instead uses the default:

```tcl
set_power_analysis_mode ... -method static ...
```

and its report header records exactly what that costs:

```
*   User-Defined Activity : N.A.
*   Activity File: N.A.
*   Sequential Element Activity: 0.200000
*   Primary Input Activity: 0.200000
*   Default icg ratio: N.A.
*   Global Comb ClockGate Ratio: N.A.
```

Every flop is assumed to toggle 20% of the time whether or not its clock is
gated off, and `Default icg ratio: N.A.` means no clock-gating credit is applied
at all.

## Route C — if you must stay vectorless

At minimum tell the engine how often the gaters are actually off. This is a
stated assumption rather than a measurement, so label it as such in any writeup:

```tcl
set_default_switching_activity -input_activity 0.2 -clock_gating_ratio 0.8
```

`-clock_gating_ratio 0.8` is the knob that fills in the `Default icg ratio`
field above. It only works on gaters the tool recognises as gaters, which is
another reason to let `-gate_clock` infer ICG cells rather than hand-rolling
a latch and an AND.
