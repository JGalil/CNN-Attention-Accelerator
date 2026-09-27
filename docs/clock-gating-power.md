# Why the clock-gated build reported more power, and how to measure it properly

This is the post-mortem on the `step5_clock_gating` / `step6` power numbers from
the original project, and the reason the same thing happens to a systolic array
when you add zero-detect comparators and watch the power go *up*.

Short version: the gating works — the MAC column enables are low **87% of the
time** on the real workload. The reported power increase was an artifact of two
separate problems, one a broken synthesis run and one a fundamental limit of
vectorless power estimation. Neither had anything to do with the comparators.

Sections 1–4 are the post-mortem and describe the code as it was. Section 5
onwards has been superseded by the rework; current numbers are in
[../results/measurements.md](../results/measurements.md) and what changed is in
[extensions.md](extensions.md). The analysis is kept because the failure mode
generalises.

---

## 1. What the original reports actually said

| build | config | dynamic | internal | switching | leakage |
|---|---|---:|---:|---:|---:|
| `step4` (no gating) | 1 core | 6.06 mW | 5.94 mW (98%) | 0.12 mW (2%) | 1.10 mW |
| `step5` (gating + isolation) | 2 cores | **80.03 mW** | 10.34 mW (13%) | **69.69 mW (87%)** | 1.80 mW |

A 13× increase, and the internal/switching split inverts. That inversion is the
tell: adding an AND gate and two comparators cannot move 85 percentage points of
power from internal to net switching. Something structural changed.

## 2. The step5 netlist was not a working netlist

Three checks on `step5_clock_gating/syn/fullchip.out.v`:

```
grep -c "^module sfp_row"        -> 0     (but sfp_row IS instantiated)
grep -c "^module async_gray_fifo"-> 0     (but it IS instantiated)
grep -c "^  tri "                -> 134
```

Against `step4`, which is clean: `sfp_row` defined, **0** `tri` nets.

`sfp_row` and `async_gray_fifo` were unresolved **black boxes**. The power report
header confirms it — step5 carries a warning step4 does not:

```
Warning: Design has unannotated black box outputs. (PWR-428)
```

An unresolved reference leaves every net it drives without a known driver, so
those nets become `tri` and the power engine falls back to its X-transition
factor (0.5 by default) on each. The nets in question are 320 bits of `sfp_out`,
320 bits of `pmem_out` and two 24-bit inter-core sum buses — enough
high-fanout, high-assumed-activity net capacitance to dominate the report. That
is the 69.69 mW of "switching power," and it is fictional.

Why it broke: `run_dc.tcl`'s `analyze` list never reads `mc_div.v`,
`async_gray_fifo.v` or `sync_mb.v`. And `sfp_row.v` declares

```verilog
wire [7:0][bw_psum-1:0] quotient_out;
```

a packed multi-dimensional array — SystemVerilog, not Verilog-2001 — so
`analyze -format verilog` cannot elaborate it either.

The script's own safety net could not catch this, because it only inspects the
top level:

```tcl
set unmapped_designs [get_designs -filter "is_unmapped == true" $top_module]
```

Drop `$top_module` and it would have failed loudly. `run_power_saif.tcl` in this
repo does that check across all designs, and refuses to report power if any
block is unmapped.

## 3. The two builds are not the same design

Counting SRAM instances in each netlist (2 per core for Q/K, 1 for the psum):

```
step4: 3 sram_w16 instances  -> 1 core
step5: 6 sram_w16 instances  -> 2 cores
```

So roughly 2× the logic before gating is considered. `step4` is also
single-core in its netlist despite its RTL instantiating two cores, meaning that
netlist is itself stale relative to its source.

And `step6`'s synthesis outputs are byte-identical to `step5`'s:

```
6d257de7a9ed249f9ec77333e3ed97c4  step5_clock_gating/syn/fullchip.out.v
6d257de7a9ed249f9ec77333e3ed97c4  step6/syn/fullchip.out.v
```

