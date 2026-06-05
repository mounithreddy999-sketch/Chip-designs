#!/usr/bin/env python3
# Copyright (c) 2026 Mounith Reddy
# SPDX-License-Identifier: Apache-2.0
"""
Generate an N-row x M-column analog CIM crossbar SPICE deck from the verified
cim_cell, and (optionally) run it to check that each column computes its
matrix-vector product:  Vdiff[c]  ~  -k * sum_r ( X[r] * W[r][c] ).

This is milestone M3: prove the cell scales into a real crossbar that stays
LINEAR (per-column Vdiff tracks the per-column active count) before committing
to full-custom layout. A single cell is a promise; a linear crossbar is a macro.

Usage (generate only):
    python sw/gen_cim_array.py --rows 8 --cols 4 --out tb/analog_cim/_cim_8x4.spice
Usage (generate + run in the iic-osic-tools Docker, parse + check):
    python sw/gen_cim_array.py --rows 8 --cols 4 --run
"""

import argparse
import os
import random
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def build(rows, cols, vxhi, cbl_ff, seed, active_frac, uniform=False):
    rng = random.Random(seed)
    if uniform:
        # CLEAN per-row-step measurement: all W=1, all rows active, so ONLY BL
        # discharges (never BL_bar). Vdiff = -dV_BL is then monotonic in row count
        # and Vdiff/rows is a true per-row step. (Random weights make Vdiff a
        # DIFFERENTIAL of BL vs BL_bar discharge -- not a per-row step, and the
        # sign flips column-to-column, which is meaningless to divide by a count.)
        W = [[1 for _ in range(cols)] for _ in range(rows)]
        X = [1 for _ in range(rows)]
    else:
        W = [[rng.randint(0, 1) for _ in range(cols)] for _ in range(rows)]
        X = [1 if rng.random() < active_frac else 0 for _ in range(rows)]
    golden = [sum(X[r] * W[r][c] for r in range(rows)) for c in range(cols)]

    L = []
    L.append(f"* Auto-generated {rows}x{cols} analog CIM crossbar (cim_cell)")
    L.append(f"* Activation pattern X = {X}")
    L.append(f"* Expected per-column active-AND-weight count = {golden}")
    L.append('.include "../../rtl/analog_cim/cim_cell.spice"')
    L.append('.lib "/foss/pdks/sky130A/libs.tech/ngspice/sky130.lib.spice" tt')
    L.append("Vpwr VPWR 0 DC 1.8")
    L.append("Vgnd VGND 0 DC 0")
    L.append("Vpre PRE 0 PULSE(0 1.8 4n 0.1n 0.1n 8n 20n)")
    L.append("")
    for c in range(cols):  # per-column bitlines: precharge PMOS + cap
        L.append(f"Xpre_l{c} BL{c}  PRE VPWR VPWR sky130_fd_pr__pfet_01v8 w=2.0 l=0.15")
        L.append(f"Xpre_r{c} BLb{c} PRE VPWR VPWR sky130_fd_pr__pfet_01v8 w=2.0 l=0.15")
        L.append(f"Cbl{c}  BL{c}  0 {cbl_ff}f")
        L.append(f"Cblb{c} BLb{c} 0 {cbl_ff}f")
    L.append("")
    for r in range(rows):  # row activations (subthreshold drive when active)
        if X[r]:
            L.append(f"Vx{r} X{r} 0 PULSE(0 {vxhi} 6n 0.1n 0.1n 4n 20n)")
        else:
            L.append(f"Vx{r} X{r} 0 DC 0")
    L.append("")
    for r in range(rows):  # crossbar cells with per-cell weights
        for c in range(cols):
            wt, wb = (1.8, 0.0) if W[r][c] else (0.0, 1.8)
            L.append(f"Vw{r}_{c}  W{r}_{c}  0 DC {wt}")
            L.append(f"Vwb{r}_{c} Wb{r}_{c} 0 DC {wb}")
            L.append(f"Xr{r}c{c} VGND VPWR X{r} W{r}_{c} Wb{r}_{c} BL{c} BLb{c} cim_cell")
    L.append("")
    L.append(".control")
    L.append("  tran 0.05n 15n")
    # Memory fix: save ONLY the bitlines + supply current, not the hundreds of
    # internal cell nodes -- saving everything is what blows up RAM / crashes WSL
    # on big crossbars. For the column-height (linearity) sweep, use --cols 1.
    L.append("  save " + " ".join(f"v(BL{c}) v(BLb{c})" for c in range(cols)) + " i(vpwr)")
    L.append("  run")
    for c in range(cols):
        L.append(f"  let vd{c} = v(BL{c}) - v(BLb{c})")
        L.append(f"  meas tran vdiff{c} find vd{c} at=10.5n")
    L.append("  let p_pwr = -i(vpwr) * 1.8")
    L.append("  meas tran energy integ p_pwr from=12n to=15n")
    for c in range(cols):
        L.append(f"  print vdiff{c}")
    L.append("  print energy")
    L.append("  quit")
    L.append(".endc")
    L.append(".end")
    return "\n".join(L) + "\n", golden


