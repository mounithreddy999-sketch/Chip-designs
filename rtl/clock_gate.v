/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * Integrated clock gate (ICG).
 *
 * Glitch-free latch-based clock gating: the enable is sampled on the LOW phase
 * of the clock (transparent latch) and then ANDed with the clock, so GCLK never
 * glitches when `enable` changes mid-cycle. Used to stop clocking stationary
 * weight registers during inference.
 *
 * Default: portable behavioral RTL (simulates in Icarus, maps in Yosys).
 * Define USE_SKY130_ICG to bind the hardened sky130 clock-gate cell instead.
 */

`default_nettype none

module clock_gate (
    input  wire clk,
    input  wire enable,
    output wire gclk
);
`ifdef USE_SKY130_ICG
    sky130_fd_sc_hd__dlclkp_1 u_icg (
        .CLK  (clk),
        .GATE (enable),
        .GCLK (gclk)
    );
`else
    reg en_latch;
    always @(*)
        if (!clk)
            en_latch = enable;
    assign gclk = clk & en_latch;
`endif

endmodule

`default_nettype wire
