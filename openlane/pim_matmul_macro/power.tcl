read_lef /work/.pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
read_lef /work/.pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef
read_liberty /work/.pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db /work/openlane/pim_matmul_macro/runs/pipelined_isolated/results/cts/pim_matmul_macro.odb
create_clock -name clk -period 10.0 [get_ports clk]
report_power
exit
