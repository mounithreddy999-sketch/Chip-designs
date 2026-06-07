#!/usr/bin/env python3
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAG_DIR = os.path.join(ROOT, "mag")
RCFILE = "/foss/pdks/sky130A/libs.tech/magic/sky130A.magicrc"

def run_cmd(cmd, cwd):
    print(f"Running: {' '.join(cmd)}")
    vol = os.getcwd().replace("/mnt/c", "C:").replace("\\", "/")
    docker_cmd = ["docker.exe", "run", "--rm", "-e", "PDK=sky130A", "-e", "MAGIC_DRC_USE_GDS=false",
                  "-v", f"{vol}:/foss/designs", "-w", cwd, "hpretl/iic-osic-tools:latest", "--skip", "bash", "-c", " ".join(cmd)]
    res = subprocess.run(docker_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Command failed:\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}")
        return False
    return True

def main():
    print("Step 1: Extracting layout to SPICE (Flat)...")
    extract_tcl = """
    drc off
    crashbackups stop
    load cim_cell_8t1c_flat.mag
    extract all
    ext2spice lvs
    ext2spice
    quit -noprompt
    """
    with open(os.path.join(MAG_DIR, "extract_lvs.tcl"), "w") as f:
        f.write(extract_tcl)
    
    if not run_cmd(["magic", "-dnull", "-noconsole", "-rcfile", RCFILE, "extract_lvs.tcl"], "/foss/designs/mag"):
        sys.exit(1)
        
    print("Extraction complete. Generated cim_cell_8t1c_flat.spice")

    # Strip .subckt from the extracted spice
    spice_path = os.path.join(MAG_DIR, "cim_cell_8t1c_flat.spice")
    with open(spice_path, "r") as f:
        lines = f.readlines()
    
    with open(spice_path, "w") as f:
        for line in lines:
            if not line.startswith(".subckt") and not line.startswith(".ends"):
                f.write(line)

    print("\nStep 2: Running Netgen LVS...")
    setup_tcl = "/foss/pdks/sky130A/libs.tech/netgen/sky130A_setup.tcl"
    
    lvs_cmd = f"netgen -batch lvs \"cim_cell_8t1c_flat.spice\" \"../rtl/analog_cim/cim_cell_8t1c.spice\" {setup_tcl} comp.out"
    run_cmd([lvs_cmd], "/foss/designs/mag")
    
    print("\nLVS Complete. Check comp.out for results.")
    
    with open(os.path.join(MAG_DIR, "comp.out"), "r", encoding="utf-8", errors="replace") as f:
        out = f.read()
        if "Netlists match uniquely." in out:
            print("\n LVS MATCHED: 8T1C layout is equivalent to the schematic!")
        else:
            print("\n LVS FAILED or WARNINGS found. See comp.out for details.")
            for line in out.splitlines():
                if "Result:" in line:
                    print(line)

if __name__ == "__main__":
    main()
