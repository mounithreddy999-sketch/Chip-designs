# mag/cim_cell_8t1c.tcl
drc off
crashbackups stop

addpath ../skywater-pdk-libs-sky130_fd_bd_sram/cells/sram_sp_cell_opt1

cellname rename (UNNAMED) test_extract

# Instantiate the SRAM cell
box 0 0 0 0
getcell sky130_fd_bd_sram__sram_sp_cell_opt1

# Find Q node in the subcell
select cell sky130_fd_bd_sram__sram_sp_cell_opt1
# Flatten the subcell!
flatten test_extract_flat
load test_extract_flat
select top cell

# Now it is flat. I can find the label Q.
goto Q
# Paint M1 to simulate a connection
paint m1
label Q_read

extract all
ext2spice cthresh 0.01
ext2spice
quit -noprompt
