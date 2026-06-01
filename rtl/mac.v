/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Parameterized Signed Multiply-Accumulate (MAC) Unit
 * Features: Active-high synchronous reset, accumulator clear,
 * saturation limits, and overflow/underflow flag registers.
 */

`default_nettype none

module mac #(
    parameter OP_WIDTH  = 8,   // Width of input operands
    parameter ACC_WIDTH = 24   // Width of accumulator register
) (
    input  wire                     clk,       // Clock signal
    input  wire                     rst,       // Synchronous active-high reset
    input  wire                     en,        // Module clock-enable
    input  wire                     valid_in,  // Trigger multiplication and accumulation
    input  wire                     clear_acc, // Direct register clear for accumulator & flags
    input  wire signed [OP_WIDTH-1:0]  a,         // Input Operand A (signed)
    input  wire signed [OP_WIDTH-1:0]  b,         // Input Operand B (signed)
    output reg  signed [ACC_WIDTH-1:0] acc,       // Accumulator register output (signed)
    output reg                      overflow,  // Saturation overflow flag
    output reg                      underflow  // Saturation underflow flag
);

    // Multiplication: signed product of operands (width = 2 * OP_WIDTH)
    wire signed [2*OP_WIDTH-1:0] product = a * b;

    // Extends addition by 1 bit to catch overflow/underflow before truncation
    wire signed [ACC_WIDTH:0] next_acc_ext = $signed(acc) + $signed(product);

    // Dynamic Parameterized Saturation Limits
    localparam signed [ACC_WIDTH-1:0] MAX_POS = {1'b0, {(ACC_WIDTH-1){1'b1}}}; // e.g. +8,388,607
    localparam signed [ACC_WIDTH-1:0] MIN_NEG = {1'b1, {(ACC_WIDTH-1){1'b0}}}; // e.g. -8,388,608

    localparam signed [ACC_WIDTH:0] MAX_POS_EXT = $signed(MAX_POS);
    localparam signed [ACC_WIDTH:0] MIN_NEG_EXT = $signed(MIN_NEG);

    always @(posedge clk) begin
        if (rst) begin
            acc       <= {ACC_WIDTH{1'b0}};
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else if (en) begin
            if (clear_acc) begin
                acc       <= {ACC_WIDTH{1'b0}};
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
                    acc       <= next_acc_ext[ACC_WIDTH-1:0];
                end
            end
        end
    end

endmodule