with the same `Date : Thu Mar 19 03:03:00 2026` in both power reports, even
though step6's RTL adds the SFP skip path. Step 6 was never re-synthesised, so
no reported number reflects the skip optimisation at all.

**Conclusion: 6.06 mW vs 80.03 mW is not a clock-gating A/B.** It compares a
clean single-core build against a broken dual-core build with two black boxes.

## 4. Even with a clean netlist, the estimate could not have shown the saving

This is the part that generalises to your systolic array, and it is the more
important lesson.

Both power engines were running **vectorless**. Design Compiler:

```
Information: Propagating switching activity (low effort zero delay simulation). (PWR-6)
Warning: Design has unannotated primary inputs. (PWR-414)
Warning: Design has unannotated sequential cell outputs. (PWR-415)
```

and Innovus, from `fullchip.post_route.power.rpt`:

```
*   User-Defined Activity : N.A.
*   Activity File: N.A.
*   Sequential Element Activity: 0.200000
*   Primary Input Activity: 0.200000
*   Default icg ratio: N.A.
*   Global Comb ClockGate Ratio: N.A.
```

Read those last four lines carefully. Every flip-flop is assumed to toggle 20%
of the time **whether or not its clock is gated off**, and `Default icg ratio:
N.A.` means no clock-gating credit is applied anywhere.

Clock gating, operand isolation and the SFP skip path all work the same way:
they make specific nets stop toggling under specific *data* conditions. A
vectorless engine assumes the gating condition is a coin flip. So it charges you
for every comparator, latch and AND gate you added — that area is real and it
sees it — and credits you with nothing, because the correlation between the
enable and the data is exactly the information it does not have.

**On a vectorless estimate, data-dependent gating can only ever look worse than
no gating.** That is not a modelling subtlety, it is the structure of the
method. This is almost certainly what you hit on the systolic array.

Two further reasons the tools saw nothing:

- **No `-gate_clock`, no `set_clock_gating_style`** anywhere in the flow. The
  gater is hand-built in RTL and maps to a general-purpose data latch plus a
  general-purpose AND (`LNQD1` + `CKAN2D1` on this library), not to the
  library's integrated clock-gating cell. Nothing in the netlist is *tagged* as
  a clock gate, so `report_power` has nothing to apply a ratio to and
  `report_clock_gating` reports nothing.
- **No `create_generated_clock` on `g_clk`.** `create_clock` marks `clk` as an
  ideal network, whose switching is not charged pre-CTS. The AND gate terminates
  that ideal network. Everything downstream of it is, to the tool, an ordinary
  high-fanout combinational net toggling at clock rate — 136 flop `CP` pins per
  column — and gets charged in full. You converted free ideal-clock capacitance
  into billed combinational capacitance.

## 5. What the gating did, measured (pre-rework)

> These numbers describe the original `mac_col`, which built its gater in RTL.
> That gater has since been replaced by a register enable and the isolation
> defects below are fixed; see [../results/measurements.md](../results/measurements.md).

No licence needed for this. `sim/vcd_activity.py` counts bit transitions per net
from the testbench VCD; on a fixed technology the ratio of transitions between
two builds of the same design is a direct proxy for the ratio of dynamic power
in the logic they share. `make -C sim compare` reproduces all of it.

Both builds pass the testbench's self-check (16/16 result vectors match), so
this is a like-for-like comparison of functionally identical designs.

### The clock

Per MAC column, over the whole run:

| net | transitions |
|---|---:|
| `clk` — ungated, as the baseline's 136 flops see it | 287 |
| `g_clk` — what the gated build's flops actually see | **46** |

**84% of clock edges are suppressed.** That is the real prize, and on the ASIC
it is worth a lot: 2176 flops (136 per column × 8 columns × 2 cores) not
clocked, plus the clock-tree capacitance feeding them. It is invisible at RTL
because there is no clock tree yet, and invisible to the vectorless estimate for
the reasons above.

