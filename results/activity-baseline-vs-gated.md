# Measured switching activity: gated vs ungated

Reproduce with `make -C sim compare`. Icarus Verilog + `sim/vcd_activity.py`, no
licensed tools involved.

- **Workload:** 8 streamed Q vectors, dual core, `tb/data/*.txt` stimulus
- **Metric:** bit transitions per net from the testbench VCD, restricted to nets
  present in *both* builds (the gated `mac_8in` declares ~520 extra named
  intermediate wires; counting those would make it look busier for free)
- **Functional check:** both builds 16/16 result vectors match the testbench's
  reference model, so this compares functionally identical designs

## Clock

Per MAC column, whole run:

| net | transitions |
|---|---:|
| `clk` (what the baseline's 136 flops see) | 287 |
| `g_clk` (what the gated build's flops see) | **46** |

**84% of clock edges suppressed**, uniformly across all 8 columns of both cores.
On the ASIC this is 2176 flops' worth of `CP`-pin and clock-tree switching
removed. It does not show up at RTL (no clock tree exists yet) and it cannot show
up in a vectorless estimate (see [docs/clock-gating-power.md](../docs/clock-gating-power.md) §4).

## Data path, one column

| net | baseline | gated | change |
|---|---:|---:|---|
| `query_q` (register output) | 713 | 713 | — |
| `key_q` (register output) | 111 | 111 | — |
| `mac_query_in` (multiplier A in) | 713 | 419 | **−41%** |
| `mac_key_in` (multiplier B in) | 111 | 205 | **+85%** ✗ |
| `psum` (multiplier out) | 163 | 123 | −25% |
| whole `mac_8in` block | 987 | 747 | **−24%** |

Register outputs are unchanged because those registers were already enable-gated
in the baseline — DC infers 132 `EDFCNQD1` enable flops per column in *both*
builds. The gating's win is in the clock, not the data.

`mac_key_in` getting 85% busier is a real defect: it isolates the *stationary*
operand using the *streaming* operand's zero flag, turning a quiet bus into a
noisy one. See [docs/extensions.md](../docs/extensions.md) §2.1.

## Second isolation layer inside `mac_8in`, summed over 8 lanes

| net | before isolation | after | change |
|---|---:|---:|---|
| A side (`a_val` → `a_iso`) | 419 | 419 | **no change** |
| B side (`b_val` → `b_iso`) | 205 | 251 | **+22%** ✗ |

`mac_col.v` already isolated the full 64-bit operands; `mac_8in.v` repeating it
per-lane buys nothing on A, hurts on B, and costs 128 `INR2D0` cells per column.

## Comparator cost — much smaller than expected

| net | transitions |
|---|---:|
| `input_zero` (64-bit zero-compare on `query_q`) | 5 |
| `weight_zero` (64-bit zero-compare on `key_q`) | 2 |
| `is_idle` / `clk_en` / `clk_en_latch` | 5 each |

The comparator *outputs* are nearly static — a 64-bit zero-detect is an OR
reduction, and the operands are usually decisively zero or decisively non-zero.
Their cost is area, leakage and OR-tree internal switching, not output activity.
They do not come close to offsetting the 84% clock saving.

## Aggregate, shared nets only

| scope | baseline | gated | change |
|---|---:|---:|---|
| MAC array, core 1 | 40,444 | 38,294 | **−5.3%** |
| whole chip | 297,231 | 290,963 | **−2.1%** |

Modest at chip level because the register-array SRAM models dominate the net
count — which is itself an argument for
[docs/extensions.md](../docs/extensions.md) §3.2 (make `sram_w16.v` infer real
memory).

## Caveats

- RTL-level, so no clock tree and no gate-level glitch power. The 84% clock
  figure is an *opportunity*, not a measured milliwatt saving.
- Bit transitions are a proxy for dynamic power, exact only for nets whose
  capacitance is the same in both builds. Cells present in one build and not the
  other are extra area and leakage on top.
- One workload, 8 vectors, one sparsity point. The useful result is the curve —
  see [docs/extensions.md](../docs/extensions.md) §2.5.
