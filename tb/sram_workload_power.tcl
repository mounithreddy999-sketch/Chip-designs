# VCD-driven power for sram_pim_macro (near-memory) — run inside OpenROAD.
#   openroad -exit tb/sram_workload_power.tcl
#
# PDN insertion is NOT needed for a power number: report_power needs only the
# netlist, the cell + SRAM .lib power tables, and switching activity (VCD).
# We read the furthest stage that completed (floorplan) since PDN blocked routing.
# This yields a pre-route ESTIMATE; the SRAM macro power (the dominant term)
# comes straight from its .lib regardless, so it is sound for the frontier.

set PDK  $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd
set SRAM /work/.pdk/sky130A/libs.ref/sky130_sram_macros
set RUN  openlane/sram_pim_macro/runs/RUN_SRAM

read_lef     $PDK/techlef/sky130_fd_sc_hd__nom.tlef
read_lef     $PDK/lef/sky130_fd_sc_hd.lef
read_lef     $SRAM/lef/sky130_sram_1kbyte_1rw1r_32x256_8.lef

read_liberty $PDK/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_liberty $SRAM/lib/sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib

# Furthest completed stage. If floorplan .odb is unavailable, fall back to the
# synthesis netlist:  read_verilog $RUN/results/synthesis/sram_pim_macro.v ; link_design sram_pim_macro
read_verilog $RUN/results/synthesis/sram_pim_macro.v
link_design sram_pim_macro
create_clock -name clk -period 10.0 [get_ports clk]

# Map the steady-state inference activity onto the netlist.
read_power_activities -vcd tb_sram_pim_macro_workload.vcd -scope tb_sram_pim_macro_workload/dut

report_power
# Total dynamic power here -> feed to the scorecard with --macs-per-cycle 4:
#   python sw/ppa_scorecard.py --n 16 --freq 100e6 --power <W> --area 0.602 --macs-per-cycle 4
