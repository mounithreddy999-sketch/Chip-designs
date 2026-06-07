#!/usr/bin/env python3
"""
M10c: Extract the access transistor junction capacitance using Magic PEX.

We draw a simplified sub-cell: the drain diffusion of a typical access/compute 
transistor connected to the bitline, plus the via stack up to metal2 (the bitline).
This allows us to accurately measure the junction capacitance (Csb/Cdb) and any 
fringe capacitance from the local interconnects, which adds to the total C_BL.

Run (iic-osic-tools Docker):
    python pex/run_cell_pex.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEX_DIR = os.path.join(ROOT, "pex")
RCFILE = "/foss/pdks/sky130A/libs.tech/magic/sky130A.magicrc"

W = 0.42  # Transistor width (um)
L_DIFF = 0.20  # Drain diffusion length (um)


def build_tcl():
    cell = "junction_cap"
    tcl = [
        "drc off",
        "crashbackups stop",
        f"cellname rename (UNNAMED) {cell}"
    ]

    # Draw the drain diffusion and via stack to metal2
    # 1. n-diffusion (drain)
    tcl.append(f"box 0um 0um {W}um {L_DIFF}um")
    tcl.append("paint ndiffusion")
    
    # 2. Local interconnect contact (ndc)
    tcl.append(f"box 0.05um 0.05um {W-0.05}um {L_DIFF-0.05}um")
    tcl.append("paint ndc")
    tcl.append("paint locali")

    # 3. Via to metal1 (viali)
    tcl.append(f"box 0.05um 0.05um {W-0.05}um {L_DIFF-0.05}um")
    tcl.append("paint viali")
    tcl.append("paint metal1")

    # 4. Via to metal2 (via1)
    tcl.append(f"box 0.05um 0.05um {W-0.05}um {L_DIFF-0.05}um")
    tcl.append("paint via1")
    
    # 5. metal2 (bitline stub)
    tcl.append(f"box 0um 0um {W}um {L_DIFF}um")
    tcl.append("paint metal2")
    tcl.append("label BL")

    tcl += [
        "select top cell",
        "extract all",
        "ext2spice cthresh 0.01",
        "ext2spice",
        "quit -noprompt",
    ]

    with open(os.path.join(PEX_DIR, f"_{cell}.tcl"), "w") as f:
        f.write("\n".join(tcl) + "\n")
    return cell


def run_magic(cell):
    vol = os.getcwd().replace("/mnt/c", "C:").replace("\\", "/")
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    cmd = [
        "docker.exe", "run", "--rm", "-v", f"{vol}:/foss/designs",
        "-w", "/foss/designs/pex", "hpretl/iic-osic-tools:latest", "--skip",
        "bash", "-c", f"magic -dnull -noconsole -rcfile {RCFILE} _{cell}.tcl >/dev/null 2>&1; cat {cell}.spice"
    ]
    return subprocess.run(cmd, capture_output=True, text=True, env=env).stdout


def extract_junction_cap(spice):
    """Sum caps whose one terminal is BL and other is substrate/GND."""
    total_fF = 0.0
    for ln in spice.splitlines():
        # Match lines like: C0 BL VSUBS 0.23f
        m = re.match(r"\s*C\d+\s+(\S+)\s+(\S+)\s+([0-9.eE+\-]+)f", ln)
        if m:
            n1, n2, val = m.groups()
            if ("BL" in (n1, n2)) and (n1 in ("0", "VSS", "GND", "VSUBS") or n2 in ("0", "VSS", "GND", "VSUBS")):
                total_fF += float(val)
    return total_fF


def main():
    print(f"Extracting sky130 junction capacitance for access transistor drain (W={W}um, L_diff={L_DIFF}um)\n")
    cell = build_tcl()
    spice = run_magic(cell)
    
    c_junc = extract_junction_cap(spice)
    if c_junc == 0.0:
        print(f"[{cell}] no junction cap parsed -- raw spice:\n{spice}")
        # Look for AD / PD / AS / PS parameters on mosfets instead of explicit C elements
        # Sometimes ext2spice emits MOSFET parameters instead of explicit lumped caps for diffusion.
        for ln in spice.splitlines():
            if "ad=" in ln.lower() and "BL" in ln:
                print("Found MOSFET AD/PD parameters. ext2spice didn't lump diffusion into a capacitor.")
                print("Raw line: ", ln)
        sys.exit(1)

    print(f"Extracted Junction/Fringe Capacitance (drain + via stack): {c_junc:.4f} fF")
    print(f"\nThis replaces the conservative '0.5 fF/cell' estimate with a physically grounded value.")


if __name__ == "__main__":
    main()
