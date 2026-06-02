.PHONY: all generic_4 generic_8 ice40_4 sky130 pdk report clean

all: generic_4 generic_8 ice40_4 sky130 report

# Download Sky130 PDK Liberty cell library
pdk:
	mkdir -p pdk
	@if [ ! -f pdk/sky130_fd_sc_hd__tt_025C_1v80.lib ]; then \
		echo "Downloading Sky130 Typical Liberty cell library..."; \
		curl -sLo pdk/sky130_fd_sc_hd__tt_025C_1v80.lib https://raw.githubusercontent.com/praharshapm/vsdmixedsignalflow/master/LIB/sky130_fd_sc_hd__tt_025C_1v80.lib; \
	else \
		echo "Sky130 liberty cell library already exists."; \
	fi

# Sky130 Standard Cell ASIC synthesis for N=4
sky130: out pdk
	yosys -s synth_sky130.ys -l out/yosys_sky130.log

# Create output directory
out:
	mkdir -p out

RTL_FILES = ../rtl/mx_pe.v ../rtl/mx_systolic_mesh.v ../rtl/scratchpad_sram.v ../rtl/mx_pwl_exp.v ../rtl/mx_pwl_recip.v ../rtl/mx_softmax_unit.v ../rtl/mx_attention_core.v
READ_CMD = $(foreach file,$(RTL_FILES),read_verilog -sv $(file);)

# Generic gate-level synthesis for N=4
generic_4: out
	yosys -p '$(READ_CMD) hierarchy -top mx_attention_core -chparam N 4; synth -top mx_attention_core; check; tee -o out/report_generic_4.txt stat; write_verilog -noattr out/mx_attention_core_generic_4.v' -l out/yosys_generic_4.log

# Generic gate-level synthesis for N=8 (Scaled)
generic_8: out
	yosys -p '$(READ_CMD) hierarchy -top mx_attention_core -chparam N 8; synth -top mx_attention_core; check; tee -o out/report_generic_8.txt stat; write_verilog -noattr out/mx_attention_core_generic_8.v' -l out/yosys_generic_8.log

# iCE40 FPGA mapping for N=4
ice40_4: out
	yosys -p '$(READ_CMD) hierarchy -top mx_attention_core -chparam N 4; synth_ice40 -top mx_attention_core -device hx; check; tee -o out/report_ice40_4.txt stat; write_verilog -noattr out/mx_attention_core_ice40_4.v' -l out/yosys_ice40_4.log

CGRA_RTL_FILES = ../rtl/cgra_pe.v ../rtl/cgra_mesh.v ../rtl/cgra_sequencer.v ../rtl/cgra_top.v
CGRA_READ_CMD = $(foreach file,$(CGRA_RTL_FILES),read_verilog -sv -D SYNTHESIS $(file);)

cgra_top_generic: out
	yosys -p '$(CGRA_READ_CMD) hierarchy -top cgra_top -chparam ROWS 4 -chparam COLS 4; synth -top cgra_top; check; tee -o out/report_cgra_top_generic.txt stat; write_verilog -noattr out/cgra_top_generic.v' -l out/yosys_cgra_top_generic.log

cgra_top_sky130: out pdk
	yosys -p '$(CGRA_READ_CMD) hierarchy -top cgra_top -chparam ROWS 4 -chparam COLS 4; synth -top cgra_top; dfflibmap -liberty pdk/sky130_fd_sc_hd__tt_025C_1v80.lib; abc -liberty pdk/sky130_fd_sc_hd__tt_025C_1v80.lib; clean; tee -o out/report_cgra_top_sky130.txt stat; write_verilog -noattr out/cgra_top_sky130.v' -l out/yosys_cgra_top_sky130.log

# Generate consolidated comparative markdown report
report:
	python3 gen_report.py

clean:
	rm -rf out