def run_docker(deck_rel):
    vol = os.getcwd().replace("/mnt/c", "C:").replace("\\", "/")
    cmd = ["docker.exe", "run", "--rm", "-v", f"{vol}:/foss/designs", "-w", "/foss/designs",
           "hpretl/iic-osic-tools:latest", "--skip", "ngspice", "-b", deck_rel]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Docker failed! stdout: {result.stdout}")
        print(f"Docker failed! stderr: {result.stderr}")
        sys.exit(1)
    return result.stdout


def main():
    ap = argparse.ArgumentParser(description="Generate/run an NxM analog CIM crossbar.")
    ap.add_argument("--rows", type=int, default=8)
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--vxhi", type=float, default=0.7, help="subthreshold activation high (V)")
    ap.add_argument("--cbl", type=float, default=100.0, help="bitline cap (fF)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--active-frac", type=float, default=0.5)
    ap.add_argument("--out", default="tb/analog_cim/_cim_array.spice")
    ap.add_argument("--run", action="store_true", help="run in Docker + check columns")
    ap.add_argument("--uniform", action="store_true",
                    help="all W=1, all rows active -> CLEAN monotonic per-row Vdiff step "
                         "(use this for the column-height sweep; scale --cbl with rows so "
                         "the bitline does not rail, e.g. --cbl = ~60*rows)")
    args = ap.parse_args()

    deck, golden = build(args.rows, args.cols, args.vxhi, args.cbl, args.seed,
                         args.active_frac, args.uniform)
    out_abs = os.path.join(ROOT, args.out)
    with open(out_abs, "w") as f:
        f.write(deck)
    print(f"wrote {args.out}  ({args.rows}x{args.cols}, VXHI={args.vxhi} V)")
    print(f"expected per-column active count: {golden}")

    if not args.run:
        print("(generate-only; pass --run to simulate)")
        return

    out = run_docker(args.out)
    vd = []
    for c in range(args.cols):
        m = re.search(rf"vdiff{c}\s*=\s*([0-9eE.\-+]+)", out)
        vd.append(float(m.group(1)) if m else None)
    print(f"\n{'col':>3} | {'expected':>8} | {'Vdiff(mV)':>10}")
    print("-" * 28)
    for c in range(args.cols):
        v = f"{vd[c]*1e3:.1f}" if vd[c] is not None else "parse-fail"
        print(f"{c:>3} | {golden[c]:>8} | {v:>10}")
    print("\nLINEARITY CHECK: |Vdiff| should rank-order with the expected count, and")
    print("ideally scale ~linearly. If it does, the crossbar computes MVM at scale.")


if __name__ == "__main__":
    main()
