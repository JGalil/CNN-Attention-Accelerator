SHELL := /bin/bash

# Licence-free functional + activity flow: Icarus Verilog for simulation,
# vcd_activity.py for switching activity. No Synopsys, Cadence or Quartus
# licence is needed for anything in this file.
#
#   make sim        run the final (gated) design, check against the TB model
#   make baseline   run the ungated variant
#   make compare    A/B the switching activity of the two, like-for-like
#   make clean

IVERILOG ?= iverilog
VVP      ?= vvp
PY       ?= python3

TB      := ../tb/fullchip_tb.v
DATA    := $(wildcard ../tb/data/*.txt)
RTL     := $(wildcard ../rtl/*.v)

# The ungated variant swaps in the pre-optimisation mac_col / mac_8in, which
# declare the same module names, so they drop straight in.
RTL_BASE := $(filter-out ../rtl/mac_col.v ../rtl/mac_8in.v,$(RTL)) \
            ../rtl/experimental/mac_col_baseline.v \
            ../rtl/experimental/mac_8in_baseline.v

DUT := fullchip_tb.fullchip_instance

.PHONY: all sim baseline compare vcd clean
all: sim

define build
	@mkdir -p $(1)
	@cp $(DATA) $(1)/
	$(IVERILOG) -g2012 -o $(1)/tb.vvp -s fullchip_tb $(TB) $(2)
	@cd $(1) && $(VVP) tb.vvp > run.log 2>&1 || true
	@# The testbench prints an "Actual" and a "Pred Norm" line per cycle per
	@# core; they must agree or the optimisation broke functionality.
	@cd $(1) && paste <(grep "Actual=" run.log | sed 's/.*Actual= *//') \
	                  <(grep "Pred Norm=" run.log | sed 's/.*Pred Norm= *//') \
	   | awk -F'\t' 'BEGIN{n=0}{n++; if($$1!=$$2) bad++} \
	       END{ if(bad) {printf "  FAIL: %d/%d mismatched\n", bad, n; exit 1} \
	            else     printf "  PASS: %d/%d result vectors match\n", n, n }'
endef

sim:
	@echo "== gated (rtl/ as shipped)"
	$(call build,build_gated,$(RTL))

baseline:
	@echo "== ungated baseline"
	$(call build,build_baseline,$(RTL_BASE))

vcd: sim
	@mkdir -p build && cp build_gated/fullchip_tb.vcd build/fullchip.vcd
	@echo "build/fullchip.vcd ready for Quartus power analysis"

compare: sim baseline
	@echo
	@echo "=============== whole chip, shared nets only ==============="
	@$(PY) vcd_activity.py build_baseline/fullchip_tb.vcd \
	    --compare build_gated/fullchip_tb.vcd --scope $(DUT) --common --top 6
	@echo
	@echo "=============== MAC array (core 1) ========================="
	@$(PY) vcd_activity.py build_baseline/fullchip_tb.vcd \
	    --compare build_gated/fullchip_tb.vcd \
	    --scope $(DUT).core_instance1.mac_array_instance --common --top 6

clean:
	rm -rf build build_gated build_baseline
