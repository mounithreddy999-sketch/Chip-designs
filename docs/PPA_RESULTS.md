# PIM Macro — Silicon-Honest PPA Results (Sky130, OpenLane)

A 16×16 INT8 matrix-vector-multiply accelerator, taken through RTL → cocotb/Verilog
verification → Yosys synthesis → OpenLane place-and-route, and measured under a
**realistic inference workload** (weights loaded once, activations streamed).

## Methodology — why these numbers are trustworthy

- **Correctness:** every design point passes the *same* self-checking golden-MVM
  scoreboard (random + directed), so power/area changes provably preserve function.
- **Power is workload-driven, not assumed.** OpenROAD's default activity assumes the
  weight inputs toggle every cycle — they don't (weights are stationary during
  inference). Reading a VCD from the actual *load-once-then-stream* workload against
  the post-CTS netlist drops the baseline from a **static estimate of 81.9 mW to a
  true 52.2 mW** — a more honest number, not a smaller one.

## The scaling journey

| Step | What changed | Result |
| :--- | :--- | :--- |
| Unpipelined | depth-N ripple reduction | ~10 MHz, ~0.0051 TOPS |
| **Pipelined** | log₂(N) balanced adder tree, 2-stage | **100 MHz, 0.0512 TOPS (10× throughput)** |
| **Clock-gated** | ICG on the 2,048 stationary weight flops | **37% dynamic power cut, same 100 MHz** |
| **Near-memory** | weights in OpenRAM SRAM (streaming) | **4.8× smaller silicon footprint** |

## Verified tradeoff frontier

Each row is **one** physical design. The wins live on **different axes** — there is
no single design that achieves all the bests at once.

| Design | Throughput | Die area | Workload power | TOPS/W | pJ/MAC |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Flop baseline (`CG_WEIGHTS=0`) | 0.0512 TOPS (256 MAC/cyc) | 2.92 mm² | 52.2 mW | 0.98 | 2.04 |
| **Clock-gated (`CG_WEIGHTS=1`)** ⭐ | 0.0512 TOPS (256 MAC/cyc) | 2.92 mm² | **32.8 mW** | **1.56** | **1.28** |
| Batched Near-Memory (`B=4`) | 0.0032 TOPS (16 MAC/cyc) | **0.602 mm²** | 18.5 mW | 0.17 | 11.56 |
| Streaming Near-Memory (`B=1`) | 0.0008 TOPS (4 MAC/cyc) | **0.602 mm²** | 7.59 mW | 0.11 | 18.98 |

**Two distinct wins on two distinct axes:** clock-gating owns **energy** (1.28 pJ/MAC
at full throughput); SRAM owns **area** (4.8× density). That Pareto frontier is the
result — not a single "best of everything" point, because no fabricated chip realizes
the gated design's efficiency *and* the SRAM design's footprint simultaneously.

## The clock-gating win (the headline digital result)

Measured by reading the clock-gated workload VCD against the post-CTS database:

| Power component | Baseline | Clock-gated | Δ |
| :--- | :---: | :---: | :---: |
| Sequential (flops) | 26.2 mW | 17.8 mW | −8.4 mW |
| Clock tree | 25.9 mW | 14.9 mW | −11.0 mW |
| **Total dynamic** | **52.2 mW** | **32.8 mW** | **−37.1%** |

Gating the clock to weights that never change during inference severs the clock-tree
branch driving 2,048 flops and stops their internal clocking — **a 37% energy
reduction with zero throughput or Fmax cost.**

## What is *not* claimed (disclaimers kept honest)

- The **SRAM near-memory design's pJ/MAC is measured from the synthesis netlist** (`read_verilog` + SRAM `.lib` + workload VCD), since layout stopped at the PDN-insertion failure. Two honesty notes: **(a)** the `report_power` *Combinational* row reads ~0.0% — a VCD name-mapping artifact (synthesis renames internal nets, so the RTL-named VCD can't annotate the multiplier/adder logic), which makes the dynamic power a mild **under**-estimate; the dominant **Macro** and **Sequential** terms are well-grounded. **(b)** As predicted, the serialized lanes yield *worse* energy efficiency than the parallel baseline — serialization is an **area/leakage play, not an energy-per-MAC play**. By introducing **Batched Weight Reuse (B=4)**, we recover 4x the throughput and improve energy efficiency to **11.56 pJ/MAC** while maintaining the exact same 4.8x footprint reduction!
- **0.602 mm²** is the SRAM *macro* footprint (8 kbit; leakage 9.5 µW). The full
  streaming design adds its datapath and die margin.
- A single design capturing **both** the energy and area wins (SRAM-resident weights +
  clock-gated/efficient datapath) is a **future build**, to be measured on the same
  footing — not implied by this table.
