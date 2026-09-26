# 100 MHz, matching the 10 ns period used in the ASIC constraints so the two
# flows are at least nominally comparable.
create_clock -name clk  -period 10.000 [get_ports clk]

# Core 2's clock. Declared asynchronous to clk so the tool does not try to time
# the gray-pointer crossings in async_gray_fifo as single-cycle paths.
create_clock -name clk2 -period 10.000 [get_ports clk2]
set_clock_groups -asynchronous -group {clk} -group {clk2}

derive_clock_uncertainty

# reset is asserted asynchronously by the testbench and held for many cycles.
set_false_path -from [get_ports reset]

# Virtual pins carry no board-level timing meaning.
set_false_path -from [get_ports {mem_in_1[*] mem_in_2[*] inst[*] skip_thresh[*]}]
set_false_path -to   [get_ports {pmem_out_1[*] pmem_out_2[*] sfp_out_1[*] sfp_out_2[*] div_done_1 div_done_2}]
