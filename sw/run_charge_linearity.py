#!/usr/bin/env python3
"""
Charge-domain CIM linearity + segmentation experiment (M6/M7).

Tests the moon thesis committed in docs/MOONSHOT.md: a *segmented* charge-domain
bitline keeps the per-row voltage step resolvable where a long *continuous*
bitline collapses below the sense-amp offset -- which is how segmentation breaks
the ~9-row passive ceiling we measured on the current-steering cell.

For each column config (N cells, bitline cap C_BL) it sweeps the active-row count
0..N. Each active cell drives its 1 fF MOM cap to VDD; passive charge sharing onto
the precharged, floating bitline yields:

        V_BL(n) = n * Cc * VDD / (N*Cc + C_BL)         (capacitor divider)

so the slope (mV/row) is constant -> the MAC is LINEAR, and shrinks as C_BL grows.
That closed form is the independent oracle: the SPICE measurement must reproduce it.

Run (needs the iic-osic-tools Docker image, like sw/gen_cim_array.py):
    python sw/run_charge_linearity.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VDD = 1.8
CC_FF = 1.0          # MOM unit coupling cap, fF (matches cim_cell_charge.spice)
MEAS_T = "12n"       # sample BL after EN settles (EN high 6n..14n)

# (label, N cells on this bitline, C_BL in fF)
CONFIGS = [
    ("segment-8",     8,  50.0),    # short local segment
    ("segment-16",   16, 100.0),    # the "break 9 -> 16 rows" target
    ("continuous-64", 64, 500.0),   # long global bitline (heavy wire parasitic)
]
SA_OFFSET_MV = 5.0   # reference 3-sigma sense-amp offset; step must clear this


def least_squares(xs, ys):
    """Ordinary least-squares line fit -> (slope, intercept, R^2). Pure Python."""
    nn = len(xs)
    sx, sy = sum(xs), sum(ys)
    sxx = sum(x * x for x in xs)
    sxy = sum(x * y for x, y in zip(xs, ys))
    slope = (nn * sxy - sx * sy) / (nn * sxx - sx * sx)
    intercept = (sy - slope * sx) / nn
    ybar = sy / nn
    ss_tot = sum((y - ybar) ** 2 for y in ys)
    ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 1.0
    return slope, intercept, r2


def build_deck(n_cells, cbl_ff):
    """Self-contained behavioral charge-domain column; .control loops over
    active-row count via `foreach` (textual substitution -> robust in -b mode)."""
    L = [
        f"* charge-domain linearity sweep  N={n_cells}  C_BL={cbl_ff}fF  (auto-generated)",
        ".subckt cim_cell_charge VDD VSS X W EN BL",
        "Bm m VSS V = V(VDD) * (V(X) > 0.9) * (V(W) > 0.9) * (V(EN) > 0.9)",
        f"Cc m BL {CC_FF}f",
        ".ends",
        "",
        "Vvdd VDD 0 DC 1.8",
        "Vvss VSS 0 DC 0",
        f"Cbl BL 0 {cbl_ff}f",
        "* precharge BL to 0 (switch on 0..5n), then float for compute",
        "Vpre PREB 0 PULSE(1.8 0 5n 0.1n 0.1n 10n 20n)",
        "Spre BL 0 PREB 0 swpre",
        ".model swpre sw vt=0.9 ron=10 roff=1e12",
        "* compute enable fires at 6n",
        "Ven EN 0 PULSE(0 1.8 6n 0.1n 0.1n 8n 20n)",
        "Vw W 0 DC 1.8",
        "* NACT = how many rows are active; cell k active iff NACT > k",
        "Vnact NACT 0 DC 0",
    ]
    for k in range(n_cells):
        L.append(f"Bx{k} X{k} 0 V = 1.8*(V(NACT) > {k}.5)")
        L.append(f"Xc{k} VDD VSS X{k} W EN BL cim_cell_charge")
    sweep = " ".join(str(n) for n in range(n_cells + 1))
    L += [
        "",
        ".control",
        f"  foreach n {sweep}",
        "    reset",
        "    alter vnact = $n",
        "    tran 0.02n 15n",
        f"    meas tran vbl find v(BL) at={MEAS_T}",
        "  end",
        "  quit",
        ".endc",
        ".end",
        "",
    ]
    return "\n".join(L)


def run_docker(deck_rel):
    vol = os.getcwd().replace("/mnt/c", "C:").replace("\\", "/")
    cmd = ["docker.exe", "run", "--rm", "-v", f"{vol}:/foss/designs", "-w", "/foss/designs",
           "hpretl/iic-osic-tools:latest", "--skip", "ngspice", "-b", deck_rel]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"Docker/ngspice failed!\nstdout:\n{r.stdout}\nstderr:\n{r.stderr}")
        sys.exit(1)
    return r.stdout


def sweep_config(label, n_cells, cbl_ff):
    deck_rel = f"tb/analog_cim/_charge_lin_{label}.spice"
    with open(os.path.join(ROOT, deck_rel), "w") as f:
        f.write(build_deck(n_cells, cbl_ff))
    out = run_docker(deck_rel)
    # one `vbl = <value>` per foreach iteration, in n=0..N order
    vbls = [float(m) for m in re.findall(r"vbl\s*=\s*([0-9eE.\-+]+)", out)]
    if len(vbls) != n_cells + 1:
        print(f"[{label}] expected {n_cells+1} measurements, parsed {len(vbls)}:\n{out}")
        sys.exit(1)
    n = list(range(n_cells + 1))
    v_mv = [v * 1e3 for v in vbls]
    slope, intercept, r2 = least_squares(n, v_mv)         # mV/row
    analytic = CC_FF * VDD / (n_cells * CC_FF + cbl_ff) * 1e3  # mV/row, closed form
    return dict(label=label, N=n_cells, cbl=cbl_ff, n=n, v_mv=v_mv,
                slope=slope, r2=r2, analytic=analytic)


def main():
    results = [sweep_config(*c) for c in CONFIGS]

    print("\n=== charge-domain bitline: per-row step (mV/row) ===")
    print(f"{'config':>14} | {'N':>3} | {'C_BL':>6} | {'meas slope':>10} | "
          f"{'analytic':>9} | {'err':>6} | {'R^2':>7} | {'step/offset':>11}")
    print("-" * 86)
    for r in results:
        err = abs(r["slope"] - r["analytic"]) / r["analytic"] * 100
        margin = r["slope"] / SA_OFFSET_MV
        verdict = "RESOLVABLE" if margin >= 1.0 else "below offset"
        print(f"{r['label']:>14} | {r['N']:>3} | {r['cbl']:>5.0f}f | "
              f"{r['slope']:>8.2f}mV | {r['analytic']:>7.2f}mV | {err:>5.1f}% | "
              f"{r['r2']:>7.5f} | {margin:>5.1f}x {verdict}")

    print(f"\n(reference sense-amp 3-sigma offset = {SA_OFFSET_MV:.1f} mV)")
    print("\nper-row curves (mV):")
    for r in results:
        pts = " ".join(f"{v:5.1f}" for v in r["v_mv"][:9])
        tail = " ..." if r["N"] > 8 else ""
        print(f"  {r['label']:>14}  n=0..8: {pts}{tail}")

    seg = next(r for r in results if r["label"] == "segment-16")
    cont = next(r for r in results if r["label"] == "continuous-64")
    print("\n=== VERDICT ===")
    print(f"segment-16   step = {seg['slope']:.1f} mV/row  -> {seg['slope']/SA_OFFSET_MV:.1f}x "
          f"the {SA_OFFSET_MV:.0f} mV offset  (linear, R^2={seg['r2']:.4f})")
    print(f"continuous-64 step = {cont['slope']:.1f} mV/row -> {cont['slope']/SA_OFFSET_MV:.1f}x "
          f"the offset")
    if seg["slope"] / SA_OFFSET_MV >= 1.0 and cont["slope"] / SA_OFFSET_MV < seg["slope"] / SA_OFFSET_MV:
        print("=> Segmentation keeps the step resolvable where the continuous bitline collapses.")
        print("   The ~9-row passive ceiling is a CONTINUOUS-bitline limit, not a charge-domain one.")
    else:
        print("=> Prediction NOT supported -- inspect the decks.")


if __name__ == "__main__":
    main()
