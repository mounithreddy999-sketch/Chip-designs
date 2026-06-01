/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * INT4 Vector Dot Product Processing Element (PE)
 * Computes the dot product of two packed 4-element vectors of 4-bit signed integers.
 * Accumulates the result into a 16-bit signed register with saturation clamping.
 */

`default_nettype none

module dot_product_pe (
    input  wire                     clk,         // Clock signal
    input  wire                     rst,         // Synchronous active-high reset
    input  wire                     en,          // Clock-enable
    input  wire                     valid_in,    // Vector inputs valid strobe
    input  wire                     clear_acc,   // Synchronous accumulator reset
    input  wire [15:0]              vector_a,    // Packed Vector A: 4 elements of 4-bit signed integers
    input  wire [15:0]              vector_b,    // Packed Vector B: 4 elements of 4-bit signed integers
    output reg  signed [15:0]       acc,         // 16-bit signed Accumulator output
    output reg                      overflow,    // Positive saturation indicator
    output reg                      underflow    // Negative saturation indicator
);

    // Unpack Vector A elements (4-bit signed)
    wire signed [3:0] a0 = vector_a[3:0];
    wire signed [3:0] a1 = vector_a[7:4];
    wire signed [3:0] a2 = vector_a[11:8];
    wire signed [3:0] a3 = vector_a[15:12];

    // Unpack Vector B elements (4-bit signed)
    wire signed [3:0] b0 = vector_b[3:0];
    wire signed [3:0] b1 = vector_b[7:4];
    wire signed [3:0] b2 = vector_b[11:8];
    wire signed [3:0] b3 = vector_b[15:12];

    // Concurrent signed multiplications: 4-bit signed * 4-bit signed -> 8-bit signed
    wire signed [7:0] p0 = a0 * b0;
    wire signed [7:0] p1 = a1 * b1;
    wire signed [7:0] p2 = a2 * b2;
    wire signed [7:0] p3 = a3 * b3;

    // Concurrently sum the products (10-bit signed intermediate sum)
    wire signed [9:0] intermediate_sum = $signed(p0) + $signed(p1) + $signed(p2) + $signed(p3);

    // Extends addition by 1 bit to catch overflow/underflow prior to register latching
    wire signed [16:0] next_acc_ext = $signed(acc) + $signed(intermediate_sum);

    // Saturation Limits for 16-bit Signed Integer
    localparam signed [15:0] MAX_POS = 16'sh7FFF;  // +32,767
    localparam signed [15:0] MIN_NEG = 16'sh8000;  // -32,768

    localparam signed [16:0] MAX_POS_EXT = $signed(MAX_POS);
    localparam signed [16:0] MIN_NEG_EXT = $signed(MIN_NEG);

    always @(posedge clk) begin
        if (rst) begin
            acc       <= 16'sd0;
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else if (en) begin
            if (clear_acc) begin
                acc       <= 16'sd0;
                overflow  <= 1'b0;
                underflow <= 1'b0;
            end else if (valid_in) begin
                // Saturation detection and clamping
                if (next_acc_ext > MAX_POS_EXT) begin
                    acc       <= MAX_POS;
                    overflow  <= 1'b1;
                end else if (next_acc_ext < MIN_NEG_EXT) begin
                    acc       <= MIN_NEG;
                    underflow <= 1'b1;
                end else begin
                    acc       <= next_acc_ext[15:0];
                end
            end
        end
    end

endmodule
