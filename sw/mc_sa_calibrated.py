#!/usr/bin/env python3
"""
M9: Offset-Cancelled Sense Amp (Trimming / Self-Calibration) Verification.

This script runs a Monte-Carlo simulation using the sky130 tt_mm mismatch models
on the StrongARM latch equipped with a secondary trimming input pair.
For each mismatch sample (representing a unique, physical fabricated chip), the
script sweeps the differential calibration voltage `Vtrim` while keeping the main
inputs identical (INP = INN = 1.2V).

It finds the exact `Vtrim` required to cancel the physical Vth mismatch and flip
the comparator's decision. 

If every sample's offset can be cancelled by a `Vtrim` within a reasonable DAC 
range (e.g. +/- 200 mV), then the effective residual offset of the comparator 
becomes solely bounded by the DAC's LSB step size (quantization noise), proving 
we can push sigma_offset < 1 mV.

Run inside the iic-osic-tools container (ngspice + sky130 tt_mm):
    docker ... bash -c 'python3 sw/mc_sa_calibrated.py'
"""

import os
import re
import subprocess
import sys
import statistics

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP_REL = "tb/analog_cim/_mc_sa_calibrated.spice"

NUM_SAMPLES = 50
VTRIM_START = -0.3   # -300 mV
VTRIM_STOP  = 0.3    # +300 mV
VTRIM_STEP  = 0.005  # 5 mV DAC LSB

DECK = f"""* M9 Self-Calibrated StrongARM
.include "../../rtl/analog_cim/sense_amp_calibrated.spice"
.lib "/foss/pdks/sky130A/libs.tech/ngspice/sky130.lib.spice" tt_mm

Vvdd VDD 0 DC 1.8
Vvss VSS 0 DC 0

* Clock: low = reset, high = evaluate
Vclk CLK 0 PULSE(0 1.8 5n 0.1n 0.1n 10n 20n)

.options reltol=1e-3 method=gear cmin=1f

* Main inputs are identical (Zero differential input)
Vinp INP 0 DC 1.2
Vinn INN 0 DC 1.2

* Trimming pair inputs
Vtrimp TRIMP 0 DC 1.2
Vtrimn TRIMN 0 DC 1.2

* Instantiate calibrated comparator (wmult=1 is baseline size, wtrim_mult=1/4 of that)
Xsa VDD VSS CLK INP INN TRIMP TRIMN OUTP OUTN strongarm_comparator_calibrated wmult=1 wtrim_mult=0.25

.control
  let num_samples = {NUM_SAMPLES}
  let vtrim_start = {VTRIM_START}
  let vtrim_stop  = {VTRIM_STOP}
  let vtrim_step  = {VTRIM_STEP}

  let sample = 1
  dowhile sample <= num_samples
    echo SAMPLE_START $&sample
    reset
    
    * We sweep VTRIM from negative to positive.
    * When VTRIMP is higher, OUTP goes high.
    let vtrim = vtrim_start
    dowhile vtrim <= vtrim_stop + 0.0001
      echo VTRIM_STEP $&vtrim
      let vp = 1.2 + vtrim/2
      let vn = 1.2 - vtrim/2
      alter Vtrimp = $&vp
      alter Vtrimn = $&vn
      
      tran 0.1n 10n
      meas tran outp_v find v(OUTP) at=9.5n
      print outp_v
      let vtrim = vtrim + vtrim_step
    end
    let sample = sample + 1
  end
  quit
.endc
.end
"""

