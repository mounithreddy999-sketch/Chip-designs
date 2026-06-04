#!/usr/bin/env python3
import os
import subprocess
import re
import sys

def main():
    print("=========================================================")
    # Resolve workspace paths
    cwd = os.getcwd()
    # Normalize path for Docker volume mounting (Windows/Unix compatibility)
    docker_vol = cwd.replace('\\', '/')
    
    # We will invoke ngspice using the iic-osic-tools Docker container
    docker_cmd = [
        "docker", "run", "--rm",
        "-v", f"{docker_vol}:/foss/designs",
        "-w", "/foss/designs",
        "hpretl/iic-osic-tools:latest",
        "--skip",
        "ngspice", "-b", "tb/analog_cim/tb_cim_transient.spice"
    ]
    
    print(f"Running analog simulation via Docker:")
    print(" ".join(docker_cmd))
    print("=========================================================")
    
    try:
        result = subprocess.run(docker_cmd, capture_output=True, text=True, check=True)
        output = result.stdout
        print(output)
    except subprocess.CalledProcessError as e:
        print("Error: Docker simulation failed!", file=sys.stderr)
        print(e.stderr, file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print("Error: 'docker' command not found. Please ensure Docker Desktop is running.", file=sys.stderr)
        sys.exit(1)

    # Parse measurement: energy_mac_1 = <val>
    # In ngspice, measurement output looks like:
    # energy_mac_1        =  1.54321e-13
    # which is the integrated current (charge in Coulombs)
    match = re.search(r"energy_mac_1\s*=\s*([0-9eE\.\-\+]+)", output)
    if not match:
        print("Error: Could not extract charge measurement 'energy_mac_1' from ngspice output.", file=sys.stderr)
        sys.exit(1)
    
    charge_coulombs = float(match.group(1))
    
    # Bitline bias voltage is 1.2V
    v_bias = 1.2
    energy_joules = charge_coulombs * v_bias
    energy_pj = energy_joules * 1e12  # convert to picojoules
    
    print("\n=========================================================")
    print(" ANALOG COMPUTE-IN-MEMORY SIMULATION RESULTS")
    print("=========================================================")
    print(f"Total Integrated Charge per MAC:  {charge_coulombs * 1e12:.3f} pC (picocoulombs)")
    print(f"Bitline Bias Voltage:              {v_bias} V")
    print(f"Calculated Energy per MAC:         {energy_pj:.4f} pJ")
    print("=========================================================")
    
    # Print comparison table
    print("\n=========================================================")
    print(" 4-POINT PARETO FRONTIER VS ANALOG CIM PROTOTYPE")
    print("=========================================================")
    print("  Design                 | Area     | Power   | pJ/MAC")
    print(" ------------------------+----------+---------+----------")
    print("  Flop Baseline (CG=0)   | 2.92 mm² | 52.2 mW | 2.04 pJ")
    print("  Clock-Gated (CG=1)     | 2.92 mm² | 32.8 mW | 1.28 pJ")
    print("  Batched SRAM (B=4)     | 0.602 mm²| 18.5 mW | 11.56 pJ")
    print("  Streaming SRAM (B=1)   | 0.602 mm²| 7.59 mW | 18.98 pJ")
    print(f"  Analog CIM Cell (Sky130)| Single   | Analog  | {energy_pj:.4f} pJ (Simulated)")
    print("=========================================================")

if __name__ == "__main__":
    main()
