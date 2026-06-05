#!/usr/bin/env python3
"""
M10 (part A): extract the real sky130 bitline WIRE capacitance with Magic PEX.

The charge-domain per-row step is  Cc*VDD / (N*Cc + C_BL), so the row limit hinges
entirely on C_BL. MOONSHOT.md used *placeholder* C_BL (50/100/500 fF). This pins down
the WIRE component for real, in three cross-sections so we bracket it honestly:

  iso    : a lone min-width met2 bitline over substrate            (floor)
  nbr    : + two grounded met2 neighbor bitlines at min spacing    (adds lateral coupling)
  plane  : + a met1 ground plane under the whole run               (ceiling)

Magic draws each (1 internal unit = 0.005 um), extracts with resistance OFF (we want a
clean lumped node cap, not an RC network), and ext2spice emits `C<i> BL <node> <val>f`.
We sum every cap incident on BL -> total C_BL(wire); divide by length -> fF/um.

Run (iic-osic-tools Docker, like sw/gen_cim_array.py):
    python pex/run_bitline_pex.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEX_DIR = os.path.join(ROOT, "pex")
L_UM = 50.0          # extraction length; cap is linear in length -> report fF/um
W = 0.14             # met2 min width (um)
SP = 0.14            # met2 min spacing (um)
RCFILE = "/foss/pdks/sky130A/libs.tech/magic/sky130A.magicrc"


def rect(x1, y1, x2, y2, layer, label):
    return [f"box {x1}um {y1}um {x2}um {y2}um", f"paint {layer}", f"label {label}"]


def build_tcl(cfg):
    cell = f"bl_{cfg}"
    L = ["drc off", "crashbackups stop", f"cellname rename (UNNAMED) {cell}"]
    # BL in the middle; left neighbor at x[0,W], BL at x[W+SP, 2W+SP], right at x[2W+2SP, 3W+2SP]
    blx0 = W + SP
    L += rect(blx0, 0, blx0 + W, L_UM, "metal2", "BL")
    if cfg in ("nbr", "plane"):
        L += rect(0, 0, W, L_UM, "metal2", "gndL")
        L += rect(2 * W + 2 * SP, 0, 3 * W + 2 * SP, L_UM, "metal2", "gndR")
    if cfg == "plane":
        L += rect(-0.3, -0.3, 3 * W + 2 * SP + 0.3, L_UM + 0.3, "metal1", "gndP")
    L += [
        "select top cell",
        "extract all",
        "ext2spice cthresh 0.01",   # default (no extresist) -> clean lumped node cap
        "ext2spice",
        "quit -noprompt",
    ]
    path = os.path.join(PEX_DIR, f"_bl_{cfg}.tcl")
    with open(path, "w") as f:
        f.write("\n".join(L) + "\n")
    return cell


def run_magic(cell):
    vol = os.getcwd().replace("/mnt/c", "C:").replace("\\", "/")
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    cmd = ["docker.exe", "run", "--rm", "-v", f"{vol}:/foss/designs",
           "-w", "/foss/designs/pex", "hpretl/iic-osic-tools:latest", "--skip",
           "bash", "-c", f"magic -dnull -noconsole -rcfile {RCFILE} _{cell}.tcl >/dev/null 2>&1; cat {cell}.spice"]
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    return r.stdout


def total_bl_cap(spice):
    """Sum every cap incident on node BL (BL may be one terminal of each C line)."""
    total = 0.0
    for ln in spice.splitlines():
        m = re.match(r"\s*C\d+\s+(\S+)\s+(\S+)\s+([0-9.eE+\-]+)f", ln)
        if m and "BL" in (m.group(1), m.group(2)):
            total += float(m.group(3))
    return total


def main():
    print(f"Extracting sky130 met2 bitline cap (W={W}um, spacing={SP}um, L={L_UM}um)\n")
    rows = []
    for cfg in ("iso", "nbr", "plane"):
        cell = build_tcl(cfg)
        spice = run_magic(cell)
        c_tot = total_bl_cap(spice)
        if c_tot == 0.0:
            print(f"[{cfg}] no BL caps parsed -- raw spice:\n{spice}")
            sys.exit(1)
        rows.append((cfg, c_tot, c_tot / L_UM))

    print(f"{'cross-section':>22} | {'C_BL(50um)':>11} | {'fF/um':>8}")
    print("-" * 48)
    names = {"iso": "isolated/substrate", "nbr": "+ grounded neighbors",
             "plane": "+ met1 ground plane"}
    for cfg, c_tot, per_um in rows:
        print(f"{names[cfg]:>22} | {c_tot:>9.3f}f | {per_um:>7.4f}")

    realistic = next(p for c, t, p in rows if c == "nbr")
    print(f"\nRealistic wire cap (with neighbor coupling): {realistic:.4f} fF/um")
    for pitch in (2.0, 3.0):
        print(f"  @ {pitch:.0f}um cell pitch -> wire C_BL = {realistic*pitch:.3f} fF/row "
              f"| 16-row={realistic*pitch*16:.1f}f  64-row={realistic*pitch*64:.1f}f")
    print("\nNOTE: WIRE term only. Full C_BL also has per-cell access-transistor junction")
    print("      cap + the N MOM caps (N*Cc). Those need the cell drawn (M10b).")


if __name__ == "__main__":
    main()
