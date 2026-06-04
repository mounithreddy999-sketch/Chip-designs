#!/usr/bin/env python3
# Copyright (c) 2026 Mounith Reddy
# SPDX-License-Identifier: Apache-2.0
"""
Render docs/frontier.svg (the verified Pareto frontier) from docs/frontier.csv.

Pure-Python, zero dependencies (writes SVG directly) so it works anywhere and
the figure regenerates from the single source-of-truth CSV. Axes: die area (x,
log) vs energy-per-MAC (y, log) -- both "lower is better", so the ideal sits in
the empty lower-left corner: small AND efficient = the analog-CIM frontier.
"""

import csv
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CSV_PATH = os.path.join(ROOT, "docs", "frontier.csv")
OUT_PATH = os.path.join(ROOT, "docs", "frontier.svg")

W, H = 780, 470
ML, MR, MT, MB = 72, 60, 48, 58
PW, PH = W - ML - MR, H - MT - MB

XMIN, XMAX = 0.5, 3.5      # area mm^2
YMIN, YMAX = 1.0, 25.0     # pJ/MAC
LXMIN, LXMAX = math.log10(XMIN), math.log10(XMAX)
LYMIN, LYMAX = math.log10(YMIN), math.log10(YMAX)


def mx(area):
    return ML + (math.log10(area) - LXMIN) / (LXMAX - LXMIN) * PW


def my(pj):
    return MT + (1 - (math.log10(pj) - LYMIN) / (LYMAX - LYMIN)) * PH


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def main():
    rows = list(csv.DictReader(open(CSV_PATH)))
    s = []
    s.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
        f'viewBox="0 0 {W} {H}" font-family="system-ui,Segoe UI,Arial,sans-serif">'
    )
    s.append(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')
    s.append(
        f'<text x="{ML}" y="27" font-size="17" font-weight="700" fill="#0f172a">'
        f'Sky130 16×16 INT8 PIM — Verified Pareto Frontier</text>'
    )
    s.append(f'<rect x="{ML}" y="{MT}" width="{PW}" height="{PH}" fill="#f8fafc" stroke="#cbd5e1"/>')

    for a in (0.5, 0.602, 1, 2, 2.92):
        x = mx(a)
        s.append(f'<line x1="{x:.1f}" y1="{MT}" x2="{x:.1f}" y2="{MT+PH}" stroke="#eef2f7"/>')
        s.append(
            f'<text x="{x:.1f}" y="{MT+PH+17}" font-size="11" fill="#475569" '
            f'text-anchor="middle">{a:g}</text>'
        )
    for p in (1, 2, 5, 10, 20):
        y = my(p)
        s.append(f'<line x1="{ML}" y1="{y:.1f}" x2="{ML+PW}" y2="{y:.1f}" stroke="#eef2f7"/>')
        s.append(
            f'<text x="{ML-9}" y="{y+4:.1f}" font-size="11" fill="#475569" '
            f'text-anchor="end">{p:g}</text>'
        )

    s.append(
        f'<text x="{ML+PW/2:.0f}" y="{H-14}" font-size="13" fill="#0f172a" '
        f'text-anchor="middle">die area (mm²) — smaller is better →</text>'
    )
    s.append(
        f'<text x="20" y="{MT+PH/2:.0f}" font-size="13" fill="#0f172a" text-anchor="middle" '
        f'transform="rotate(-90 20 {MT+PH/2:.0f})">pJ / MAC — lower is better ↓</text>'
    )
    # ideal (empty) lower-left corner
    s.append(
        f'<text x="{ML+10}" y="{MT+PH-12}" font-size="12" font-weight="700" fill="#b45309">'
        f'★ empty: small AND efficient → analog compute-in-memory</text>'
    )

    for r in rows:
        x, y = mx(float(r["area_mm2"])), my(float(r["pj_per_mac"]))
        parallel = int(r["mac_per_cycle"]) >= 256
        col = "#2563eb" if parallel else "#059669"
        star = r["design"].lower().startswith("clock")
        rad = 9 if star else 6
        s.append(
            f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{rad}" fill="{col}" '
            f'stroke="#ffffff" stroke-width="1.6"/>'
        )
        gops = float(r["throughput_tops"]) * 1000
        tag = f'{r["design"]}{" ★" if star else ""} ({float(r["pj_per_mac"]):g} pJ, {gops:g} GOPS)'
        right_side = x > ML + PW * 0.5
        tx = x - rad - 6 if right_side else x + rad + 6
        anchor = "end" if right_side else "start"
        s.append(
            f'<text x="{tx:.1f}" y="{y+4:.1f}" font-size="11.5" fill="#0f172a" '
            f'text-anchor="{anchor}">{esc(tag)}</text>'
        )

    s.append(
        f'<text x="{ML+PW-4}" y="{MT+16}" font-size="11" fill="#64748b" text-anchor="end">'
        f'blue = parallel (256 MAC/cyc) · green = near-memory SRAM</text>'
    )
    s.append("</svg>")
    open(OUT_PATH, "w", encoding="utf-8").write("\n".join(s))
    print("wrote", OUT_PATH)


if __name__ == "__main__":
    main()
