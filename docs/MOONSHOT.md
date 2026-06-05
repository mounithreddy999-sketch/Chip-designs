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
- **M8 — Real PDK Monte-Carlo offset** ✅ *done + re-verified*: 50-sample MC sweep of $V_{diff}$ with
  Sky130 `tt_mm` mismatch on the StrongARM (`sw/mc_sa_probit.py`). Re-run confirms the probit CDF is
  **smooth, R²=0.97** → real per-sample mismatch, Gaussian offset (not a degenerate single draw). Robust
  **probit-regression $\sigma_{offset} \approx 10.3\ mV$** (3σ ≈ 31 mV); this supersedes the fragile
  two-crossing read, which scatters 9.66–10.9 mV at 50 samples/point. Verdicts hold (see M10 below).
- **M9 — Offset reduction** ✅ *done (sizing)*: input-pair upsizing sweep (`sw/mc_offset_vs_size.py`).
  σ: 11.1→5.8 mV over 1→4× area (Pelgrom 1/√WL holds), then **floors ~5 mV at 8×** (latch mismatch
  dominates). **4× input area makes the 64-row column resolvable** (σ=5.8, 3σ=17.4 < 18.3 mV step).
  Below ~5 mV needs the latch upsized too, or auto-zero/CDS (area-free). See result below.
- **M10 — Layout + PEX** ◑ *parts A+B+C done*: WIRE `C_BL` **0.232 fF/µm** (`pex/run_bitline_pex.py`),
  MOM `Cc` **0.308 fF/µm²** (`pex/run_mom_pex.py`), access-transistor junction **0.073 fF/cell**
  (`pex/run_junction_pex.py`, real PDK device). **Every bitline-budget cap is now extracted from sky130
  layout.** See results below. *Remaining stretch:* full 8T1C cell layout + Netgen LVS.
- **M11 — EACB (offset-aware training)** ✅ *done*: `sw/eacb_demo.py` injects the measured FIXED
  comparator-offset distribution into MLP training (digits). **At our ~7-bit readout SNR the offset
  costs ~0.2 pt (97.4→97.2%) — EACB unneeded.** It earns its keep only at ~6× worse offset (naive
  89.5% → EACB 94.0%, +4.5 pt), i.e. aggressive scaling / skipping M9. See result below.

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
- **σ_offset ≈ 10.3 mV** extracted + re-verified (M8 MC, probit R²=0.97) → 3σ ≈ 31 mV.
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

| rows | N·Cc | C_BL (wire+junc) | step (mV/row) | vs 31 mV (3σ) |
| --: | --: | --: | --: | :-- |
| 16 (segment) | 16 fF | ~11 fF | **~67** | 2.3× — resolvable per-row, no cal |
| 64 (continuous) | 64 fF | ~44 fF | **~17** | 0.6× — marginal, needs M9 |

The 16-row verdict is **robust to the junction estimate**: even at a generous 0.5 fF/cell the step is
~57 mV ≫ 31 mV.

**M10b — MOM cap `Cc` (`pex/run_mom_pex.py`):** single-layer met2 interdigitated comb (min finger
W/spacing) extracts **0.308 fF/µm²**:

| fingers | area (µm²) | Cc (fF) |
| --: | --: | --: |
| 8 | 4.48 | 1.30 |
| 12 | 6.72 | 2.03 |
| 16 | 13.44 | 4.45 |

So the **1 fF `Cc` assumption is real** — achievable in ~3.2 µm² single-layer (~1.8 µm square), or
~1.3 µm² stacking M2–M4.

**M10c — access-transistor junction (`pex/run_junction_pex.py`):** a real sky130 nfet (W=0.42, L=0.15)
drawn with the PDK device generator extracts to `ad=0.122 µm²`, `pd=1.42 µm`, **drain junction
`Cjd` = 0.073 fF/cell** (the only DRC flags are Metal1 min-area on the isolated terminal stubs — an
extraction artifact that vanishes once pins connect to bitline/wordline routing; the diffusion geometry
is valid). That's *smaller* than the 0.2 fF estimate, so the step nudges up.

**Complete measured `C_BL` budget** (every cap from sky130 layout/MC; only the 2 µm pitch is assumed):

| rows | wire | N·junc | N·Cc | step (mV/row) | vs 31 mV (3σ) |
| --: | --: | --: | --: | --: | :-- |
| 16 (segment) | 7.4 fF | 1.2 fF | 16 fF | **73.3** | 2.4× — resolvable, no cal |
| 64 (continuous) | 29.7 fF | 4.7 fF | 64 fF | **18.3** | 0.6× — marginal, M9 |

The **16-row segment is now fully silicon-grounded** — wire, MOM, junction all PEX-extracted, offset
from real-PDK MC — and resolvable with zero calibration. The cell load `N·Cc` dominates; the verdict is
robust to the 2 µm pitch assumption (3 µm → step still ~64 mV).

## M9 result — offset reduction by input-pair sizing (`sw/mc_offset_vs_size.py`)
Swept the StrongARM input-pair width (area) and re-ran the `tt_mm` MC + probit fit at each:

| input area | σ_offset (mV) | 3σ (mV) | σ·√area | 64-row (18.3 mV step)? |
| --: | --: | --: | --: | :-- |
| 1× | 11.1 | 33.3 | 11.1 | no |
| 2× | 7.8 | 23.3 | 11.0 | no |
| 4× | 5.8 | 17.4 | 11.6 | **yes** |
| 8× | 5.25 | 15.8 | 14.9 | yes |

**Pelgrom σ∝1/√(WL) holds 1→4×** (σ·√area ≈ 11, constant), then **floors at ~5 mV by 8×**: once the
input pair is no longer dominant, the **latch regeneration mismatch** sets the floor, so input-pair
upsizing saturates. **4× input-pair area makes the 64-row column resolvable** (3σ=17.4 < the 18.3 mV/row
step). Going below ~5 mV (more rows / margin) needs the latch upsized too, or — the area-free route —
**auto-zeroing / CDS** (sample-and-subtract the offset, limited only by charge-injection residual). That
is the M9 follow-up for 128+ rows.

## M11 result — offset-aware (EACB) training (`sw/eacb_demo.py`)
The comparator offset is a FIXED per-column bias (not random noise), so it is *trainable-away*.
Injected the measured offset distribution into a 64→32→10 MLP (digits, both layers analog);
deployment accuracy averaged over 25 offset draws ("chips"), ideal (clean) = 0.974:

| offset (× pre-act std) | naive | EACB | EACB gain |
| :-- | --: | --: | --: |
| 0.05 (~HW point, SNR 114) | 0.972 | 0.976 | +0.4 pt |
| 0.10 | 0.967 | 0.971 | +0.3 pt |
| 0.20 | 0.950 | 0.953 | +0.3 pt |
| 0.30 (~6× our offset) | 0.895 | 0.940 | **+4.5 pt** |

**Honest takeaway: at the extracted readout SNR the fixed offset costs ~0.2 pt — EACB is *not needed*
for the 16/64-row column.** It earns its keep only at ~6× worse offset (naive loses 8 pt, EACB recovers
4.5), i.e. when pushing to very high row counts or skipping the M9 sizing. A clean-enough analog macro
beats one that *relies* on error-correction.

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
