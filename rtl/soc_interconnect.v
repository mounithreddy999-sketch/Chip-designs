/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * SoC Interconnect (2 Masters, 5 Slaves)
 * Fixed priority arbiter: Master 0 (CPU) > Master 1 (DMA).
 */

`default_nettype none
`include "soc_memory_map.vh"

module soc_interconnect (
    input wire clk,
    input wire rst,

    // Master 0 (PicoRV32)
    input  wire        m0_valid,
    output reg         m0_ready,
    input  wire [31:0] m0_addr,
    input  wire [31:0] m0_wdata,
    input  wire [ 3:0] m0_wstrb,
    output reg  [31:0] m0_rdata,

    // Master 1 (DMA)
    input  wire        m1_valid,
    output reg         m1_ready,
    input  wire [31:0] m1_addr,
    input  wire [31:0] m1_wdata,
    input  wire [ 3:0] m1_wstrb,
    output reg  [31:0] m1_rdata,

    // Slave 0 (SRAM)
    output reg         s0_valid,
    input  wire        s0_ready,
    output reg  [31:0] s0_addr,
    output reg  [31:0] s0_wdata,
    output reg  [ 3:0] s0_wstrb,
    input  wire [31:0] s0_rdata,

    // Slave 1 (DMA Control)
    output reg         s1_valid,
    input  wire        s1_ready,
    output reg  [31:0] s1_addr,
    output reg  [31:0] s1_wdata,
    output reg  [ 3:0] s1_wstrb,
    input  wire [31:0] s1_rdata,

    // Slave 2 (CGRA)
    output reg         s2_valid,
    input  wire        s2_ready,
    output reg  [31:0] s2_addr,
    output reg  [31:0] s2_wdata,
    output reg  [ 3:0] s2_wstrb,
    input  wire [31:0] s2_rdata,

    // Slave 3 (Softmax)
    output reg         s3_valid,
    input  wire        s3_ready,
    output reg  [31:0] s3_addr,
    output reg  [31:0] s3_wdata,
    output reg  [ 3:0] s3_wstrb,
    input  wire [31:0] s3_rdata,

    // Slave 4 (Testbench)
    output reg         s4_valid,
    input  wire        s4_ready,
    output reg  [31:0] s4_addr,
    output reg  [31:0] s4_wdata,
    output reg  [ 3:0] s4_wstrb,
    input  wire [31:0] s4_rdata
);

    // Arbitration state
    reg active_master; // 0 = M0, 1 = M1
    reg in_transaction;

    always @(posedge clk) begin
        if (rst) begin
            active_master <= 1'b0;
            in_transaction <= 1'b0;
        end else begin
            if (in_transaction) begin
                // End transaction when the selected master receives ready
                if ((active_master == 1'b0 && m0_ready) || 
                    (active_master == 1'b1 && m1_ready)) begin
                    in_transaction <= 1'b0;
                end
            end else begin
                if (m0_valid) begin
                    active_master <= 1'b0;
                    in_transaction <= 1'b1;
                end else if (m1_valid) begin
                    active_master <= 1'b1;
                    in_transaction <= 1'b1;
                end
            end
        end
    end

    // Routing Logic
    wire        sel_valid = (active_master == 0) ? m0_valid : m1_valid;
    wire [31:0] sel_addr  = (active_master == 0) ? m0_addr  : m1_addr;
    wire [31:0] sel_wdata = (active_master == 0) ? m0_wdata : m1_wdata;
    wire [ 3:0] sel_wstrb = (active_master == 0) ? m0_wstrb : m1_wstrb;

    wire hit_s0 = (sel_addr & `ADDR_MEM_MASK) == `ADDR_MEM_BASE;
    wire hit_s1 = (sel_addr & `ADDR_DMA_MASK) == `ADDR_DMA_BASE;
    wire hit_s2 = (sel_addr & `ADDR_CGRA_MASK) == `ADDR_CGRA_BASE;
    wire hit_s3 = (sel_addr & `ADDR_SOFTMAX_MASK) == `ADDR_SOFTMAX_BASE;
    wire hit_s4 = (sel_addr & `ADDR_TEST_MASK) == `ADDR_TEST_BASE;

    always @(*) begin
        // Default outputs
        s0_valid = 0; s1_valid = 0; s2_valid = 0; s3_valid = 0; s4_valid = 0;
        s0_addr = sel_addr; s1_addr = sel_addr; s2_addr = sel_addr; s3_addr = sel_addr; s4_addr = sel_addr;
        s0_wdata = sel_wdata; s1_wdata = sel_wdata; s2_wdata = sel_wdata; s3_wdata = sel_wdata; s4_wdata = sel_wdata;
        s0_wstrb = sel_wstrb; s1_wstrb = sel_wstrb; s2_wstrb = sel_wstrb; s3_wstrb = sel_wstrb; s4_wstrb = sel_wstrb;

        m0_ready = 0; m1_ready = 0;
        m0_rdata = 0; m1_rdata = 0;

        if (sel_valid && in_transaction) begin
            if (hit_s0) begin
                s0_valid = sel_valid;
                if (active_master == 0) begin m0_ready = s0_ready; m0_rdata = s0_rdata; end
                else                    begin m1_ready = s0_ready; m1_rdata = s0_rdata; end
            end else if (hit_s1) begin
                s1_valid = sel_valid;
                if (active_master == 0) begin m0_ready = s1_ready; m0_rdata = s1_rdata; end
                else                    begin m1_ready = s1_ready; m1_rdata = s1_rdata; end
            end else if (hit_s2) begin
                s2_valid = sel_valid;
                if (active_master == 0) begin m0_ready = s2_ready; m0_rdata = s2_rdata; end
                else                    begin m1_ready = s2_ready; m1_rdata = s2_rdata; end
            end else if (hit_s3) begin
                s3_valid = sel_valid;
                if (active_master == 0) begin m0_ready = s3_ready; m0_rdata = s3_rdata; end
                else                    begin m1_ready = s3_ready; m1_rdata = s3_rdata; end
            end else if (hit_s4) begin
                s4_valid = sel_valid;
                if (active_master == 0) begin m0_ready = s4_ready; m0_rdata = s4_rdata; end
                else                    begin m1_ready = s4_ready; m1_rdata = s4_rdata; end
            end else begin
                // Invalid address -> Return error/ready immediately to prevent hang
                if (active_master == 0) begin m0_ready = 1'b1; m0_rdata = 32'hDEADBEEF; end
                else                    begin m1_ready = 1'b1; m1_rdata = 32'hDEADBEEF; end
            end
        end
    end

endmodule
