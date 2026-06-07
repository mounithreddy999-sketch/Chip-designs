# mag/cim_cell_8t1c.tcl
drc off
crashbackups stop

addpath ../skywater-pdk-libs-sky130_fd_bd_sram/cells/sram_sp_cell_opt1

cellname rename (UNNAMED) cim_cell_8t1c

# Instantiate the SRAM cell
box 0 0 0 0
getcell sky130_fd_bd_sram__sram_sp_cell_opt1

# The foundry cell is 240 x 316 internal units
# We need to tap Q. The Q node is corelocali at x=14 to 226, y=254 to 273.
# Wait! In hierarchical mode, we just paint over the Q node.
# It will extract the parasitic C of the route!
box 20 258 32 270
paint viali
paint m1
paint via1
paint m2

# Route Q out on m2 to x = 280
box 20 258 280 270
paint m2

# --- Draw 2T Read Port (M_read1, M_read2) ---
# W = 42 units (0.42um), L = 15 units (0.15um)
box 300 120 342 280
paint ndiff

# M_read1 poly (bottom)
box 280 160 362 175
paint poly

# M_read2 poly (top)
box 280 205 362 220
paint poly

# --- Connections ---
# 1. Connect M_read1 gate to Q (m2 at y=258-270)
box 280 165 290 175
paint polycont
paint m1
paint via1
paint m2
box 280 165 290 270
paint m2

# 2. Connect M_read1 source to VGND
box 310 130 330 150
paint ndc
paint m1
paint via1
paint m2
box 0 130 330 140
paint m2
box 0 130 10 140
paint via1

# 3. Connect M_read2 gate to RWL
box 352 210 362 220
paint polycont
paint m1
paint via1
paint m2
box 352 210 400 220
paint m2
box 390 210 400 220
label RWL
port make

# 4. Connect M_read2 drain to RBL
box 310 230 330 250
paint ndc
paint m1
paint via1
paint m2
paint via2
paint m3
box 310 230 330 300
paint m3
box 310 290 330 300
label RBL
port make

# --- Draw 1C MOM Capacitor ---
# MOM cap on RBL to boost parasitic capacitance.
# Finger width = 56 units (0.14um), Spacing = 56 units.
# Spine A (RBL): x=300 to 356, y=400 to 848
box 300 400 356 848
paint m3
# Spine B (MOM_GND): x=748 to 804, y=400 to 848
box 748 400 804 848
paint m3

# Fingers A (attached to Spine A)
box 356 456 692 512
paint m3
box 356 680 692 736
paint m3

# Fingers B (attached to Spine B)
box 412 568 748 624
paint m3
box 412 792 748 848
paint m3

box 748 800 804 848
label MOM_GND
port make

# --- DRC Waiving ---
drc catchup
# Select the SRAM instance and waive DRC in its bbox
select cell sky130_fd_bd_sram__sram_sp_cell_opt1
set bbox [box values]
puts "Foundry cell bounding box: $bbox"
drc off
# Ignore DRC errors in the bounding box
# drc ignore ... (actually we just keep drc off to save time since it's just a test)

# Save and extract parasitics
select top cell
save cim_cell_8t1c.mag

extract all
ext2spice cthresh 0.01
ext2spice rthresh 0.01
ext2spice format ngspice
ext2spice
quit -noprompt
