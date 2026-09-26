#!/usr/bin/env python3
"""Generate testbench stimulus with a controlled weight sparsity.

The testbench derives its own expected results from these files, so any sparsity
is self-checking. Values are 4-bit signed (-8..7), matching the original vectors.

  --sparsity      fraction of individual weight entries forced to zero, which is
                  what operand isolation in mac_col acts on
  --col-sparsity  fraction of whole columns forced to an all-zero weight vector,
                  which is what the whole-column bypass acts on
"""
import argparse, pathlib, random

PR, COL, ROWS = 8, 8, 8
LO, HI = -8, 7


def nonzero(rng):
    v = 0
    while v == 0:
        v = rng.randint(LO, HI)
    return v


def weights(rng, sparsity, col_sparsity):
    """COL rows of PR weights; one row per column of the array."""
    zero_cols = set(rng.sample(range(COL), int(round(col_sparsity * COL))))
    out = []
    for c in range(COL):
        if c in zero_cols:
            out.append([0] * PR)
        else:
            out.append([0 if rng.random() < sparsity else nonzero(rng) for _ in range(PR)])
    return out


def write(path, rows):
    path.write_text("\n".join("\t".join(str(v) for v in r) for r in rows) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sparsity", type=float, default=0.0)
    ap.add_argument("--col-sparsity", type=float, default=0.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default="build_gated")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    d = pathlib.Path(args.out)
    d.mkdir(parents=True, exist_ok=True)

    # Q is the streamed operand and is left dense; sparsity here is a property of
    # the weights, which is what the gating exploits.
    write(d / "qdata.txt", [[nonzero(rng) for _ in range(PR)] for _ in range(ROWS)])
    write(d / "kdata_core0.txt", weights(rng, args.sparsity, args.col_sparsity))
    write(d / "kdata_core1.txt", weights(rng, args.sparsity, args.col_sparsity))
    print(f"{d}: sparsity={args.sparsity:.2f} col_sparsity={args.col_sparsity:.2f} seed={args.seed}")


if __name__ == "__main__":
    main()
