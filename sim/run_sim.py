#!/usr/bin/env python3
"""
Lightweight Regression Simulation Runner for Icarus Verilog
Compiles and runs design verification testbenches for:
  1. Parameterized MAC Unit (rtl/mac.v)
  2. INT4 Vector Dot Product PE (rtl/dot_product_pe.v)
"""

import subprocess
import shutil
import sys
import os

def run_test(test_name, rtl_file, tb_file, vvp_file):
    print("\n" + "="*50)
    print(f"   Running Verification: {test_name}")
    print("="*50)

    # Check if files exist
    if not os.path.exists(rtl_file) or not os.path.exists(tb_file):
        print(f"[ERROR] Missing source files for {test_name}.")
        return False

    print("Compiling Verilog files...")
    compile_cmd = ["iverilog", "-o", vvp_file, rtl_file, tb_file]
    print(f"Command: {' '.join(compile_cmd)}")
    
    compilation = subprocess.run(compile_cmd, capture_output=True, text=True)
    if compilation.returncode != 0:
        print("\n[FAIL] Compilation failed!")
        print("Compiler Stderr:")
        print(compilation.stderr)
        return False
    print("Compilation successful.")

    print("Executing simulation via vvp...")
    execute_cmd = ["vvp", vvp_file]
    print(f"Command: {' '.join(execute_cmd)}")
    
    execution = subprocess.run(execute_cmd, capture_output=True, text=True)
    
    print("\n--- Simulation Output Trace ---")
    print(execution.stdout)
    if execution.stderr:
        print("--- Simulation Stderr Trace ---")
        print(execution.stderr)

    if "ALL TEST CASES PASSED!" in execution.stdout:
        print(f"[SUCCESS] {test_name} Verified!")
        return True
    else:
        print(f"[FAIL] {test_name} Verification Failed.")
        return False

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sim_dir = os.path.join(repo_root, "sim")
    
    print("==================================================")
    print("   Starting Local Hardware Regression Runner      ")
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

    # Test 1: Parameterized MAC Unit
    test1_rtl = os.path.join(repo_root, "rtl", "mac.v")
    test1_tb  = os.path.join(repo_root, "tb", "tb_mac.v")
    test1_vvp = os.path.join(sim_dir, "mac_tb.vvp")
    t1_success = run_test("Parameterized MAC Unit", test1_rtl, test1_tb, test1_vvp)

    # Test 2: INT4 Dot Product PE
    test2_rtl = os.path.join(repo_root, "rtl", "dot_product_pe.v")
    test2_tb  = os.path.join(repo_root, "tb", "tb_dot_product_pe.v")
    test2_vvp = os.path.join(sim_dir, "dot_product_pe_tb.vvp")
    t2_success = run_test("INT4 Vector Dot Product PE", test2_rtl, test2_tb, test2_vvp)

    print("\n" + "="*50)
    print("   Regression Test Results Summary")
    print("="*50)
    print(f"1. Parameterized MAC Unit:      {'PASSED' if t1_success else 'FAILED'}")
    print(f"2. INT4 Vector Dot Product PE:  {'PASSED' if t2_success else 'FAILED'}")
    print("="*50)

    if t1_success and t2_success:
        print("   [SUCCESS] All design suites fully verified!")
        print("="*50)
        sys.exit(0)
    else:
        print("   [FAIL] Some design suites failed verification.")
        print("="*50)
        sys.exit(1)

if __name__ == "__main__":
    main()
