#!/usr/bin/env python3
"""
M10b: extract the real MOM coupling cap Cc with Magic PEX.

The charge-domain cell's compute element is a MOM (metal-oxide-metal) fringe capacitor
-- interdigitated fingers whose lateral edge coupling is the cap. cim_cell_charge.spice
assumes Cc = 1 fF; this measures what a real sky130 interdigitated comb actually gives,
so the per-row step (which scales with Cc) stops resting on a guess.

Structure: two combs A and B. Left spine (A) + right spine (B); fingers alternate A/B in
y at min pitch (Wf+Sf) and overlap in x, so adjacent A/B finger edges couple across the
min spacing -> the MOM cap. Single metal layer here (a LOWER bound; a real MOM stacks
M2+M3+M4 with vias for ~2-3x density). We extract C(A,B) only (caps to substrate excluded).

Run (iic-osic-tools Docker):
    python pex/run_mom_pex.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEX_DIR = os.path.join(ROOT, "pex")
RCFILE = "/foss/pdks/sky130A/libs.tech/magic/sky130A.magicrc"

WF = 0.14            # finger width (met2 min)
SF = 0.14            # finger spacing (met2 min) -> max fringe density
LAYER = "metal2"


def rect(x1, y1, x2, y2, layer, label=None):
    out = [f"box {x1}um {y1}um {x2}um {y2}um", f"paint {layer}"]
    if label:
        out.append(f"label {label}")
    return out


def build_tcl(nf, width_um):
    """nf interdigitated fingers, comb bounding-box width width_um (um)."""
    cell = f"mom_{nf}"
    pitch = WF + SF
    H = nf * pitch
    W = width_um
    L = ["drc off", "crashbackups stop", f"cellname rename (UNNAMED) {cell}"]
    # spines
    L += rect(0, 0, WF, H, LAYER, "A")
    L += rect(W - WF, 0, W, H, LAYER, "B")
    # interleaved fingers: even=A (touch left spine), odd=B (touch right spine)
    for i in range(nf):
        y0 = i * pitch
        if i % 2 == 0:
            L += rect(0, y0, W - WF - SF, y0 + WF, LAYER)       # A finger: left spine -> gap before B spine
        else:
            L += rect(WF + SF, y0, W, y0 + WF, LAYER)            # B finger: gap after A spine -> right spine
    L += [
        "select top cell",
        "extract all",
        "ext2spice cthresh 0.01",
        "ext2spice",
        "quit -noprompt",
    ]
    with open(os.path.join(PEX_DIR, f"_{cell}.tcl"), "w") as f:
        f.write("\n".join(L) + "\n")
    return cell, W, H


def run_magic(cell):
    vol = os.getcwd().replace("/mnt/c", "C:").replace("\\", "/")
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    cmd = ["docker.exe", "run", "--rm", "-v", f"{vol}:/foss/designs",
           "-w", "/foss/designs/pex", "hpretl/iic-osic-tools:latest", "--skip",
           "bash", "-c", f"magic -dnull -noconsole -rcfile {RCFILE} _{cell}.tcl >/dev/null 2>&1; cat {cell}.spice"]
    return subprocess.run(cmd, capture_output=True, text=True, env=env).stdout


def cap_AB(spice):
    """Sum caps whose two terminals are exactly {A,B} -> the MOM cap."""
    total = 0.0
    for ln in spice.splitlines():
        m = re.match(r"\s*C\d+\s+(\S+)\s+(\S+)\s+([0-9.eE+\-]+)f", ln)
        if m and {m.group(1), m.group(2)} == {"A", "B"}:
            total += float(m.group(3))
    return total


def main():
    print(f"Extracting sky130 {LAYER} interdigitated MOM cap "
          f"(finger W={WF}um, spacing={SF}um)\n")
    print(f"{'fingers':>7} | {'area(um^2)':>10} | {'Cc(fF)':>8} | {'fF/um^2':>8}")
    print("-" * 42)
    data = []
    for nf, width in ((8, 2.0), (12, 2.0), (16, 3.0)):
        cell, W, H = build_tcl(nf, width)
        spice = run_magic(cell)
        c = cap_AB(spice)
        if c == 0.0:
            print(f"[{cell}] no A-B cap parsed -- raw spice:\n{spice}")
            sys.exit(1)
        area = W * H
        data.append((nf, area, c))
        print(f"{nf:>7} | {area:>10.3f} | {c:>8.4f} | {c/area:>8.4f}")

    dens = sum(c / a for _, a, c in data) / len(data)
    print(f"\nSingle-layer {LAYER} MOM density ~ {dens:.4f} fF/um^2 (LOWER bound; "
          f"stacking M2+M3+M4 ~2-3x).")
    area_for_1ff = 1.0 / dens
    print(f"-> a 1 fF single-layer Cc needs ~{area_for_1ff:.1f} um^2 "
          f"(~{area_for_1ff**0.5:.1f}um square); a 3-layer stack ~{area_for_1ff/2.5:.1f} um^2.")
    print("Implication for the step: Cc sets the absolute per-row step "
          "Cc*VDD/(N*Cc+C_BL); see docs/MOONSHOT.md M10.")


if __name__ == "__main__":
    main()
