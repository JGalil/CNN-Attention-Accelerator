# Provenance and redistribution notice

Read this before making the repository public. There are **two separate**
encumbrances, and only one of them has been dealt with mechanically.

---

## 1. Vendor PDK — handled

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

## 2. Course-provided RTL — **not** handled, needs your decision

This is the more restrictive of the two, and it applies to the RTL itself rather
than to the build products.

Most of the module skeletons carry this header:

```verilog
// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission
```

That is an explicit request not to redistribute, and it is independent of the
PDK question. Making the repository public without permission would disregard it.

### What is actually yours

Determined by diffing the `step1` baseline against the final `step6` RTL.

**Written by your team — no course header, safe to publish:**

| file | notes |
|---|---|
| `rtl/async_gray_fifo.v` | new — gray-code CDC FIFO |
| `rtl/mc_div.v` | new — divider wrapper |
| `rtl/sync_mb.v` | new — multi-bit synchroniser |
| `rtl/experimental/mac_8in_pl.v` | new — 3-stage pipelined MAC |

**Substantially modified by your team, but built on a course skeleton:**

| file | lines changed vs `step1` |
|---|---:|
| `tb/fullchip_tb.v` | 493 |
| `rtl/fullchip.v` | 110 |
| `rtl/sfp_row.v` | 96 — header was stripped; restore it |
| `rtl/mac_8in.v` | 63 |
| `rtl/core.v` | 42 |
| `rtl/mac_col.v` | 40 |

**Course-provided and unmodified — 0 lines changed, entirely Prof. Kang's:**

`rtl/sync.v`, `rtl/sram_w16.v`, `rtl/ofifo.v`, `rtl/mac_array.v`,
`rtl/fifo_depth16.v`, `rtl/fifo_mux_16_1.v`, `rtl/fifo_mux_8_1.v`,
`rtl/fifo_mux_2_1.v`

### Options

1. **Ask.** One email to Prof. Kang covers it, and course staff are often fine
   with published coursework. Cleanest outcome, and it lets the repo stay
   complete and buildable.
2. **Keep it private** and share by invitation. Costs nothing, and it is what the
   header asks for by default.
3. **Rewrite the unmodified eight.** They are small, generic structures — a
   synchroniser, a register-file SRAM model, a FIFO, some muxes, a generate-loop
   array wrapper. Rewriting them from their interfaces makes the repo wholly
   yours and, per [docs/extensions.md](docs/extensions.md) §3.2, `sram_w16.v`
   wants rewriting anyway. Then publish freely.
4. **Publish only your own work** — the four new files plus the analysis and the
   flow scripts — as a portfolio piece, with the course modules referenced but
   not included. The repo no longer builds standalone, which is a real cost.

Option 1 then 3 is the best combination: ask now, and rewrite `sram_w16.v` for
its own sake regardless of the answer.

> A teammate's repository for the related CNN variant is public, which suggests
> this may already be accepted practice for this course. It is not evidence of
> permission for *this* code, and it is not a substitute for asking.

---

## 3. Also worth checking before publishing

- `tb/data/*.txt` are generated test vectors. Confirm they are synthetic and not
  derived from a distributed dataset.
- `docs/clock-gating-power.md` quotes tool report fragments (DC `PWR-*` warnings,
  an Innovus report header). These are your own tool output describing your own
  design and contain no library data, but they do name tool versions.
- Nothing here contains the course locker path any more; it was parameterised out
  of `syn/` and `pnr/`.
