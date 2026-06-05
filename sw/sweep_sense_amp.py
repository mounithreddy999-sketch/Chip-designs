#!/usr/bin/env python3
import os
import subprocess
import re
import sys

def run_sense_amp(vdiff_mv):
    cwd = os.getcwd()
    docker_vol = cwd.replace('/mnt/c', 'C:').replace('\\', '/')
    
    # Calculate voltages
    vdiff = vdiff_mv / 1000.0
    vcm = 1.2
    vinp = vcm + vdiff/2.0
    vinn = vcm - vdiff/2.0
    
    deck_path = "tb/analog_cim/tb_sense_amp.spice"
    
    with open(deck_path, "r") as f:
        content = f.read()
        
    # Replace VDIFF param
    content = re.sub(r"\.param\s+VDIFF\s*=\s*[0-9\.\-]+", f".param VDIFF = {vdiff}", content)
    # Replace Vinp and Vinn
    content = re.sub(r"Vinp\s+INP\s+0\s+DC\s+[0-9\.\-]+", f"Vinp INP 0 DC {vinp:.4f}", content)
    content = re.sub(r"Vinn\s+INN\s+0\s+DC\s+[0-9\.\-]+", f"Vinn INN 0 DC {vinn:.4f}", content)
    
    with open(deck_path, "w") as f:
        f.write(content)
        
    cmd = ["docker.exe", "run", "--rm", "-v", f"{docker_vol}:/foss/designs", "-w", "/foss/designs",
           "hpretl/iic-osic-tools:latest", "--skip", "ngspice", "-b", deck_path]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Docker failed for {vdiff_mv}mV!")
        sys.exit(1)
        
    # Parse output
    out = result.stdout
    # ngspice print output looks like:
    # outp_v = 1.800000e+00
    # outn_v = 0.000000e+00
    # e_decision = 1.234e-14
    m_outp = re.search(r"outp_v\s*=\s*([0-9eE\.\-\+]+)", out)
    m_outn = re.search(r"outn_v\s*=\s*([0-9eE\.\-\+]+)", out)
    m_edec = re.search(r"e_decision\s*=\s*([0-9eE\.\-\+]+)", out)
    
    outp = float(m_outp.group(1)) if m_outp else -1
    outn = float(m_outn.group(1)) if m_outn else -1
    edec = float(m_edec.group(1)) if m_edec else -1
    
    return outp, outn, edec

def main():
    print("Sweeping Sense Amp VDIFF...")
    print(f"{'VDIFF(mV)':<10} | {'OUTP(V)':<10} | {'OUTN(V)':<10} | {'E_DECISION(fJ)':<15} | {'RESOLVED?':<10}")
    print("-" * 65)
    
    # 50mV is the baseline. Then sweep down.
    for vdiff_mv in [50, 20, 10, 5, 2, 1, 0.5, 0.1]:
        outp, outn, edec = run_sense_amp(vdiff_mv)
        resolved = "YES" if (outp > 1.5 and outn < 0.3) else "NO"
        edec_fj = edec * 1e15 if edec != -1 else 0
        print(f"{vdiff_mv:<10.1f} | {outp:<10.4f} | {outn:<10.4f} | {edec_fj:<15.4f} | {resolved:<10}")

if __name__ == "__main__":
    main()
