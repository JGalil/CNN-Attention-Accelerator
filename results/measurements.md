# Measurements

Everything here is reproducible without a licensed tool: Icarus Verilog for
simulation, `sim/vcd_activity.py` for switching activity, yosys for area and
logic depth.

**Target: none.** These are RTL and technology-independent measurements: bit
transitions from simulation, and yosys generic-cell counts and logic depth. They
are not ASIC or FPGA power. FPGA power is in [fpga-quartus.md](fpga-quartus.md).
The 65 nm ASIC numbers describe the course RTL, not this RTL; see the README.

```sh
make -C sim compare      # activity A/B
sim/sweep.sh             # sparsity sweep
sim/sweep.sh --col       # whole-column sparsity sweep
```

Activity is bit transitions per net from the testbench VCD, restricted to nets
present in both builds being compared. That restriction matters: the two builds
do not declare the same number of intermediate wires, and without it the build
with more named nets looks busier for free.

**What activity counting cannot show.** It is an RTL metric. There is no clock
tree, so the clock-gating saving does not appear; and a combinational operator
such as `dividend / divisor` is a single unnamed net, so the switching inside a
large combinational block is invisible while an equivalent sequential block's
state is counted in full. Where that distinction decides the answer, area and
logic depth from yosys are used instead.

---

## 1. Verification

| test | scope | result |
|---|---|---|
| `make -C sim sim` | full chip, optimised | 16/16 result vectors match |
| `make -C sim baseline` | full chip, pre-optimisation | 16/16 match |
| `tb/tb_seq_div.v` | divider | 0 errors / 500 random + saturation, divide-by-zero, gated lane |
| `tb/tb_mac_pl.v` | pipelined MAC | 0 errors / 600 random × 3 depths, gated and reset-while-idle |
| `tb/tb_cdc.v` | async FIFO | 0 errors / 12,000 words across 6 clock ratios + 3 staggered-reset cases |

## 2. Clock gating opportunity

The gating is now a register enable rather than a hand-built gated clock, so the
measurable quantity is the enable's duty cycle. Measured with
`vcd_activity.py --duty .col_en`:

| | |
|---|---|
| `col_en` asserted | 12.8% |
| **`col_en` low — the clock-gating ratio** | **87.2%** |

Uniform across all 16 MAC columns. This is the number to hand a vectorless power
estimate, and it is the field Innovus reports as `Default icg ratio: N.A.` when
left unset:

```tcl
set_default_switching_activity -input_activity 0.2 -clock_gating_ratio 0.872
```

On the ASIC this is 2176 flops (136 per column × 8 columns × 2 cores) whose
clock is suppressed 87% of the time, plus the clock-tree capacitance feeding
them. None of that is visible at RTL.

## 3. Current design vs. the pre-work design

First commit vs. HEAD, same stimulus, shared nets only:

| scope | before | after | change |
|---|---:|---:|---|
| MAC array (core 1) | 55,618 | 47,607 | **−14.4%** |
| whole chip | 297,509 | 289,719 | **−2.6%** |
| SFP (core 1) | 14,896 | 16,317 | +9.5% |

The SFP figure is the artifact described above, not a regression. The original
`mc_div` computed a full combinational divide and sampled it after a counter
delay; at RTL that whole divider is one net. `seq_div` holds its remainder and
quotient in named registers across four cycles, so its work is counted and the
combinational version's is not. Area and depth settle it:

| | cells | logic depth | flops |
|---|---:|---:|---:|
| `mc_div` (combinational divide + counter) | 1,650 | 490 | 26 |
| `seq_div` (restoring, 2 bits/cycle) | **553** | **109** | 69 |

**3.0× fewer cells and 4.5× shorter logic depth.** There are 16 instances
(8 lanes × 2 cores), so 26,400 cells become 8,848 — about **17,550 cells
removed** — and the divider no longer sits in the critical path. Latency is
unchanged at the 5-cycle cadence the previous implementation reported, and
`seq_div` is exact against Verilog's `/`, saturating above 2^qw−1.

## 4. Memory inference

`sram_w16` with an asynchronous reset on the storage array cannot infer RAM.
yosys, 160-bit instance:

| | cells | inferred memories | flop banks |
|---|---:|---:|---:|
| before (async reset on the array) | 57 | 0 | 16 × 160 bit |
| after (no reset on the array) | **9** | **1** | 1 × 160 bit (output register only) |

