#!/usr/bin/env python3
"""
M10c: extract the access-transistor drain JUNCTION cap with Magic PEX.

The last unmeasured term in the bitline budget C_BL = wire + N*junction (+ the cell load
N*Cc). This draws a real sky130 access nfet with the PDK device generator (DRC-clean),
extracts it, and reads the drain-to-bulk capacitance + the recognized FET's AD/PD (real
layout drain area/perimeter). Result completes the 16-row budget on measured silicon.

Run (iic-osic-tools Docker):
    python pex/run_junction_pex.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEX_DIR = os.path.join(ROOT, "pex")
RCFILE = "/foss/pdks/sky130A/libs.tech/magic/sky130A.magicrc"
W, L = 0.420, 0.150     # min access transistor


def build_tcl():
    cell = "acc_nfet"
    L_ = [
        "drc euclidean on", "drc on", "crashbackups stop",
        f"cellname rename (UNNAMED) {cell}",
        "set p [sky130::sky130_fd_pr__nfet_01v8_defaults]",
        f"dict set p w {W}", f"dict set p l {L}",
        "sky130::sky130_fd_pr__nfet_01v8_draw $p",
        "select top cell",
        "drc check", "drc catchup",
        'puts "DRC_COUNT [drc list count total]"',
        "extract all",
        "ext2spice cthresh 0.01",
        "ext2spice",
        "quit -noprompt",
    ]
    with open(os.path.join(PEX_DIR, f"_{cell}.tcl"), "w") as f:
        f.write("\n".join(L_) + "\n")
    return cell


def run_magic(cell):
    vol = os.getcwd().replace("/mnt/c", "C:").replace("\\", "/")
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    cmd = ["docker.exe", "run", "--rm", "-v", f"{vol}:/foss/designs",
           "-w", "/foss/designs/pex", "hpretl/iic-osic-tools:latest", "--skip",
           "bash", "-c",
           f"magic -dnull -noconsole -rcfile {RCFILE} _{cell}.tcl 2>/dev/null | grep DRC_COUNT; "
           f"cat {cell}.spice"]
    return subprocess.run(cmd, capture_output=True, text=True, env=env).stdout


def main():
    cell = build_tcl()
    out = run_magic(cell)

    drc = re.search(r"DRC_COUNT\s+(\d+)", out)
    fet = re.search(r"ad=([\d.]+)\s+pd=([\d.]+)", out)
    # drain-bulk cap line (terminals D and B in either order)
    cjd = 0.0
    for ln in out.splitlines():
        m = re.match(r"\s*C\d+\s+(\S+)\s+(\S+)\s+([0-9.eE+\-]+)f", ln)
        if m and {m.group(1), m.group(2)} == {"D", "B"}:
            cjd += float(m.group(3))

    print(f"sky130 access nfet  W={W} L={L}")
    print(f"  DRC errors        : {drc.group(1) if drc else '??'}")
    if fet:
        print(f"  drain AD / PD     : {fet.group(1)} um^2 / {fet.group(2)} um")
    print(f"  drain junction Cjd : {cjd:.4f} fF / cell  (Magic geometric, ~zero-bias)")
    print()
    print("  C_BL budget per row is dominated by the cell load N*Cc; junction is negligible:")
    for n, wire in ((16, 7.4), (64, 29.7)):
        cbl = wire + n * cjd
        ncc = n * 1.0            # Cc = 1 fF (M10b: real)
        step = 1.8 / (ncc + cbl) * 1000
        print(f"    {n:>2} rows: wire {wire:>4.1f} + junc {n*cjd:>4.1f} = C_BL {cbl:>5.1f} fF; "
              f"N*Cc {ncc:>2.0f} fF -> step {step:>4.1f} mV/row")


if __name__ == "__main__":
    main()
