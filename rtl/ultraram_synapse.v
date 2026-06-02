/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * ULTRARAM-Inspired High-Endurance Artificial Synapse
 * Models a multi-level conductance state using an 8-bit register.
 * Provides linear and symmetric potentiation (programming) and depression (erasing)
 * with adjustable step sizes controlled by the input pulse amplitude.
 * Includes a 32-bit cycle counter to track program/erase operations.
 */

`default_nettype none

module ultraram_synapse (
    input  wire                     clk,             // Clock signal
    input  wire                     rst,             // Synchronous active-high reset
    input  wire                     en,              // Clock enable
    input  wire                     pulse,           // Program/Erase pulse strobe
    input  wire                     op_type,         // Operation select: 1=Program (Potentiation), 0=Erase (Depression)
    input  wire [2:0]               pulse_amplitude, // Controls programming step size (dynamic conductance change)
    output reg  [7:0]               conductance,     // 8-bit unsigned conductance state
    output reg  [31:0]              cycle_count      // 32-bit lifetime program/erase cycles
);

    // Determine the programming step size based on pulse_amplitude.
    // If amplitude is 0, step size is 1. Otherwise, step size is the amplitude value.
    wire [7:0] step_size = (pulse_amplitude == 3'd0) ? 8'd1 : {5'd0, pulse_amplitude};

    // Intermediate calculations to detect saturation prior to register latching
    wire [8:0] next_conductance_pgm = conductance + step_size;
    wire signed [8:0] next_conductance_ers = $signed({1'b0, conductance}) - $signed({1'b0, step_size});

    always @(posedge clk) begin
        if (rst) begin
            conductance <= 8'h00; // Initialize to fully depressed (discharged) state
            cycle_count <= 32'd0;
        end else if (en) begin
            if (pulse) begin
                cycle_count <= cycle_count + 32'd1;
                if (op_type) begin
                    // Potentiation (Program): clamp at 255 (fully programmed)
                    if (next_conductance_pgm > 9'd255) begin
                        conductance <= 8'd255;
                    end else begin
                        conductance <= next_conductance_pgm[7:0];
                    end
                end else begin
                    // Depression (Erase): clamp at 0 (fully erased)
                    if (next_conductance_ers < 9'sd0) begin
                        conductance <= 8'd0;
                    end else begin
                        conductance <= next_conductance_ers[7:0];
                    end
                end
            end
        end
    end

endmodule