Before, the array became 16 × 160 flops plus 15 comparators and a 16-way mux.
Across the design — 2 cores × (2 × 64-bit Q/K + 1 × 160-bit psum) — this is
**9,216 flops replaced by 6 memories and 576 flops**. This is the largest single
area change in the set.

## 5. Weight sparsity sweep

Each row regenerates stimulus at that sparsity and re-verifies both builds; every
point passes 16/16.

### Element-level sparsity — individual weights zeroed

| sparsity | chip before | chip after | ratio | array before | array after | ratio |
|---:|---:|---:|---:|---:|---:|---:|
| 0.0 | 300,326 | 298,604 | 0.994 | 34,632 | 33,770 | 0.975 |
| 0.2 | 297,938 | 296,314 | 0.995 | 32,996 | 32,192 | 0.976 |
| 0.4 | 293,696 | 292,242 | 0.995 | 31,824 | 30,946 | 0.972 |
| 0.6 | 268,715 | 267,679 | 0.996 | 28,622 | 27,934 | 0.976 |
| 0.8 | 229,117 | 227,263 | 0.992 | 24,088 | 22,897 | 0.951 |
| 0.9 | 196,002 | 193,504 | 0.987 | 18,640 | 17,104 | **0.918** |

### Whole-column sparsity — entire weight vectors zeroed

| sparsity | chip before | chip after | ratio | array before | array after | ratio |
|---:|---:|---:|---:|---:|---:|---:|
| 0.0 | 300,326 | 298,604 | 0.994 | 34,632 | 33,770 | 0.975 |
| 0.2 | 267,166 | 264,164 | 0.989 | 29,726 | 28,404 | 0.956 |
| 0.4 | 251,507 | 247,855 | 0.986 | 30,124 | 28,267 | 0.938 |
| 0.6 | 205,257 | 200,739 | 0.978 | 26,726 | 24,389 | 0.913 |
| 0.8 | 192,230 | 187,512 | 0.976 | 24,232 | 21,876 | 0.903 |
| 0.9 | 176,003 | 171,647 | 0.975 | 21,384 | 19,155 | **0.896** |

The benefit tracks sparsity, and whole-column sparsity is worth roughly twice as
much as the same fraction spread over individual weights — the column bypass
suppresses a column's entire product, where element sparsity only reaches the
lanes that happen to be zero. Absolute activity falls with sparsity in both
builds because zeros propagate regardless of any optimisation; the ratio column
is the part attributable to the gating.

This is the plot that answers whether the gating pays for its area, and it needs
no licence. It understates the benefit for the reason in §2: the clock saving is
the larger prize and is not visible here.

## 6. SFP skip path

Threshold now a runtime input (`skip_thresh`), driven at 660 to match the
testbench's reference model. On the reference workload it fires on 4 of 8 rows:

| row | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| skipped | · | · | yes | yes | · | yes | · | yes |
| cycles | 7 | 8 | 3 | 3 | 8 | 3 | 8 | 3 |

A skipped row costs 3 cycles against 7–8 for a computed one, so the skip saves
about 5 cycles and one division per row it fires on. The same rows are skipped as
in the original design.

## 7. Measured post-fit — see [fpga-quartus.md](fpga-quartus.md)

Power and Fmax are now measured on Cyclone IV GX. The headline is that **the
MAC-column gating does not pay on FPGA**: +6.1% logic, −9.3% Fmax, and +1.2% to
+3.1% core dynamic power against the pre-optimisation build. Causes and the
confidence caveat are in that file.

The activity figures in this document are unaffected and stand. What changed is
the interpretation of §2: the 87.2% enable duty is real, but on an FPGA the
clock network is powered regardless, and the registers it gates were already
conditionally written, so it converts to no saving on this target. It remains
the right structure for an ASIC, which is untested.

## 8. Still not measured

- **ASIC power.** `syn/run_power_saif.tcl` and `syn/clock_gating_setup.tcl` are
  ready; needs a PDK and Design Compiler.
- **Combinational activity.** 99.2% of combinational nodes are estimated
  vectorlessly from an RTL VCD, so the operand isolation's savings are not
  observed. A post-fit gate-level sim in Questa would fix this and is the
  outstanding question.
- **Glitch power.** RTL simulation has no delays, so glitches are absent. A
  gate-level VCD would include them, and would also make the combinational
  divider's real cost visible.