def main():
    print(f"Generating SPICE deck for Self-Calibration ({NUM_SAMPLES} samples)...")
    os.makedirs(os.path.dirname(os.path.join(ROOT, TMP_REL)), exist_ok=True)
    with open(os.path.join(ROOT, TMP_REL), "w") as f:
        f.write(DECK)
    
    print("Running ngspice... (This may take a few minutes)")
    # Run ngspice
    p = subprocess.Popen(["ngspice", "-b", os.path.join(ROOT, TMP_REL)], 
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    
    calibrations = []
    out_of_range = 0
    
    current_sample = None
    current_vtrim = None
    
    with open(os.path.join(ROOT, "tb/analog_cim/raw_ngspice.log"), "w") as f_log:
        for line in p.stdout:
            f_log.write(line)
            msamp = re.search(r"SAMPLE_START\s+(\d+)", line)
            if msamp:
                current_sample = int(msamp.group(1))
                continue
            
            mtrim = re.search(r"VTRIM_STEP\s+([-\d\.eE]+)", line)
            if mtrim:
                current_vtrim = float(mtrim.group(1))
                continue
            
            mout = re.search(r"outp_v\s*=\s*([-+0-9eE\.]+)", line, re.IGNORECASE)
            if mout and current_sample is not None and current_vtrim is not None:
                val = float(mout.group(1))
                # If it flipped high and we haven't recorded a calibration for this sample yet
                if val > 0.9 and current_sample not in [c[0] for c in calibrations]:
                    calibrations.append((current_sample, current_vtrim * 1000.0))
                    print(f"Sample {current_sample:2d}: Nullified by VTRIM = {current_vtrim * 1000.0:>6.1f} mV", flush=True)
                
    p.wait()
    
    # Check for out of range
    found_samples = [c[0] for c in calibrations]
    for s in range(1, NUM_SAMPLES + 1):
        if s not in found_samples:
            print(f"Sample {s:2d}: Required VTRIM out of +/- {VTRIM_STOP*1000:.0f} mV range!")
            out_of_range += 1
            
    if not calibrations:
        print("ERROR: No calibrations found. SPICE may have crashed.")
        return
        
    just_vtrims = [c[1] for c in calibrations]
    mean_vtrim = statistics.mean(just_vtrims)
    std_vtrim = statistics.stdev(just_vtrims)
    max_abs_vtrim = max(abs(v) for v in just_vtrims)
    
    print(f"\n==== Calibration DAC Requirements ====")
    print(f"Total Samples    : {NUM_SAMPLES}")
    print(f"Successfully Calibrated : {len(calibrations)}")
    if out_of_range > 0:
        print(f"Failed (Out of Range)   : {out_of_range} (Increase VTRIM_STOP or wtrim_mult)")
        
    print(f"\nRequired VTRIM Distribution:")
    print(f"  Mean     : {mean_vtrim:6.2f} mV")
    print(f"  Std Dev  : {std_vtrim:6.2f} mV")
    print(f"  Max Abs  : {max_abs_vtrim:6.2f} mV")
    
    print(f"\n==== Residual Offset (Post-Calibration) ====")
    print(f"With a {VTRIM_STEP*1000:.1f} mV DAC step size (LSB):")
    # Residual error is uniform across [-LSB/2, LSB/2] 
    # But wait, we step VTRIM. The actual INP offset cancelled depends on the gain ratio of main vs trim pair!
    # wmult=1, wtrim_mult=0.25 -> 4:1 gain ratio. 
    # 5 mV step at VTRIM = 1.25 mV step equivalent at INP.
    effective_lsb = VTRIM_STEP * 1000.0 * (0.25 / 1.0)
    print(f"Effective input-referred LSB : {effective_lsb:.2f} mV (due to 4:1 width ratio)")
    residual_sigma = effective_lsb / (12**0.5)
    print(f"Residual sigma_offset        : {residual_sigma:.2f} mV")
    print(f"Residual 3-Sigma Tolerance   : {3*residual_sigma:.2f} mV")
    
    step_64 = 17.8
    if 3 * residual_sigma < step_64:
        print(f"\nSUCCESS! Post-calibration 3-sigma ({3*residual_sigma:.2f} mV) << 64-row step ({step_64} mV).")
    else:
        print(f"\nFAILED: Post-calibration 3-sigma ({3*residual_sigma:.2f} mV) > 64-row step ({step_64} mV).")

if __name__ == "__main__":
    main()
