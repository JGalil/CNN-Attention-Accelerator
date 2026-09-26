#!/usr/bin/env python3
"""
Tool-independent switching-activity analysis from a VCD.

Why this exists
---------------
Dynamic power is  P = alpha * C * V^2 * f  summed over nets.  For two builds of
the same design on the same technology, the C's of the shared nets are
unchanged, so the ratio of total *bit transitions* between two runs is a direct
proxy for the ratio of dynamic power in the logic they share.  That makes it
possible to measure whether clock gating and operand isolation are actually
suppressing activity, with no synthesis tool and no licence.

This is deliberately not a power estimate -- it has no capacitance model, so it
cannot tell you milliwatts, and it cannot see glitch power in a gate-level
netlist.  What it does tell you is the thing the vectorless estimators in
Design Compiler and Innovus structurally cannot: how often each register and
each net in *your* design actually toggles on *your* workload.

Usage
-----
  ./vcd_activity.py build/fullchip.vcd
  ./vcd_activity.py build/fullchip.vcd --scope fullchip_tb.fullchip_instance
  ./vcd_activity.py a.vcd --compare b.vcd --scope fullchip_tb.fullchip_instance
  ./vcd_activity.py build/fullchip.vcd --start 20000 --by-module
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict

TIME_RE = re.compile(rb"^#(\d+)")


class Signal:
    __slots__ = ("name", "width", "value", "toggles", "changes",
                 "high_time", "last_t", "first_t")

    def __init__(self, name: str, width: int) -> None:
        self.name = name
        self.width = width
        self.value = None      # last seen value, as a bit string
        self.toggles = 0       # bit transitions (Hamming distance), the power proxy
        self.changes = 0       # value-change events, regardless of how many bits
        self.high_time = 0     # time spent non-zero, for duty measurement
        self.last_t = None
        self.first_t = None


def _norm(v: str, width: int) -> str:
    """Left-pad a VCD value to `width`, VCD-style (extend with the leading char)."""
    if len(v) >= width:
        return v[-width:]
    pad = v[0] if v[0] in "xzXZ" else "0"
    return pad * (width - len(v)) + v


def _hamming(a: str, b: str) -> int:
    """Bit transitions between two values. x/z on either side counts as a change
    on that bit, which matches how a power tool charges an unresolved node."""
    return sum(1 for x, y in zip(a, b) if x != y)


def parse(path: str, scope_filter: str | None, start: int, end: int | None):
    """Single pass over the VCD. Returns {full_name: Signal}."""
    codes: dict[str, list[Signal]] = defaultdict(list)   # code -> signals (aliases)
    signals: dict[str, Signal] = {}
    stack: list[str] = []
    t = 0
    in_defs = True

    with open(path, "r", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue

            if in_defs:
                if line.startswith("$scope"):
                    parts = line.split()
                    if len(parts) >= 3:
                        stack.append(parts[2])
                    continue
                if line.startswith("$upscope"):
                    if stack:
                        stack.pop()
                    continue
                if line.startswith("$var"):
                    # $var wire 8 ! q_in [7:0] $end
                    p = line.split()
                    try:
                        width = int(p[2])
                    except (IndexError, ValueError):
                        continue
                    code = p[3]
                    base = p[4] if len(p) > 4 else code
                    # p[5] may be a bit-select like [7:0]; keep it for uniqueness
                    suffix = p[5] if len(p) > 5 and p[5].startswith("[") else ""
                    full = ".".join(stack + [base]) + suffix
                    sig = signals.get(full)
                    if sig is None:
                        sig = Signal(full, width)
                        signals[full] = sig
                    codes[code].append(sig)
                    continue
                if line.startswith("$enddefinitions"):
                    in_defs = False
                    continue
                continue

            # --- value change section ---
            if line[0] == "#":
                try:
                    t = int(line[1:])
                except ValueError:
                    pass
                continue

            c0 = line[0]
            if c0 in "bB":
                parts = line.split()
                if len(parts) < 2:
                    continue
                val, code = parts[0][1:], parts[1]
            elif c0 in "rR":
                parts = line.split()
                if len(parts) < 2:
                    continue
                val, code = parts[0][1:], parts[1]   # real: treat as one node
            elif c0 in "01xzXZ":
                val, code = line[0], line[1:].strip()
            else:
                continue                             # $dumpvars/$end/$comment

            targets = codes.get(code)
            if not targets:
                continue

            for sig in targets:
                nv = _norm(val, sig.width) if c0 not in "rR" else val
                ov = sig.value
                # Accumulate time-at-value for duty reporting.
                if sig.last_t is not None and ov is not None:
                    if "1" in ov:
                        sig.high_time += t - sig.last_t
                sig.last_t = t
                if sig.first_t is None:
                    sig.first_t = t
                if ov is None:
                    sig.value = nv          # first value: initialise, do not count
                    continue
                if ov == nv:
                    continue
                if start <= t and (end is None or t <= end):
                    sig.toggles += (_hamming(ov, nv) if c0 not in "rR" else 1)
                    sig.changes += 1
                sig.value = nv

    if scope_filter:
        pref = scope_filter + "."
        signals = {k: v for k, v in signals.items()
                   if k == scope_filter or k.startswith(pref)}
    return signals


def module_of(name: str) -> str:
    return name.rsplit(".", 1)[0] if "." in name else "(top)"


def summarise(signals: dict[str, Signal]):
    total = sum(s.toggles for s in signals.values())
    per_mod: dict[str, int] = defaultdict(int)
    for s in signals.values():
        per_mod[module_of(s.name)] += s.toggles
    return total, per_mod


def fmt(n: int) -> str:
    return f"{n:,}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("vcd")
    ap.add_argument("--compare", metavar="VCD",
                    help="second VCD; report per-module deltas against it")
    ap.add_argument("--scope", help="restrict to this hierarchical scope")
    ap.add_argument("--start", type=int, default=0,
                    help="ignore activity before this VCD time (skip reset/preload)")
    ap.add_argument("--end", type=int, default=None)
    ap.add_argument("--top", type=int, default=20, help="rows to show")
    ap.add_argument("--by-module", action="store_true",
                    help="aggregate by parent scope instead of listing signals")
    ap.add_argument("--duty", metavar="SUBSTRING",
                    help="instead of activity, report the fraction of time each "
                         "matching signal is non-zero. For a register enable this "
                         "is the clock-gating ratio to hand a vectorless power "
                         "estimate (Design Compiler -clock_gating_ratio, or the "
                         "'Default icg ratio' field Innovus reports as N.A.).")
    ap.add_argument("--common", action="store_true",
                    help="with --compare, restrict both sides to signals present "
                         "in BOTH VCDs. Use this whenever the two builds differ "
                         "in how many intermediate wires they declare, otherwise "
                         "the build with more named nets looks busier for free.")
    args = ap.parse_args()

    a = parse(args.vcd, args.scope, args.start, args.end)
    if not a:
        print(f"no signals matched in {args.vcd}"
              + (f" under scope {args.scope}" if args.scope else ""), file=sys.stderr)
        return 1
    if args.duty:
        rows = [s for s in a.values() if args.duty in s.name]
        if not rows:
            print(f"no signal name contains {args.duty!r}", file=sys.stderr)
            return 1
        end = args.end if args.end is not None else max(
            (s.last_t for s in a.values() if s.last_t is not None), default=0)
        print(f"{'signal':<64} {'high':>8} {'gated':>8}")
        print("-" * 82)
        for s in sorted(rows, key=lambda s: s.name):
            span = end - (s.first_t if s.first_t is not None else 0)
            if span <= 0:
                continue
            duty = s.high_time / span
            print(f"{s.name:<64} {duty:7.1%} {1-duty:7.1%}")
        agg = [s for s in rows if s.first_t is not None and end > s.first_t]
        if agg:
            m = sum(s.high_time / (end - s.first_t) for s in agg) / len(agg)
            print("-" * 82)
            print(f"{'mean over ' + str(len(agg)) + ' signals':<64} {m:7.1%} {1-m:7.1%}")
        return 0

    a_total, a_mod = summarise(a)

    if not args.compare:
        print(f"{args.vcd}: {fmt(a_total)} bit transitions across "
              f"{fmt(len(a))} signals\n")
        if args.by_module:
            print(f"{'module':<62} {'toggles':>12}  {'%':>6}")
            print("-" * 84)
            for m, v in sorted(a_mod.items(), key=lambda kv: -kv[1])[:args.top]:
                print(f"{m:<62} {fmt(v):>12}  {100*v/a_total if a_total else 0:5.1f}%")
        else:
            print(f"{'signal':<62} {'toggles':>12}  {'%':>6}")
            print("-" * 84)
            for s in sorted(a.values(), key=lambda s: -s.toggles)[:args.top]:
                print(f"{s.name:<62} {fmt(s.toggles):>12}  "
                      f"{100*s.toggles/a_total if a_total else 0:5.1f}%")
        return 0

    b = parse(args.compare, args.scope, args.start, args.end)

    if args.common:
        shared = a.keys() & b.keys()
        only_a = len(a) - len(shared)
        only_b = len(b) - len(shared)
        a = {k: a[k] for k in shared}
        b = {k: b[k] for k in shared}
        a_total, a_mod = summarise(a)
        print(f"comparing {fmt(len(shared))} signals present in both "
              f"(dropped {fmt(only_a)} A-only, {fmt(only_b)} B-only)\n")
        if not shared:
            print("no shared signals -- check --scope", file=sys.stderr)
            return 1

    b_total, b_mod = summarise(b)

    print(f"A  {args.vcd:<40} {fmt(a_total):>14} bit transitions")
    print(f"B  {args.compare:<40} {fmt(b_total):>14} bit transitions")
    if a_total:
        d = 100 * (b_total - a_total) / a_total
        verdict = "B has MORE activity" if d > 0 else "B has LESS activity"
        print(f"\n   B/A = {b_total/a_total:.3f}   ({d:+.1f}%)  ->  {verdict}")
        print("   Interpreted as dynamic power, this ratio holds only for the")
        print("   logic the two builds share; cells that exist in one build and")
        print("   not the other are extra area and extra leakage on top.\n")

    mods = set(a_mod) | set(b_mod)
    rows = [(m, a_mod.get(m, 0), b_mod.get(m, 0)) for m in mods]
    rows.sort(key=lambda r: -abs(r[2] - r[1]))
    print(f"{'module':<52} {'A':>11} {'B':>11} {'delta':>11}")
    print("-" * 88)
    for m, av, bv in rows[:args.top]:
        print(f"{m:<52} {fmt(av):>11} {fmt(bv):>11} {("+" if bv-av>0 else "")+fmt(bv-av):>11}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
