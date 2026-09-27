# Post-fit FPGA results

Quartus Prime Lite 25.1std, Cyclone IV GX `EP4CGX150DF31I7AD`, Slow 1200 mV /
100 °C model. Device chosen to match the ECE 284 reports so the two are
comparable.

```sh
make -C sim vcd
fpga/run_quartus.sh all                 # optimised
VARIANT=baseline fpga/run_quartus.sh all  # pre-optimisation mac_col/mac_8in
```

---

## 1. Headline: the optimisation does not pay on FPGA

Both builds verify 16/16 and differ only in `mac_col`/`mac_8in`.

| | baseline | optimised | change |
|---|---:|---:|---|
| Logic elements | 16,500 (11%) | 17,505 (12%) | **+6.1%** |
| Registers | 9,602 | 9,634 | +0.3% |
| Block memory bits | 9,216 | 9,216 | — |
| Fmax, `clk` | 74.38 MHz | 67.44 MHz | **−9.3%** |
| Fmax, `clk2` | 72.76 MHz | 65.48 MHz | −10.0% |
| Core dynamic, dense stimulus | 172.14 mW | 174.16 mW | **+1.2%** |
| Core dynamic, 80% column sparsity | 136.85 mW | 141.15 mW | **+3.1%** |
| MAC array dynamic, 80% sparsity | 8.90 mW | 10.60 mW | **+19%** |

More area, slower, and more power — and the power gap *widens* with sparsity
rather than closing. The regression localises to the MAC array, which is where
the changes are.

## 2. Why

Three causes, two of them real and one a measurement limit.

**The registers were already enable-gated.** `col_en` was added on the
assumption that it would stop the column's registers toggling when idle. They
already held: the original `if (inst_q[0]) ... else if (inst_q[1])` structure
writes `query_q`/`key_q` conditionally, so synthesis had always inferred
enable flops. The RTL activity measurement said so and it was read too
narrowly at the time — `query_q` and `key_q` toggle 713 and 111 times in *both*
builds. `col_en` therefore adds an `is_idle` comparator and its enable fanout
while removing no register activity.

**On FPGA there is no clock-tree prize.** The justification for accepting that
overhead was the clock: 87.2% of cycles with the enable low, across 2,176 flops.
On an ASIC that converts to a real saving through an integrated clock-gating
cell and the clock tree it shuts off. On a Cyclone IV the global clock network
is pre-fabricated and powered whether or not any register uses its `ena` input,
so a register clock-enable saves only the register's own toggling — which, per
the point above, was already zero when idle. The 87.2% figure is real and buys
nothing here.

**The isolation savings are not observed.** 99.2% of combinational nodes take
their toggle rate from vectorless estimation, because an RTL VCD matches
register names but not the LUT nodes synthesis creates. The operand-isolation
muxes and column bypass act on combinational activity, so their cost is charged
in full and their benefit is estimated away. This one is a measurement limit,
not a design fault, and it is the open question below.

The Fmax loss is straightforward: the isolation mux and the psum zero-force sit
in the MAC path.

## 3. Comparison with ECE 284

Same device, same corner.

| | ECE 284 Alpha 1 | this design |
|---|---:|---:|
| Logic elements | 30,889 (21%) | 17,505 (12%) |
| Registers | 15,802 | 9,634 |
| Block memory bits | **0** | **9,216** |
| Real pins | 458 | **3** |
| Fmax | 93.46 MHz | 67.44 MHz |
| Worst setup slack | −9.700 ns | −5.271 ns |
| **Core dynamic power** | **0.00 mW** | **174.16 mW** |
| I/O power | 173.01 mW | 10.94 mW |

Two differences in method matter more than the numbers:

- **ECE 284 reported 0.00 mW of core dynamic power.** Its Power Analyzer had no
  activity data for the core. The figure its report labels "Dynamic Power —
  173 mW" is the I/O line, pad power across 458 real pins, and the derived
  138 GOPS/W divides throughput by pad power. Using virtual pins here drops I/O
  to 10.94 mW and leaves a core number that means something.
- **Neither design meets timing.** −9.700 ns there, −5.271 ns here. Both
  quoted Fmax figures describe designs that fail setup at their constraint.

## 4. Confidence

Quartus rates both runs **"Low: user provided insufficient toggle rate data."**

| node type | from simulation | vectorless |
|---|---:|---:|
| Registered | **96.1%** | 3.9% |
| Combinational | **0.8%** | **99.2%** |
| Overall | 26.7% | 73.3% |

Registers are well annotated; combinational logic is not. The comparison between
the two builds is run under identical methodology, so the *relative* numbers are
meaningful. The absolute figures are not, and should not be quoted as measured
power.

**What would settle it:** a post-fit gate-level simulation in the bundled Questa,
producing a VCD whose node names match the fitted netlist. That would annotate
the combinational nodes the isolation logic acts on, and is the only way to test
whether the isolation pays once its savings are visible. Until then the fair
statement is that the optimisation costs area and frequency, and no power
benefit has been demonstrated on this target.

## 5. Two traps worth knowing

**The Power Analyzer needs the Assembler.** `quartus_pow` fails with
`Error (215039)` unless `quartus_asm` has run, even when no programming file is
wanted. It is in `run_quartus.sh`.

**A VCD carries its own timebase, and the analyser believes it.** The testbench
used `` `timescale 1ns/1ps `` with `#0.5` half-cycle delays, giving a 1 ns period.
Quartus read 919.89 MHz out of the VCD and scaled dynamic power to it, reporting
**1741.59 mW**. Changing the testbench to `` `timescale 10ns/1ps `` makes those
delays 5 ns and the period the 10 ns the design is constrained at; power fell to
174.16 mW, almost exactly the frequency ratio. Nothing errors when this is wrong
— the number is simply scaled.

## 6. What this does not say

This is an FPGA result. The ASIC case rests on clock-tree power and an
integrated clock-gating cell on 2,176 flops, neither of which exists on a
Cyclone IV, and it remains untested — `syn/run_power_saif.tcl` and
`syn/clock_gating_setup.tcl` are in place for a PDK run.

It also does not overturn the RTL activity measurements in
[measurements.md](measurements.md), which stand: the gating does suppress
toggling, and the divider and memory changes are unambiguous wins here too
(9,216 block memory bits against ECE 284's zero, at 43% fewer registers). What
it overturns is the assumption that the MAC-column gating would convert that
into lower power on this target.
