/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Piecewise-Linear (PWL) Reciprocal Module (2-Stage Pipelined)
 * Approximates 1/S for S in [1.0, 8.0].
 * Input: 16-bit unsigned Q3.13 format (range: [1.0, 8.0], where 16'h2000 = 1.0)
 * Output: 16-bit unsigned Q1.15 format (range: [0.125, 1.0], where 16'h7FFF = 1.0)
 * 
 * Pipeline Latency: 2 cycles.
 */

`default_nettype none

module mx_pwl_recip (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     en,
    input  wire [15:0]              in_data,  // Q3.13 unsigned input
    output reg  [15:0]              out_data  // Q1.15 unsigned output
);

    // ====================================================
    // STAGE 1: Range Decode & Table Selection (Combinational)
    // ====================================================
    reg [15:0] base_val;
    reg [15:0] slope;
    reg [15:0] offset;

    always @(*) begin
        // default settings for S < 1.0
        base_val = 16'h7FFF; // 1.0 in Q1.15
        slope    = 16'd0;
        offset   = 16'h2000;

        if (in_data >= 16'hE000) begin
            // 7.0 <= S <= 8.0 -> 1/S = 0.1429 - 0.0179 * (S - 7.0)
            base_val = 16'd4681;  // 0.1429 in Q1.15
            slope    = 16'd585;   // 0.0179 in Q1.15
            offset   = 16'hE000;  // 7.0 in Q3.13
        end else if (in_data >= 16'hC000) begin
            // 6.0 <= S < 7.0 -> 1/S = 0.1667 - 0.0238 * (S - 6.0)
            base_val = 16'd5461;  // 0.1667 in Q1.15
            slope    = 16'd780;   // 0.0238 in Q1.15
            offset   = 16'hC000;  // 6.0 in Q3.13
        end else if (in_data >= 16'hA000) begin
            // 5.0 <= S < 6.0 -> 1/S = 0.2000 - 0.0333 * (S - 5.0)
            base_val = 16'd6554;  // 0.2000 in Q1.15
            slope    = 16'd1092;  // 0.0333 in Q1.15
            offset   = 16'hA000;  // 5.0 in Q3.13
        end else if (in_data >= 16'h8000) begin
            // 4.0 <= S < 5.0 -> 1/S = 0.2500 - 0.0500 * (S - 4.0)
            base_val = 16'd8192;  // 0.2500 in Q1.15
            slope    = 16'd1638;  // 0.0500 in Q1.15
            offset   = 16'h8000;  // 4.0 in Q3.13
        end else if (in_data >= 16'h6000) begin
            // 3.0 <= S < 4.0 -> 1/S = 0.3333 - 0.0833 * (S - 3.0)
            base_val = 16'd10922; // 0.3333 in Q1.15
            slope    = 16'd2730;  // 0.0833 in Q1.15
            offset   = 16'h6000;  // 3.0 in Q3.13
        end else if (in_data >= 16'h4000) begin
            // 2.0 <= S < 3.0 -> 1/S = 0.5000 - 0.1667 * (S - 2.0)
            base_val = 16'd16384; // 0.5000 in Q1.15
            slope    = 16'd5462;  // 0.1667 in Q1.15
            offset   = 16'h4000;  // 2.0 in Q3.13
        end else if (in_data >= 16'h2000) begin
            // 1.0 <= S < 2.0 -> 1/S = 1.0000 - 0.5000 * (S - 1.0)
            base_val = 16'h7FFF;  // 1.0000 in Q1.15
            slope    = 16'd16384; // 0.5000 in Q1.15
            offset   = 16'h2000;  // 1.0 in Q3.13
        end
    end

    // ====================================================
    // STAGE 1 REGISTERS (Pipeline registers)
    // ====================================================
    reg [15:0] r_in_data;
    reg [15:0] r_base_val;
    reg [15:0] r_slope;
    reg [15:0] r_offset;

    always @(posedge clk) begin
        if (rst) begin
            r_in_data  <= 16'h0000;
            r_base_val <= 16'h0000;
            r_slope    <= 16'd0;
            r_offset   <= 16'h0000;
        end else if (en) begin
            r_in_data  <= in_data;
            r_base_val <= base_val;
            r_slope    <= slope;
            r_offset   <= offset;
        end
    end

    // ====================================================
    // STAGE 2: Offset Subtraction & Multiplication (Arithmetic)
    // ====================================================

    // Compute delta S = S - offset using registered Stage 1 values
    wire [15:0] dS = (r_in_data > r_offset) ? (r_in_data - r_offset) : 16'd0;

    // Multiply: dS (Q3.13) * slope (Q1.15) -> Q4.28. Shift by 13 to get Q1.15
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] dy_ext = dS * r_slope;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [15:0] dy = {1'b0, dy_ext[27:13]};

    // Compute 1/S = base_val - dy
    // Ensure we do not underflow past 0
    wire [15:0] next_out_data = (r_base_val > dy) ? (r_base_val - dy) : 16'h0000;

    // ====================================================
    // STAGE 2 REGISTERS (Output registers)
    // ====================================================
    always @(posedge clk) begin
        if (rst) begin
            out_data <= 16'h0000;
        end else if (en) begin
            out_data <= next_out_data;
        end
    end

endmodule
