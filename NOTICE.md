# Provenance and redistribution notice

Two separate encumbrances applied to the original project tree. Both are
resolved: the foundry PDK is stripped, and the course-provided RTL is cleared for
publication.

---

## 1. Vendor PDK — stripped

The original project tree carried, in each `step*/` directory, files that are
foundry IP and cannot be redistributed:

- `tcbn65gplus.v` — standard-cell behavioural models (~1.1 MB)
- `.lib` / `.db` timing libraries, `.lef` abstracts, capacitance tables
- `fullchip.gds2`, `fullchip.def`, `fullchip_{BC,WC}.sdf` — layout and
  back-annotation derived from the library
- `fullchip.out.v`, `fullchip.pnr.v`, `sram_w16.pnr.v` — mapped netlists, which
  instantiate vendor cell names throughout and are arguably derivative
- `xcelium.d/` compiled simulation libraries containing the above

**None of this is in this repository.** Verified by sweep:

```sh
grep -rniE "tcbn|cln65|PDKdata|tsmc|ieng6|65gplus" .    # no matches
```

The RTL is fully technology-independent — no vendor cell is instantiated in
`rtl/` or `tb/`. The flow scripts reference the technology only through
environment variables, so **you can still run them against your own PDK** while
the repository itself carries nothing proprietary:

| variable | meaning |
|---|---|
| `STDCELL_DB` | worst-case `.db` for Design Compiler |
| `PDK_ROOT` | root of the PDK install |
| `DESIGN_DATA` | site design-data directory |
| `STDCELL_LIB_BC` / `STDCELL_LIB_WC` | best/worst `.lib` basenames |
| `STDCELL_LEF` | LEF basename |
| `CAPTBL_BEST` / `CAPTBL_WORST` | capacitance table filenames |

`.gitignore` additionally blocks `*.gds2 *.def *.sdf *.lib *.db *.lef *.out.v
*.pnr.v xcelium.d/` so a stray copy cannot be committed by accident.

---

## 2. Course-provided RTL — cleared for publication

The module skeletons carry:

```verilog
// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission
```

The repository owner has confirmed this code may be made public. The headers are
retained on every file that carries them, and files modified for this project
note what changed on the line below.

Provenance, for attribution rather than permission:

**Written for this project — no course header:**

| file | notes |
|---|---|
| `rtl/async_gray_fifo.v` | gray-code CDC FIFO |
| `rtl/seq_div.v` | sequential restoring divider |
| `rtl/sync_mb.v` | multi-bit synchroniser |
| `rtl/experimental/mac_8in_pl.v` | pipelined MAC |
| `sim/vcd_activity.py`, `sim/gen_stimulus.py`, `sim/sweep.sh` | measurement flow |
| `tb/tb_seq_div.v`, `tb/tb_mac_pl.v`, `tb/tb_cdc.v` | unit tests |
| `fpga/*`, `syn/run_power_saif.tcl`, `syn/clock_gating_setup.tcl` | flows |

**Course skeleton, substantially modified here:** `rtl/fullchip.v`, `rtl/core.v`,
`rtl/mac_col.v`, `rtl/mac_8in.v`, `rtl/mac_array.v`, `rtl/sfp_row.v`,
`rtl/sram_w16.v`, `tb/fullchip_tb.v`.

**Course-provided, unmodified:** `rtl/sync.v`, `rtl/ofifo.v`,
`rtl/fifo_depth16.v`, `rtl/fifo_mux_16_1.v`, `rtl/fifo_mux_8_1.v`,
`rtl/fifo_mux_2_1.v`.

---

## 3. Also worth checking before publishing

- `tb/data/*.txt` are 4-bit signed test vectors; `sim/gen_stimulus.py`
  regenerates equivalents. Confirm the originals are synthetic and not derived
  from a distributed dataset.
- `docs/clock-gating-power.md` quotes tool report fragments (DC `PWR-*` warnings,
  an Innovus report header). These are your own tool output describing your own
  design and contain no library data, but they do name tool versions.
- Nothing here contains the course locker path any more; it was parameterised out
  of `syn/` and `pnr/`.
