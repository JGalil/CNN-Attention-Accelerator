# Dual-Core Self-Attention Accelerator

An 8×8 MAC-array accelerator for self-attention inference, taped out through a
65 nm ASIC flow as a UCSD ECE 260B project, with a low-power study covering
clock gating, operand isolation and threshold-based compute skipping.

> **Read [NOTICE.md](NOTICE.md) before making this repository public.** The
> foundry PDK has been stripped and verified absent, but much of the module
> skeleton is course-provided and carries an explicit "do not spread without
> permission" header. That is unresolved and needs a decision.

---

## What it computes

A two-core attention datapath. Each core holds Q and K vectors in local memory,
streams Q through a weight-stationary 8×8 MAC array to produce Q·Kᵀ partial
sums, then normalises them in a special-function unit. The two cores exchange
row sums across a clock-domain crossing so normalisation can span both.

```
mem_in ─► qmem ─┐
                ├─► mac_array (8 cols × 8 lanes, 8-bit) ─► ofifo ─► pmem
        kmem ─┘                                                      │
                                                                     ▼
   ┌──────────────────────────── sfp_row ◄────────────────────────────┘
   │   |x| ─► Σ ─► threshold skip ─► ÷ row-sum ─► sfp_out
   │                    │
   │              sum_out ─► async_gray_fifo ─► other core's sum_in
   └── (mirrored in core 2)
```

| parameter | value |
|---|---|
| Datapath width | 8-bit operands, 20-bit partial sums |
| Array | 8 columns × 8 parallel products per column |
| Cores | 2, each with Q/K/psum memories and its own SFP |
| Inter-core link | gray-code async FIFO + 2-flop synchronisers |
| Target clock | 100 MHz (10 ns), both flows |

### Modules

| file | role |
|---|---|
| `rtl/fullchip.v` | top level: two cores + the two CDC FIFOs |
| `rtl/core.v` | one core: memories, array, output FIFO, SFP |
| `rtl/mac_array.v` / `mac_col.v` / `mac_8in.v` | the systolic array; gating and operand isolation live in `mac_col.v` |
| `rtl/sfp_row.v` | absolute value, row sum, threshold skip, 8 dividers |
| `rtl/mc_div.v` | divider wrapper (see [extensions](docs/extensions.md) §3.1) |
| `rtl/async_gray_fifo.v` / `sync_mb.v` | clock-domain crossing |
| `rtl/ofifo.v` / `fifo_depth16.v` / `fifo_mux_*.v` | output FIFO tree |
| `rtl/sram_w16.v` | 16-entry memory model |
| `rtl/experimental/` | pipelined MAC variant, and the pre-optimisation baseline used for A/B |

---

## Quick start — no licence required

Icarus Verilog is enough to simulate the design and to measure the power
optimisations.

```sh
make -C sim sim        # run the design, self-checks against the TB model
make -C sim baseline   # run the pre-optimisation variant
make -C sim compare    # A/B their switching activity, like-for-like
```

`make sim` prints `PASS: 16/16 result vectors match` — the testbench carries its
own reference model and checks every output against it.

`make compare` drives `sim/vcd_activity.py`, a VCD toggle counter that measures
what the vendor power tools could not. Sample output:

```
MAC array (core 1):   40,444 -> 38,294   (-5.3%)
whole chip:          297,231 -> 290,963   (-2.1%)
```

---

## Results

**The clock gating removes 84% of clock edges** at the MAC columns on the real
workload (`g_clk` toggles 46 times where `clk` toggles 287). Full measured
tables, including the two places where operand isolation makes things *worse*,
are in [results/activity-baseline-vs-gated.md](results/activity-baseline-vs-gated.md).

The original project's synthesis reports claimed the opposite — an 80 mW gated
build against a 6 mW ungated one. That comparison is invalid, for reasons worth
reading if you ever add zero-detect logic to a datapath and watch the power
estimate go up:

- the gated netlist had two **unresolved black boxes** (134 `tri` nets), so most
  of its "switching power" was the tool's default X-transition factor on
  undriven high-fanout buses;
- the two builds had **different core counts** (1 vs 2);
- the final step was **never re-synthesised** (byte-identical outputs to the
  previous step);
