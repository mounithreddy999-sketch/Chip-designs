/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * 3x3 Weight-Stationary Systolic Array Matrix Multiplier
 * Instantiates a 3x3 grid of systolic processing elements (PEs).
 * Weights are pre-loaded into each PE. Activations shift left-to-right,
 * and partial sums shift top-to-bottom.
 */

`default_nettype none

// Helper processing element (PE) cell
module systolic_pe (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     en,
    input  wire                     w_write_en,
    input  wire signed [7:0]        w_data_in,
    input  wire signed [7:0]        act_in,
    input  wire signed [23:0]       partial_sum_in,
    output reg  signed [7:0]        act_out,
    output reg  signed [23:0]       partial_sum_out
);

    reg signed [7:0] r_weight;

    always @(posedge clk) begin
        if (rst) begin
            r_weight        <= 8'sd0;
            act_out         <= 8'sd0;
            partial_sum_out <= 24'sd0;
        end else begin
            if (w_write_en) begin
                r_weight <= w_data_in;
            end
            if (en) begin
                act_out         <= act_in;
                partial_sum_out <= partial_sum_in + (act_in * r_weight);
            end
        end
    end

endmodule


// Top level 3x3 systolic array
module systolic_array (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     en,
    
    // Weight Programming Interface
    input  wire [1:0]               w_addr_row,      // Target PE row index (0 to 2)
    input  wire [1:0]               w_addr_col,      // Target PE col index (0 to 2)
    input  wire                     w_write_en,      // Programming enable strobe
    input  wire signed [7:0]        w_data_in,       // Signed weight data
    
    // Streaming Inputs (Skewed activations entering from the West)
    input  wire signed [7:0]        act_in_row0,
    input  wire signed [7:0]        act_in_row1,
    input  wire signed [7:0]        act_in_row2,
    
    // Streaming partial sums entering from the North (typically zeroed)
    input  wire signed [23:0]       partial_sum_in_col0,
    input  wire signed [23:0]       partial_sum_in_col1,
    input  wire signed [23:0]       partial_sum_in_col2,
    
    // Final outputs exiting from the South
    output wire signed [23:0]       out_col0,
    output wire signed [23:0]       out_col1,
    output wire signed [23:0]       out_col2
);

    // Gated weight write enables for each PE
    wire w_en_00 = w_write_en && (w_addr_row == 2'd0) && (w_addr_col == 2'd0);
    wire w_en_01 = w_write_en && (w_addr_row == 2'd0) && (w_addr_col == 2'd1);
    wire w_en_02 = w_write_en && (w_addr_row == 2'd0) && (w_addr_col == 2'd2);
    
    wire w_en_10 = w_write_en && (w_addr_row == 2'd1) && (w_addr_col == 2'd0);
    wire w_en_11 = w_write_en && (w_addr_row == 2'd1) && (w_addr_col == 2'd1);
    wire w_en_12 = w_write_en && (w_addr_row == 2'd1) && (w_addr_col == 2'd2);
    
    wire w_en_20 = w_write_en && (w_addr_row == 2'd2) && (w_addr_col == 2'd0);
    wire w_en_21 = w_write_en && (w_addr_row == 2'd2) && (w_addr_col == 2'd1);
    wire w_en_22 = w_write_en && (w_addr_row == 2'd2) && (w_addr_col == 2'd2);

    // Interconnect wires for activations (horizontal)
    wire signed [7:0] act_00_to_01, act_01_to_02, act_02_out;
    wire signed [7:0] act_10_to_11, act_11_to_12, act_12_out;
    wire signed [7:0] act_20_to_21, act_21_to_22, act_22_out;

    // Interconnect wires for partial sums (vertical)
    wire signed [23:0] psum_00_to_10, psum_10_to_20;
    wire signed [23:0] psum_01_to_11, psum_11_to_21;
    wire signed [23:0] psum_02_to_12, psum_12_to_22;

    // ----------------------------------------------------
    // Row 0
    // ----------------------------------------------------
    systolic_pe pe00 (
        .clk(clk), .rst(rst), .en(en),
        .w_write_en(w_en_00), .w_data_in(w_data_in),
        .act_in(act_in_row0), .partial_sum_in(partial_sum_in_col0),
        .act_out(act_00_to_01), .partial_sum_out(psum_00_to_10)
    );

    systolic_pe pe01 (
        .clk(clk), .rst(rst), .en(en),
        .w_write_en(w_en_01), .w_data_in(w_data_in),
        .act_in(act_00_to_01), .partial_sum_in(partial_sum_in_col1),
        .act_out(act_01_to_02), .partial_sum_out(psum_01_to_11)
    );

    systolic_pe pe02 (
        .clk(clk), .rst(rst), .en(en),
        .w_write_en(w_en_02), .w_data_in(w_data_in),
        .act_in(act_01_to_02), .partial_sum_in(partial_sum_in_col2),
        .act_out(act_02_out), .partial_sum_out(psum_02_to_12)
    );

    // ----------------------------------------------------
    // Row 1
    // ----------------------------------------------------
    systolic_pe pe10 (
        .clk(clk), .rst(rst), .en(en),
        .w_write_en(w_en_10), .w_data_in(w_data_in),
        .act_in(act_in_row1), .partial_sum_in(psum_00_to_10),
        .act_out(act_10_to_11), .partial_sum_out(psum_10_to_20)
    );

    systolic_pe pe11 (
        .clk(clk), .rst(rst), .en(en),
        .w_write_en(w_en_11), .w_data_in(w_data_in),
        .act_in(act_10_to_11), .partial_sum_in(psum_01_to_11),
        .act_out(act_11_to_12), .partial_sum_out(psum_11_to_21)
    );

    systolic_pe pe12 (
        .clk(clk), .rst(rst), .en(en),
        .w_write_en(w_en_12), .w_data_in(w_data_in),
        .act_in(act_11_to_12), .partial_sum_in(psum_02_to_12),
        .act_out(act_12_out), .partial_sum_out(psum_12_to_22)
    );

    // ----------------------------------------------------
    // Row 2
    // ----------------------------------------------------
    systolic_pe pe20 (
        .clk(clk), .rst(rst), .en(en),
        .w_write_en(w_en_20), .w_data_in(w_data_in),
        .act_in(act_in_row2), .partial_sum_in(psum_10_to_20),
        .act_out(act_20_to_21), .partial_sum_out(out_col0)
    );

    systolic_pe pe21 (
        .clk(clk), .rst(rst), .en(en),
        .w_write_en(w_en_21), .w_data_in(w_data_in),
        .act_in(act_20_to_21), .partial_sum_in(psum_11_to_21),
        .act_out(act_21_to_22), .partial_sum_out(out_col1)
    );

    systolic_pe pe22 (
        .clk(clk), .rst(rst), .en(en),
        .w_write_en(w_en_22), .w_data_in(w_data_in),
        .act_in(act_21_to_22), .partial_sum_in(psum_12_to_22),
        .act_out(act_22_out), .partial_sum_out(out_col2)
    );

endmodule
