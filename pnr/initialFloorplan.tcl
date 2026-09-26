# Floorplan
floorPlan -site core -r 1 0.40 50.0 50.0 50.0 50.0

timeDesign -preplace -prefix preplace

globalNetConnect VDD -type pgpin -pin VDD -inst * -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -verbose

addRing -spacing {top 20 bottom 20 left 20 right 20} -width {top 10 bottom 10 left 10 right 10}  -layer {top M1 bottom M1 left M2 right M2} -center 1 -type core_rings -nets {VSS  VDD}

setAddStripeMode -break_at {block_ring}

### Note: Change the number of strip  by looking at the layout #########
#addStripe -number_of_sets 10  -spacing 6 -layer M6 -width 4 -nets { VSS VDD }
#################################################

#addStripe -nets {VDD VSS} -layer M4 -direction vertical -width 1.8 -spacing 1.8 -number_of_sets 5 -start_from left -start 80 -stop 180 

#setDrawView fplan


setObjFPlanBox Instance core_instance/kmem_instance 90.91 222.2185 181.11 862.0185
selectInst core_instance/kmem_instance
flipOrRotateObject -rotate R90
deselectAll

setObjFPlanBox Instance core_instance/qmem_instance 235.675 221.5165 325.875 861.3165
selectInst core_instance/qmem_instance
flipOrRotateObject -rotate R90
deselectAll

setObjFPlanBox Instance core_instance/psum_mem_instance 178.5855 76.759 818.3855 166.959
selectInst core_instance/psum_mem_instance
flipOrRotateObject -flip MX
flipOrRotateObject -flip MY

addHaloToBlock 20 20 20 20 core_instance/psum_mem_instance
addHaloToBlock 20 20 20 20 core_instance/kmem_instance
addHaloToBlock 20 20 20 20 core_instance/qmem_instance

addRing -nets {VDD VSS} -type block_rings -around each_block -layer {top M1 bottom M1 left M2 right M2} -width {top 4 bottom 4 left 4 right 4} -spacing {top 2 bottom 2 left 2 right 2} 


globalNetConnect VDD -type pgpin -pin VDD -sinst core_instance/psum_mem_instance -verbose -override
globalNetConnect VSS -type pgpin -pin VSS -sinst core_instance/psum_mem_instance -verbose -override        
globalNetConnect VDD -type pgpin -pin VDD -sinst core_instance/kmem_instance -verbose -override
globalNetConnect VSS -type pgpin -pin VSS -sinst core_instance/kmem_instance -verbose -override        
globalNetConnect VDD -type pgpin -pin VDD -sinst core_instance/qmem_instance -verbose -override
globalNetConnect VSS -type pgpin -pin VSS -sinst core_instance/qmem_instance -verbose -override        

addStripe -number_of_sets 10  -spacing 6 -layer M6 -width 4 -nets { VSS VDD }

sroute


