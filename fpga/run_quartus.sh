#!/usr/bin/env bash
# Drive the Quartus flow from WSL.
#
# Quartus is a Windows binary and cannot follow WSL paths (\\wsl.localhost UNC
# paths make it reset its cwd), so the project is staged onto the Windows
# filesystem and run from there. Reports are copied back into ../results/.
#
#   ./run_quartus.sh syn      analysis + synthesis only (fast, gives LE counts)
#   ./run_quartus.sh fit      through fitter + timing (gives Fmax)
#   ./run_quartus.sh power    power analysis (needs ../sim/build/fullchip.vcd)
#   ./run_quartus.sh all      fit + power
set -euo pipefail

# Quartus Prime Lite needs no licence. 25.1std is the first of the installed
# trees to carry both binaries and the Cyclone IV device families.
QUARTUS_ROOT="${QUARTUS_ROOT:-/mnt/c/altera_lite/25.1std/quartus}"
BIN="$QUARTUS_ROOT/bin64"
# VARIANT=baseline builds the pre-optimisation mac_col/mac_8in instead, into a
# separate staging directory, so the two can be compared post-fit.
VARIANT="${VARIANT:-opt}"
STAGE_WIN="${STAGE_WIN:-/mnt/c/quartus_build/attention_accel_$VARIANT}"
PROJ=attention_accel
STEP="${1:-syn}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -x "$BIN/quartus_sh.exe" ]] || { echo "Quartus not found at $BIN" >&2; exit 1; }

echo "==> staging to $STAGE_WIN"
mkdir -p "$STAGE_WIN"
# Keep the ../rtl relative layout the .qsf expects. Only the RTL is wiped:
# fpga/ holds db/ and output_files/ from a previous compile, and a power run
# needs the fitter's database, so removing it would force a full recompile.
rm -rf "$STAGE_WIN/rtl"
mkdir -p "$STAGE_WIN/rtl" "$STAGE_WIN/fpga" "$STAGE_WIN/sim/build"
cp "$REPO"/rtl/*.v                "$STAGE_WIN/rtl/"
if [[ "$VARIANT" == "baseline" ]]; then
    # Same module names, so they drop straight in.
    cp "$REPO"/rtl/experimental/mac_col_baseline.v "$STAGE_WIN/rtl/mac_col.v"
    cp "$REPO"/rtl/experimental/mac_8in_baseline.v "$STAGE_WIN/rtl/mac_8in.v"
    echo "    variant: baseline (pre-optimisation mac_col/mac_8in)"
fi
cp "$REPO"/fpga/"$PROJ".{qpf,qsf,sdc} "$STAGE_WIN/fpga/"
cp "$REPO"/fpga/*.tcl             "$STAGE_WIN/fpga/" 2>/dev/null || true
# Each variant is annotated with the VCD from its own simulation.
if [[ "$VARIANT" == "baseline" && -f "$REPO/sim/build/fullchip_baseline.vcd" ]]; then
    cp "$REPO/sim/build/fullchip_baseline.vcd" "$STAGE_WIN/sim/build/fullchip.vcd"
elif [[ -f "$REPO/sim/build/fullchip.vcd" ]]; then
    cp "$REPO/sim/build/fullchip.vcd" "$STAGE_WIN/sim/build/"
fi

# Windows-side path to the staged fpga/ dir, for the .exe's cwd.
WINDIR="$(wslpath -w "$STAGE_WIN/fpga")"

run() {  # run <exe> <args...>   with cwd = staged fpga/
    local exe="$1"; shift
    ( cd "$STAGE_WIN/fpga" && "$BIN/$exe" "$@" ) 2>&1 \
      | grep -vE "^TBBmalloc:|^$" || true
}

case "$STEP" in
  syn)
    run quartus_map.exe "$PROJ" --read_settings_files=on
    ;;
  fit|all)
    run quartus_map.exe "$PROJ" --read_settings_files=on
    run quartus_fit.exe "$PROJ"
    run quartus_sta.exe "$PROJ"
    # The Power Analyzer refuses to run without a successful Assembler pass
    # (Error 215039), so it is part of the flow even though no programming
    # file is wanted here.
    run quartus_asm.exe "$PROJ"
    ;;
esac

if [[ "$STEP" == "power" || "$STEP" == "all" ]]; then
    run quartus_asm.exe "$PROJ"
    if [[ ! -f "$STAGE_WIN/sim/build/fullchip.vcd" ]]; then
        echo "!! No VCD at sim/build/fullchip.vcd."
        echo "!! Run 'make -C ../sim vcd' first, or the analyser will fall back"
        echo "!! to vectorless estimation and the numbers will not reflect any"
        echo "!! data-dependent gating. See docs/clock-gating-power.md."
    fi
    # --input_vcd annotates real per-node toggle rates. Without it the
    # analyser falls back to vectorless estimation, and with nothing driving the
    # core it can report 0.00 mW of core dynamic power -- which is exactly what
    # the ECE 284 reports show.
    if [[ -f "$STAGE_WIN/sim/build/fullchip.vcd" ]]; then
        run quartus_pow.exe "$PROJ" \
            --input_vcd=../sim/build/fullchip.vcd \
            --vcd_filter_glitches=on \
            --use_vectorless_estimation=on
    else
        run quartus_pow.exe "$PROJ" --use_vectorless_estimation=on
    fi
fi

echo "==> collecting reports"
mkdir -p "$REPO/results"
shopt -s nullglob
mkdir -p "$REPO/results/$VARIANT"
for f in "$STAGE_WIN/fpga/output_files"/*.rpt "$STAGE_WIN/fpga/output_files"/*.summary; do
    cp "$f" "$REPO/results/$VARIANT/"
done
ls -1 "$REPO/results" | sed 's/^/    /'
echo "==> done ($STEP).  Reports in results/"
