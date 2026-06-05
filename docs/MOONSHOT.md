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
- **M6 — Charge-domain cell** ✅ *done (behavioral)*: `rtl/analog_cim/cim_cell_charge.spice` — MOM
  coupling cap + product driver. RBL voltage confirmed **linear** in Σ(X·W) (R²=1.0). See result below.
- **M7 — Segmented vs continuous** ✅ *done (behavioral)*: `sw/run_charge_linearity.py`. Per-row step
  stays resolvable at 16 rows (15.5 mV) where the continuous 64-row line collapses (3.2 mV). See below.
- **M8 — Real PDK Monte-Carlo offset** ✅ *done*: We ran a 50-sample Monte Carlo simulation for $V_{diff}$ using Sky130 `tt_mm` mismatch models on the StrongARM sense amp. Extracted $\sigma_{offset} = 9.66\ mV$. 3-sigma tolerance = $29\ mV$. Since our bitline swing is $\approx 100\ mV$, this offset is safely resolvable!
- **M9 — Offset-cancelled sense amp**: add dynamic body biasing / self-calibration to the
  StrongARM, target σ_offset < ~3 mV → set the real max column height = full-scale / 3σ.
- **M10 — Layout + PEX** ◑ *part A done*: bitline WIRE cap extracted in Magic
  (`pex/run_bitline_pex.py`) = **0.232 fF/µm** (met2, min-width, min-spacing grounded neighbors).
  See result below. *Part B (pending):* draw the cell → extract the MOM cap Cc + access-transistor
  junction; LVS via Netgen. The `C_BL / N·Cc` ratio is what decides whether the math survives physics.
- **M11 — EACB**: train a small classifier on the extracted hardware offset/noise model so final
  accuracy ≈ FP baseline at the analog macro's TOPS/W.

## M6/M7 result — linearity + segmentation (`sw/run_charge_linearity.py`)
Swept active rows 0..N for three column configs in ngspice (batch, iic-osic-tools Docker).
The SPICE reproduces the capacitor-divider closed form `V_BL(n)=n·Cc·VDD/(N·Cc+C_BL)` **exactly**:

| config | N | C_BL | step (mV/row) | analytic | R² | vs 5 mV offset |
| :-- | --: | --: | --: | --: | --: | :-- |
| segment-8 | 8 | 50 fF | 31.0 | 31.0 | 1.0000 | 6.2× resolvable |
| segment-16 | 16 | 100 fF | 15.5 | 15.5 | 1.0000 | 3.1× resolvable |
| continuous-64 | 64 | 500 fF | 3.2 | 3.2 | 1.0000 | 0.6× — below offset |

**Establishes:** the charge-domain MAC is *linear* (a cap ratio); the per-row step is set by the
ratio of parasitic `C_BL` to the cell load `N·Cc`. **The `C_BL` column above is placeholder** — M10
PEX (below) extracts the real value, which revises the magnitudes substantially.

**Does NOT prove / since-corrected (honest caveats):**
- Behavioral cell (ideal product source + ideal cap): no NMOS-pass Vth drop, charge injection,
  or junction cap. R²=1.0 confirms the *math is self-consistent*, **not silicon**.
- **σ_offset = 9.66 mV** extracted (M8 MC on the StrongARM) → 3σ ≈ 29 mV.
- **The C_BL placeholders were ~10× too high.** M10 PEX (below) measures the real wire C_BL; with it
  the 16-row step is ~67 mV (resolvable, *no* calibration) and the 64-row step ~17 mV (marginal, M9).
  i.e. the cell load `N·Cc` dominates the small parasitic — the *opposite* of what the placeholders
  implied. The ~9-row wall was a *current-steering* property; the charge-domain limit is ~16–60 rows.

Remaining to fully close: extract the MOM cap **Cc** + the access-transistor junction (M10b), then **M9**.

## M10 result (part A) — real bitline WIRE cap via Magic PEX (`pex/run_bitline_pex.py`)
Extracted sky130 met2 bitline cap (W=0.14 µm, min-spacing grounded neighbors, resistance off,
`cthresh 0.01`), three cross-sections to bracket it:

| cross-section | fF/µm |
| :-- | --: |
| isolated over substrate (floor) | 0.078 |
| **+ grounded neighbor bitlines (coupling)** | **0.232** |
| + met1 ground plane (ceiling) | 0.277 |

Coupling to adjacent min-spacing bitlines triples the wire cap — the dominant wire term, as expected.
At a ~2 µm cell pitch the realistic **wire** C_BL is 0.46 fF/row → **7.4 fF over 16 rows, 29.7 fF over
64 rows** — ~10× *smaller* than the 50/100/500 fF placeholders.

Real per-row step `Cc·VDD/(N·Cc + C_BL)`, using extracted wire + estimated ~0.2 fF/cell junction +
the cells' MOM load (Cc = 1 fF, *still placeholder*):

| rows | N·Cc | C_BL (wire+junc) | step (mV/row) | vs 29 mV (3σ) |
| --: | --: | --: | --: | :-- |
| 16 (segment) | 16 fF | ~11 fF | **~67** | 2.3× — resolvable per-row, no cal |
| 64 (continuous) | 64 fF | ~44 fF | **~17** | 0.6× — marginal, needs M9 |

The 16-row verdict is **robust to the junction estimate**: even at a generous 0.5 fF/cell the step is
~57 mV ≫ 29 mV. **Measured = the wire cap (0.232 fF/µm).** Still estimated/assumed: the MOM cap `Cc`
(→ M10b extract the interdigitated fingers), the junction (→ draw the cell), and the 2 µm pitch.

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
