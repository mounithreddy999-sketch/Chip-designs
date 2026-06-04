# VCD-driven power for sram_pim_batched_macro (near-memory mid-frontier).
# run inside OpenROAD: openroad -exit tb/sbm_workload_power.tcl

set PDK  $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd
set SRAM /work/.pdk/sky130A/libs.ref/sky130_sram_macros
set RUN  openlane/sram_pim_batched_macro/runs/RUN_SBM

read_lef     $PDK/techlef/sky130_fd_sc_hd__nom.tlef
read_lef     $PDK/lef/sky130_fd_sc_hd.lef
read_lef     $SRAM/lef/sky130_sram_1kbyte_1rw1r_32x256_8.lef

read_liberty $PDK/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_liberty $SRAM/lib/sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib

read_verilog $RUN/results/synthesis/sram_pim_batched_macro.v
link_design sram_pim_batched_macro
create_clock -name clk -period 10.0 [get_ports clk]

read_power_activities -vcd tb_sram_pim_batched_macro_workload.vcd -scope tb_sram_pim_batched_macro_workload/dut
report_power
