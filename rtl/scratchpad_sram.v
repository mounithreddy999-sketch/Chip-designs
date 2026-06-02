/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Parameterized Scratchpad SRAM Memory Module
 * Partitioned into:
 *   1. Query SRAM (128 words x DATA_WIDTH)
 *   2. Key SRAM   (128 words x DATA_WIDTH)
 * Dual-port architecture allows simultaneous external writes and internal reads.
 */

`default_nettype none

module scratchpad_sram #(
    parameter N = 4,
    parameter DATA_WIDTH = N * 4
) (
    input  wire                     clk,
    
    // Query SRAM Ports
    input  wire                     q_write_en,
    input  wire [6:0]               q_write_addr,
    input  wire [DATA_WIDTH-1:0]    q_write_data,
    input  wire                     q_read_en,
    input  wire [6:0]               q_read_addr,
    output reg  [DATA_WIDTH-1:0]    q_read_data,
    
    // Key SRAM Ports
    input  wire                     k_write_en,
    input  wire [6:0]               k_write_addr,
    input  wire [DATA_WIDTH-1:0]    k_write_data,
    input  wire                     k_read_en,
    input  wire [6:0]               k_read_addr,
    output reg  [DATA_WIDTH-1:0]    k_read_data
);

    // Query SRAM Memory Array
    reg [DATA_WIDTH-1:0] sram_query [0:127];
    
    // Key SRAM Memory Array
    reg [DATA_WIDTH-1:0] sram_key   [0:127];

    // Query SRAM Read/Write Logic
    always @(posedge clk) begin
        if (q_write_en) begin
            sram_query[q_write_addr] <= q_write_data;
        end
        if (q_read_en) begin
            q_read_data <= sram_query[q_read_addr];
        end
    end

    // Key SRAM Read/Write Logic
    always @(posedge clk) begin
        if (k_write_en) begin
            sram_key[k_write_addr] <= k_write_data;
        end
        if (k_read_en) begin
            k_read_data <= sram_key[k_read_addr];
        end
    end

endmodule
