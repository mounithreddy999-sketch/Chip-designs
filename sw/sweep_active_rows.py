#!/usr/bin/env python3
# Copyright (c) 2026 Mounith Reddy
# SPDX-License-Identifier: Apache-2.0

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DECK = os.path.join(ROOT, "tb", "analog_cim", "tb_cim_subvt.spice")

VXHI = 0.7  # The sweet spot found previously

def run_one(active_rows):
    base = open(DECK).read()
    
    # Force all weights to 1 to see pure accumulation
    base = re.sub(r"Vw2 W2 0 DC 0", "Vw2 W2 0 DC 1.8", base)
    base = re.sub(r"Vw2_bar W2_bar 0 DC 1.8", "Vw2_bar W2_bar 0 DC 0", base)
    
    # Configure Vx pulses depending on active_rows
    for i in range(4):
        if i < active_rows:
            pulse = f"Vx{i} X{i} 0 PULSE(0 {VXHI} 6n 0.1n 0.1n 4n 20n)"
        else:
            pulse = f"Vx{i} X{i} 0 DC 0"
        
        # Replace existing Vx{i} line
        base = re.sub(rf"Vx{i} X{i} 0.*", pulse, base)

    tmp_rel = "tb/analog_cim/_sweep_rows_tmp.spice"
    tmp_abs = os.path.join(ROOT, "tb", "analog_cim", "_sweep_rows_tmp.spice")
    with open(tmp_abs, "w") as f:
        f.write(base)
        
    try:
        vol = os.getcwd().replace("\\", "/")
        cmd = [
            "docker", "run", "--rm",
            "-v", f"{vol}:/foss/designs", "-w", "/foss/designs",
            "hpretl/iic-osic-tools:latest", "--skip",
            "ngspice", "-b", tmp_rel,
        ]
        out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    finally:
        if os.path.exists(tmp_abs):
            os.remove(tmp_abs)

    e = re.search(r"energy_precharge\s*=\s*([0-9eE.\-+]+)", out)
    v = re.search(r"vdiff_final\s*=\s*([0-9eE.\-+]+)", out)
    if not (e and v):
        print(f"  parse failure at {active_rows} rows", file=sys.stderr)
        return None
    return float(e.group(1)), float(v.group(1))

def main():
    print(f"Sweeping active rows at VXHI = {VXHI}V")
    print(f"{'Rows':>4} | {'Vdiff(mV)':>10} | {'E/cycle(fJ)':>12} | {'fJ/active-MAC':>14}")
    print("-" * 46)
    for rows in [1, 2, 3, 4]:
        res = run_one(rows)
        if res is None:
            continue
        e_j, vd = res
        e_fj = e_j * 1e15
        print(f"{rows:>4} | {vd * 1e3:>10.2f} | {e_fj:>12.2f} | {e_fj / rows:>14.2f}")

if __name__ == "__main__":
    main()
