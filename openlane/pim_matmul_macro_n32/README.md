# N=32 scaling experiment

Same `pim_matmul_macro` RTL, synthesized at **N=32** (1,024 MACs/cycle, 4× the
N=16 array). Two configs:

- `pim_matmul_macro_n32/`    — baseline (CG_WEIGHTS=0)
- `pim_matmul_macro_n32_cg/` — clock-gated (CG_WEIGHTS=1)

**Question:** does the clock-gating energy win (1.28 pJ/MAC at N=16) *hold, grow,
or shrink* at 4× the array? Weight flops scale as N² (1,024 → gated), pipeline
flops scale as N² too, so the gated fraction should stay ~constant — but CTS and
wire load change with size. Measure it, don't assume.

## Run + measure (same flow as N=16)

```bash
# functional check at N=32 (already passing: 6496 checks)
iverilog -g2012 -D TB_N=32 rtl/pim_matmul_macro.v rtl/clock_gate.v \
    tb/tb_pim_matmul_macro.v && vvp a.out

# workload VCD at N=32
iverilog -g2012 -D TB_N=32 -D WORKLOAD_VECTORS=2000 rtl/pim_matmul_macro.v \
    rtl/clock_gate.v tb/tb_pim_matmul_macro_workload.v && vvp a.out   # baseline
#  + -D TB_CG for the gated VCD

# OpenLane each config, then VCD power (workload_power.tcl), then:
python sw/ppa_scorecard.py --n 32 --freq <Fmax> --power <W> --area <mm2>
```

Notes:
- `CLOCK_PERIOD=10` (100 MHz) is the target; the N=32 adder tree is 5 levels (vs
  4 at N=16), so if WNS goes negative, relax toward ~12 ns and re-score at the
  achieved Fmax.
- `FP_CORE_UTIL` lowered to 40 (the 4× cell count routes harder); raise if the
  die is wastefully large, lower if routing congests.
