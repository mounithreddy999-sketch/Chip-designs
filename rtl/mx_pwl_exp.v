/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Piecewise-Linear (PWL) Exponentiation Module (2-Stage Pipelined)
 * Approximates e^x for x <= 0.
 * Input: 16-bit signed Q4.12 format (range: [-8.0, 0.0])
 * Output: 16-bit unsigned Q1.15 format (range: [0.0, 1.0], where 16'h7FFF = 1.0)
 * 
 * Pipeline Latency: 2 cycles.
 */

`default_nettype none

module mx_pwl_exp (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     en,
    input  wire signed [15:0]       in_data,  // Q4.12 signed input
    output reg  [15:0]              out_data  // Q1.15 unsigned output
);

    // ====================================================
    // STAGE 1: Absolute Value & Range Decode (Combinational)
    // ====================================================
    
    // Compute absolute value of input (since input should be <= 0, absolute value z = -in_data)
    wire signed [15:0] z = (in_data[15] == 1'b1) ? -in_data : 16'sd0;

    reg [15:0] base_val;
    reg [15:0] slope;
    reg [15:0] offset;

    always @(*) begin
        // default settings for z = 0
        base_val = 16'h7FFF; // 1.0 in Q1.15
        slope    = 16'd20713; // 0.63212 in Q1.15
        offset   = 16'h0000;

        if (in_data >= 16'sd0) begin
            // Positive inputs clamped to 1.0
            base_val = 16'h7FFF;
            slope    = 16'd0;
            offset   = 16'h0000;
        end else if (z >= 16'h4000) begin
            // z >= 4.0 -> e^-z = 0
            base_val = 16'h0000;
            slope    = 16'd0;
            offset   = 16'h4000;
        end else if (z >= 16'h3000) begin
            // 3.0 <= z < 4.0 -> e^-z = 0.04979 - 0.03147 * (z - 3.0)
            base_val = 16'd1631;  // 0.04979 in Q1.15
            slope    = 16'd1031;  // 0.03147 in Q1.15
            offset   = 16'h3000;  // 3.0 in Q4.12
        end else if (z >= 16'h2000) begin
            // 2.0 <= z < 3.0 -> e^-z = 0.13534 - 0.08555 * (z - 2.0)
            base_val = 16'd4435;  // 0.13534 in Q1.15
            slope    = 16'd2803;  // 0.08555 in Q1.15
            offset   = 16'h2000;  // 2.0 in Q4.12
        end else if (z >= 16'h1000) begin
            // 1.0 <= z < 2.0 -> e^-z = 0.36788 - 0.23254 * (z - 1.0)
            base_val = 16'd12055; // 0.36788 in Q1.15
            slope    = 16'd7620;  // 0.23254 in Q1.15
            offset   = 16'h1000;  // 1.0 in Q4.12
        end else begin
            // 0.0 <= z < 1.0 -> e^-z = 1.00000 - 0.63212 * z
            base_val = 16'h7FFF; // 1.00000 in Q1.15
            slope    = 16'd20713; // 0.63212 in Q1.15
            offset   = 16'h0000;
        end
    end

    // ====================================================
    // STAGE 1 REGISTERS (Pipeline registers)
    // ====================================================
    reg signed [15:0] r_z;
    reg [15:0]        r_base_val;
    reg [15:0]        r_slope;
    reg [15:0]        r_offset;

    always @(posedge clk) begin
        if (rst) begin
            r_z        <= 16'sd0;
            r_base_val <= 16'h0000;
            r_slope    <= 16'd0;
            r_offset   <= 16'h0000;
        end else if (en) begin
            r_z        <= z;
            r_base_val <= base_val;
            r_slope    <= slope;
            r_offset   <= offset;
        end
    end

    // ====================================================
    // STAGE 2: Offset Subtraction & Multiplication (Arithmetic)
    // ====================================================

    // Compute delta z = z - offset
    wire [15:0] dz = $unsigned(r_z - r_offset);

    // Multiply: dz (Q4.12) * slope (Q1.15) -> Q5.27. Shift by 12 to get Q1.15
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] dy_ext = dz * r_slope;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [15:0] dy = {1'b0, dy_ext[26:12]};

    // Compute e^-z = base_val - dy
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
