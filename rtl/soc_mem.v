/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Simple Block RAM for RISC-V SoC.
 * Provides 64KB (16K x 32-bit) of memory for instructions and data.
 */

`default_nettype none

module soc_mem #(
    parameter MEM_SIZE = 16384 // 16K words = 64KB
) (
    input  wire         clk,
    input  wire         mem_valid,
    output reg          mem_ready,
    input  wire [31:0]  mem_addr,
    input  wire [31:0]  mem_wdata,
    input  wire [3:0]   mem_wstrb,
    output reg  [31:0]  mem_rdata
);

    reg [31:0] memory [0:MEM_SIZE-1];

    // Optional: Load firmware if firmware.hex exists
    initial begin
        $readmemh("../sw/firmware/firmware.hex", memory);
    end

    wire [29:0] word_addr = mem_addr[31:2];

    always @(posedge clk) begin
        // By default, ready is low
        mem_ready <= 1'b0;

        if (mem_valid && !mem_ready) begin
            if (word_addr < MEM_SIZE) begin
                if (|mem_wstrb) begin
                    // Write
                    if (mem_wstrb[0]) memory[word_addr][7:0]   <= mem_wdata[7:0];
                    if (mem_wstrb[1]) memory[word_addr][15:8]  <= mem_wdata[15:8];
                    if (mem_wstrb[2]) memory[word_addr][23:16] <= mem_wdata[23:16];
                    if (mem_wstrb[3]) memory[word_addr][31:24] <= mem_wdata[31:24];
                end
                // Read
                mem_rdata <= memory[word_addr];
                mem_ready <= 1'b1;
            end
        end
    end

endmodule