### The data path

| net | baseline | gated | change |
|---|---:|---:|---|
| `query_q` (register output) | 713 | 713 | — |
| `key_q` (register output) | 111 | 111 | — |
| `mac_query_in` (multiplier A input) | 713 | **419** | **−41%** |
| `mac_key_in` (multiplier B input) | 111 | **205** | **+85%** |
| `psum` (multiplier output) | 163 | **123** | **−25%** |
| whole `mac_8in` block | 987 | **747** | **−24%** |

Aggregated, shared nets only:

```
MAC array (core 1):   40,444 -> 38,294   (-5.3%)
whole chip:          297,231 -> 290,963   (-2.1%)
```

Note `query_q` and `key_q` are unchanged. The clock gating did **not** reduce
register output toggling, because those registers were already enable-gated —
Design Compiler infers 132 `EDFCNQD1` enable flops per column in *both* builds,
from the `if (inst_q[0])` conditions and the `cnt_q <= cnt_q;` default
assignments that were always in the RTL. The gating's benefit is entirely in the
clock, not in the data.

### The comparators are not the problem

This is the surprise, and it contradicts the hypothesis:

| net | transitions over the run |
|---|---:|
| `input_zero` (64-bit zero-compare on `query_q`) | **5** |
| `weight_zero` (64-bit zero-compare on `key_q`) | **2** |
| `is_idle` / `clk_en` / `clk_en_latch` | 5 each |

The comparator *outputs* are essentially static. A 64-bit zero-detect is an
OR-reduction tree, and because the operands are usually either clearly zero or
clearly non-zero, its output barely moves. Their real cost is area and leakage
(~40–50 gates each × 8 columns × 2 cores) plus internal OR-tree node switching
that RTL cannot show — not output toggling. On these numbers the comparators
come nowhere near paying for the 84% clock saving.

### What *is* the problem: isolating the stationary operand, twice

Two genuine defects, both visible in the table above.

**(a) `mac_key_in` gets 85% busier.** In `rtl/mac_col.v`:

```verilog
wire input_zero  = (query_q == 0);
wire mac_key_in  = input_zero ? 0 : key_q;
```

`key_q` is the *stationary* operand — it changes only on a weight load, and
toggles just 111 times all run. Forcing it to zero whenever the *streaming*
query happens to be zero takes a nearly-quiet 64-bit bus and makes it toggle 205
times. The isolation is strictly counterproductive on that side. Isolating the
streaming operand with the stationary one (`mac_query_in`, 713 → 419) is the
half that works, because whole columns hold zero weights for long stretches.

**Fix:** isolate the streaming operand only. Drop the `mac_key_in` mux and feed
`key_q` straight to the multiplier.

**(b) The isolation is applied twice.** `mac_col.v` isolates the full 64-bit
operands, then `mac_8in.v` does it again per 8-bit lane:

```verilog
wire [bw-1:0] a_iso = b_val ? a_val : {bw{1'b0}};
wire [bw-1:0] b_iso = a_val ? b_val : {bw{1'b0}};
```

Measured, summed over the 8 lanes of one column:

```
a_val 419  ->  a_iso 419     no change at all
b_val 205  ->  b_iso 251     +22% worse
```

The second layer buys nothing on the A side and actively hurts on the B side,
while costing 128 `INR2D0` mux cells per column in the netlist. It is pure
overhead.

Also in `mac_8in.v`, these two lines are dead code:

```verilog
wire a_zero = (a_val == 0);
wire b_zero = (b_val == 0);
```

Nothing reads them — the muxes test `b_val`/`a_val` directly, which synthesises
the OR-reduction inline. Synthesis removes them, but they make the intent look
like something it isn't when you read the file.

## 6. Doing it properly from here

All four of these have been done — see [extensions.md](extensions.md). Kept here
because the ordering is the useful part.

