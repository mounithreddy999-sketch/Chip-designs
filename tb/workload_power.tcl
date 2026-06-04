# VCD-driven power for pim_matmul_macro — run inside OpenROAD.
#   openroad -exit tb/workload_power.tcl
# Edit the paths to your PDK and the OpenLane run you want to measure.
#
# Two accuracy tiers:
#   (1) Quick   : read the post-PnR .odb below + this RTL VCD (name-mapped).
#   (2) Rigorous: gate-level simulate the synthesized netlist with
#                 tb_pim_matmul_macro_workload.v to produce a netlist-level VCD,
#                 then read THAT here. Cell-accurate clock-tree activity.

set PDK   $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd
set RUN   openlane/pim_matmul_macro_cg/runs/RUN_CG

read_lef     $PDK/techlef/sky130_fd_sc_hd__nom.tlef
read_lef     $PDK/lef/sky130_fd_sc_hd.lef
read_liberty $PDK/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db      $RUN/results/cts/pim_matmul_macro.odb
create_clock -name clk -period 10.0 [get_ports clk]

# Map the captured inference-phase activity onto the netlist.
read_power_activities -vcd cg.vcd -scope tb_pim_matmul_macro_workload/dut

report_power
# Compare the "Sequential" + "Clock" rows between the baseline run and the
# CG run: that delta is the clock-gating win on the stationary weight flops.
