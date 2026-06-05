#!/usr/bin/env python3
"""
M9: StrongARM offset vs input-pair area (Pelgrom sizing).

sigma_offset ~ AVT/sqrt(W*L) and the input pair dominates -> scaling the input-pair width
by `wmult` should drop sigma ~ 1/sqrt(wmult). This sweeps wmult, runs the real sky130 tt_mm
Monte-Carlo at each, and extracts sigma via probit regression (all points). It then reports,
for each size, whether the 16-row (~67 mV/row) and 64-row (~17 mV/row) CIM steps from M10
clear 3-sigma -> i.e. how much input-pair area buys the 64-row column.

This is offset *reduction by sizing* (brute-force area), the baseline M9 lever. Auto-zeroing /
CDS would cut offset to the charge-injection residual independent of size -- the area-free
alternative, noted for follow-up.

Run inside the iic-osic-tools container (ngspice + sky130 tt_mm):
    docker ... bash -c 'python3 sw/mc_offset_vs_size.py'
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mc_sa_probit import probit_regression  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WMULTS = [1, 2, 4, 8]
VDIFF_START, VDIFF_STOP, VDIFF_STEP = -0.025, 0.025, 0.001
NUM_SAMPLES = 50
STEP_16, STEP_64 = 67.0, 17.0   # mV/row from M10 (16-row segment, 64-row continuous)


def deck(wmult):
    return f"""* M9 offset vs size, wmult={wmult}
.include "../../rtl/analog_cim/sense_amp_sized.spice"
.lib "/foss/pdks/sky130A/libs.tech/ngspice/sky130.lib.spice" tt_mm
Vvdd VDD 0 DC 1.8
Vvss VSS 0 DC 0
Vclk CLK 0 PULSE(0 1.8 5n 0.1n 0.1n 10n 20n)
.options reltol=1e-3 method=gear cmin=1f
Vinp INP 0 DC 1.2
Vinn INN 0 DC 1.2
Xsa VDD VSS CLK INP INN OUTP OUTN strongarm_comparator wmult={wmult}
.control
  let vd = {VDIFF_START}
  dowhile vd <= {VDIFF_STOP} + 0.0001
    echo VDIFF_STEP $&vd
    let s = 1
    dowhile s <= {NUM_SAMPLES}
      reset
      let vp = 1.2 + vd/2
      let vn = 1.2 - vd/2
      alter Vinp = $&vp
      alter Vinn = $&vn
      tran 0.1n 10n
      meas tran outp_v find v(OUTP) at=9.5n
      print outp_v
      let s = s + 1
    end
    let vd = vd + {VDIFF_STEP}
  end
  quit
.endc
.end
"""


def run_mc(wmult):
    path = os.path.join(ROOT, f"tb/analog_cim/_mc_size_{wmult}.spice")
    with open(path, "w") as f:
        f.write(deck(wmult))
    p = subprocess.run(["ngspice", "-b", path], capture_output=True, text=True)
    vdiffs, probs = [], []
    cur_v, res = None, []
    for line in p.stdout.splitlines():
        ms = re.search(r"VDIFF_STEP\s+([-\d.eE]+)", line)
        if ms:
            if cur_v is not None:
                probs.append(sum(1 for v in res if v > 0.9) / len(res) if res else 0.0)
                vdiffs.append(cur_v)
            cur_v = float(ms.group(1))
            res = []
            continue
        mv = re.search(r"outp_v\s*=\s*([-+0-9eE.]+)", line, re.I)
        if mv and cur_v is not None:
            res.append(float(mv.group(1)))
    if cur_v is not None:
        probs.append(sum(1 for v in res if v > 0.9) / len(res) if res else 0.0)
        vdiffs.append(cur_v)
    return vdiffs, probs


def main():
    print(f"{'wmult':>5} | {'in WL(x)':>8} | {'sigma(mV)':>9} | {'3sig(mV)':>8} | {'R2':>5} | "
          f"{'sig*sqrt(wm)':>12} | {'16-row':>7} | {'64-row':>7}")
    print("-" * 80)
    for wm in WMULTS:
        vd, pr = run_mc(wm)
        sig_v, mu_v, r2 = probit_regression(vd, pr)
        if sig_v is None:
            print(f"{wm:>5} | parse/MC failed")
            continue
        sig = sig_v * 1000.0
        t3 = 3 * sig
        ok16 = "yes" if STEP_16 > t3 else "NO"
        ok64 = "yes" if STEP_64 > t3 else "NO"
        print(f"{wm:>5} | {wm:>8} | {sig:>9.2f} | {t3:>8.2f} | {r2:>5.2f} | "
              f"{sig*wm**0.5:>12.2f} | {ok16:>7} | {ok64:>7}")
    print("\n(sig*sqrt(wm) ~ constant => Pelgrom 1/sqrt(area) scaling holds)")
    print("64-row (17 mV/row) becomes resolvable once 3-sigma < 17 mV, i.e. sigma < 5.7 mV.")


if __name__ == "__main__":
    main()
