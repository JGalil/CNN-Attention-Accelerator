# Possible extensions

Ordered by value-per-effort. Everything in tiers 1–2 is doable with only Icarus
Verilog and Quartus Prime Lite; nothing needs the ASIC tools.

Items marked **[bug]** are defects found while reading the RTL, not speculative
improvements. Fix those first — some of them invalidate results you already have.

---

## Tier 1 — correctness, and results that are currently wrong

### 1.1 **[bug]** `sync_mb.v` has no working reset

```verilog
always @ (posedge clk or posedge reset) begin
    if(reset) begin
        int1 = 0;        // blocking
        int2 = 0;
    end
    int1 <= in;          // runs unconditionally, overrides the above
    int2 <= int1;
end
```

The reset branch uses blocking assignments and then falls through to the
non-blocking ones, which always execute. The blocking writes are overwritten in
the same evaluation, so **reset does nothing**. This is the CDC synchroniser for
both async FIFO pointers, so on reset the gray pointers are whatever `in`
happened to be — the FIFOs can come up non-empty. It has not bitten you because
both cores currently run on the same clock and the testbench holds reset long
enough for the garbage to flush.

```verilog
always @ (posedge clk or posedge reset) begin
    if (reset) begin
        int1 <= 0;
        int2 <= 0;
    end else begin
        int1 <= in;
        int2 <= int1;
    end
end
```

### 1.2 **[bug]** `async_gray_fifo.v` drives one register array from two clock domains

The FIFO storage is written in the write domain:

```verilog
always @(posedge wr_clk or posedge wr_rst)
    ... fifo[wr_ptr[addr-1:0]] <= wr_data;
```

and cleared in the read domain:

```verilog
always @(posedge rd_clk or posedge rd_rst)
    if (rd_rst) for (i...) fifo[i] <= 0;
```

The same `fifo` array has two drivers on two different clocks. That is a
multiple-driver error for synthesis and defeats the entire point of the gray-code
pointer scheme — the payload is supposed to be written in one domain and read
combinationally in the other, never reset from the far side. Drop the clearing
loop; an empty FIFO is defined by the pointers, not by zeroed storage. It also
costs 8 × 20 = 160 flops of reset fanout and prevents RAM inference.

### 1.3 **[bug]** `mac_8in_pl.v` resets registers from a gated clock

In `rtl/experimental/mac_8in_pl.v`:

```verilog
assign s1_clk = mac_en_q && clk;
always @ (posedge s1_clk) begin
    if (reset) begin product0_q <= 0; ... end
```

`reset` is synchronous to `s1_clk`, which is gated off by `mac_en_q`. If the MAC
is idle during reset — the normal case, since `mac_en` is derived from data being
non-zero — **the pipeline registers never reset**.

Worse, `add_0_3_q` and `add_4_7_q` are assigned in *two* always blocks (the
`s1_clk` reset branch and the whole `s2_clk` block), so they have two drivers on
two different gated clocks. This variant cannot synthesise correctly as written.
Use an async reset on the ungated `clk`, and assign each register in exactly one
block.

### 1.4 **[bug]** `async_gray_fifo.v` depth comment contradicts the parameter

`parameter addr = 3` gives depth 8; the comment says `2^4 = 16`. Harmless today
but it is the kind of thing that turns into an off-by-8 later.

### 1.5 Restore the stripped attribution header on `sfp_row.v`

`step6`'s `sfp_row.v` had the course header removed while the file still contains
course-provided structure. See `NOTICE.md` — put it back.

### 1.6 Make the synthesis script fail loudly on black boxes

The single highest-value change to the ASIC flow, and the reason the step5/step6
power numbers are meaningless. `syn/run_power_saif.tcl` already does this; fold
the same check into `run_dc.tcl`, and add the missing `analyze` lines for
`mc_div.v`, `async_gray_fifo.v` and `sync_mb.v`. See
[clock-gating-power.md](clock-gating-power.md) §2.

---

## Tier 2 — the power story, done properly

### 2.1 Fix the two operand-isolation defects

Measured in [clock-gating-power.md](clock-gating-power.md) §5:

- Isolating the **stationary** operand (`mac_key_in`) makes a quiet bus 85%
  busier. Delete that mux.
- The isolation is applied **twice**, once on 64-bit operands in `mac_col.v` and
  again per-lane in `mac_8in.v`. The second layer changes nothing on the A side
  and is 22% worse on the B side, while costing 128 mux cells per column. Delete
  it.
- Remove the dead `a_zero` / `b_zero` wires in `mac_8in.v`.

Expected: strictly less area and strictly less activity, with identical function.
`make -C sim compare` will confirm it.

### 2.2 Register the weight-zero flag instead of recomputing it

`weight_zero = (key_q == 0)` is a 64-bit compare evaluated every cycle, but
`key_q` only changes on a weight load. Compute it once at load time and register
it — one flop replaces a continuously-powered comparator. (Its *output* barely
toggles, so the win is the OR-tree's internal switching and its area, not output
activity.)

### 2.3 Let the tool infer integrated clock gaters

