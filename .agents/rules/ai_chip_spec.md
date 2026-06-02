# Workspace Rule: AI Accelerator Spec
# Activation: Always On

## Architectural Guidelines
- **Architecture Type**: Systolic Array. Design a 2D mesh of Processing Elements (PEs) working cooperatively to handle matrix-matrix multiplication (^\top$).
- **Numeric Precision**: Quantize weights using Microscaling (**MXFP8** or **MXINT4**) formats with a shared exponent across vector blocks of 32 or 64 elements. This reduces hardware Multiplier-Accumulator (MAC) area by up to 40%.
- **Memory Wall Mitigation**: Implement on-chip scratchpad SRAM memory with tiled data pathways (FlashAttention-4 style) to compute attention scores in small, local blocks and bypass external memory bandwidth limits.
- **Dataflow Strategy**: Optimize for weight-stationary or output-stationary configurations dynamically.

## Implementation Constraints
- Never write sequential software logic inside Verilog blocks; hardware design must remain concurrent and parallel.
- Any edits to a Verilog module must have a corresponding test case update in the Python Cocotb testbench.
