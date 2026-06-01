#!/usr/bin/env python3
"""
Lightweight Simulation Runner for Icarus Verilog
Compiles design and testbench files, executes the simulation,
and prints stdout test results.
"""

import subprocess
import shutil
import sys
import os

def run_simulation():
    # File Paths relative to repository root
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rtl_src = os.path.join(repo_root, "rtl", "mac.v")
    tb_src = os.path.join(repo_root, "tb", "tb_mac.v")
    sim_dir = os.path.join(repo_root, "sim")
    vvp_out = os.path.join(sim_dir, "mac_tb.vvp")

    print("==================================================")
    print("   Starting Local Hardware Simulation Runner      ")
    print("==================================================")

    # Check if iverilog is installed
    if not shutil.which("iverilog"):
        print("\n[ERROR] 'iverilog' (Icarus Verilog compiler) was not found in your system PATH.")
        print("Please install Icarus Verilog to run simulations locally.")
        print("Installation instructions:")
        print(" - Windows (Chocolatey): choco install icarus-verilog")
        print(" - Windows (Direct installer): https://bleyer.org/icarus/")
        print(" - MacOS (Homebrew): brew install icarus-verilog")
        print(" - Linux (APT): sudo apt-get install iverilog")
        print("\nSimulation aborted.")
        sys.exit(1)

    print("Compiling Verilog source files...")
    compile_cmd = ["iverilog", "-o", vvp_out, rtl_src, tb_src]
    print(f"Command: {' '.join(compile_cmd)}")
    
    compilation = subprocess.run(compile_cmd, capture_output=True, text=True)
    if compilation.returncode != 0:
        print("\n[FAIL] Compilation failed!")
        print("Compiler Stderr:")
        print(compilation.stderr)
        sys.exit(1)
    print("Compilation successful.")

    print("\nExecuting simulation via vvp...")
    execute_cmd = ["vvp", vvp_out]
    print(f"Command: {' '.join(execute_cmd)}")
    
    execution = subprocess.run(execute_cmd, capture_output=True, text=True)
    
    print("\n--- Simulation Output Trace ---")
    print(execution.stdout)
    if execution.stderr:
        print("--- Simulation Stderr Trace ---")
        print(execution.stderr)

    if "ALL TEST CASES PASSED!" in execution.stdout:
        print("==================================================")
        print("   [SUCCESS] Hardware Design Fully Verified!      ")
        print("==================================================")
    else:
        print("==================================================")
        print("   [FAIL] Simulation Verification Failed          ")
        print("==================================================")
        sys.exit(1)

if __name__ == "__main__":
    run_simulation()