Delete the hand-rolled latch+AND from `mac_col.v` and use
`syn/clock_gating_setup.tcl` with `compile_ultra -gate_clock`. Glitch-free,
CTS-aware, checked, and visible to `report_clock_gating`. On FPGA the equivalent
is register clock-enable, which `AUTO_CLOCK_ENABLE_RECOGNITION ON` infers from
the enable conditions already present — a hand-built gated clock on Cyclone IV is
actively harmful.

### 2.4 Close the loop on activity-annotated power

`syn/run_power_saif.tcl` + `sim/gen_saif.md` for the ASIC flow;
`POWER_USE_INPUT_FILE VCD` (already in the `.qsf`) for Quartus. Then re-run the
step4-vs-step6 comparison with matched core counts and publish a table that
means something.

### 2.5 Sweep sparsity to find the break-even point

The interesting result is not one number but the curve. Parameterise the
testbench's stimulus generator by weight sparsity, sweep 0–90%, and plot activity
against it for gated and ungated builds. That is the plot that answers "is the
gating worth its area?" and it needs no licence at all — `vcd_activity.py`
produces every point.

---

## Tier 3 — architecture

### 3.1 Replace the fake multi-cycle divider

`mc_div.v` is the biggest structural liability in the design:

```verilog
assign quotient_c = dividend / divisor;   // full combinational divide
...
if (count == cycles) quotient_q <= quotient_c;
```

The `cycles` counter does not pipeline anything — it waits four cycles and then
samples a purely combinational 20-bit divide. The critical path still contains a
whole divider, ×8 instances per core, ×2 cores. On FPGA this infers 16
`LPM_DIVIDE` blocks and will set your Fmax.

Options, cheapest first:

- **Shift-based normalisation.** The SFP divides by a row sum to normalise. If
  you round the divisor to a power of two you replace all 16 dividers with
  barrel shifters. For an attention weight feeding an 8-bit datapath the accuracy
  cost is likely negligible — quantify it against the testbench's reference model
  before committing.
- **Reciprocal once, multiply eight times.** All 8 lanes share one divisor. Compute
  `1/sum` once (LUT or Newton–Raphson) and replace 8 dividers with 1 reciprocal
  and 8 multipliers.
- **A real iterative divider.** Restoring or non-restoring, one quotient bit per
  cycle. Genuinely multi-cycle, and short-path.

Also: **divide-by-zero is unhandled.** `sum == 0` is reachable whenever a whole
row is zero — which the skip path already detects, so the guard exists but the
divider does not rely on it.

### 3.2 Let `sram_w16.v` infer real memory

The async reset on the memory array blocks block-RAM inference on FPGA and forces
a flop array on ASIC: 16 × 160 bits = 2560 flops for the psum memory alone, plus
a 16-way 160-bit mux. Drop the array reset (or make it synchronous and
write-enable gated) and the psum memory becomes one M9K. This is probably the
single largest area and power win available, and it is a handful of lines.

### 3.3 Actually exercise the CDC

`fullchip.v` contains two async gray-code FIFOs and two synchronisers, then ties
both cores to the same clock:

```verilog
assign core1_clk = clk;
assign core2_clk = clk;
```

So the CDC machinery you built is never tested in the condition it exists for.
Add a second clock, run core 2 at a different frequency, and the FIFOs start
earning their keep — and the reset bug in 1.1 will show up immediately. This is
also the most defensible extension to write up, because the hardware is already
there.

### 3.4 Skip at column granularity, not chip granularity

The `SKIP_GATING_THRESH = 660` check in `sfp_row.v` skips the division for a
whole row when the sum is below threshold. On the current workload it fires on 4
of 8 cycles. Two refinements:

- Make the threshold a runtime input rather than a `localparam`, so it is a
  tunable accuracy/power knob instead of a magic number.
- Skip *per lane*: a row can have a large sum while individual `abs` values are
  negligible.

### 3.5 Exploit structural zeros in the MAC array

Operand isolation suppresses toggling but the multiplier still exists and is
still clocked. With real sparsity you can skip the *cycle*: if a whole column's
weights are zero, advance the instruction stream past it. That converts a power
saving into a throughput saving, which is a better trade. This is what the
teammate's "80% of MACs skipped" number refers to and it is a much stronger
result than isolation alone.

### 3.6 Revisit the pipelined MAC

`rtl/experimental/mac_8in_pl.v` claims 0.45 ns (2.22 GHz) typical in its header
comment against the 10 ns period the design is constrained to — a 20× timing
margin that suggests the constraint, not the MAC, is what limits you. Fix the
bugs in 1.3, then either retarget the whole design to a much faster clock (where
the pipelined MAC pays for itself) or drop the variant. Running a 2.2 GHz-capable
MAC at 100 MHz is pure wasted area.

### 3.7 Quantify, don't assert

The teammate's README quotes 23.9 GOPS and 138 GOPS/W. This design has no
comparable published figure because its only power numbers came from the broken
runs. Once 2.4 is done, a matched table (throughput, area, power, GOPS/W, at a
stated sparsity and a stated clock, measured not estimated) is the single most
useful thing to add to the README.
