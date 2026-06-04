#!/usr/bin/env python3
# Copyright (c) 2026 Mounith Reddy
# SPDX-License-Identifier: Apache-2.0
"""
AI-accelerator PPA scorecard.

Converts raw post-layout numbers (clock, power, die area) for an NxN
weight-stationary MVM macro into the metrics that actually let you compare
against a GPU on a fixed kernel:

    peak TOPS, TOPS/W, TOPS/mm^2, and energy-per-MAC (pJ/MAC).

Conventions are made explicit so the TOPS number isn't ambiguous:
  - The macro performs N*N multiply-accumulates per cycle (one per PE).
  - 1 MAC is counted as `ops_per_mac` operations (default 2: one mul, one add),
    matching how vendors quote dense TOPS.
  - "peak" assumes one valid activation vector every cycle (100% utilization).

Usage:
    python ppa_scorecard.py --n 16 --freq 100e6 --power 5e-3 --area 1.32
"""

from __future__ import annotations

import argparse


def ppa_metrics(
    n: int,
    f_hz: float,
    power_w: float,
    die_area_mm2: float,
    ops_per_mac: int = 2,
    macs_per_cycle: int | None = None,
):
    """Return PPA metrics for an MVM macro.

    Args:
        n: array dimension (NxN).
        f_hz: clock frequency in Hz.
        power_w: total power in Watts (from report_power).
        die_area_mm2: die area in mm^2 (from the final DEF).
        ops_per_mac: operations counted per MAC (2 = mul+add).
        macs_per_cycle: sustained MACs per cycle. Defaults to N*N for a fully
            parallel array; pass the lane width (e.g. 4) for a serialized /
            weight-streaming design so TOPS and pJ/MAC reflect real throughput.

    Raises:
        ValueError: on non-positive inputs (efficiency is undefined).
    """
    if n < 1:
        raise ValueError("n must be >= 1")
    if f_hz <= 0:
        raise ValueError("f_hz must be > 0")
    if power_w <= 0:
        raise ValueError("power_w must be > 0")
    if die_area_mm2 <= 0:
        raise ValueError("die_area_mm2 must be > 0")
    if ops_per_mac < 1:
        raise ValueError("ops_per_mac must be >= 1")

    if macs_per_cycle is None:
        macs_per_cycle = n * n
    if macs_per_cycle < 1:
        raise ValueError("macs_per_cycle must be >= 1")

    macs_per_s = macs_per_cycle * f_hz
    peak_tops = ops_per_mac * macs_per_s / 1e12
    tops_per_w = peak_tops / power_w
    tops_per_mm2 = peak_tops / die_area_mm2
    pj_per_mac = (power_w / macs_per_s) * 1e12

    return {
        "n": n,
        "f_hz": f_hz,
        "power_w": power_w,
        "die_area_mm2": die_area_mm2,
        "ops_per_mac": ops_per_mac,
        "macs_per_cycle": macs_per_cycle,
        "macs_per_s": macs_per_s,
        "peak_tops": peak_tops,
        "tops_per_w": tops_per_w,
        "tops_per_mm2": tops_per_mm2,
        "pj_per_mac": pj_per_mac,
    }


def format_scorecard(m) -> str:
    return "\n".join(
        [
            "================ PIM Macro PPA Scorecard ================",
            f"  Array              : {m['n']}x{m['n']}  ({m['macs_per_cycle']} MACs/cycle)",
            f"  Clock              : {m['f_hz']/1e6:.1f} MHz",
            f"  Power              : {m['power_w']*1e3:.4g} mW",
            f"  Die area           : {m['die_area_mm2']:.4g} mm^2",
            "  ------------------------------------------------------",
            f"  Peak throughput    : {m['peak_tops']*1e3:.4g} GOPS"
            f"  ({m['peak_tops']:.5g} TOPS, {m['ops_per_mac']} ops/MAC)",
            f"  Energy efficiency  : {m['tops_per_w']:.4g} TOPS/W",
            f"  Area efficiency    : {m['tops_per_mm2']:.4g} TOPS/mm^2",
            f"  Energy per MAC     : {m['pj_per_mac']:.4g} pJ/MAC",
            "========================================================",
        ]
    )


def main() -> None:
    p = argparse.ArgumentParser(description="AI-accelerator PPA scorecard")
    p.add_argument("--n", type=int, required=True, help="array dimension N (NxN)")
    p.add_argument("--freq", type=float, required=True, help="clock frequency in Hz")
    p.add_argument("--power", type=float, required=True, help="total power in Watts")
    p.add_argument("--area", type=float, required=True, help="die area in mm^2")
    p.add_argument("--ops-per-mac", type=int, default=2, help="ops counted per MAC")
    p.add_argument(
        "--macs-per-cycle",
        type=int,
        default=None,
        help="sustained MACs/cycle (default N*N; pass lane width for streaming)",
    )
    args = p.parse_args()

    m = ppa_metrics(
        args.n, args.freq, args.power, args.area, args.ops_per_mac, args.macs_per_cycle
    )
    print(format_scorecard(m))


if __name__ == "__main__":
    main()
