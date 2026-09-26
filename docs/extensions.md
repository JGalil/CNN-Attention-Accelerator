# Extensions

Status of the backlog. Measurements for everything marked done are in
[../results/measurements.md](../results/measurements.md).

| | item | status |
|---|---|---|
| 1.1 | `sync_mb` reset was a no-op | done |
| 1.2 | FIFO array driven from two clock domains | done |
| 1.3 | pipelined MAC reset off a gated clock, double-driven registers | done, as part of 3.6 |
| 1.4 | FIFO depth comment | done |
| 1.5 | `sfp_row` attribution header | done |
| 1.6 | synthesis could not fail on black boxes | done |
| 2.1 | operand isolation defects | done |
| 2.2 | recomputed weight-zero comparator | done |
| 2.3 | hand-rolled clock gater | done |
| 2.4 | activity-annotated power | hooks in place; needs a tool |
| 2.5 | sparsity sweep | done |
| 3.1 | fake multi-cycle divider | done |
| 3.2 | memory inference | done |
| 3.3 | exercise the CDC | done for the data path; control bus open |
| 3.4 | skip granularity | done |
| 3.5 | structural zeros in the MAC array | done, reframed — see below |
| 3.6 | pipelined MAC | done |
| 3.7 | quantify | done for area and activity; power and Fmax need a tool |

---

## What changed

### Tier 1 — bugs

**1.1** `sync_mb` wrote its reset values with blocking assignments and then fell
through to unconditional non-blocking ones, so the reset values were overwritten
in the same evaluation and reset did nothing.

Worth being precise about the impact: the fault is **masked in this design**. The
synchronised value is a gray-coded pointer that is itself reset to zero by the
same reset, so the two-stage pipeline flushes to zero within two cycles either
way. `tb/tb_cdc.v` does not distinguish the two versions, including under
staggered reset release. The fix is still required — the code claimed a reset it
did not perform, and the masking is a property of the caller, not of `sync_mb` —
but it did not fix an observable failure. The synchroniser now also carries
`ASYNC_REG`/`preserve` so the two stages are not merged or retimed.

**1.2** The FIFO storage was written in the write domain and cleared in the read
domain: two drivers on two different clocks. The clearing loop is gone;
emptiness is defined by the pointers, and the single write driver is what allows
RAM inference.

**1.3** Folded into 3.6 rather than fixed separately, since 3.6 rewrites the file.

**1.6** `run_dc.tcl` checked `is_unmapped` on `$top_module` only, so a
black-boxed sub-block was never reported — which is why the step5/step6 power
reports went unnoticed. It now checks every design, checks for `tri` nets, and
exits non-zero. The `analyze` list was also hand-maintained and had drifted;
`rtl/filelist.txt` is now the single source of truth read by `syn/run_dc.tcl`,
`fpga/gen_qsf.py` and `sim/Makefile`, so a new module cannot be missing from one
of them.

### Tier 2 — power

**2.1 / 2.2 / 2.3** done as one rewrite of `mac_col`/`mac_8in`, since 2.3 deletes
the lines the other two sit next to. The hand-rolled latch+AND is replaced by a
register enable, which Design Compiler converts to an integrated clock gating
cell under `-gate_clock` and Quartus maps to the LE register clock-enable.
Operand isolation applies only to the streaming operand, the duplicate per-lane
layer in `mac_8in` is gone along with the dead `a_zero`/`b_zero` wires, and the
weight-zero flag is registered at load time instead of recomputed from a 64-bit
compare every cycle.

**2.4** The `$toggle_*` hooks are in `tb/fullchip_tb.v` behind `SAIF_DUMP`
(Icarus does not implement them), capture bounded to the compute phase.
`syn/run_power_saif.tcl` annotates the SAIF and refuses to report power if any
block is unmapped. Running it needs Design Compiler; the Quartus equivalent is
already configured in the `.qsf`.

**2.5** `sim/gen_stimulus.py` plus `sim/sweep.sh`. Both element-level and
whole-column sparsity, every point re-verified.

### Tier 3 — architecture

**3.1** `seq_div` replaces `mc_div`: restoring division, two quotient bits per
cycle, exact against Verilog's `/` and saturating above 2^qw−1. 3.0× fewer cells
and 4.5× shorter logic depth, at the same 5-cycle cadence.

