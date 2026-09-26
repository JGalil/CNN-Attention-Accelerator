# Dual-Core Self-Attention Accelerator

An 8×8 MAC-array accelerator for self-attention inference, taped out through a
65 nm ASIC flow as a UCSD ECE 260B project, with a low-power study covering
clock gating, operand isolation and threshold-based compute skipping.

> The foundry PDK is stripped and verified absent; see [NOTICE.md](NOTICE.md)
> for provenance and attribution.

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
| Inter-core link | gray-code async FIFO + 2-flop synchronisers (`clk2` for core 2) |
| Target clock | 100 MHz (10 ns), both flows |

### Modules

| file | role |
|---|---|
| `rtl/fullchip.v` | top level: two cores + the two CDC FIFOs |
| `rtl/core.v` | one core: memories, array, output FIFO, SFP |
| `rtl/mac_array.v` / `mac_col.v` / `mac_8in.v` | the systolic array; gating and operand isolation live in `mac_col.v` |
| `rtl/sfp_row.v` | absolute value, row sum, runtime threshold skip, 8 dividers |
| `rtl/seq_div.v` | sequential restoring divider, exact and short-path |
| `rtl/async_gray_fifo.v` / `sync_mb.v` | clock-domain crossing |
| `rtl/ofifo.v` / `fifo_depth16.v` / `fifo_mux_*.v` | output FIFO tree |
| `rtl/sram_w16.v` | 16-entry memory, RAM-inferable |
| `rtl/experimental/` | pipelined MAC variant, and the pre-optimisation baseline used for A/B |

---

## Quick start — no licence required

Icarus Verilog and yosys are enough to verify the design and measure every
optimisation in it.

```sh
make -C sim sim         # full chip, optimised   -> PASS: 16/16
make -C sim baseline    # full chip, pre-optimisation
make -C sim compare     # A/B their switching activity, like-for-like
sim/sweep.sh            # sweep weight sparsity, re-verifying each point
sim/sweep.sh --col      # same, for whole-column sparsity
```

Unit tests:

```sh
iverilog -g2012 -o /tmp/t tb/tb_seq_div.v rtl/seq_div.v            && vvp /tmp/t
iverilog -g2012 -o /tmp/t tb/tb_cdc.v rtl/async_gray_fifo.v rtl/sync_mb.v && vvp /tmp/t
iverilog -g2012 -o /tmp/t tb/tb_mac_pl.v rtl/experimental/mac_8in_pl.v rtl/mac_8in.v && vvp /tmp/t
```

`rtl/filelist.txt` is the single RTL list read by the simulation, synthesis and
Quartus flows, so a module cannot be missing from one of them.

---

## Results

Full tables: **[results/measurements.md](results/measurements.md)**.

| | |
|---|---|
| Verification | 16/16 full-chip vectors; 0 errors across the three unit tests |
| Clock-gating ratio | **87.2%** of cycles with the MAC column enables low, uniform across all 16 columns |
| MAC array activity | **−14.4%** vs. the pre-work design |
| Divider | **3.0× fewer cells, 4.5× shorter logic depth** (1650 → 553 cells, ×16 instances) |
| Memories | **9,216 flops → 6 inferred memories + 576 flops** |
| Sparsity | array activity ratio falls to 0.90 at 90% whole-column weight sparsity |

Power in milliwatts and Fmax are *not* measured — both need a tool that is not
currently available here. The activity figures are ratios, and the RTL metric
cannot see the clock tree, which is where the clock gating actually pays. See §7
of the measurements for what is and is not established.

### The original power numbers were invalid

The pre-work synthesis reported an 80 mW gated build against a 6 mW ungated one.
That comparison does not measure clock gating:

- the gated netlist had two **unresolved black boxes** (134 `tri` nets), so most
  of its "switching power" was the tool's default X-transition factor applied to
  undriven high-fanout buses;
- the two builds had **different core counts** (1 vs 2);
- the final step was **never re-synthesised** — byte-identical outputs to the
  previous step;
