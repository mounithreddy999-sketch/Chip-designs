/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * PIM Neural Network Layer
 * Fuses the 4x4 Compute-in-Memory (PIM) SRAM Crossbar with four PWL Activation Units.
 * Creates a 2-cycle pipelined hardware layer:
 *   - Cycle 1: Matrix-Vector Multiplication computed and registered.
 *   - Cycle 2: Saturated sums are passed through Sigmoid or ReLU and registered.
 */

`default_nettype none

module pim_neural_layer (
    input  wire                     clk,             // Clock signal
    input  wire                     rst,             // Synchronous active-high reset
    input  wire                     en,              // Compute enable (pipelined)
    
    // Weight Programming Interface for internal SRAM crossbar
    input  wire [1:0]               w_addr_row,
    input  wire [1:0]               w_addr_col,
    input  wire                     w_write_en,
    input  wire signed [7:0]        w_data_in,
    
    // Input Activations (Vector inputs applied to rows)
    input  wire signed [7:0]        act_0,
    input  wire signed [7:0]        act_1,
    input  wire signed [7:0]        act_2,
    input  wire signed [7:0]        act_3,
    
    // Activation config
    input  wire                     act_mode,        // 0=ReLU, 1=Sigmoid
    
    // Activated Outputs
    output wire signed [15:0]       out_act_0,
    output wire signed [15:0]       out_act_1,
    output wire signed [15:0]       out_act_2,
    output wire signed [15:0]       out_act_3
);

    // Wires connecting crossbar outputs to activation unit inputs
    wire signed [15:0] crossbar_out_0;
    wire signed [15:0] crossbar_out_1;
    wire signed [15:0] crossbar_out_2;
    wire signed [15:0] crossbar_out_3;

    // Instantiate 4x4 PIM Crossbar
    pim_crossbar #(
        .ACT_WIDTH(8),
        .W_WIDTH(8),
        .OUT_WIDTH(16)
    ) p_crossbar (
        .clk(clk),
        .rst(rst),
        .en(en),
        .w_addr_row(w_addr_row),
        .w_addr_col(w_addr_col),
        .w_write_en(w_write_en),
        .w_data_in(w_data_in),
        .act_0(act_0),
        .act_1(act_1),
        .act_2(act_2),
        .act_3(act_3),
        .out_0(crossbar_out_0),
        .out_1(crossbar_out_1),
        .out_2(crossbar_out_2),
        .out_3(crossbar_out_3)
    );

    // Instantiate 4 Activation Units (one per column output)
    activation_unit #(
        .DATA_WIDTH(16)
    ) act_unit_0 (
        .clk(clk),
        .rst(rst),
        .en(en),
        .mode(act_mode),
        .in_data(crossbar_out_0),
        .out_data(out_act_0)
    );

    activation_unit #(
        .DATA_WIDTH(16)
    ) act_unit_1 (
        .clk(clk),
        .rst(rst),
        .en(en),
        .mode(act_mode),
        .in_data(crossbar_out_1),
        .out_data(out_act_1)
    );

    activation_unit #(
        .DATA_WIDTH(16)
    ) act_unit_2 (
        .clk(clk),
        .rst(rst),
        .en(en),
        .mode(act_mode),
        .in_data(crossbar_out_2),
        .out_data(out_act_2)
    );

    activation_unit #(
        .DATA_WIDTH(16)
    ) act_unit_3 (
        .clk(clk),
        .rst(rst),
        .en(en),
        .mode(act_mode),
        .in_data(crossbar_out_3),
        .out_data(out_act_3)
    );

endmodule
