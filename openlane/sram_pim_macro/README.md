# sram_pim_macro — OpenLane hardened-SRAM integration

Near-memory MVM macro (`rtl/sram_pim_macro.v`) with the weight matrix resident in
a hardened **OpenRAM** SRAM (`sky130_sram_1kbyte_1rw1r_32x256_8`) instead of a
flip-flop array. This run measures the **area** and **leakage** that make the
near-memory case — *not* a peak pJ/MAC win (see the project notes: a 4-wide
streaming lane sacrifices the parallelism that amortizes overhead).

## Before you run — supply the hardened macro views

The behavioral model in `tb/sky130_sram_1kbyte_1rw1r_32x256_8.v` is **simulation
only**. Physical implementation needs the real hardened macro. Drop these into
`openlane/sram_pim_macro/macros/` (or repoint the paths in `config.json`):

```
macros/sky130_sram_1kbyte_1rw1r_32x256_8.lef   # abstract (placement/routing)
macros/sky130_sram_1kbyte_1rw1r_32x256_8.lib   # timing + power (synth blackbox + STA)
macros/sky130_sram_1kbyte_1rw1r_32x256_8.gds   # layout (final stream-out)
```

These ship with the sky130 OpenRAM macro set (commonly under
`$PDK_ROOT/sky130A/libs.ref/sky130_sram_macros/...` or your OpenRAM build output).
Yosys black-boxes the SRAM from the `.lib` (`EXTRA_LIBS`) — no Verilog stub needed,
and the behavioral model is intentionally **excluded** from `VERILOG_FILES`.

## Tuning knobs

- `DIE_AREA` / `macro_placement.cfg`: size the die and place `u_sram` to fit the
  macro's actual LEF dimensions (~0.68 × 0.45 mm) plus logic + pin ring.
- `FP_PDN_MACRO_HOOKS`: connects the macro's `vccd1/vssd1` to the PDN.
- Run in a **Linux Docker** container (Windows dies at GDS signoff).

## After it closes — fill the scorecard

Grab `wns` (sta summary), total **power** and the **leakage** component
(`report_power` / `metrics.csv`), and `DIEAREA_mm^2`, then:

```bash
# streaming lane = 4 MACs/cycle (NOT N*N) -> honest TOPS + pJ/MAC
python ../../sw/ppa_scorecard.py --n 16 --freq <Fmax_Hz> --power <W> --area <mm2> --macs-per-cycle 4
```

Then compare head-to-head with the flop baseline (`pim_matmul_macro`:
2.92 mm², 81.9 mW, 3.2 pJ/MAC, 256 MAC/cycle). Expect: **SRAM wins area + leakage,
loses peak pJ/MAC.** Report both — that honest tradeoff curve is the result.
