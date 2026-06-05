# Moonshot — Charge-Domain Analog CIM on Sky130

The novel, "known-in-the-open-silicon-world" axis. The digital Pareto frontier is the
**bird in hand** (verified, measured); this is the **moon shot**: an analog Compute-In-Memory
macro that beats the digital pJ/MAC and scales past the passive ~9-row wall we measured.

## Where we are (and why the "failure" was the right move)
- We built a **current-steering** analog cell and measured the **passive ~9-row charge-sharing
  limit** + the Pelgrom-mismatch sensitivity (σ_Vth = 4.33 mV from the PDK).
- **Verdict (research-confirmed): current-domain / subthreshold steering is scientifically
  disqualified on Sky130** — bitline droop pushes cells out of saturation (severe
  non-linearity) and subthreshold current is *exponentially* sensitive to Vth mismatch.
  Rigorously killing it is the result, not a setback.

## The next architecture (the moon): Charge-Domain + MOM caps + Segmented Bitlines
Linearity from a **capacitor ratio**, not transistor current → PVT-robust. Lineage: C3SRAM →
PICO-RAM (in-situ multi-bit, the same MOM caps reused for DAC + MAC + SAR-ADC).

| Lever | Why | Sky130 specific |
| :--- | :--- | :--- |
| **MOM fringe capacitor** | Linear C(V), excellent matching | interdigitated M3/M4 fingers (NOT MOSCAP — MOSCAPs are wildly non-linear) |
| **Charge-domain MAC** | RBL voltage = Σ(Xᵢ·Wᵢ)·C_unit / (Σ C_unit + C_par) — *linear* | passive switching, ~zero static power |
| **Segmented bitline (SBCS)** | local BL of 8–16 cells (small C_par) keeps the step large; buffer onto global BL | breaks ~9 rows → **64–256 rows** |
| **8T1C / 10T1C cell** | isolated read port (no read-disturb), fixes NMOS-pass-high Vth drop | ~1.5× 6T area; 10T1C uses bottom-plate sampling |
| **Offset-cancelled sense amp** | σ_offset sets max rows; DBB + self-cal → σ < ~3 mV | dynamic body bias on the input pair |
| **EACB (system)** | train the net on the *measured* hardware non-idealities to absorb residual noise | hardware-aware AdaBoost |

## Execution plan (mapped to our tooling)
- **M6 — Charge-domain cell** ✦ *first build*: `rtl/analog_cim/cim_cell_charge.spice` — MOM
  coupling cap + product driver. Demonstrate the RBL voltage is **linear** in Σ(X·W).
- **M7 — Segmented vs continuous**: local-BL clusters + buffer onto global BL. Show the per-row
  step stays resolvable at 16, 32, 64 rows where the continuous array collapsed at ~9.
- **M8 — Real PDK Monte-Carlo offset**: rewrite the MC to use the *actual* sky130 statistical
  models — `.param mc_mm_switch=1` / `mc_pr_switch=0` + a `.control` reset/run loop — instead of
  the injected-source hack that broke the solver. Probit-fit σ_offset.
- **M9 — Offset-cancelled sense amp**: add dynamic body biasing / self-calibration to the
  StrongARM, target σ_offset < ~3 mV → set the real max column height = full-scale / 3σ.
- **M10 — Layout + PEX**: draw the cell in Magic; extract parasitics with
  `ext2spice cthresh 0.01` + `ext2spice extresist on`, LVS via Netgen. The C_par/C_unit ratio
  from PEX is what decides whether the math survives physics.
- **M11 — EACB**: train a small classifier on the extracted hardware offset/noise model so final
  accuracy ≈ FP baseline at the analog macro's TOPS/W.

## Verification methodology (open-source, from the research)
- **ngspice MC**: `mc_mm_switch=1` (local mismatch), `mc_pr_switch=0` (no global spread); loop
  `reset; run` for 30+ seeds; parse with Python; extract σ at 3σ vs the ADC/SA tolerance.
- **Magic PEX**: `ext2spice cthresh 0.01`, `ext2spice extresist on` → annotated netlist → resim
  the charge-sharing on the *real* global bitline → confirm step stays above the SA offset.

## Target
Break the measured ~9-row passive ceiling → a **segmented charge-domain CIM column on open
Sky130** with a measured pJ/MAC that beats the digital frontier and a *layout-validated* (PEX)
signal margin. That — fully open, silicon-honest — is the genuinely-new contribution.

*(Synthesized from the user's research report "Analog CIM Exploration Next Steps" — C3SRAM,
PICO-RAM, SBCS, time-domain, DBB sense amps, EACB. Time-domain (delay + SAR-TDC) is the
documented secondary path if charge-domain layout proves intractable.)*
