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

QUARTUS_ROOT="${QUARTUS_ROOT:-/mnt/c/intelFPGA/23.1stdlite/quartus}"
BIN="$QUARTUS_ROOT/bin64"
STAGE_WIN="${STAGE_WIN:-/mnt/c/quartus_build/attention_accel}"
PROJ=attention_accel
STEP="${1:-syn}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -x "$BIN/quartus_sh.exe" ]] || { echo "Quartus not found at $BIN" >&2; exit 1; }

echo "==> staging to $STAGE_WIN"
mkdir -p "$STAGE_WIN"
# Keep the ../rtl relative layout the .qsf expects.
rm -rf "$STAGE_WIN/rtl" "$STAGE_WIN/fpga"
mkdir -p "$STAGE_WIN/rtl" "$STAGE_WIN/fpga" "$STAGE_WIN/sim/build"
cp "$REPO"/rtl/*.v                "$STAGE_WIN/rtl/"
cp "$REPO"/fpga/"$PROJ".{qpf,qsf,sdc} "$STAGE_WIN/fpga/"
cp "$REPO"/fpga/*.tcl             "$STAGE_WIN/fpga/" 2>/dev/null || true
[[ -f "$REPO/sim/build/fullchip.vcd" ]] && cp "$REPO/sim/build/fullchip.vcd" "$STAGE_WIN/sim/build/"

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
    ;;
esac

if [[ "$STEP" == "power" || "$STEP" == "all" ]]; then
    if [[ ! -f "$STAGE_WIN/sim/build/fullchip.vcd" ]]; then
        echo "!! No VCD at sim/build/fullchip.vcd."
        echo "!! Run 'make -C ../sim vcd' first, or the analyser will fall back"
        echo "!! to vectorless estimation and the numbers will not reflect any"
        echo "!! data-dependent gating. See docs/clock-gating-power.md."
    fi
    run quartus_pow.exe "$PROJ"
fi

echo "==> collecting reports"
mkdir -p "$REPO/results"
shopt -s nullglob
for f in "$STAGE_WIN/fpga/output_files"/*.rpt "$STAGE_WIN/fpga/output_files"/*.summary; do
    cp "$f" "$REPO/results/"
done
ls -1 "$REPO/results" | sed 's/^/    /'
echo "==> done ($STEP).  Reports in results/"
