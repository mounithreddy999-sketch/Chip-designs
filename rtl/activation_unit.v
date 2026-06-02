/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Piecewise-Linear (PWL) Activation Unit
 * Supports ReLU and Sigmoid activation functions.
 * Input format: 16-bit signed Q4.12 format (range: [-8.0, 7.99])
 * Output format:
 *   - ReLU: Q4.12 format (same as input)
 *   - Sigmoid: Q1.15 format (range: [0.0, 1.0], where 0 = 16'h0000, 1.0 = 16'h7FFF)
 * Uses a symmetric 4-segment PWL approximation for the Sigmoid curve.
 */

`default_nettype none

module activation_unit #(
    parameter DATA_WIDTH = 16
) (
    input  wire                     clk,      // Clock signal
    input  wire                     rst,      // Synchronous active-high reset
    input  wire                     en,       // Clock enable
    input  wire                     mode,     // Mode select: 0=ReLU, 1=Sigmoid
    input  wire signed [DATA_WIDTH-1:0] in_data, // Q4.12 signed input
    output reg  signed [DATA_WIDTH-1:0] out_data // Registered output
);

    // Compute absolute value of input for symmetric Sigmoid evaluation
    wire signed [DATA_WIDTH-1:0] abs_in = (in_data[DATA_WIDTH-1] == 1'b1) ? -in_data : in_data;

    // PWL approximation registers for Sigmoid( |x| )
    reg [DATA_WIDTH-1:0] base_val;
    reg [DATA_WIDTH-1:0] slope;
    reg [DATA_WIDTH-1:0] offset_x;

    always @(*) begin
        // default settings
        base_val = 16'd16384; // 0.5 in Q1.15
        slope    = 16'd7536;  // 0.23 in Q1.15
        offset_x = 16'd0;

        if (abs_in >= 16'h4000) begin
            // |x| >= 4.0 -> S(|x|) = 1.0 (16'h7FFF)
            base_val = 16'h7FFF;
            slope    = 16'd0;
            offset_x = 16'h4000;
        end else if (abs_in >= 16'h2000) begin
            // 2.0 <= |x| < 4.0 -> S(|x|) = 0.88 + 0.05 * (|x| - 2.0)
            base_val = 16'd28836; // 0.88 in Q1.15
            slope    = 16'd1638;  // 0.05 in Q1.15
            offset_x = 16'h2000; // 2.0 in Q4.12
        end else if (abs_in >= 16'h1000) begin
            // 1.0 <= |x| < 2.0 -> S(|x|) = 0.73 + 0.15 * (|x| - 1.0)
            base_val = 16'd23920; // 0.73 in Q1.15
            slope    = 16'd4915;  // 0.15 in Q1.15
            offset_x = 16'h1000; // 1.0 in Q4.12
        end else begin
            // 0.0 <= |x| < 1.0 -> S(|x|) = 0.50 + 0.23 * |x|
            base_val = 16'd16384; // 0.50 in Q1.15
            slope    = 16'd7536;  // 0.23 in Q1.15
            offset_x = 16'h0000; // 0.0 in Q4.12
        end
    end

    // Compute delta x = |x| - offset_x
    wire [DATA_WIDTH-1:0] dx = abs_in - offset_x;

    // Multiply: dx (Q4.12) * slope (Q1.15) -> Q5.27. Shift by 12 to get Q1.15
    wire [31:0] dy_ext = dx * slope;
    wire [DATA_WIDTH-1:0] dy = dy_ext[26:12];

    // Compute S(|x|) in Q1.15
    wire [DATA_WIDTH-1:0] sig_abs = base_val + dy;

    // Sigmoid(x) = S(x) if x >= 0 else 1.0 - S(|x|)
    wire [DATA_WIDTH-1:0] sigmoid_out = (in_data[DATA_WIDTH-1] == 1'b0) ? sig_abs : (16'h7FFF - sig_abs);

    // Compute next output state based on mode
    reg [DATA_WIDTH-1:0] next_out_data;
    always @(*) begin
        if (mode == 1'b0) begin
            // ReLU Mode
            if (in_data > 16'sd0) begin
                next_out_data = in_data;
            end else begin
                next_out_data = 16'h0000;
            end
        end else begin
            // Sigmoid Mode
            next_out_data = sigmoid_out;
        end
    end

    // Clocked output update
    always @(posedge clk) begin
        if (rst) begin
            out_data <= 16'h0000;
        end else if (en) begin
            out_data <= next_out_data;
        end
    end

endmodule
