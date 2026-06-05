#!/usr/bin/env python3
import os
import subprocess
import sys

def main():
    cwd = os.getcwd()
    docker_vol = cwd.replace('/mnt/c', 'C:').replace('\\', '/')
    
    deck_rel = "tb/analog_cim/tb_sense_amp.spice"
    cmd = ["docker.exe", "run", "--rm", "-v", f"{docker_vol}:/foss/designs", "-w", "/foss/designs",
           "hpretl/iic-osic-tools:latest", "--skip", "ngspice", "-b", deck_rel]
    
    print(f"Running M4 sense amp simulation via Docker...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Docker failed! stdout: {result.stdout}")
        print(f"Docker failed! stderr: {result.stderr}")
        sys.exit(1)
    print(result.stdout)

if __name__ == "__main__":
    main()
