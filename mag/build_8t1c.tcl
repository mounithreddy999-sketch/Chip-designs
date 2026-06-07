# mag/cim_cell_8t1c.tcl
drc off
crashbackups stop

addpath ../skywater-pdk-libs-sky130_fd_bd_sram/cells/sram_sp_cell_opt1

# Create a new top-level cell
cellname rename (UNNAMED) cim_cell_8t1c

# Set box to origin and getcell
box 0 0 0 0
getcell sky130_fd_bd_sram__sram_sp_cell_opt1

# Select the instance we just placed
select cell sky130_fd_bd_sram__sram_sp_cell_opt1

# Get bounding box of the instance
set bbox [box values]
puts "Bounding box of foundry cell: $bbox"

# Push into the instance to see its labels
pushbox
set labels [dump labels]
puts "Internal labels inside the macro: $labels"

goto Q
set q_box [box values]
puts "Q node box: $q_box"

goto Q_bar
set qbar_box [box values]
puts "Q_bar node box: $qbar_box"

popbox

quit -noprompt