Reciprocal-once-then-multiply was considered and rejected: the testbench's
reference model is exact truncating division, and a reciprocal multiply differs by
an LSB unless a correction step is added, which costs a second multiplier per
lane. Changing the reference model to match an approximation would have been
moving the goalposts. Shift-based normalisation is still open as an accuracy/area
trade if the row norm may be rounded to a power of two — that is a numerical
question to settle against the model first.

`qw` is sized from the application bound rather than the operand width: the
dividend is one `|psum|` and the divisor is the row norm shifted right by 7, so
the quotient cannot exceed about 160 and 8 bits suffice. This is what keeps the
latency inside the host's handshake window.

**3.2** The asynchronous reset on the storage array is gone, so the memories
infer. 9,216 flops across the design become 6 memories and 576 flops. The reset
port is retained and clears the output register, which is all a memory can
meaningfully reset.

**3.3** `fullchip` now takes `clk2` for core 2, and the row-sum FIFOs cross
between the two domains. `tb/tb_cdc.v` drives the FIFO across six clock ratios
and three staggered-reset cases.

**Still open, and the reason `clk2` must currently be driven from `clk`:** the
instruction bus is not synchronised. `inst` is driven in the `clk` domain and
consumed by both cores, so `write_sum_out` (`inst[19]`) reaches core 2
unsynchronised. Running the two domains genuinely asynchronously needs either a
second instruction port or a command FIFO into core 2. The *data* path between
cores is safe; the control path is not.

**3.4** `skip_thresh` is a runtime input rather than a `localparam`, so the
accuracy/power trade is tunable without a rebuild. Per-lane gating holds the
divider datapath for any lane whose magnitude is zero, since that lane
normalises to zero for any divisor. Note the lanes deliberately stay in lockstep
on the control path — only the wide datapath is gated — so that one `done` is a
valid reference for all of them.

**3.5 — reframed.** The original text proposed advancing the instruction stream
past a zero column. That is wrong for this architecture: all eight columns
compute in parallel on the streamed query, so skipping one saves no cycles. A
zero-weight column also cannot stop clocking, because it relays the query to the
next column through `q_out`.

What it *can* do is suppress its own product for as long as those weights are
loaded. That is what is implemented: the registered `key_zero_q` isolates the
query operand into the multiplier and forces the column's psum to zero at the
source, and `col_active` exports the flag. The sweep in §5 of the measurements
shows whole-column sparsity is worth roughly twice as much as the same fraction
spread over individual weights.

Converting sparsity into throughput rather than power would need a different
dataflow — output-stationary, or a compressed weight format that lets the host
skip issuing work — which is a larger change than this item.

**3.6** `mac_8in_pl` rewritten with a parameterisable depth (`stages` 1–3),
register-enable gating on the ungated clock, asynchronous reset independent of
`en`, and one always block per register. `mac_col_pipelined.v` delays the
output-valid instruction by the pipeline depth so `fifo_wr` still lines up.

It remains experimental rather than default, and the reasoning is unchanged: the
design is constrained at 10 ns, where the combinational MAC closes with large
margin, so the extra registers buy nothing. It is here for retargeting to a
faster clock. Whether that is worth doing should be decided from a real Fmax
number, which needs Quartus.

---

## Remaining work

1. **Power in milliwatts.** Needs Quartus (`fpga/run_quartus.sh power`, already
   configured to read a VCD) or a PDK with Design Compiler
   (`syn/run_power_saif.tcl`). Everything on the tool side is in place.
2. **Fmax.** `fpga/run_quartus.sh fit`. This also decides 3.6 and tells you
   whether the 10 ns constraint was ever the real limit.
3. **Synchronise the instruction bus into core 2**, so `clk2` can actually run
   asynchronously. A command FIFO reusing `async_gray_fifo` is the obvious route.
4. **Gate-level activity.** RTL simulation has no delays, so glitch power is
   absent and large combinational blocks are undercounted. A post-fit gate-level
   VCD from Questa would fix both and make the divider comparison direct rather
   than inferred from cell counts.
5. **Shift-based normalisation**, if the accuracy cost measures acceptable
   against the reference model — the remaining large arithmetic simplification.
