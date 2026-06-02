/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Coarse-Grained Reconfigurable Architecture (CGRA) PE Node
 * Dynamically routes inputs from physical neighbors or global buses
 * and performs configurable operations using local configurations.
 */

`default_nettype none

module cgra_pe (
    input  wire                     clk,           // Clock signal
    input  wire                     rst,           // Synchronous active-high reset
    input  wire                     en,            // Execution clock enable
    input  wire [15:0]              config_data,   // Configuration command bus
    input  wire                     config_valid,  // Load configuration strobe
    input  wire signed [7:0]        data_n,        // Neighbor North data input
    input  wire signed [7:0]        data_s,        // Neighbor South data input
    input  wire signed [7:0]        data_e,        // Neighbor East data input
    input  wire signed [7:0]        data_w,        // Neighbor West data input
    input  wire signed [7:0]        data_global,   // Global data input bus
    output wire signed [7:0]        out_n,         // Neighbor North data output
    output wire signed [7:0]        out_s,         // Neighbor South data output
    output wire signed [7:0]        out_e,         // Neighbor East data output
    output wire signed [7:0]        out_w          // Neighbor West data output
);

    // Configuration Register
    reg [15:0] r_config;

    // Local Accumulator Register
    reg signed [15:0] r_accumulator;

    // Input Multiplexer Selection Logic
    reg signed [7:0] op_a;
    reg signed [7:0] op_b;

    always @(*) begin
        case (r_config[2:0]) // src_a
            3'b000:  op_a = data_n;
            3'b001:  op_a = data_s;
            3'b010:  op_a = data_e;
            3'b011:  op_a = data_w;
            3'b100:  op_a = data_global;
            3'b101:  op_a = r_accumulator[7:0]; // Feed back LSB of accumulator
            default: op_a = 8'sd0;
        endcase
    end

    always @(*) begin
        case (r_config[5:3]) // src_b
            3'b000:  op_b = data_n;
            3'b001:  op_b = data_s;
            3'b010:  op_b = data_e;
            3'b011:  op_b = data_w;
            3'b100:  op_b = data_global;
            3'b101:  op_b = r_accumulator[7:0]; // Feed back LSB of accumulator
            default: op_b = 8'sd0;
        endcase
    end

    // ALU Operations
    reg signed [15:0] alu_out;
    always @(*) begin
        case (r_config[7:6]) // op_select
            2'b00:   alu_out = r_accumulator + (op_a * op_b);  // MAC
            2'b01:   alu_out = $signed(op_a) + $signed(op_b);  // ADD
            2'b10:   alu_out = $signed(op_a);                  // Pass A
            2'b11:   alu_out = $signed(op_b);                  // Pass B
            default: alu_out = 16'sd0;
        endcase
    end

    // 8-bit Output Saturation (prevents data width expansion between nodes)
    reg signed [7:0] alu_out_sat;
    always @(*) begin
        if (r_accumulator > 16'sd127) begin
            alu_out_sat = 8'sd127;
        end else if (r_accumulator < -16'sd128) begin
            alu_out_sat = -8'sd128;
        end else begin
            alu_out_sat = r_accumulator[7:0];
        end
    end

    // Output Destination Routing Logic
    reg signed [7:0] r_out_n;
    reg signed [7:0] r_out_s;
    reg signed [7:0] r_out_e;
    reg signed [7:0] r_out_w;

    assign out_n = r_out_n;
    assign out_s = r_out_s;
    assign out_e = r_out_e;
    assign out_w = r_out_w;

    always @(*) begin
        r_out_n = 8'sd0;
        r_out_s = 8'sd0;
        r_out_e = 8'sd0;
        r_out_w = 8'sd0;

        case (r_config[10:8]) // dest_route
            3'b000: begin
                r_out_n = alu_out_sat;
                r_out_s = alu_out_sat;
                r_out_e = alu_out_sat;
                r_out_w = alu_out_sat;
            end
            3'b001: r_out_n = alu_out_sat;
            3'b010: r_out_s = alu_out_sat;
            3'b011: r_out_e = alu_out_sat;
            3'b100: r_out_w = alu_out_sat;
            default: ;
        endcase
    end

    // Register Clock Updates
    always @(posedge clk) begin
        if (rst) begin
            r_config      <= 16'h0;
            r_accumulator <= 16'sd0;
        end else begin
            if (config_valid) begin
                r_config <= config_data;
            end
            if (en) begin
                r_accumulator <= alu_out;
`ifndef SYNTHESIS
                $display("[%0t] PE Exec: op=%0d src_a_val=%0d src_b_val=%0d next_acc=%0d dest=%0d", 
                         $time, r_config[7:6], op_a, op_b, alu_out, r_config[10:8]);
`endif
            end
        end
    end

endmodule
