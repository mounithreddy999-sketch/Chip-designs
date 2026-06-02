# Workflow: Agentic Build and Verify Flow
# Description: Executes a rigorous 5-step hardware design and verification loop.

Follow this sequence strictly to implement my hardware requirements:

1. **Discover**: Run ls -R and cat to discover and read all pre-existing files and module dependencies in the workspace.
2. **Plan**: Write out an explicit implementation plan in markdown justifying all intended Verilog edits before modifying any file.        
3. **Apply**: Implement only the planned changes inside the synthesizable Verilog modules.
4. **Verify**: Run the local diagnostics toolchain sequentially in the terminal:
    - Compile and lint using iverilog.
    - Perform cycle-accurate semantic linting using Verilator to catch race conditions or timing anomalies.
    - Synthesize using Yosys for structural gate-level checks.
    - Run Cocotb testbenches via make SIM=verilator to verify functional correctness in Python.
5. **Complete**: Call the complete-task command only when all verification steps compile and pass with zero structural or timing errors.  
