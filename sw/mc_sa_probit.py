#!/usr/bin/env python3
# Copyright (c) 2026 Mounith Reddy
# SPDX-License-Identifier: Apache-2.0

"""
M8: Real PDK Monte-Carlo Offset Extraction for the StrongARM sense amp.
Sweeps Vdiff, runs N Monte Carlo samples per Vdiff inside ngspice,
and extracts the probability of OUTP resolving high.
Uses linear interpolation of the CDF to extract sigma_offset.
"""

import os
import re
import subprocess
from statistics import NormalDist

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP_REL = "tb/analog_cim/_mc_sa_probit.spice"

# Vdiff sweep parameters
VDIFF_START = -0.02  # -20 mV
VDIFF_STOP  = 0.02   # +20 mV
VDIFF_STEP  = 0.001  # 1 mV
NUM_SAMPLES = 50

DECK = f"""* M8 Probit Monte Carlo
.include "../../rtl/analog_cim/sense_amp.spice"
.lib "/foss/pdks/sky130A/libs.tech/ngspice/sky130.lib.spice" tt_mm

Vvdd VDD 0 DC 1.8
Vvss VSS 0 DC 0

* Clock: low = reset (0-5ns), high = evaluate (5-15ns)
Vclk CLK 0 PULSE(0 1.8 5n 0.1n 0.1n 10n 20n)

.options reltol=1e-3 method=gear cmin=1f

Vinp INP 0 DC 1.2
Vinn INN 0 DC 1.2

Xsa VDD VSS CLK INP INN OUTP OUTN strongarm_comparator

.control
  let vdiff_start = {VDIFF_START}
  let vdiff_stop  = {VDIFF_STOP}
  let vdiff_step  = {VDIFF_STEP}
  let num_samples = {NUM_SAMPLES}

  let vdiff_curr = vdiff_start
  dowhile vdiff_curr <= vdiff_stop + 0.0001
    echo VDIFF_STEP $&vdiff_curr
    let sample = 1
    dowhile sample <= num_samples
      reset
      let vinp_val = 1.2 + vdiff_curr / 2
      let vinn_val = 1.2 - vdiff_curr / 2
      alter Vinp = $&vinp_val
      alter Vinn = $&vinn_val
      
      tran 0.1n 10n
      meas tran outp_v find v(OUTP) at=9.5n
      print outp_v
      let sample = sample + 1
    end
    let vdiff_curr = vdiff_curr + vdiff_step
  end
  quit
.endc
.end
"""

def interp_sigma(vdiff_list, prob_list, target_prob):
    """Linearly interpolate the Vdiff that gives exactly target_prob."""
    for i in range(len(prob_list) - 1):
        p1 = prob_list[i]
        p2 = prob_list[i+1]
        
        # If the target is exactly on a point or crosses between i and i+1
        if p1 == target_prob: return vdiff_list[i]
        if p2 == target_prob: return vdiff_list[i+1]
        
        # Since it's a CDF, it should be monotonically increasing (mostly)
        if (p1 < target_prob < p2) or (p1 > target_prob > p2):
            v1, v2 = vdiff_list[i], vdiff_list[i+1]
            return v1 + (v2 - v1) * (target_prob - p1) / (p2 - p1)
    
    # If target is outside the sweep range
    return None

def probit_regression(vdiffs, probs):
    """ROBUST sigma: fit Phi^-1(P) = (Vdiff - mu)/sigma over ALL interior points
    (0<P<1) instead of two noisy CDF crossings. Returns (sigma, mu, r2)."""
    xs, ys = [], []
    for v, p in zip(vdiffs, probs):
        if 0.0 < p < 1.0:
            xs.append(v)
            ys.append(NormalDist().inv_cdf(p))
    if len(xs) < 3:
        return None, None, None
    n = len(xs)
    sx, sy = sum(xs), sum(ys)
    sxx = sum(x * x for x in xs)
    sxy = sum(x * y for x, y in zip(xs, ys))
    slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    icpt = (sy - slope * sx) / n
    sigma = abs(1.0 / slope)
    mu = -icpt / (1.0 / slope)
    yb = sy / n
    ssr = sum((y - (slope * x + icpt)) ** 2 for x, y in zip(xs, ys))
    sst = sum((y - yb) ** 2 for y in ys)
    r2 = 1.0 - ssr / sst if sst > 0 else 0.0
    return sigma, mu, r2


