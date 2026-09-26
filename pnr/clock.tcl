# Clock tree synthesis 
set_ccopt_property -update_io_latency false
create_ccopt_clock_tree_spec -file ./constraints/$design.ccopt
ccopt_design

# Use actual clock network
set_propagated_clock [all_clocks]

# Post-CTS timing optimization
optDesign -postCTS -hold

addFiller -cell {DCAP DCAP4 DCAP8 DCAP16 DCAP32} -merge true


saveDesign cts.enc
