# mag/generate_gds.tcl
drc off
crashbackups stop

addpath ../skywater-pdk-libs-sky130_fd_bd_sram/cells/sram_sp_cell_opt1
load cim_cell_8t1c.mag

# Ensure all cells are expanded before writing GDS
expand

# Set GDS options
gds flatten yes
gds merge yes

# Write the GDS to the tapeout directory
gds write ../tapeout/cim_cell_8t1c.gds

quit -noprompt
