# Graph Report - C:/Users/mouni/Documents/GitHub/My-Chips  (2026-06-04)

## Corpus Check
- Large corpus: 1217 files � ~242,492,695 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder.

## Summary
- 284 nodes · 288 edges · 88 communities (77 shown, 11 thin omitted)
- Extraction: 80% EXTRACTED · 20% INFERRED · 0% AMBIGUOUS · INFERRED: 59 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Digital MAC  Pareto Frontier|Digital MAC / Pareto Frontier]]
- [[_COMMUNITY_CGRA Python Driver|CGRA Python Driver]]
- [[_COMMUNITY_MX Reference Models (cocotb)|MX Reference Models (cocotb)]]
- [[_COMMUNITY_Attention SoC Pipeline|Attention SoC Pipeline]]
- [[_COMMUNITY_PPA Scorecard|PPA Scorecard]]
- [[_COMMUNITY_CGRA Assembler  Driver|CGRA Assembler / Driver]]
- [[_COMMUNITY_Synthesis Report Parser|Synthesis Report Parser]]
- [[_COMMUNITY_Analog CIM Crossbar|Analog CIM Crossbar]]
- [[_COMMUNITY_Firmware Encoder (Go)|Firmware Encoder (Go)]]
- [[_COMMUNITY_CGRA RTL Fabric|CGRA RTL Fabric]]
- [[_COMMUNITY_CGRA Go Compiler|CGRA Go Compiler]]
- [[_COMMUNITY_Analog Sense-Amp  Offset|Analog Sense-Amp / Offset]]
- [[_COMMUNITY_Sim Regression Runner|Sim Regression Runner]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 82|Community 82]]
- [[_COMMUNITY_Community 83|Community 83]]
- [[_COMMUNITY_Community 84|Community 84]]
- [[_COMMUNITY_Community 86|Community 86]]
- [[_COMMUNITY_Community 87|Community 87]]

## God Nodes (most connected - your core abstractions)
1. `CGRADriver` - 11 edges
2. `Analog CIM Cell (current-steering MAC)` - 10 edges
3. `ppa_metrics()` - 9 edges
4. `Pipelined PIM Matmul Macro` - 9 edges
5. `GenerateFirmware()` - 8 edges
6. `test_mx_attention_core()` - 7 edges
7. `SoC Top` - 7 edges
8. `Verified Pareto Frontier` - 7 edges
9. `CGRAAssembler` - 6 edges
10. `generate_report()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Pipelined PIM Matmul Macro` --semantically_similar_to--> `Analog CIM Cell (current-steering MAC)`  [INFERRED] [semantically similar]
  rtl/pim_matmul_macro.v → rtl/analog_cim/cim_cell.spice
- `Flop Baseline (CG=0, 2.04 pJ/MAC)` --references--> `Pipelined PIM Matmul Macro`  [INFERRED]
  docs/PPA_RESULTS.md → rtl/pim_matmul_macro.v
- `Near-Memory Streaming Macro` --semantically_similar_to--> `Analog CIM Cell (current-steering MAC)`  [INFERRED] [semantically similar]
  rtl/sram_pim_macro.v → rtl/analog_cim/cim_cell.spice
- `CIM Crossbar Generator` --references--> `Analog CIM Cell (current-steering MAC)`  [INFERRED]
  sw/gen_cim_array.py → rtl/analog_cim/cim_cell.spice
- `Frontier Plot Generator` --references--> `Verified Pareto Frontier`  [INFERRED]
  sw/plot_frontier.py → docs/PPA_RESULTS.md

## Communities (88 total, 11 thin omitted)

### Community 0 - "Digital MAC / Pareto Frontier"
Cohesion: 0.11
Nodes (20): activation_unit, Batched Near-Memory (B=4, 0.602 mm2), Integrated Clock Gate, Clock-Gated Variant (CG=1, 1.28 pJ/MAC), INT4 Vector Dot-Product PE, Flop Baseline (CG=0, 2.04 pJ/MAC), Parameterized Signed MAC, Microscaling PE (MXFP4/8) (+12 more)

### Community 1 - "CGRA Python Driver"
Cohesion: 0.11
Nodes (10): CGRADriver, Stops running execution., Returns the current boundary outputs of the mesh., Asserts active-high reset for 2 clock cycles and cleans up control signals., Writes a single 64-bit microcode word to the sequencer memory., program: List of up to 32 64-bit integers., Sets values on boundary data ports of the mesh., Triggers a single-step execution and waits for execution cycle to finish. (+2 more)

### Community 2 - "MX Reference Models (cocotb)"
Cohesion: 0.24
Nodes (15): decode_e2m1(), decode_e4m3(), decode_e5m2(), matmul(), mx_pwl_exp_ref(), mx_pwl_recip_ref(), mx_softmax_unit_ref(), pack_word() (+7 more)

### Community 3 - "Attention SoC Pipeline"
Cohesion: 0.15
Nodes (16): Hybrid Attention Coprocessor, Transformer Firmware Driver, MX Attention Core, PWL Exponential, PWL Reciprocal, Softmax MMIO Wrapper, Row-wise Softmax Unit, MX Systolic Mesh (+8 more)

