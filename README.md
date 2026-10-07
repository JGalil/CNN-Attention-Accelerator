# Dual-Core Self-Attention Accelerator

An 8×8 MAC-array accelerator for self-attention inference, built for UCSD ECE 260B.
The design was taken to GDS in a 65 nm Design Compiler + Innovus flow. It includes a
low-power study of clock gating, operand isolation and threshold-based compute skipping.

> The foundry PDK is stripped and verified absent. See [NOTICE.md](NOTICE.md) for
> provenance and attribution.

---

## What it computes

A two-core attention datapath. Each core holds Q and K vectors in local memory and
streams Q through a weight-stationary 8×8 MAC array to produce Q·Kᵀ partial sums.
A special-function unit then normalises them. The two cores exchange row sums across
a clock-domain crossing, so normalisation spans both.

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
| Datapath | 8-bit operands, 20-bit partial sums |
| Array | 8 columns × 8 parallel products per column |
| Cores | 2, each with Q/K/psum memories and its own SFP |
| Inter-core link | gray-code async FIFO + 2-flop synchronisers (`clk2` for core 2) |
| Clock constraint | 10 ns in every flow |

### Modules

| file | role |
|---|---|
| `rtl/fullchip.v` | top level: two cores + the two CDC FIFOs |
| `rtl/core.v` | one core: memories, array, output FIFO, SFP |
| `rtl/mac_array.v` / `mac_col.v` / `mac_8in.v` | the MAC array; gating and operand isolation are in `mac_col.v` |
| `rtl/sfp_row.v` | absolute value, row sum, runtime threshold skip, 8 dividers |
| `rtl/seq_div.v` | sequential restoring divider, 2 quotient bits per cycle |
| `rtl/async_gray_fifo.v` / `sync_mb.v` | clock-domain crossing |
| `rtl/ofifo.v` / `fifo_depth16.v` / `fifo_mux_*.v` | output FIFO tree |
| `rtl/sram_w16.v` | 16-entry memory, RAM-inferable |
| `rtl/experimental/` | pipelined MAC variant, and the pre-optimisation baseline used for A/B |

`rtl/filelist.txt` is the single RTL list. The simulation, synthesis and Quartus
flows all read it.

---

## Quick start (no licence required)

Icarus Verilog is enough to verify the design and measure its switching activity.

```sh
make -C sim sim         # full chip, optimised           -> PASS: 16/16
make -C sim baseline    # full chip, pre-optimisation    -> PASS: 16/16
make -C sim compare     # A/B switching activity on shared nets
sim/sweep.sh            # weight-sparsity sweep, re-verifying each point
sim/sweep.sh --col      # same, whole-column sparsity
```

Unit tests:

```sh
iverilog -g2012 -o /tmp/t tb/tb_seq_div.v rtl/seq_div.v                              && vvp /tmp/t
iverilog -g2012 -o /tmp/t tb/tb_cdc.v rtl/async_gray_fifo.v rtl/sync_mb.v             && vvp /tmp/t
iverilog -g2012 -o /tmp/t tb/tb_mac_pl.v rtl/experimental/mac_8in_pl.v rtl/mac_8in.v  && vvp /tmp/t
```

---

## Results

Full tables are in [results/measurements.md](results/measurements.md) (RTL activity,
area, sparsity) and [results/fpga-quartus.md](results/fpga-quartus.md) (post-fit).

| | |
|---|---|
| Verification | 16/16 full-chip vectors (optimised and baseline); 0 errors across the three unit tests |
| Clock-gating opportunity | MAC column enables low **87.2%** of cycles, uniform across all 16 columns |
| MAC array activity | **−14.4%** vs. the pre-optimisation design |
| Divider | **3.0× fewer cells, 4.5× shorter logic depth** (1,650 → 553 cells, ×16 instances) |
| Memories | **9,216 flops → 6 inferred memories + 576 flops** |
| Sparsity | array activity ratio 0.896 at 90% whole-column weight sparsity |

### FPGA, post-fit

Quartus Prime Lite 25.1std, Cyclone IV GX `EP4CGX150DF31I7AD`, slow 1200 mV / 100 °C model:

| | baseline | optimised |
|---|---:|---:|
| Logic elements | 16,500 | 17,505 |
| Registers | 9,602 | 9,634 |
| Block memory bits | 9,216 | 9,216 |
| Fmax, `clk` | 74.38 MHz | 67.44 MHz |
| Core dynamic power, dense stimulus | 172.14 mW | 174.16 mW |

Neither build closes at 10 ns; the optimised build has −5.271 ns worst setup slack.

