/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * 4x4 Compute-in-Memory (PIM) SRAM Crossbar
 * Fuses 16 local weight registers (SRAM cell representation) directly adjacent
 * to MAC units. Performs matrix-vector multiplication (MVM) along column adder trees
 * and applies 16-bit signed output saturation.
 */

`default_nettype none

module pim_crossbar #(
    parameter ACT_WIDTH = 8,  // Activation input precision (signed)
    parameter W_WIDTH   = 8,  // Stored weights precision (signed)
    parameter OUT_WIDTH = 16  // Saturated output precision (signed)
) (
    input  wire                     clk,             // Clock signal
    input  wire                     rst,             // Synchronous active-high reset
    input  wire                     en,              // Compute enable
    
    // Weight Programming Interface (Addressable Cell Write)
    input  wire [1:0]               w_addr_row,      // Row address (0 to 3)
    input  wire [1:0]               w_addr_col,      // Column address (0 to 3)
    input  wire                     w_write_en,      // Write enable strobe
    input  wire signed [W_WIDTH-1:0] w_data_in,      // Signed weight value to write
    
    // Input Activations (Vector inputs applied to rows)
    input  wire signed [ACT_WIDTH-1:0] act_0,
    input  wire signed [ACT_WIDTH-1:0] act_1,
    input  wire signed [ACT_WIDTH-1:0] act_2,
    input  wire signed [ACT_WIDTH-1:0] act_3,
    
    // Saturated Outputs (Sum of products along columns)
    output reg  signed [OUT_WIDTH-1:0] out_0,
    output reg  signed [OUT_WIDTH-1:0] out_1,
    output reg  signed [OUT_WIDTH-1:0] out_2,
    output reg  signed [OUT_WIDTH-1:0] out_3
);

    // 4x4 Weight Registers (SRAM storage)
    reg signed [W_WIDTH-1:0] r_weights [3:0][3:0];

    // Programming Logic
    integer r, c;
    always @(posedge clk) begin
        if (rst) begin
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    r_weights[r][c] <= {W_WIDTH{1'b0}};
                end
            end
        end else if (w_write_en) begin
            r_weights[w_addr_row][w_addr_col] <= w_data_in;
        end
    end

    // Product matrix (2 * W_WIDTH bits signed)
    wire signed [ACT_WIDTH+W_WIDTH-1:0] products [3:0][3:0];
    
    // Fused Multiplications: act_i * weight_ij
    assign products[0][0] = act_0 * r_weights[0][0];
    assign products[0][1] = act_0 * r_weights[0][1];
    assign products[0][2] = act_0 * r_weights[0][2];
    assign products[0][3] = act_0 * r_weights[0][3];

    assign products[1][0] = act_1 * r_weights[1][0];
    assign products[1][1] = act_1 * r_weights[1][1];
    assign products[1][2] = act_1 * r_weights[1][2];
    assign products[1][3] = act_1 * r_weights[1][3];

    assign products[2][0] = act_2 * r_weights[2][0];
    assign products[2][1] = act_2 * r_weights[2][1];
    assign products[2][2] = act_2 * r_weights[2][2];
    assign products[2][3] = act_2 * r_weights[2][3];

    assign products[3][0] = act_3 * r_weights[3][0];
    assign products[3][1] = act_3 * r_weights[3][1];
    assign products[3][2] = act_3 * r_weights[3][2];
    assign products[3][3] = act_3 * r_weights[3][3];

    // Column Adder Trees
    // Outputs are 18-bit signed sums (16-bit product + 2 bits to capture summation without overflow)
    wire signed [ACT_WIDTH+W_WIDTH+1:0] col_sums [3:0];
    
    assign col_sums[0] = $signed(products[0][0]) + $signed(products[1][0]) + $signed(products[2][0]) + $signed(products[3][0]);
    assign col_sums[1] = $signed(products[0][1]) + $signed(products[1][1]) + $signed(products[2][1]) + $signed(products[3][1]);
    assign col_sums[2] = $signed(products[0][2]) + $signed(products[1][2]) + $signed(products[2][2]) + $signed(products[3][2]);
    assign col_sums[3] = $signed(products[0][3]) + $signed(products[1][3]) + $signed(products[2][3]) + $signed(products[3][3]);

    // Saturation Clamping Limits for OUT_WIDTH-bit Signed output
    localparam signed [OUT_WIDTH-1:0] MAX_POS = {1'b0, {(OUT_WIDTH-1){1'b1}}}; // +32,767
    localparam signed [OUT_WIDTH-1:0] MIN_NEG = {1'b1, {(OUT_WIDTH-1){1'b0}}}; // -32,768

    localparam signed [ACT_WIDTH+W_WIDTH+1:0] MAX_POS_EXT = $signed(MAX_POS);
    localparam signed [ACT_WIDTH+W_WIDTH+1:0] MIN_NEG_EXT = $signed(MIN_NEG);

    // Compute Output Registers Latching
    always @(posedge clk) begin
        if (rst) begin
            out_0 <= {OUT_WIDTH{1'b0}};
            out_1 <= {OUT_WIDTH{1'b0}};
            out_2 <= {OUT_WIDTH{1'b0}};
            out_3 <= {OUT_WIDTH{1'b0}};
        end else if (en) begin
            // Column 0
            if (col_sums[0] > MAX_POS_EXT) begin
                out_0 <= MAX_POS;
            end else if (col_sums[0] < MIN_NEG_EXT) begin
                out_0 <= MIN_NEG;
            end else begin
                out_0 <= col_sums[0][OUT_WIDTH-1:0];
            end

            // Column 1
            if (col_sums[1] > MAX_POS_EXT) begin
                out_1 <= MAX_POS;
            end else if (col_sums[1] < MIN_NEG_EXT) begin
                out_1 <= MIN_NEG;
            end else begin
                out_1 <= col_sums[1][OUT_WIDTH-1:0];
            end

            // Column 2
            if (col_sums[2] > MAX_POS_EXT) begin
                out_2 <= MAX_POS;
            end else if (col_sums[2] < MIN_NEG_EXT) begin
                out_2 <= MIN_NEG;
            end else begin
                out_2 <= col_sums[2][OUT_WIDTH-1:0];
            end

            // Column 3
            if (col_sums[3] > MAX_POS_EXT) begin
                out_3 <= MAX_POS;
            end else if (col_sums[3] < MIN_NEG_EXT) begin
                out_3 <= MIN_NEG;
            end else begin
                out_3 <= col_sums[3][OUT_WIDTH-1:0];
            end
        end
    end

endmodule
