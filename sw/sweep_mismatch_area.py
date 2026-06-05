#!/usr/bin/env python3
# Copyright (c) 2026 Mounith Reddy
# SPDX-License-Identifier: Apache-2.0

import os
import re
import statistics
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP_REL = "/tmp/_mc_sweep.spice" if os.path.exists("/tmp") else "tb/analog_cim/_mc_sweep.spice"

SIZES = [
    (0.42, 0.15),  # Minimum size
    (1.0,  0.5),   # Moderate size
    (2.0,  1.0)    # Large size
]
VGS_LIST = [0.4, 0.6]  # Deep subthreshold, Moderate inversion
MC_RUNS = 30

DECK = """* Single NMOS Subthreshold Mismatch Sweep
.lib "/foss/pdks/sky130A/libs.tech/ngspice/sky130.lib.spice" tt_mm

Vdd D 0 DC 0.8
Vg G 0 DC {vg}
Vs S 0 DC 0
Vb B 0 DC 0

XM1 D G S B sky130_fd_pr__nfet_01v8 w={w:.2f} l={l:.2f}

.control
  let run = 1
  dowhile run <= {runs}
    reset
    op
    print i(Vdd)
    let run = run + 1
  end
  quit
.endc
.end
"""

def main():
    results = []
    print(f"Sweeping W, L, Vg for subthreshold mismatch, {MC_RUNS} runs per point...")
    print(f"{'Vg (V)':>6} | {'W (um)':>6} | {'L (um)':>6} | {'Area':>6} | {'mu_Id (uA)':>10} | {'sigma_Id (uA)':>13} | {'Rel Sigma (%)':>13}")
    print("-" * 70)

    for vg in VGS_LIST:
        for w, l in SIZES:
            txt = DECK.format(vg=vg, w=w, l=l, runs=MC_RUNS)
            with open(TMP_REL, "w") as f:
                f.write(txt)
            
            out = subprocess.run(["ngspice", "-b", TMP_REL], capture_output=True, text=True).stdout
            
            currents = []
            for match in re.finditer(r"i\(vdd\)\s*=\s*([-0-9eE.]+)", out, re.IGNORECASE):
                currents.append(abs(float(match.group(1))))
            
            if len(currents) < 2:
                print(f"{vg:>6.2f} | {w:>6.2f} | {l:>6.2f} | {w*l:>6.3f} | {'ERROR':>10} | {'ERROR':>13} | {'ERROR':>13}")
                continue
                
            mu = statistics.mean(currents)
            sigma = statistics.stdev(currents)
            rel_sigma = (sigma / mu) * 100 if mu != 0 else 0
            
            results.append((vg, w, l, w*l, mu, sigma, rel_sigma))
            print(f"{vg:>6.2f} | {w:>6.2f} | {l:>6.2f} | {w*l:>6.3f} | {mu*1e6:>10.3f} | {sigma*1e6:>13.3f} | {rel_sigma:>13.2f}", flush=True)

    print("\n==== Area vs Relative Mismatch ====")
    for vg, w, l, area, mu, sigma, rel_sigma in results:
        print(f"Vg={vg}V, Area {area:.3f} um2 (W={w}, L={l}): mu={mu*1e6:.3f}uA, Rel Sigma = {rel_sigma:.2f}%")

if __name__ == "__main__":
    main()
