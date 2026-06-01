# Chip-designs

A custom, from-scratch hardware design repository for developing high-performance AI accelerator blocks and processor components.

This repository is built completely from the ground up, containing custom modular arithmetic hardware, self-checking testbenches, and automation setups.

## Repository Directory Layout

* **`rtl/`**: Register-Transfer Level (RTL) synthesizable Verilog modules.
  * [mac.v](file:///c:/Users/mouni/Documents/GitHub/My-Chips/rtl/mac.v): Parameterized 8-bit signed Multiply-Accumulate unit with saturation limits and overflow/underflow flags.
* **`tb/`**: Native Verilog verification testbenches.
  * [tb_mac.v](file:///c:/Users/mouni/Documents/GitHub/My-Chips/tb/tb_mac.v): Self-checking testbench driving clock generator, loading values, and running validation assertions.
* **`sim/`**: Scripts and automation configurations for simulation.
  * [run_sim.py](file:///c:/Users/mouni/Documents/GitHub/My-Chips/sim/run_sim.py): Lightweight python runner to automate compiling and executing local simulations using Icarus Verilog.

---

## 1. Multiply-Accumulate (MAC) Module

The first core block in our processor design is the `mac` unit, representing the mathematical engine used in artificial neural network accelerators.

### Mathematical Equation
$$\text{acc} \leftarrow \text{acc} + (a \times b)$$
* **Input precision**: Parameterized signed integers (default: 8-bit).
* **Accumulator width**: Parameterized signed integer register (default: 24-bit).

### Features
* **Active-High Synchronous Reset (`rst`)**: Clears the accumulator and status flags.
* **Clock Enable (`en`)**: Powers down register clock updates when low.
* **Data Valid (`valid_in`)**: Toggles the multiplication and addition step.
* **Direct Accumulator Clear (`clear_acc`)**: Resets the accumulator register independently without resetting control lines.
* **Hard Saturation**:
  * Clamps upper accumulations exceeding $+8,388,607$ (`24'sh7FFFFF`) and locks the `overflow` status bit.
  * Clamps lower accumulations falling below $-8,388,608$ (`24'sh800000`) and locks the `underflow` status bit.

---

## 2. Running Simulations Locally

### Prerequisites
Ensure you have **Icarus Verilog** (`iverilog` and `vvp`) installed on your system.

### Command Execution
To run the automated test suite simulation:
```powershell
python sim/run_sim.py
```

### Manual Compilation
If you prefer running commands manually:
```powershell
# Compile the design & testbench
iverilog -o sim/mac_tb.vvp rtl/mac.v tb/tb_mac.v

# Run the simulation executable
vvp sim/mac_tb.vvp
```
To view the simulation waveforms, open the generated dump file `tb_mac.vcd` using **GTKWave**:
```powershell
gtkwave tb_mac.vcd
```
