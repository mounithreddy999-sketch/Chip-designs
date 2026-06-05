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
    
    docker_cmd = [
        "docker", "run", "--rm",
        "-v", f"{docker_vol}:/foss/designs",
        "-w", "/foss/designs",
        "hpretl/iic-osic-tools:latest",
        "--skip",
        "ngspice", "-b", "tb/analog_cim/tb_cim_array.spice"
    ]
    
    print(f"Running charge-domain analog array simulation via Docker:")
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

    # Parse measurements:
    # energy_precharge = <val>
    # vdiff_final = <val>
    match_energy = re.search(r"energy_precharge\s*=\s*([0-9eE\.\-\+]+)", output)
    match_vdiff = re.search(r"vdiff_final\s*=\s*([0-9eE\.\-\+]+)", output)
    
    if not match_energy or not match_vdiff:
        print("Error: Could not extract measurement values from ngspice output.", file=sys.stderr)
        sys.exit(1)
    
    energy_joules = float(match_energy.group(1))
    vdiff = float(match_vdiff.group(1))
    
    # Energy per MAC: The array contains 4 cells (4 rows), so we divide by 4.
    num_macs = 4
    energy_pj = (energy_joules * 1e12) / num_macs
    energy_fj = energy_pj * 1000.0
    
    print("\n=========================================================")
    print(" CHARGE-DOMAIN ANALOG CIM ARRAY SIMULATION RESULTS")
    print("=========================================================")
    print(f"Total Array Precharge Energy:      {energy_joules * 1e12:.4f} pJ ({energy_joules * 1e15:.2f} fJ)")
    print(f"Differential Bitline Delta (Vdiff): {vdiff:.4f} V (BL - BL_bar)")
    print(f"Calculated Energy per MAC:         {energy_fj:.2f} fJ ({energy_pj:.4f} pJ)")
    # Honesty: in tb_cim_array.spice only X0,X1 are driven high -> 2 of 4 rows
    # actually compute a non-zero product. Report per-ACTIVE-MAC too.
    active_rows = 2
    print(f"Per ACTIVE 1b MAC ({active_rows}/4 rows driven): "
          f"{(energy_joules * 1e15) / active_rows:.2f} fJ")
    print("=========================================================")

    # Print comparison table
    print("\n=========================================================")
    print(" 5-POINT PARETO FRONTIER VS CHARGE-DOMAIN CIM")
    print("=========================================================")
    print("  Design                 | Area     | Power/Method | pJ/MAC")
    print(" ------------------------+----------+--------------+----------")
    print("  Flop Baseline (CG=0)   | 2.92 mm² | 52.2 mW (Dig)| 2.04 pJ")
    print("  Clock-Gated (CG=1)     | 2.92 mm² | 32.8 mW (Dig)| 1.28 pJ")
    print("  Batched SRAM (B=4)     | 0.602 mm²| 18.5 mW (Dig)| 11.56 pJ")
    print("  Streaming SRAM (B=1)   | 0.602 mm²| 7.59 mW (Dig)| 18.98 pJ")
    print(f"  Analog CIM Array (Sky130)| 4-Row    | Charge-Domain| {energy_pj:.4f} pJ ({energy_fj:.1f} fJ)")
    print("=========================================================")

    # ---- CAVEATS: these must travel with the number ----
    print("\nCAVEATS (do NOT quote the fJ figure without these):")
    print(f"  * RAILED readout: Vdiff = {vdiff:.2f} V ~ full 1.8V discharge. A railed")
    print("    bitline is a saturated (digital-ish) discharge, NOT a linear analog sum")
    print("    -> the dot-product VALUE is unreadable. The low fJ is the cap's CV^2")
    print("    (cells starve once BL hits 0), divided by rows -- not true MAC energy.")
    print("  * INPUT-DEPENDENT: only 2 of 4 rows active; energy scales with activation")
    print("    density. Report density, or sweep it.")
    print("  * 1-BIT analog vs 8-BIT digital: NOT normalized (~64x the work). Do not")
    print("    claim an X-times win over the 8b digital MACs.")
    print("  * Function UNVERIFIED: confirm Vdiff scales with sum(X*W) in the LINEAR")
    print("    region -> tb/analog_cim/tb_cim_array_linear.spice")
    print("=========================================================")

if __name__ == "__main__":
    main()
