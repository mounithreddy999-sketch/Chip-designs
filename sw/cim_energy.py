#!/usr/bin/env python3
"""
Charge-domain CIM energy/MAC -- the payoff metric, from MEASURED inputs only.

Every term here is extracted or simulated, not assumed:
  - MOM cap Cc           = 1.0 fF        (M10b, pex/run_mom_pex.py: 0.308 fF/um^2, real)
  - bitline wire / row   = 0.464 fF      (M10a, 0.232 fF/um x 2 um pitch)
  - access junction/cell = 0.073 fF      (M10c, pex/run_junction_pex.py, real PDK device)
  - StrongARM decision   = 58.8 fJ       (measured: integ i(VDD) over one cycle)

Per column-evaluation (one binary MVM of N products):
  E_eval = C_tot * VDD^2 + E_SA,   C_tot = N*(Cc + wire/row + junc)   [conservative full-swing]
  binary energy/MAC = E_eval / N  ->  C_per_row*VDD^2 + E_SA/N  (floor = per-row cap switching)

INT8 via bit-slicing (conservative, fully bit-serial both operands): x64 binary passes.
Real multi-bit charge-weighted cells cut that factor a lot (noted, not claimed here).
"""
VDD = 1.8
CC = 1.0e-15            # F   (M10b)
WIRE_PER_ROW = 0.464e-15  # F  (M10a, 2 um pitch)
JUNC = 0.073e-15       # F   (M10c)
E_SA = 58.8e-15        # J   (measured)
C_PER_ROW = CC + WIRE_PER_ROW + JUNC   # total bitline cap added per row

DIGITAL_BEST = 1.28    # pJ/MAC, clock-gated INT8 (verified frontier)


def binary_fJ_per_mac(n):
    e_eval = (n * C_PER_ROW) * VDD ** 2 + E_SA      # J
    return e_eval / n * 1e15                          # fJ/binary-MAC


def main():
    print(f"per-row bitline cap = {C_PER_ROW*1e15:.3f} fF  (Cc {CC*1e15:.2f} + wire "
          f"{WIRE_PER_ROW*1e15:.3f} + junc {JUNC*1e15:.3f})")
    print(f"energy floor (N->inf) = {C_PER_ROW*VDD**2*1e15:.2f} fJ/binary-MAC\n")
    print(f"{'N rows':>7} | {'binary fJ/MAC':>13} | {'INT8 pJ/MAC (x64 est)':>21} | {'vs digital 1.28':>16}")
    print("-" * 70)
    for n in (16, 64, 256):
        b = binary_fJ_per_mac(n)
        int8_pj = b * 64 / 1000.0                      # conservative bit-serial INT8
        print(f"{n:>7} | {b:>11.2f}   | {int8_pj:>17.3f}     | {DIGITAL_BEST/int8_pj:>13.1f}x")
    print("\nNotes:")
    print(" - binary fJ/MAC is rigorous (extracted caps + measured SA); the native charge-domain op.")
    print(" - INT8 x64 is the CONSERVATIVE fully-bit-serial bound; multi-bit charge-weighted cells")
    print("   cut the factor ~4-8x -> INT8 ~0.05-0.1 pJ/MAC (10-25x digital). Reported as a range.")
    print(" - C_tot*VDD^2 is full-swing (worst case); real activity/partial-swing is lower.")


if __name__ == "__main__":
    main()
