# pim_matmul_macro_cg — clock-gated weight baseline

Identical to `pim_matmul_macro` but synthesized with `CG_WEIGHTS=1`, which gates
the clock to the 2,048 stationary weight flops (enable = `w_write_en | rst`).
Goal: cut the dominant clock-tree/flop switching power of holding weights that
never change during inference. Throughput and Fmax are unchanged (256 MAC/cycle,
100 MHz target).

## Two things to know before trusting the power number

1. **Inferred latch vs hardened ICG.** The portable `clock_gate` (rtl/clock_gate.v)
   builds a latch-based gate in RTL. Yosys maps it, but if your OpenLane setup
   trips latch checks, either relax that check or rebuild with the real cell by
   defining `USE_SKY130_ICG` (binds `sky130_fd_sc_hd__dlclkp_1`). CTS must be
   allowed to build the gated clock branch.

2. **The win only shows under realistic activity.** With OpenLane's *default*
   switching activity, the tool may assume `w_write_en` toggles often and miss
   the benefit. The honest measurement is **VCD/SAIF-driven**: simulate the
   "load weights once, then stream many activation vectors" workload (w_write_en
   held low during inference), dump a VCD, and run `read_vcd` + `report_power`.
   That's where the gated weight flops show ~0 clock power.

## Compare three points

| Design | Throughput | Notes |
|---|---|---|
| `pim_matmul_macro` (CG=0) | 256 MAC/cyc | flop baseline: 2.92 mm², 81.9 mW, 3.2 pJ/MAC |
| `pim_matmul_macro_cg` (CG=1) | 256 MAC/cyc | this run — expect lower dynamic power, same area/Fmax |
| `sram_pim_macro` | 4 MAC/cyc | near-memory: area/leakage win, not pJ/MAC |

```bash
python ../../sw/ppa_scorecard.py --n 16 --freq <Fmax_Hz> --power <W> --area <mm2>
```