- and both power engines were running **vectorless** — `Activity File: N.A.`,
  `Sequential Element Activity: 0.200000`, `Default icg ratio: N.A.` — which
  structurally cannot see a data-dependent saving.

Full post-mortem: **[docs/clock-gating-power.md](docs/clock-gating-power.md)**.
It also explains why the same optimisation measured favourably on a Cyclone IV
Quartus flow (§7): Quartus was given a real VCD, so it was vector-based.

---

## Flows

### FPGA — Quartus (`fpga/`)

```sh
make -C sim vcd                  # activity data for the power analyser
fpga/run_quartus.sh syn          # analysis + synthesis
fpga/run_quartus.sh fit          # + fitter and timing
fpga/run_quartus.sh power        # power analysis, VCD-annotated
```

Targets Cyclone IV E `EP4CE115F29C7`. The core has ~790 ports, so all but `clk`
and `reset` are assigned `VIRTUAL_PIN`. `run_quartus.sh` stages onto the Windows
filesystem first, because Quartus is a Windows binary and cannot follow WSL
paths.

The `.qsf` sets `POWER_USE_INPUT_FILE VCD` so the Power Analyzer uses real toggle
rates rather than its 12.5% default, and leaves `AUTO_CLOCK_ENABLE_RECOGNITION`
on — register clock-enable is the FPGA equivalent of an ICG, and a hand-built
gated clock on Cyclone IV is actively harmful. See
[docs/clock-gating-power.md](docs/clock-gating-power.md) §7.

**Tooling status:** not currently runnable here. Quartus Standard 23.1's 30-day
evaluation has expired, the two Quartus Lite installs contain device files but no
executables, and the Questa Starter licence expired 6 Jan 2026. Installing
**Quartus Prime Lite** fixes it — no licence, no expiry, supports Cyclone IV/V
and the Power Analyzer.

### ASIC — Design Compiler + Innovus (`syn/`, `pnr/`)

Retained because they document how the original results were produced, and they
still run against your own PDK. The technology is referenced only through
environment variables, so nothing proprietary is in the repository:

```sh
export PDK_ROOT=/path/to/pdk
export STDCELL_DB=$PDK_ROOT/db/<worst_case_lib>.db
export DESIGN_DATA=/path/to/designdata
export STDCELL_LIB_BC=<best_lib>  STDCELL_LIB_WC=<worst_lib>
export STDCELL_LEF=<lef_basename>
export CAPTBL_BEST=<best.captable> CAPTBL_WORST=<worst.captable>

cd syn && dc_shell-xg-t -f run_dc.tcl
```

| script | purpose |
|---|---|
| `syn/run_dc.tcl` | synthesis, as originally run |
| `syn/run_power_saif.tcl` | **activity-annotated** power, and refuses to report if any block is a black box |
| `syn/clock_gating_setup.tcl` | tool-inferred integrated clock gaters, to replace the hand-rolled latch+AND |
| `sim/gen_saif.md` | how to produce the SAIF / VCD both flows want |

---

## Where to go next

[docs/extensions.md](docs/extensions.md) has a ranked list. The short version:

- **Four real bugs** to fix first — a synchroniser whose reset does nothing, a
  FIFO array driven from two clock domains, a pipelined MAC that resets off a
  gated clock and double-drives two registers, and a synthesis script that
  cannot fail on black boxes.
- **Two operand-isolation defects** that measurably make activity worse, both
  a few lines.
- `mc_div.v` is a **combinational divide** behind a counter that pipelines
  nothing — 16 of them, and they will set your Fmax.
- `sram_w16.v`'s async array reset blocks block-RAM inference; fixing it is
  probably the largest single area win available.
- Both cores are tied to the same clock, so **the CDC hardware you built is never
  exercised** in the condition it exists for.

---

## Layout

```
rtl/          synthesisable RTL (technology-independent)
  experimental/   pipelined MAC, and pre-optimisation baseline for A/B
tb/           testbench + generated stimulus in tb/data/
sim/          licence-free flow: Makefile, VCD activity analyser, SAIF notes
fpga/         Quartus project, constraints, WSL run wrapper
syn/ pnr/     ASIC scripts, PDK referenced via environment variables
docs/         clock-gating post-mortem, extension backlog
results/      measured activity tables
```
