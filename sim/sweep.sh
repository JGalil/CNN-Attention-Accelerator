#!/usr/bin/env bash
# Sweep weight sparsity and report switching activity for the optimised and the
# pre-optimisation builds at each point. Licence-free: Icarus Verilog only.
#
#   ./sweep.sh              sweep element sparsity 0 .. 0.9
#   ./sweep.sh --col        sweep whole-column sparsity instead
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:---element}"
DUT=fullchip_tb.fullchip_instance
RTL=$(sed -E '/^\s*(#|$)/d' ../rtl/filelist.txt | sed 's|^|../rtl/|')
RTL_BASE=$(echo "$RTL" | grep -vE '/(mac_col|mac_8in)\.v$')
RTL_BASE="$RTL_BASE ../rtl/experimental/mac_col_baseline.v ../rtl/experimental/mac_8in_baseline.v"

mkdir -p sweep
iverilog -g2012 -o sweep/gated.vvp    -s fullchip_tb ../tb/fullchip_tb.v $RTL
iverilog -g2012 -o sweep/baseline.vvp -s fullchip_tb ../tb/fullchip_tb.v $RTL_BASE

ARRAY=$DUT.core_instance1.mac_array_instance
printf '%-9s %12s %12s %7s  %12s %12s %7s  %s\n' \
  sparsity chip_base chip_opt ratio arr_base arr_opt ratio status
printf '%s\n' "---------------------------------------------------------------------------------------"

for s in 0.0 0.2 0.4 0.6 0.8 0.9; do
  if [ "$MODE" = "--col" ]; then
    python3 gen_stimulus.py --col-sparsity "$s" --out sweep >/dev/null
  else
    python3 gen_stimulus.py --sparsity "$s" --out sweep >/dev/null
  fi

  ok=PASS
  for v in baseline gated; do
    ( cd sweep && vvp "$v.vvp" > "$v.log" 2>&1 || true
      mv fullchip_tb.vcd "$v.vcd" )
    n=$(cd sweep && paste <(grep "Actual=" $v.log | sed 's/.*Actual= *//') \
                          <(grep "Pred Norm=" $v.log | sed 's/.*Pred Norm= *//') \
        | awk -F'\t' '{if($1!=$2) b++} END{print b+0}')
    [ "$n" = "0" ] || ok="FAIL($v:$n)"
  done

  # Totals are extracted numerically and the ratio computed here, rather than
  # scraped from the report text.
  stat() {
    python3 vcd_activity.py sweep/baseline.vcd --compare sweep/gated.vcd \
        --scope "$1" --common 2>/dev/null \
      | awk '/^A /{gsub(/,/,"",$3); a=$3} /^B /{gsub(/,/,"",$3); b=$3}
             END{ printf "%d %d %.4f", a, b, (a?b/a:0) }'
  }
  read -r ca cb cr <<<"$(stat $DUT)"
  read -r aa ab ar <<<"$(stat $ARRAY)"
  printf "%-9s %12d %12d %7.4f  %12d %12d %7.4f  %s\n" \
    "$s" "$ca" "$cb" "$cr" "$aa" "$ab" "$ar" "$ok"
done
