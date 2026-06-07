#!/usr/bin/env python3
import subprocess

try:
    p = subprocess.run(["ngspice", "-b", "smoke_test.spice"], capture_output=True, text=True, timeout=5)
    print("STDOUT:", p.stdout)
    print("STDERR:", p.stderr)
except subprocess.TimeoutExpired as e:
    print("STDOUT:", e.stdout)
    print("STDERR:", e.stderr)
