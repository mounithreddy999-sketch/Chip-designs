SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# RTL source files
VERILOG_SOURCES += $(PWD)/../rtl/mx_pe.v
VERILOG_SOURCES += $(PWD)/../rtl/mx_systolic_mesh.v
VERILOG_SOURCES += $(PWD)/../rtl/scratchpad_sram.v
VERILOG_SOURCES += $(PWD)/../rtl/mx_pwl_exp.v
VERILOG_SOURCES += $(PWD)/../rtl/mx_pwl_recip.v
VERILOG_SOURCES += $(PWD)/../rtl/mx_softmax_unit.v
VERILOG_SOURCES += $(PWD)/../rtl/mx_attention_core.v

# Top-level module name inside RTL
TOPLEVEL = mx_attention_core

# Name of the python testbench file (without .py)
MODULE = tb_mx_attention_core

include $(shell cocotb-config --makefiles)/Makefile.sim
