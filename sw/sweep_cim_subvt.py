#!/usr/bin/env python3
# Copyright (c) 2026 Mounith Reddy
# SPDX-License-Identifier: Apache-2.0
"""
Sweep the subthreshold activation drive (VXHI) for tb_cim_subvt.spice and tabulate
energy/MAC vs readability (Vdiff). This is the experiment that finds the FUNCTIONAL
sub-100 fJ sweet spot instead of guessing it.

Run from the repo root (same as simulate_analog_cim.py):
    python sw/sweep_cim_subvt.py

For each VXHI it patches the activation amplitude in the deck, runs ngspice in the
iic-osic-tools Docker container, and parses recharge energy + Vdiff. The sweet spot
is the lowest VXHI where |Vdiff| still scales linearly with active rows AND stays
above your sense-amp noise floor -- that row is your defensible functional pJ/MAC.
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DECK = os.path.join(ROOT, "tb", "analog_cim", "tb_cim_subvt.spice")
ACTIVE_ROWS = 2  # Vx0, Vx1 are the driven rows in the deck

VXHI_SWEEP = [0.5, 0.6, 0.7, 0.8, 1.0, 1.2, 1.8]


def run_one(vxhi):
    """Patch the activation amplitude, run ngspice in Docker, return (E_joules, Vdiff)."""
    base = open(DECK).read()
    patched = re.sub(r"(Vx[01] X[01] 0 PULSE\(0 )[0-9.]+", rf"\g<1>{vxhi}", base)

    tmp_rel = "tb/analog_cim/_sweep_tmp.spice"
    tmp_abs = os.path.join(ROOT, "tb", "analog_cim", "_sweep_tmp.spice")
    with open(tmp_abs, "w") as f:
        f.write(patched)
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
        print(f"  parse failure at VXHI={vxhi} V (check ngspice output)", file=sys.stderr)
        return None
    return float(e.group(1)), float(v.group(1))


def main():
    print(f"{'VXHI(V)':>8} | {'Vdiff(mV)':>10} | {'E/cycle(fJ)':>12} | {'fJ/active-MAC':>14}")
    print("-" * 54)
    for vx in VXHI_SWEEP:
        res = run_one(vx)
        if res is None:
            continue
        e_j, vd = res
        e_fj = e_j * 1e15
        print(f"{vx:>8.2f} | {vd * 1e3:>10.2f} | {e_fj:>12.2f} | {e_fj / ACTIVE_ROWS:>14.2f}")
    print("\nRead it as a tradeoff curve: energy falls steeply as VXHI drops, but so")
    print("does |Vdiff|. The sweet spot is the lowest VXHI where Vdiff is still linear")
    print("with active-row count and above your sense-amp noise -> defensible fJ/MAC.")


if __name__ == "__main__":
    main()