- and both power engines ran **vectorless** — `Activity File: N.A.`,
  `Sequential Element Activity: 0.200000`, `Default icg ratio: N.A.` — which
  structurally cannot see a data-dependent saving.

Worth reading if you have ever added zero-detect logic to a datapath and watched
the power estimate go up: **[docs/clock-gating-power.md](docs/clock-gating-power.md)**.
§7 explains why the same optimisation measured favourably on a Cyclone IV Quartus
flow — Quartus was given a real VCD, so it was vector-based.

---

## Flows

### FPGA — Quartus (`fpga/`)

```sh
make -C sim vcd                  # activity data for the power analyser
fpga/run_quartus.sh syn          # analysis + synthesis
fpga/run_quartus.sh fit          # + fitter and timing
fpga/run_quartus.sh power        # power analysis, VCD-annotated
```

Targets Cyclone IV E `EP4CE115F29C7`. The core has ~800 ports, so all but `clk`,
`clk2` and `reset` are assigned `VIRTUAL_PIN`; `fpga/gen_qsf.py` regenerates the
project from `rtl/filelist.txt` and the port list. `run_quartus.sh` stages onto
the Windows filesystem first, because Quartus is a Windows binary and cannot
follow WSL paths.

The `.qsf` sets `POWER_USE_INPUT_FILE VCD` so the Power Analyzer uses real toggle
rates rather than its 12.5% default, and leaves `AUTO_CLOCK_ENABLE_RECOGNITION`
on — register clock-enable is the FPGA equivalent of an ICG, and a hand-built
gated clock on Cyclone IV is actively harmful. See
[docs/clock-gating-power.md](docs/clock-gating-power.md) §7.

All RTL is plain Verilog-2005 — the SystemVerilog packed array that previously
forced `sfp_row.v` to be read as SystemVerilog is gone, which is also what made
it an unresolved black box under `analyze -format verilog`.

**Tooling status:** Quartus Standard 23.1's 30-day evaluation has expired and the
two Quartus Lite trees under `/mnt/c/intelFPGA_lite` contain device files but no
executables. Quartus Prime Lite needs no licence and does not expire; set
`QUARTUS_ROOT` if it installs somewhere other than the default.

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
| `syn/run_dc.tcl` | synthesis; reads `rtl/filelist.txt`, exits non-zero on any unmapped block or `tri` net |
| `syn/run_power_saif.tcl` | **activity-annotated** power, and refuses to report if any block is a black box |
| `syn/clock_gating_setup.tcl` | tool-inferred integrated clock gaters, to replace the hand-rolled latch+AND |
| `sim/gen_saif.md` | how to produce the SAIF / VCD both flows want |

---

## Where to go next

[docs/extensions.md](docs/extensions.md) tracks status. What remains:

1. **Power and Fmax.** `fpga/run_quartus.sh power` and `... fit`. The tool side is
   configured; only the tool is missing. Fmax also decides whether the pipelined
   MAC variant is worth adopting.
2. **Synchronise the instruction bus into core 2.** `fullchip` now takes `clk2`
   and the row-sum FIFOs cross domains correctly, but `inst` is driven in the
   `clk` domain and read by both cores, so `clk2` must still be tied to `clk`.
   A command FIFO reusing `async_gray_fifo` is the obvious route.
3. **Gate-level activity.** RTL simulation has no delays, so glitch power is
   absent and large combinational blocks are undercounted.
4. **Shift-based normalisation**, if the accuracy cost measures acceptable
   against the testbench's reference model.

---

## Layout

```
rtl/          synthesisable RTL (technology-independent)
  experimental/   pipelined MAC, and pre-optimisation baseline for A/B
tb/           testbench + generated stimulus in tb/data/
sim/          licence-free flow: Makefile, VCD activity analyser, stimulus
              generator, sparsity sweep, SAIF notes
fpga/         Quartus project, constraints, WSL run wrapper
syn/ pnr/     ASIC scripts, PDK referenced via environment variables
docs/         clock-gating post-mortem, extension backlog
results/      measured activity, area and sparsity tables
```
