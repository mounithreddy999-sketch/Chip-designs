/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Reconfigurable Processing Element (PE) Node
 * Supports MXINT4 (integer), MXFP4 (E2M1), and MXFP8 (E4M3 / E5M2) floating-point formats.
 * Incorporates a reconfigurable decoder and barrel shifter to align calculations.
 */

`default_nettype none

module mx_pe (
    input  wire                     clk,               // Clock signal
    input  wire                     rst,               // Global synchronous active-high reset
    input  wire                     clear,             // Local execution clear (resets accumulator/psum)
    input  wire                     en,                // Execution enable
    input  wire                     shift_en,          // Shift-out enable
    input  wire                     dataflow_mode_sel, // 0 = Weight-Stationary, 1 = Output-Stationary
    input  wire                     w_write_en,        // Weight write enable (WS mode)
    input  wire [1:0]               format_mode,       // 00 = MXINT4, 01 = MXFP4, 10 = MXFP8 (E4M3), 11 = MXFP8 (E5M2)
    input  wire signed [7:0]        w_data_in,         // Weight data configuration
    input  wire signed [7:0]        act_in,            // Activation input (streams from West to East)
    input  wire signed [7:0]        weight_in,         // Weight input (streams from North to South, OS mode)
    input  wire signed [15:0]       partial_sum_in,    // Partial sum input (streams from North to South)
    output reg  signed [7:0]        act_out,           // Activation output (propagates to East)
    output reg  signed [7:0]        weight_out,        // Weight output (propagates to South)
    output wire signed [15:0]       partial_sum_out    // Partial sum output (propagates to South)
);

    // Internal registers
    reg signed [7:0]  r_weight;           // Holds weight locally in WS mode
    reg signed [15:0] r_accumulator;      // Accumulates sum locally in OS mode
    reg signed [15:0] r_partial_sum_reg;  // Registered partial sum output for WS mode

    // Selected weight operand
    wire signed [7:0] selected_weight = dataflow_mode_sel ? weight_in : r_weight;

    // ====================================================
    // WEIGHT DECODER
    // ====================================================
    reg w_sign;
    reg [4:0] w_exp;
    reg [3:0] w_mant;
    reg [4:0] w_bias;
    reg [1:0] w_mant_frac;

    always @(*) begin
        // Default settings for MXINT4 (signed 4-bit integer)
        w_sign      = selected_weight[3];
        w_exp       = 5'd0;
        w_bias      = 5'd0;
        w_mant_frac = 2'd0;
        if (selected_weight[3]) begin
            w_mant = -selected_weight[3:0];
        end else begin
            w_mant = selected_weight[3:0];
        end

        case (format_mode)
            2'b01: begin // MXFP4 (E2M1) - 4 bits
                w_sign      = selected_weight[3];
                w_bias      = 5'd1;
                w_exp       = {3'd0, selected_weight[2:1]};
                w_mant_frac = 2'd1;
                if (selected_weight[2:1] == 2'b00) begin
                    w_mant = {3'b000, selected_weight[0]}; // Subnormal
                end else begin
                    w_mant = {3'b001, selected_weight[0]}; // Normal
                end
            end
            
            2'b10: begin // MXFP8 (E4M3) - 8 bits
                w_sign      = selected_weight[7];
                w_bias      = 5'd7;
                w_exp       = {1'b0, selected_weight[6:3]};
                w_mant_frac = 2'd3;
                if (selected_weight[6:3] == 4'b0000) begin
                    w_mant = {1'b0, selected_weight[2:0]}; // Subnormal
                end else begin
                    w_mant = {1'b1, selected_weight[2:0]}; // Normal
                end
            end
            
            2'b11: begin // MXFP8 (E5M2) - 8 bits
                w_sign      = selected_weight[7];
                w_bias      = 5'd15;
                w_exp       = selected_weight[6:2];
                w_mant_frac = 2'd2;
                if (selected_weight[6:2] == 5'b00000) begin
                    w_mant = {2'b00, selected_weight[1:0]}; // Subnormal
                end else begin
                    w_mant = {2'b01, selected_weight[1:0]}; // Normal
                end
            end
            
            default: ;
        endcase
    end

    // ====================================================
    // PRODUCT CALCULATION
    // ====================================================
    wire signed [7:0]  act_val = act_in;
    wire signed [4:0]  w_mant_signed = {1'b0, w_mant};
    wire signed [12:0] raw_product = act_val * w_mant_signed;
    wire signed [12:0] signed_product = w_sign ? -raw_product : raw_product;

    // Effective exponent shift logic
    wire [4:0] w_exp_eff = (format_mode != 2'b00 && w_exp == 5'd0) ? 5'd1 : w_exp;
    wire signed [5:0] effective_shift = $signed({1'b0, w_exp_eff}) - $signed({1'b0, w_bias}) - $signed({4'b0000, w_mant_frac});

    // Barrel Shifter and Saturation Logic
    reg signed [15:0] shifted_product;
    reg signed [31:0] temp_shift;
    always @(*) begin
        if (format_mode == 2'b00) begin
            shifted_product = { {3{signed_product[12]}}, signed_product };
        end else begin
            if (effective_shift >= 6'sd0) begin
                temp_shift = { {19{signed_product[12]}}, signed_product } <<< effective_shift;
                if (temp_shift > 32'sd32767) begin
                    shifted_product = 16'sd32767;
                end else if (temp_shift < -32'sd32768) begin
                    shifted_product = -16'sd32768;
                end else begin
                    shifted_product = temp_shift[15:0];
                end
            end else begin
                shifted_product = signed_product >>> (-effective_shift);
            end
        end
    end

    // Combinational output multiplexing for partial_sum_out
    assign partial_sum_out = shift_en ? r_accumulator : r_partial_sum_reg;

    always @(posedge clk) begin
        if (rst) begin
            r_weight          <= 8'sd0;
            r_accumulator     <= 16'sd0;
            r_partial_sum_reg <= 16'sd0;
            act_out           <= 8'sd0;
            weight_out        <= 8'sd0;
        end else begin
            if (clear) begin
                r_accumulator     <= 16'sd0;
                r_partial_sum_reg <= 16'sd0;
            end
            
            if (en) begin
                // Propagation registers
                act_out    <= act_in;
                weight_out <= weight_in;

                // Weight loading logic (WS mode)
                if (!dataflow_mode_sel && w_write_en) begin
                    r_weight <= w_data_in;
                end

                // Accumulation logic
                if (dataflow_mode_sel) begin
                    // Output-Stationary Mode
                    if (shift_en) begin
                        r_accumulator <= partial_sum_in;
                    end else if (!clear) begin
                        r_accumulator <= r_accumulator + shifted_product;
                    end
                end else begin
                    // Weight-Stationary Mode
                    if (!clear) begin
                        r_partial_sum_reg <= partial_sum_in + shifted_product;
                    end
                end
            end
        end
    end

endmodule