1. **Delete the hand-rolled gater; let the tool infer ICGs.** The enable
   conditions are already in the RTL — that is what those 132 `EDFCNQD1` per
   column encode. `syn/clock_gating_setup.tcl` plus `compile_ultra -gate_clock`
   converts them into integrated clock-gating cells: glitch-free by
   construction, CTS-aware, covered by clock-gating setup/hold checks, visible
   to `report_clock_gating`, and eligible for the ICG credit in
   `report_power`. One gated clock pin per bank instead of 132 enable muxes.
2. **Annotate real activity.** `syn/run_power_saif.tcl` reads a SAIF before
   `report_power`; `sim/gen_saif.md` has the `$toggle_*` calls and the Innovus
   `read_activity_file` equivalent. The testbench has always written a full VCD
   — the activity data existed the whole time, it was just never fed back.
3. **Fix the two isolation defects** in §5: streaming operand only, one layer.
4. **Compare like with like.** Same core count, same block set, both netlists
   verified free of black boxes and `tri` nets, and re-synthesise after every
   RTL change.

If you must stay vectorless, at least state the assumption to the tool:

```tcl
set_default_switching_activity -input_activity 0.2 -clock_gating_ratio 0.8
```

`-clock_gating_ratio` is what fills the `Default icg ratio: N.A.` field. It only
works on gaters the tool recognises, which is another reason to let
`-gate_clock` do the inference. And label it an assumption, not a measurement.

---

## 7. Quartus: how the FPGA flow differs

You asked how the Quartus simulation handled clock gating, since the teammate's
Cyclone IV project reported a 64% dynamic reduction where Design Compiler
reported an increase. The two numbers are not in conflict; they measure different
things with different methods.

**Correction — the Cyclone IV numbers were not VCD-annotated either.** An
earlier revision of this document assumed the teammate's flow fed PowerPlay a
VCD, and that this was the whole difference. The ECE 284 synthesis reports
(`Part1_Vanilla/synth/FPGA_Report.pdf`, `Part5_Alpha/.../FPGA_Syn_Final.pdf`)
show otherwise. Both Power Analyzer summaries read:

```
Core Dynamic Thermal Power Dissipation :   0.00 mW
Core Static  Thermal Power Dissipation : 119.47 mW   (119.86 mW for Alpha 1)
I/O          Thermal Power Dissipation : 171.97 mW   (173.01 mW for Alpha 1)
Total        Thermal Power Dissipation : 291.44 mW   (292.87 mW for Alpha 1)
```

**Core dynamic power is 0.00 mW.** The analyser had no activity data for the
core at all. The figure quoted as "Dynamic Power — 172 mW / 173 mW" in those
reports is the **I/O** line, which is pad power across 454 and 458 real pins
(`Total virtual pins: 0`), not the accelerator's compute power. The derived
96.6 and 138 GOPS/W therefore divide throughput by pad power.

That resolves the apparent contradiction without needing the VCD explanation:
**neither flow ever measured core dynamic power.** Design Compiler measured a
vectorless estimate of a broken netlist; PowerPlay measured pads. Clock gating
could not have shown up in either, and the "2.78× from weight sparsity" figure
was, by the project's own notes, a team estimate for a `mac_tile` variant that
was never wired into the synthesised design.

It also means the two projects' power numbers are not comparable to each other
or to anything else, and that this repository has no prior number to beat — only
a method to fix.

**What PowerPlay needs to report core power.** The tool does accept real
per-node toggle rates; it simply was not given any. Either annotate a VCD:

```sh
quartus_pow <project> --input_vcd=../sim/build/fullchip.vcd \
                      --vcd_filter_glitches=on --use_vectorless_estimation=on
```

(`POWER_USE_INPUT_FILE` in a `.qsf` accepts only `"No File"`,
`"Signal Activity File"` or `"VCD File"`, and `POWER_INPUT_FILE_NAME` requires a
section id, so the command line is the simpler route for a plain path — see
`fpga/run_quartus.sh`.)