def main():
    print(f"Generating SPICE deck ({NUM_SAMPLES} samples per point)...")
    with open(TMP_REL, "w") as f:
        f.write(DECK)
    
    # Read the output log line by line, to see progress
    p = subprocess.Popen(["ngspice", "-b", TMP_REL], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    
    results = [] # list of (vdiff, probability)
    current_vdiff = None
    current_resolves = []
    
    for line in p.stdout:
        # print(line, end="") # Uncomment if you want raw spice output
        match_step = re.search(r'VDIFF_STEP\s+([-\d\.eE]+)', line)
        if match_step:
            if current_vdiff is not None:
                p_high = sum(1 for v in current_resolves if v > 0.9) / len(current_resolves) if current_resolves else 0
                results.append((current_vdiff, p_high))
                print(f"Step {current_vdiff*1000:5.1f} mV: P(OUTP=1) = {p_high:.2f}", flush=True)
            current_vdiff = float(match_step.group(1))
            current_resolves = []
            continue
            
        match_val = re.search(r'outp_v\s*=\s*([-+0-9eE\.]+)', line, re.IGNORECASE)
        if match_val and current_vdiff is not None:
            current_resolves.append(float(match_val.group(1)))
            
    p.wait()

    # Don't forget the last step
    if current_vdiff is not None:
        p_high = sum(1 for v in current_resolves if v > 0.9) / len(current_resolves) if current_resolves else 0
        results.append((current_vdiff, p_high))

    if not results:
        print("ERROR: Failed to parse any results. SPICE might have crashed.")
        print(out[:1000])
        return

    print(f"\\n{'Vdiff (mV)':>10} | {'P(OUTP=1)':>10}")
    print("-" * 23)
    vdiffs = []
    probs = []
    for vdiff, p in results:
        print(f"{vdiff*1000:>10.1f} | {p:>10.3f}")
        vdiffs.append(vdiff)
        probs.append(p)
        
    # PRIMARY (robust): probit regression over every interior point.
    pr_sigma, pr_mu, pr_r2 = probit_regression(vdiffs, probs)
    print("\\n==== sigma_offset (probit regression -- ROBUST, uses all points) ====")
    if pr_sigma is not None:
        print(f"sigma_offset      : {pr_sigma*1000:.2f} mV")
        print(f"3-Sigma Tolerance : {3*pr_sigma*1000:.2f} mV")
        print(f"mean offset       : {pr_mu*1000:.2f} mV")
        print(f"probit fit R^2    : {pr_r2:.3f}   (near 1.0 => real Gaussian MC, not a degenerate draw)")

    # CROSS-CHECK: two-crossing method (fragile on a noisy 50-sample CDF).
    v_minus_sigma = interp_sigma(vdiffs, probs, 0.1587)
    v_plus_sigma  = interp_sigma(vdiffs, probs, 0.8413)

    print("\\n==== cross-check: two-crossing method (fragile) ====")
    if v_minus_sigma is None or v_plus_sigma is None:
        print("ERROR: Sweep range did not fully cover the +/- 1 sigma probabilities (15.87% to 84.13%).")
        if v_minus_sigma is None: print("Failed to find V_minus_sigma.")
        if v_plus_sigma is None: print("Failed to find V_plus_sigma.")
    else:
        sigma = (v_plus_sigma - v_minus_sigma) / 2
        print(f"-1 Sigma (15.87%) : {v_minus_sigma*1000:.2f} mV")
        print(f"+1 Sigma (84.13%) : {v_plus_sigma*1000:.2f} mV")
        print(f"Extracted Sigma   : {sigma*1000:.2f} mV")
        print(f"3-Sigma Tolerance : {3*sigma*1000:.2f} mV")

if __name__ == "__main__":
    main()
