#!/usr/bin/env python3
# Copyright (c) 2026 Mounith Reddy
# SPDX-License-Identifier: Apache-2.0
"""
M5: Monte-Carlo input-referred OFFSET of the StrongARM comparator (probit method).

Mismatch injection: the input-pair Vth mismatch is FOLDED INTO THE DC INPUT
SOURCES (Vinn += offset) -- zero added circuit elements, so the ngspice sparse
solver stays well-conditioned and every sample runs in ~2 s. (Earlier versions
injected series gate sources on the dynamic latch nodes, which collapsed the
timestep to femtoseconds -- avoided entirely here.) This captures the DOMINANT,
input-pair offset term; the latch term is a secondary refinement best done with
the PDK statistical (mc) corner.

PROBIT METHOD: for each fixed VDIFF, run K mismatched samples, count the fraction
that resolve OUTP high (a Gaussian CDF), and read sigma = (V84 - V16)/2. No sample
sits at metastability, so no convergence stalls.

Run (native ngspice):
    python sw/mc_offset.py --k 30 --sigma-vth 0.00433   # 0.00433 = sky130 AVT/sqrt(WL)
"""

import argparse
import math
import os
import random
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP_REL = "/tmp/_mc_tmp.spice" if os.path.exists("/tmp") else "tb/analog_cim/_mc_tmp.spice"

DECK = """* MC offset sample -- input-pair Vth mismatch folded into the DC inputs.
.include "{root}/rtl/analog_cim/sense_amp.spice"
.lib "/foss/pdks/sky130A/libs.tech/ngspice/sky130.lib.spice" tt
Vvdd VDD 0 DC 1.8
Vvss VSS 0 DC 0
Vclk CLK 0 PULSE(0 1.8 5n 0.1n 0.1n 10n 20n)
Vinp INP 0 DC {vinp:.6f}
Vinn INN 0 DC {vinn:.6f}
Xsa VDD VSS CLK INP INN OUTP OUTN strongarm_comparator
.options reltol=1e-3 abstol=1e-9 vntol=1e-3
.control
  tran 0.02n 20n
  save v(OUTP)
  run
  meas tran outp find v(OUTP) at=9.5n
  print outp
  quit
.endc
.end
"""


def resolve(vdiff, voff, vcm):
    """One sample: effective input = vdiff - voff (offset folded into Vinn). True = OUTP high."""
    txt = DECK.format(root=ROOT.replace("\\", "/"),
                      vinp=vcm + vdiff / 2, vinn=vcm - vdiff / 2 + voff)
    with open(TMP_REL, "w") as f:
        f.write(txt)
    try:
        out = subprocess.run(["ngspice", "-b", TMP_REL],
                             capture_output=True, text=True, timeout=15.0).stdout
    except subprocess.TimeoutExpired:
        return None
    m = re.search(r"outp\s*=\s*([0-9eE.\-+]+)", out)
    return (float(m.group(1)) > 0.9) if m else None


def interp_cross(xs, ys, target):
    for i in range(1, len(xs)):
        if (ys[i - 1] - target) * (ys[i] - target) <= 0 and ys[i] != ys[i - 1]:
            t = (target - ys[i - 1]) / (ys[i] - ys[i - 1])
            return xs[i - 1] + t * (xs[i] - xs[i - 1])
    return None


def main():
    ap = argparse.ArgumentParser(description="Monte-Carlo StrongARM offset (probit).")
    ap.add_argument("--k", type=int, default=30, help="mismatched samples per VDIFF point")
    ap.add_argument("--sigma-vth", type=float, default=0.00433,
                    help="per-device Vth mismatch sigma (V) = sky130 AVT/sqrt(W*L)")
    ap.add_argument("--vmax-mv", type=float, default=25.0)
    ap.add_argument("--step-mv", type=float, default=2.5)
    ap.add_argument("--vcm", type=float, default=1.2)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    # input-pair differential offset: voff = off_inp - off_inn  ~ N(0, sqrt(2)*sigma_vth)
    rng = random.Random(args.seed)
    n = int(round(2 * args.vmax_mv / args.step_mv)) + 1
    vdiffs = [(-args.vmax_mv + i * args.step_mv) / 1000.0 for i in range(n)]
    fracs = []
    print(f"{'VDIFF(mV)':>9} | {'P(high)':>8}")
    print("-" * 21)
    for vd in vdiffs:
        hi = tot = 0
        for _ in range(args.k):
            voff = rng.gauss(0, args.sigma_vth) - rng.gauss(0, args.sigma_vth)
            r = resolve(vd, voff, args.vcm)
            if r is not None:
                tot += 1
                hi += 1 if r else 0
        f = hi / tot if tot else float("nan")
        fracs.append(f)
        print(f"{vd * 1e3:>9.1f} | {f:>8.3f}", flush=True)

    v16, v50, v84 = (interp_cross(vdiffs, fracs, t) for t in (0.16, 0.50, 0.84))
    print("\n==== StrongARM input-pair offset (Monte-Carlo, probit) ====")
    if None in (v16, v50, v84):
        print("  CDF did not span 0.16-0.84 -- widen --vmax-mv and re-run.")
        sys.exit(1)
    sigma = (v84 - v16) / 2
    print(f"  mean offset (mu)      : {v50 * 1e3:+.2f} mV")
    print(f"  input-pair sigma      : {sigma * 1e3:.2f} mV  (expect ~sqrt(2)*sigma_vth)")
    print(f"  3-sigma (input-pair)  : {3 * sigma * 1e3:.2f} mV")
    print("\n  NOTE: input-pair-dominant. Total offset adds a latch term (~20-40% more);")
    print("  the gold number is the sky130 statistical (mc) corner. For the verdict,")
    print("  full-scale 190 mV / 3-sigma ~ max column height.")


if __name__ == "__main__":
    main()