Or, failing that, at least enable vectorless estimation so the core is modelled
at a default toggle rate rather than not at all. And use **virtual pins**: with
454 real pins the I/O term swamps everything and the core number is what you
actually wanted.

**But "clock gating" means something different on an FPGA.** There is no ICG
cell in a Cyclone IV LE. Three things can happen to `wire g_clk = clk & en;`:

- Quartus recognises the pattern and converts it to the register's dedicated
  **clock-enable** (`ena`) input. This is the good outcome and it is free — every
  LE register has that port. It is what `AUTO_CLOCK_ENABLE_RECOGNITION ON`
  does, and it is inferred most reliably from `if (en) q <= d;` inside a normal
  `always @(posedge clk)` block — i.e. from *exactly* the enable style already in
  `mac_col.v`, not from a hand-built gated clock.
- It does not recognise it, and routes a LUT output onto a global clock network.
  You get a warning about a clock driven by combinational logic, plus real skew
  and a Fmax hit.
- Worse, it routes the gated clock on **general-purpose routing**, at which
  point skew makes timing closure unreliable.

Critically, on an FPGA the clock network is pre-fabricated and powered whether or
not you use it. Register clock-enable does **not** save clock-tree power the way
an ASIC ICG does — it saves the register's own toggling and, more importantly,
all the downstream combinational toggling that would have followed. So the
teammate's 64% is a *data*-toggling number.

That is the real reconciliation of your two experiences:

- **On the FPGA** you measured suppressed data toggling, with a real VCD. Genuine
  and visible.
- **On the ASIC** the prize was clock-tree and flop `CP` power (the 84% above),
  and you measured it with an engine that assumes fixed flop activity and
  applies no gating credit — against a broken netlist, in a different
  configuration.

For true clock gating on Cyclone V there is the clock control block
(`altclkctrl` with `clkena`), which does gate a global network — but there are
only a handful per device, so it is coarse-grained. Fine-grained per-column
gating on FPGA should be register clock-enable, full stop.

### Practical notes for re-targeting this design to Quartus

- ~~`rtl/sfp_row.v` must be read as SystemVerilog (the packed array in §2).~~
  Fixed: the packed array is gone and all RTL is plain Verilog-2005, which also
  removes the construct that black-boxed it under `analyze -format verilog`.
- ~~`rtl/sram_w16.v` has an asynchronous reset on the memory array, which blocks
  M9K inference.~~ Fixed: the array carries no reset and now infers. Measured
  with yosys, the 160-bit instance went from 57 cells with 16 × 160-bit flop
  banks to 9 cells with one inferred memory.
- ~~`rtl/mc_div.v` computes `dividend / divisor` combinationally and merely waits
  four cycles before sampling it.~~ Replaced by `rtl/seq_div.v`: 3.0× fewer cells
  and 4.5× shorter logic depth at the same latency, so it no longer infers a
  `LPM_DIVIDE` in the critical path.
- The core has ~800 ports, far beyond any package, so everything except `clk`,
  `clk2` and `reset` is assigned `VIRTUAL_PIN` in the `.qsf`.

### Tooling status

- Quartus Prime **Standard** 23.1 at `/mnt/c/intelFPGA/23.1stdlite/quartus` —
  binaries present, 30-day evaluation **expired** (`Error (292037)`).
- Quartus Prime **Lite** at `/mnt/c/intelFPGA_lite/{21.1,23.1}` — device files
  only, **no executables**.
- Questa Starter licence at `/mnt/c/intelFPGA/LR-211345_License.dat` — **expired
  06-Jan-2026**.

Quartus Prime Lite needs no licence and does not expire, and supports Cyclone
IV E / Cyclone V and the Power Analyzer. `fpga/run_quartus.sh` honours
`QUARTUS_ROOT` if it installs elsewhere.

Until then everything in [../results/measurements.md](../results/measurements.md)
runs on Icarus Verilog and yosys, both already installed.