**The MAC-column gating does not pay on FPGA.** It costs +6.1% logic, −9.3% Fmax and
+1.2–3.1% core dynamic power. The global clock network is powered regardless of
register enables, and the gated registers already had conditional writes.
[fpga-quartus.md](results/fpga-quartus.md) covers the causes and the confidence
caveat: 99.2% of combinational nodes were annotated vectorlessly. The ASIC case
depends on clock-tree power and integrated clock-gating cells, and is untested.

### The original 65 nm power numbers were invalid

The course flow reported 80 mW for the gated build against 6 mW ungated. That
comparison does not measure clock gating:

- the gated netlist had two **unresolved black boxes** (134 `tri` nets), so most
  of its switching power was the default X-transition factor applied to undriven
  buses;
- the two builds had **different core counts** (1 vs 2);
- the final step was **never re-synthesised**: its outputs are byte-identical to
  the previous step's;
- both power engines ran **vectorless** (`Activity File: N.A.`,
  `Default icg ratio: N.A.`), which cannot see a data-dependent saving.

Full write-up: [docs/clock-gating-power.md](docs/clock-gating-power.md).

---

## Flows

### FPGA: Quartus (`fpga/`)

```sh
make -C sim vcd                           # activity data for the power analyser
fpga/run_quartus.sh syn                   # analysis + synthesis
fpga/run_quartus.sh fit                   # + fitter and timing
fpga/run_quartus.sh power                 # VCD-annotated power
fpga/run_quartus.sh all                   # fit + power
VARIANT=baseline fpga/run_quartus.sh all  # pre-optimisation mac_col / mac_8in
```

- **Pins.** The core has 817 ports. All but `clk`, `clk2` and `reset` are
  `VIRTUAL_PIN`, so I/O power does not swamp the core figure.
- **Project file.** `fpga/gen_qsf.py` regenerates the project from
  `rtl/filelist.txt` and the port list.
- **Power settings.** `run_quartus.sh` passes the VCD to `quartus_pow`
  (`--input_vcd`, `--vcd_filter_glitches=on`), so the power analyser uses simulated
  toggle rates instead of its 12.5% default. `AUTO_CLOCK_ENABLE_RECOGNITION` is on.
- **Running from WSL.** `run_quartus.sh` stages the project onto the Windows
  filesystem, because Quartus cannot follow WSL paths. Set `QUARTUS_ROOT` if
  Quartus is not at `/mnt/c/altera_lite/25.1std/quartus`.
- **VCD timebase.** The testbench uses `` `timescale 10ns/1ps `` so the VCD's
  clock period matches the 10 ns constraint. Quartus scales dynamic power to the
  VCD timebase without warning.

### ASIC: Design Compiler + Innovus (`syn/`, `pnr/`)

These are the scripts that produced the original 65 nm results. They still run
against your own PDK. The technology is referenced only through environment
variables:

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
| `syn/run_dc.tcl` | synthesis from `rtl/filelist.txt`; exits non-zero on any unmapped block or `tri` net |
| `syn/run_power_saif.tcl` | activity-annotated power; refuses to report if any block is a black box |
| `syn/clock_gating_setup.tcl` | tool-inferred integrated clock gaters |
| `sim/gen_saif.md` | producing the SAIF / VCD both flows read |

---

## Open work

Status is tracked in [docs/extensions.md](docs/extensions.md).

1. **ASIC power and Fmax with an open-source flow** (Yosys, OpenROAD, LibreLane on
   sky130). This is the only way left to test the clock-gating case on a target
   where an ICG stops a clock.
2. **Synchronise the instruction bus into core 2.** The row-sum FIFOs cross
   domains correctly, but `inst` is driven in the `clk` domain and read by both
   cores, so `clk2` must still be driven from `clk`. A command FIFO built on
   `async_gray_fifo` is the obvious route.
3. **Gate-level activity.** RTL simulation has no delays, so glitch power is
   missing and large combinational blocks are undercounted.
4. **Pipelined MAC.** `rtl/experimental/mac_col_pipelined.v` is verified but not
   adopted. The worst FPGA setup path runs from a MAC column into the output FIFO
   (`mac_col.key_zero_q` → `ofifo`, −5.271 ns), so this is the next timing lever.
5. **Shift-based normalisation**, if its accuracy cost is acceptable against the
   testbench's reference model.

---

## Layout

```
rtl/            synthesisable RTL, technology-independent
  experimental/ pipelined MAC, and the pre-optimisation baseline for A/B
tb/             testbenches; generated stimulus in tb/data/
sim/            licence-free flow: Makefile, VCD activity analyser, stimulus
                generator, sparsity sweep, SAIF notes
fpga/           Quartus project, constraints, WSL run wrapper
syn/ pnr/       Design Compiler and Innovus scripts; PDK via environment variables
docs/           clock-gating post-mortem, extension backlog
results/        measured activity, area, sparsity and post-fit reports
```
