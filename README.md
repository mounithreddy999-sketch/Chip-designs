# Chip-designs

A custom, from-scratch hardware design repository for developing high-performance AI accelerator blocks and processor components.

This repository is built completely from the ground up, containing custom modular arithmetic hardware, self-checking testbenches, and automation setups.

## Repository Directory Layout

* **`rtl/`**: Register-Transfer Level (RTL) synthesizable Verilog modules.
  * [mac.v](file:///c:/Users/mouni/Documents/GitHub/My-Chips/rtl/mac.v): Parameterized signed Multiply-Accumulate unit with saturation limits and overflow/underflow flags.
  * [dot_product_pe.v](file:///c:/Users/mouni/Documents/GitHub/My-Chips/rtl/dot_product_pe.v): INT4 (4-bit signed) Vector Dot Product Processing Element (PE) with saturation and status registers.
  * [cgra_pe.v](file:///c:/Users/mouni/Documents/GitHub/My-Chips/rtl/cgra_pe.v): Coarse-Grained Reconfigurable Architecture (CGRA) PE Node with dynamic routing multiplexers and configuration registers.
* **`tb/`**: Native Verilog verification testbenches.
  * [tb_mac.v](file:///c:/Users/mouni/Documents/GitHub/My-Chips/tb/tb_mac.v): Self-checking testbench for the Parameterized MAC.
  * [tb_dot_product_pe.v](file:///c:/Users/mouni/Documents/GitHub/My-Chips/tb/tb_dot_product_pe.v): Self-checking testbench for the INT4 Vector Dot Product PE.
  * [tb_cgra_pe.v](file:///c:/Users/mouni/Documents/GitHub/My-Chips/tb/tb_cgra_pe.v): Self-checking testbench for the CGRA PE Node.
* **`sim/`**: Scripts and automation configurations for simulation.
  * [run_sim.py](file:///c:/Users/mouni/Documents/GitHub/My-Chips/sim/run_sim.py): Regression runner script to compile and run all local simulations using Icarus Verilog.

---

## 1. Parameterized Multiply-Accumulate (MAC) Module

The `mac` unit computes:
$$\text{acc} \leftarrow \text{acc} + (a \times b)$$
* **Input precision**: Parameterized signed integers (default: 8-bit).
* **Accumulator width**: Parameterized signed integer register (default: 24-bit).
* **Features**: Active-high synchronous reset (`rst`), update enable (`en`), data valid trigger (`valid_in`), and direct accumulator clear (`clear_acc`). Hard saturation clamps outputs to limits `[-8,388,608, +8,388,607]`.

---

## 2. INT4 Vector Dot Product Processing Element (PE)

Designed specifically for quantized neural network vector operations (such as Transformer multi-head attention acceleration), the `dot_product_pe` computes the dot product of two packed 4-element vectors:
$$\text{sum} = (a_0 \times b_0) + (a_1 \times b_1) + (a_2 \times b_2) + (a_3 \times b_3)$$
$$\text{acc} \leftarrow \text{acc} + \text{sum}$$

### Vector Packing Layout (16-bit packed word)
Each 16-bit input represents a packed vector of 4 elements of 4-bit signed integers:

| Bits | Vector Element | Data Type |
| :--- | :--- | :--- |
| `[3:0]` | Element 0 | 4-bit signed integer |
| `[7:4]` | Element 1 | 4-bit signed integer |
| `[11:8]` | Element 2 | 4-bit signed integer |
| `[15:12]` | Element 3 | 4-bit signed integer |

---

## 3. Coarse-Grained Reconfigurable Architecture (CGRA) PE Node

Going beyond standard static computing arrays, the `cgra_pe` module implements a reconfigurable processing node that can dynamically change its input sources, mathematical operations, and output destination routing at runtime via configuration registers.

### Configuration Register Mapping (16-bit register)

| Bit Range | Field Name | Description & Values |
| :--- | :--- | :--- |
| `[2:0]` | `src_a` | Selects source for Operand A:<br>`000` = North input (`data_n`) / `001` = South input (`data_s`) / `010` = East input (`data_e`) / `011` = West input (`data_w`) / `100` = Global bus (`data_global`) / `101` = Local accumulator |
| `[5:3]` | `src_b` | Selects source for Operand B (same mapping as `src_a`) |
| `[7:6]` | `op_select` | Decodes arithmetic operation:<br>`00` = Multiply-Accumulate / `01` = Addition / `10` = Pass-through A / `11` = Pass-through B |
| `[10:8]` | `dest_route` | Selects output routing:<br>`000` = Route saturated output to all neighbors / `001` = North (`out_n`) / `010` = South (`out_s`) / `011` = East (`out_e`) / `100` = West (`out_w`) |

---

## 4. Running Simulations Locally

### Prerequisites
Ensure you have **Icarus Verilog** (`iverilog` and `vvp`) installed on your system.

### Running Regression Suite
To compile and execute both simulations:
```powershell
python sim/run_sim.py
```

### Manual Compilation
```powershell
# Compile the CGRA PE Node simulation
iverilog -o sim/cgra_pe_tb.vvp rtl/cgra_pe.v tb/tb_cgra_pe.v

# Run the simulation executable
vvp sim/cgra_pe_tb.vvp
```
Waveforms are saved to `tb_cgra_pe.vcd` and can be inspected via **GTKWave**:
```powershell
gtkwave tb_cgra_pe.vcd
```
