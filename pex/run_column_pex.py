#!/usr/bin/env python3
"""
M10-stretch: INTEGRATED bitline extraction of a real tiled charge-domain column.

Instead of summing separately-extracted pieces (wire + N*Cc + N*junction), this tiles N real
MOM cells on ONE shared met2 bitline and extracts that single net -- capturing inter-cell
coupling, the real routed bitline, and a MEASURED cell pitch (vs the assumed 2 um).

Each cell: an interdigitated MOM cap whose A-plate merges into the shared bitline (met2 strip,
x[0,WF], full column height = BL) and whose B-plate is the per-cell compute node m{i}. So the
extracted BL node cap = sum_i Cc_i  +  bitline wire/coupling  =  the integrated C_tot.
Per-cell Cc = cap(BL, m{i}); wire = cap(BL, substrate). step = Cc*VDD / C_tot.

Run (iic-osic-tools Docker):
    python pex/run_column_pex.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEX_DIR = os.path.join(ROOT, "pex")
RCFILE = "/foss/pdks/sky130A/libs.tech/magic/sky130A.magicrc"
VDD = 1.8

WF, SF = 0.14, 0.14          # met2 finger width / spacing
NF = 6                        # fingers/cell -> Cc ~ 1 fF (M10b: ~0.31 fF/um^2)
W = 2.0                       # comb width (um)
PITCH = 2.5                   # cell pitch (um) -- transistor-limited 8T1C height (MOM stacks within)


def paint(x1, y1, x2, y2, layer):
    return [f"box {x1}um {y1}um {x2}um {y2}um", f"paint {layer}"]


def build_tcl(n):
    cell = f"col_{n}"
    H = NF * (WF + SF)                       # MOM height within a cell
    L = ["drc off", "crashbackups stop", f"cellname rename (UNNAMED) {cell}"]
    # shared bitline = met2 strip on the left, spanning the whole column
    L += paint(0, 0, WF, n * PITCH, "metal2")
    L += [f"box 0um 0um {WF}um {n*PITCH}um", "label BL"]
    for i in range(n):
        by = i * PITCH
        # B-spine (per-cell compute node m{i})
        L += paint(W - WF, by, W, by + H, "metal2")
        L += [f"box {W-WF}um {by}um {W}um {by+H}um", f"label m{i}"]
        for j in range(NF):
            fy = by + j * (WF + SF)
            if j % 2 == 0:        # A-finger: from bitline (x=0) toward, gap before B-spine
                L += paint(0, fy, W - WF - SF, fy + WF, "metal2")
            else:                 # B-finger: from gap after bitline to B-spine
                L += paint(WF + SF, fy, W, fy + WF, "metal2")
    L += ["select top cell", "extract all", "ext2spice cthresh 0.01", "ext2spice", "quit -noprompt"]
    with open(os.path.join(PEX_DIR, f"_{cell}.tcl"), "w") as f:
        f.write("\n".join(L) + "\n")
    return cell


def run_magic(cell):
    vol = os.getcwd().replace("/mnt/c", "C:").replace("\\", "/")
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    cmd = ["docker.exe", "run", "--rm", "-v", f"{vol}:/foss/designs",
           "-w", "/foss/designs/pex", "hpretl/iic-osic-tools:latest", "--skip",
           "bash", "-c", f"magic -dnull -noconsole -rcfile {RCFILE} _{cell}.tcl >/dev/null 2>&1; cat {cell}.spice"]
    return subprocess.run(cmd, capture_output=True, text=True, env=env).stdout


def parse(spice, n):
    c_to_cells, c_to_sub = 0.0, 0.0
    cc_each = []
    for ln in spice.splitlines():
        m = re.match(r"\s*C\d+\s+(\S+)\s+(\S+)\s+([0-9.eE+\-]+)f", ln)
        if not m:
            continue
        a, b, v = m.group(1), m.group(2), float(m.group(3))
        if "BL" in (a, b):
            other = b if a == "BL" else a
            if other.startswith("m"):
                c_to_cells += v
                cc_each.append(v)
            else:                       # VSUBS / substrate
                c_to_sub += v
    return c_to_cells, c_to_sub, cc_each


def main():
    print(f"Tiled charge-domain column: {NF} fingers/cell, pitch {PITCH} um\n")
    print(f"{'N':>3} | {'C_tot':>8} | {'Cc/cell':>8} | {'wire':>7} | {'pitch':>6} | {'step mV/row':>11}")
    print("-" * 60)
    for n in (8, 16):
        cell = build_tcl(n)
        spice = run_magic(cell)
        c_cells, c_sub, cc_each = parse(spice, n)
        if not cc_each:
            print(f"[{cell}] no BL->cell caps parsed:\n{spice[:600]}")
            sys.exit(1)
        c_tot = c_cells + c_sub
        cc = c_cells / len(cc_each)             # mean per-cell MOM cap
        step = cc / c_tot * VDD * 1000          # Cc*VDD / C_tot
        print(f"{n:>3} | {c_tot:>6.2f}f | {cc:>6.3f}f | {c_sub:>5.2f}f | {PITCH:>4.1f}u | {step:>9.1f}")
    print("\nIntegrated C_tot = N*Cc + bitline wire/coupling, from ONE extracted net (real pitch).")
    print("Compare vs component-sum estimate (docs/MOONSHOT.md): N*1.537 fF.")


if __name__ == "__main__":
    main()
