# Hardware Design Workspace Rules

These guidelines define the implementation and verification standards for all digital design modules developed in this repository.

## 1. Design & Precision Standards
* **Data Formats**:
  * For neural network weights, default to **INT4** signed packed format or **INT8** signed precision.
  * For intermediate sums and products, use sufficient bit widths (e.g., 10-bit sums for INT4 vector dot products, 16-bit/24-bit for accumulators) to prevent premature overflow prior to saturation checks.
* **Module Features**:
  * Every module must support synchronous, active-high reset (`rst`).
  * Enable/Clock-enable lines (`en`) must gate register updates.
  * Saturated output clamping must be implemented on all arithmetic outputs to prevent dynamic range expansion.
* **Coding Quality**:
  * Use strictly synthesizable Verilog HDL.
  * Avoid any sequential loops (like `for` loops with variable iteration counts) inside synthesizable code; restrict loops to compile-time parameter calculations or generate blocks.

## 2. Verification Standards
* **Self-Checking Testbenches**:
  * All new modules must be verified using a self-checking testbench.
  * Assertions or conditional checks must explicitly verify reset conditions, nominal math cases, boundary conditions, and overflow/underflow saturation limits.
* **Test Runners & Frameworks**:
  * Testbenches must compile and execute cleanly using **Icarus Verilog** (`iverilog` compiler and `vvp` runner).
  * In future expansions, Python-based testbenches utilizing `cocotb` can be integrated alongside native Verilog self-checking suites.
* **Regression Testing**:
  * The regression simulation runner script `sim/run_sim.py` must be updated to compile and verify all testbenches whenever a new component is introduced.