### Community 4 - "PPA Scorecard"
Cohesion: 0.27
Nodes (10): format_scorecard(), main(), ppa_metrics(), Return PPA metrics for an MVM macro.      Args:         n: array dimension (NxN), test_invalid_inputs_raise(), test_invalid_macs_per_cycle_raises(), test_known_values_n16_int8(), test_ops_per_mac_one_halves_tops() (+2 more)

### Community 5 - "CGRA Assembler / Driver"
Cohesion: 0.23
Nodes (6): CGRAAssembler, CGRADriver, CGRAAssembler, main(), Test full programming and execution flow of CGRA via driver, test_cgra_driver_app()

### Community 6 - "Synthesis Report Parser"
Cohesion: 0.31
Nodes (10): count_brams(), count_carries(), count_ffs(), count_luts(), generate_report(), main(), parse_sky130_report(), parse_stat_file() (+2 more)

### Community 8 - "Firmware Encoder (Go)"
Cohesion: 0.38
Nodes (9): encodeAddi(), encodeAndi(), encodeBne(), encodeJal(), encodeLui(), encodeLw(), encodeSw(), GenerateFirmware() (+1 more)

### Community 9 - "CGRA RTL Fabric"
Cohesion: 0.31
Nodes (6): cgra_mesh, CGRA MMIO Bridge, cgra_pe, cgra_sequencer, CGRA Top, CGRA Go Compiler

### Community 10 - "CGRA Go Compiler"
Cohesion: 0.22
Nodes (6): Instruction, Layer, main(), MapToCGRA(), Model, ParseModel()

### Community 11 - "Analog Sense-Amp / Offset"
Cohesion: 0.28
Nodes (5): Analog CIM Device Study, Passive Column-Height Limit (~9 rows), StrongARM Monte-Carlo Offset, StrongARM w/ Mismatch Injection, strongarm_comparator

### Community 12 - "Sim Regression Runner"
Cohesion: 0.53
Nodes (5): main(), Run Yosys synthesis + structural check on a set of RTL files.     Returns True i, run_cocotb_test(), run_synth_check(), run_test()

### Community 14 - "Community 14"
Cohesion: 0.33
Nodes (6): tb_pim_matmul_macro, tb_pim_matmul_macro_workload, tb_sram_pim_batched_macro, tb_sram_pim_batched_macro_workload, tb_sram_pim_macro, tb_sram_pim_macro_workload

### Community 15 - "Community 15"
Cohesion: 0.60
Nodes (5): mx_pwl_exp_ref(), mx_pwl_recip_ref(), mx_softmax_unit_ref(), reset_dut(), test_mx_softmax_unit()

### Community 16 - "Community 16"
Cohesion: 0.60
Nodes (4): interp_cross(), main(), One sample: effective input = vdiff - voff (offset folded into Vinn). True = OUT, resolve()

### Community 17 - "Community 17"
Cohesion: 0.70
Nodes (4): esc(), main(), mx(), my()

### Community 18 - "Community 18"
Cohesion: 0.83
Nodes (3): build(), main(), run_docker()

### Community 19 - "Community 19"
Cohesion: 0.67
Nodes (3): main(), Patch the activation amplitude, run ngspice in Docker, return (E_joules, Vdiff)., run_one()

### Community 23 - "Community 23"
Cohesion: 0.67
Nodes (3): tb_mx_attention_core (py), tb_mx_attention_core (v), tb_mx_softmax_unit (py)

### Community 24 - "Community 24"
Cohesion: 0.67
Nodes (3): tb_pim_crossbar, tb_pim_neural_layer, tb_systolic_array

## Knowledge Gaps
- **29 isolated node(s):** `Instruction`, `Model`, `Layer`, `Softmax MMIO Wrapper`, `PWL Exponential` (+24 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Pipelined PIM Matmul Macro` connect `Digital MAC / Pareto Frontier` to `Attention SoC Pipeline`, `Analog CIM Crossbar`?**
  _High betweenness centrality (0.038) - this node is a cross-community bridge._
- **Why does `Analog CIM Cell (current-steering MAC)` connect `Analog CIM Crossbar` to `Digital MAC / Pareto Frontier`, `Analog Sense-Amp / Offset`?**
  _High betweenness centrality (0.029) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `Analog CIM Cell (current-steering MAC)` (e.g. with `Pipelined PIM Matmul Macro` and `Near-Memory Streaming Macro`) actually correct?**
  _`Analog CIM Cell (current-steering MAC)` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `ppa_metrics()` (e.g. with `test_known_values_n16_int8()` and `test_ops_per_mac_one_halves_tops()`) actually correct?**
  _`ppa_metrics()` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `Pipelined PIM Matmul Macro` (e.g. with `Microscaling PE (MXFP4/8)` and `Parameterized Signed MAC`) actually correct?**
  _`Pipelined PIM Matmul Macro` has 6 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Run Yosys synthesis + structural check on a set of RTL files.     Returns True i`, `dut: Top-level cocotb testbench instance.              Expected to have standard`, `Asserts active-high reset for 2 clock cycles and cleans up control signals.` to the rest of the system?**
  _47 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Digital MAC / Pareto Frontier` be split into smaller, more focused modules?**
  _Cohesion score 0.11255411255411256 - nodes in this community are weakly interconnected._