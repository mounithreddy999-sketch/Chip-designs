/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Commercial AI Accelerator System-on-Chip (SoC) Top-Level Module.
 * Integrates:
 *   - PicoRV32 Host Processor
 *   - AXI4 Interconnect (3x5)
 *   - 64KB L2 SRAM Scratchpad (axi_ram)
 *   - 2x AXI-Stream DMA Controllers
 *   - Unified Attention Sequencer (CGRA + Softmax)
 *   - Testbench MMIO Interface
 */

`default_nettype none

`include "soc_memory_map.vh"

module soc_top (
    input  wire clk,
    input  wire rst,
    output wire trap,
    
    // Testbench observability ports
    output reg        test_done,
    output reg [31:0] test_result
);

    // ----------------------------------------------------
    // PicoRV32 + AXI Wrapper (Master 0)
    // ----------------------------------------------------
    wire        cpu_mem_valid;
    wire        cpu_mem_instr;
    wire        cpu_mem_ready;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [ 3:0] cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;

    wire dma_n_irq, dma_w_irq;

    picorv32 #(
        .COMPRESSED_ISA(1),
        .ENABLE_MUL(1),
        .ENABLE_DIV(1),
        .ENABLE_IRQ(1)
    ) cpu (
        .clk         (clk),
        .resetn      (~rst),
        .trap        (trap),
        .mem_valid   (cpu_mem_valid),
        .mem_instr   (cpu_mem_instr),
        .mem_ready   (cpu_mem_ready),
        .mem_addr    (cpu_mem_addr),
        .mem_wdata   (cpu_mem_wdata),
        .mem_wstrb   (cpu_mem_wstrb),
        .mem_rdata   (cpu_mem_rdata),
        .irq         ({30'b0, dma_w_irq, dma_n_irq})
    );

    wire [31:0] s0_axi_awaddr;  wire [ 2:0] s0_axi_awprot;  wire        s0_axi_awvalid; wire        s0_axi_awready;
    wire [31:0] s0_axi_wdata;   wire [ 3:0] s0_axi_wstrb;   wire        s0_axi_wvalid;  wire        s0_axi_wready;
    wire [ 1:0] s0_axi_bresp;                               wire        s0_axi_bvalid;  wire        s0_axi_bready;
    wire [31:0] s0_axi_araddr;  wire [ 2:0] s0_axi_arprot;  wire        s0_axi_arvalid; wire        s0_axi_arready;
    wire [31:0] s0_axi_rdata;   wire [ 1:0] s0_axi_rresp;   wire        s0_axi_rvalid;  wire        s0_axi_rready;

    picorv32_axi_wrapper cpu_axi (
        .clk(clk),
        .rstn(~rst),
        .mem_valid(cpu_mem_valid),
        .mem_instr(cpu_mem_instr),
        .mem_ready(cpu_mem_ready),
        .mem_addr(cpu_mem_addr),
        .mem_wdata(cpu_mem_wdata),
        .mem_wstrb(cpu_mem_wstrb),
        .mem_rdata(cpu_mem_rdata),
        
        .m_axi_awaddr(s0_axi_awaddr),
        .m_axi_awprot(s0_axi_awprot),
        .m_axi_awvalid(s0_axi_awvalid),
        .m_axi_awready(s0_axi_awready),
        .m_axi_wdata(s0_axi_wdata),
        .m_axi_wstrb(s0_axi_wstrb),
        .m_axi_wvalid(s0_axi_wvalid),
        .m_axi_wready(s0_axi_wready),
        .m_axi_bresp(s0_axi_bresp),
        .m_axi_bvalid(s0_axi_bvalid),
        .m_axi_bready(s0_axi_bready),
        .m_axi_araddr(s0_axi_araddr),
        .m_axi_arprot(s0_axi_arprot),
        .m_axi_arvalid(s0_axi_arvalid),
        .m_axi_arready(s0_axi_arready),
        .m_axi_rdata(s0_axi_rdata),
        .m_axi_rresp(s0_axi_rresp),
        .m_axi_rvalid(s0_axi_rvalid),
        .m_axi_rready(s0_axi_rready)
    );

    // ----------------------------------------------------
    // DMA North (Master 1 / Slave 1)
    // ----------------------------------------------------
    wire [31:0] s1_axi_awaddr;  wire [ 2:0] s1_axi_awprot;  wire        s1_axi_awvalid; wire        s1_axi_awready;
    wire [31:0] s1_axi_wdata;   wire [ 3:0] s1_axi_wstrb;   wire        s1_axi_wvalid;  wire        s1_axi_wready;
    wire [ 1:0] s1_axi_bresp;                               wire        s1_axi_bvalid;  wire        s1_axi_bready;
    wire [31:0] s1_axi_araddr;  wire [ 2:0] s1_axi_arprot;  wire        s1_axi_arvalid; wire        s1_axi_arready;
    wire [31:0] s1_axi_rdata;   wire [ 1:0] s1_axi_rresp;   wire        s1_axi_rvalid;  wire        s1_axi_rready;

    wire [31:0] m1_axi_awaddr;  wire [ 2:0] m1_axi_awprot;  wire        m1_axi_awvalid; wire        m1_axi_awready;
    wire [31:0] m1_axi_wdata;   wire [ 3:0] m1_axi_wstrb;   wire        m1_axi_wvalid;  wire        m1_axi_wready;
    wire [ 1:0] m1_axi_bresp;                               wire        m1_axi_bvalid;  wire        m1_axi_bready;
    wire [31:0] m1_axi_araddr;  wire [ 2:0] m1_axi_arprot;  wire        m1_axi_arvalid; wire        m1_axi_arready;
    wire [31:0] m1_axi_rdata;   wire [ 1:0] m1_axi_rresp;   wire        m1_axi_rvalid;  wire        m1_axi_rready;

    wire [31:0] axis_n_tdata;
    wire        axis_n_tvalid;
    wire        axis_n_tready;
    wire        axis_n_tlast;

    axi_stream_dma dma_n (
        .clk(clk),
        .rstn(~rst),
        .s_axi_awaddr(m1_axi_awaddr), .s_axi_awprot(m1_axi_awprot), .s_axi_awvalid(m1_axi_awvalid), .s_axi_awready(m1_axi_awready),
        .s_axi_wdata(m1_axi_wdata), .s_axi_wstrb(m1_axi_wstrb), .s_axi_wvalid(m1_axi_wvalid), .s_axi_wready(m1_axi_wready),
        .s_axi_bresp(m1_axi_bresp), .s_axi_bvalid(m1_axi_bvalid), .s_axi_bready(m1_axi_bready),
        .s_axi_araddr(m1_axi_araddr), .s_axi_arprot(m1_axi_arprot), .s_axi_arvalid(m1_axi_arvalid), .s_axi_arready(m1_axi_arready),
        .s_axi_rdata(m1_axi_rdata), .s_axi_rresp(m1_axi_rresp), .s_axi_rvalid(m1_axi_rvalid), .s_axi_rready(m1_axi_rready),
        
        .m_axi_araddr(s1_axi_araddr), .m_axi_arlen(), .m_axi_arsize(), .m_axi_arburst(), .m_axi_arprot(s1_axi_arprot),
        .m_axi_arvalid(s1_axi_arvalid), .m_axi_arready(s1_axi_arready),
        .m_axi_rdata(s1_axi_rdata), .m_axi_rresp(s1_axi_rresp), .m_axi_rlast(1'b1), .m_axi_rvalid(s1_axi_rvalid), .m_axi_rready(s1_axi_rready),
        
        .m_axis_tdata(axis_n_tdata), .m_axis_tvalid(axis_n_tvalid), .m_axis_tready(axis_n_tready), .m_axis_tlast(axis_n_tlast),
        .irq(dma_n_irq)
    );
    
    // DMA North only reads, disable write channels
    assign s1_axi_awaddr = 0; assign s1_axi_awprot = 0; assign s1_axi_awvalid = 0;
    assign s1_axi_wdata = 0; assign s1_axi_wstrb = 0; assign s1_axi_wvalid = 0;
    assign s1_axi_bready = 1;

    // ----------------------------------------------------
    // DMA West (Master 2 / Slave 2)
    // ----------------------------------------------------
    wire [31:0] s2_axi_awaddr;  wire [ 2:0] s2_axi_awprot;  wire        s2_axi_awvalid; wire        s2_axi_awready;
    wire [31:0] s2_axi_wdata;   wire [ 3:0] s2_axi_wstrb;   wire        s2_axi_wvalid;  wire        s2_axi_wready;
    wire [ 1:0] s2_axi_bresp;                               wire        s2_axi_bvalid;  wire        s2_axi_bready;
    wire [31:0] s2_axi_araddr;  wire [ 2:0] s2_axi_arprot;  wire        s2_axi_arvalid; wire        s2_axi_arready;
    wire [31:0] s2_axi_rdata;   wire [ 1:0] s2_axi_rresp;   wire        s2_axi_rvalid;  wire        s2_axi_rready;

    wire [31:0] m2_axi_awaddr;  wire [ 2:0] m2_axi_awprot;  wire        m2_axi_awvalid; wire        m2_axi_awready;
    wire [31:0] m2_axi_wdata;   wire [ 3:0] m2_axi_wstrb;   wire        m2_axi_wvalid;  wire        m2_axi_wready;
    wire [ 1:0] m2_axi_bresp;                               wire        m2_axi_bvalid;  wire        m2_axi_bready;
    wire [31:0] m2_axi_araddr;  wire [ 2:0] m2_axi_arprot;  wire        m2_axi_arvalid; wire        m2_axi_arready;
    wire [31:0] m2_axi_rdata;   wire [ 1:0] m2_axi_rresp;   wire        m2_axi_rvalid;  wire        m2_axi_rready;

    wire [31:0] axis_w_tdata;
    wire        axis_w_tvalid;
    wire        axis_w_tready;
    wire        axis_w_tlast;

    axi_stream_dma dma_w (
        .clk(clk),
        .rstn(~rst),
        .s_axi_awaddr(m2_axi_awaddr), .s_axi_awprot(m2_axi_awprot), .s_axi_awvalid(m2_axi_awvalid), .s_axi_awready(m2_axi_awready),
        .s_axi_wdata(m2_axi_wdata), .s_axi_wstrb(m2_axi_wstrb), .s_axi_wvalid(m2_axi_wvalid), .s_axi_wready(m2_axi_wready),
        .s_axi_bresp(m2_axi_bresp), .s_axi_bvalid(m2_axi_bvalid), .s_axi_bready(m2_axi_bready),
        .s_axi_araddr(m2_axi_araddr), .s_axi_arprot(m2_axi_arprot), .s_axi_arvalid(m2_axi_arvalid), .s_axi_arready(m2_axi_arready),
        .s_axi_rdata(m2_axi_rdata), .s_axi_rresp(m2_axi_rresp), .s_axi_rvalid(m2_axi_rvalid), .s_axi_rready(m2_axi_rready),
        
        .m_axi_araddr(s2_axi_araddr), .m_axi_arlen(), .m_axi_arsize(), .m_axi_arburst(), .m_axi_arprot(s2_axi_arprot),
        .m_axi_arvalid(s2_axi_arvalid), .m_axi_arready(s2_axi_arready),
        .m_axi_rdata(s2_axi_rdata), .m_axi_rresp(s2_axi_rresp), .m_axi_rlast(1'b1), .m_axi_rvalid(s2_axi_rvalid), .m_axi_rready(s2_axi_rready),
        
        .m_axis_tdata(axis_w_tdata), .m_axis_tvalid(axis_w_tvalid), .m_axis_tready(axis_w_tready), .m_axis_tlast(axis_w_tlast),
        .irq(dma_w_irq)
    );
    
    // DMA West only reads, disable write channels
    assign s2_axi_awaddr = 0; assign s2_axi_awprot = 0; assign s2_axi_awvalid = 0;
    assign s2_axi_wdata = 0; assign s2_axi_wstrb = 0; assign s2_axi_wvalid = 0;
    assign s2_axi_bready = 1;

    // ----------------------------------------------------
    // SoC Interconnect AXI (3x5 Crossbar)
    // ----------------------------------------------------
    wire [31:0] m0_axi_awaddr;  wire [ 2:0] m0_axi_awprot;  wire        m0_axi_awvalid; wire        m0_axi_awready;
    wire [31:0] m0_axi_wdata;   wire [ 3:0] m0_axi_wstrb;   wire        m0_axi_wvalid;  wire        m0_axi_wready;
    wire [ 1:0] m0_axi_bresp;                               wire        m0_axi_bvalid;  wire        m0_axi_bready;
    wire [31:0] m0_axi_araddr;  wire [ 2:0] m0_axi_arprot;  wire        m0_axi_arvalid; wire        m0_axi_arready;
    wire [31:0] m0_axi_rdata;   wire [ 1:0] m0_axi_rresp;   wire        m0_axi_rvalid;  wire        m0_axi_rready;

    wire [31:0] m3_axi_awaddr;  wire [ 2:0] m3_axi_awprot;  wire        m3_axi_awvalid; wire        m3_axi_awready;
    wire [31:0] m3_axi_wdata;   wire [ 3:0] m3_axi_wstrb;   wire        m3_axi_wvalid;  wire        m3_axi_wready;
    wire [ 1:0] m3_axi_bresp;                               wire        m3_axi_bvalid;  wire        m3_axi_bready;
    wire [31:0] m3_axi_araddr;  wire [ 2:0] m3_axi_arprot;  wire        m3_axi_arvalid; wire        m3_axi_arready;
    wire [31:0] m3_axi_rdata;   wire [ 1:0] m3_axi_rresp;   wire        m3_axi_rvalid;  wire        m3_axi_rready;

    wire [31:0] m4_axi_awaddr;  wire [ 2:0] m4_axi_awprot;  wire        m4_axi_awvalid; wire        m4_axi_awready;
    wire [31:0] m4_axi_wdata;   wire [ 3:0] m4_axi_wstrb;   wire        m4_axi_wvalid;  wire        m4_axi_wready;
    wire [ 1:0] m4_axi_bresp;                               wire        m4_axi_bvalid;  wire        m4_axi_bready;
    wire [31:0] m4_axi_araddr;  wire [ 2:0] m4_axi_arprot;  wire        m4_axi_arvalid; wire        m4_axi_arready;
    wire [31:0] m4_axi_rdata;   wire [ 1:0] m4_axi_rresp;   wire        m4_axi_rvalid;  wire        m4_axi_rready;

    soc_interconnect_axi bus (
        .clk(clk),
        .rstn(~rst),

        .s0_axi_awaddr(s0_axi_awaddr), .s0_axi_awprot(s0_axi_awprot), .s0_axi_awvalid(s0_axi_awvalid), .s0_axi_awready(s0_axi_awready),
        .s0_axi_wdata(s0_axi_wdata), .s0_axi_wstrb(s0_axi_wstrb), .s0_axi_wvalid(s0_axi_wvalid), .s0_axi_wready(s0_axi_wready),
        .s0_axi_bresp(s0_axi_bresp), .s0_axi_bvalid(s0_axi_bvalid), .s0_axi_bready(s0_axi_bready),
        .s0_axi_araddr(s0_axi_araddr), .s0_axi_arprot(s0_axi_arprot), .s0_axi_arvalid(s0_axi_arvalid), .s0_axi_arready(s0_axi_arready),
        .s0_axi_rdata(s0_axi_rdata), .s0_axi_rresp(s0_axi_rresp), .s0_axi_rvalid(s0_axi_rvalid), .s0_axi_rready(s0_axi_rready),

        .s1_axi_awaddr(s1_axi_awaddr), .s1_axi_awprot(s1_axi_awprot), .s1_axi_awvalid(s1_axi_awvalid), .s1_axi_awready(s1_axi_awready),
        .s1_axi_wdata(s1_axi_wdata), .s1_axi_wstrb(s1_axi_wstrb), .s1_axi_wvalid(s1_axi_wvalid), .s1_axi_wready(s1_axi_wready),
        .s1_axi_bresp(s1_axi_bresp), .s1_axi_bvalid(s1_axi_bvalid), .s1_axi_bready(s1_axi_bready),
        .s1_axi_araddr(s1_axi_araddr), .s1_axi_arprot(s1_axi_arprot), .s1_axi_arvalid(s1_axi_arvalid), .s1_axi_arready(s1_axi_arready),
        .s1_axi_rdata(s1_axi_rdata), .s1_axi_rresp(s1_axi_rresp), .s1_axi_rvalid(s1_axi_rvalid), .s1_axi_rready(s1_axi_rready),

        .s2_axi_awaddr(s2_axi_awaddr), .s2_axi_awprot(s2_axi_awprot), .s2_axi_awvalid(s2_axi_awvalid), .s2_axi_awready(s2_axi_awready),
        .s2_axi_wdata(s2_axi_wdata), .s2_axi_wstrb(s2_axi_wstrb), .s2_axi_wvalid(s2_axi_wvalid), .s2_axi_wready(s2_axi_wready),
        .s2_axi_bresp(s2_axi_bresp), .s2_axi_bvalid(s2_axi_bvalid), .s2_axi_bready(s2_axi_bready),
        .s2_axi_araddr(s2_axi_araddr), .s2_axi_arprot(s2_axi_arprot), .s2_axi_arvalid(s2_axi_arvalid), .s2_axi_arready(s2_axi_arready),
        .s2_axi_rdata(s2_axi_rdata), .s2_axi_rresp(s2_axi_rresp), .s2_axi_rvalid(s2_axi_rvalid), .s2_axi_rready(s2_axi_rready),

        .m0_axi_awaddr(m0_axi_awaddr), .m0_axi_awprot(m0_axi_awprot), .m0_axi_awvalid(m0_axi_awvalid), .m0_axi_awready(m0_axi_awready),
        .m0_axi_wdata(m0_axi_wdata), .m0_axi_wstrb(m0_axi_wstrb), .m0_axi_wvalid(m0_axi_wvalid), .m0_axi_wready(m0_axi_wready),
        .m0_axi_bresp(m0_axi_bresp), .m0_axi_bvalid(m0_axi_bvalid), .m0_axi_bready(m0_axi_bready),
        .m0_axi_araddr(m0_axi_araddr), .m0_axi_arprot(m0_axi_arprot), .m0_axi_arvalid(m0_axi_arvalid), .m0_axi_arready(m0_axi_arready),
        .m0_axi_rdata(m0_axi_rdata), .m0_axi_rresp(m0_axi_rresp), .m0_axi_rvalid(m0_axi_rvalid), .m0_axi_rready(m0_axi_rready),
        
        .m0_axi_awid(m0_axi_awid), .m0_axi_bid(m0_axi_bid),
        .m0_axi_arid(m0_axi_arid), .m0_axi_rid(m0_axi_rid),

        .m1_axi_awaddr(m1_axi_awaddr), .m1_axi_awprot(m1_axi_awprot), .m1_axi_awvalid(m1_axi_awvalid), .m1_axi_awready(m1_axi_awready),
        .m1_axi_wdata(m1_axi_wdata), .m1_axi_wstrb(m1_axi_wstrb), .m1_axi_wvalid(m1_axi_wvalid), .m1_axi_wready(m1_axi_wready),
        .m1_axi_bresp(m1_axi_bresp), .m1_axi_bvalid(m1_axi_bvalid), .m1_axi_bready(m1_axi_bready),
        .m1_axi_araddr(m1_axi_araddr), .m1_axi_arprot(m1_axi_arprot), .m1_axi_arvalid(m1_axi_arvalid), .m1_axi_arready(m1_axi_arready),
        .m1_axi_rdata(m1_axi_rdata), .m1_axi_rresp(m1_axi_rresp), .m1_axi_rvalid(m1_axi_rvalid), .m1_axi_rready(m1_axi_rready),

        .m2_axi_awaddr(m2_axi_awaddr), .m2_axi_awprot(m2_axi_awprot), .m2_axi_awvalid(m2_axi_awvalid), .m2_axi_awready(m2_axi_awready),
        .m2_axi_wdata(m2_axi_wdata), .m2_axi_wstrb(m2_axi_wstrb), .m2_axi_wvalid(m2_axi_wvalid), .m2_axi_wready(m2_axi_wready),
        .m2_axi_bresp(m2_axi_bresp), .m2_axi_bvalid(m2_axi_bvalid), .m2_axi_bready(m2_axi_bready),
        .m2_axi_araddr(m2_axi_araddr), .m2_axi_arprot(m2_axi_arprot), .m2_axi_arvalid(m2_axi_arvalid), .m2_axi_arready(m2_axi_arready),
        .m2_axi_rdata(m2_axi_rdata), .m2_axi_rresp(m2_axi_rresp), .m2_axi_rvalid(m2_axi_rvalid), .m2_axi_rready(m2_axi_rready),

        .m3_axi_awaddr(m3_axi_awaddr), .m3_axi_awprot(m3_axi_awprot), .m3_axi_awvalid(m3_axi_awvalid), .m3_axi_awready(m3_axi_awready),
        .m3_axi_wdata(m3_axi_wdata), .m3_axi_wstrb(m3_axi_wstrb), .m3_axi_wvalid(m3_axi_wvalid), .m3_axi_wready(m3_axi_wready),
        .m3_axi_bresp(m3_axi_bresp), .m3_axi_bvalid(m3_axi_bvalid), .m3_axi_bready(m3_axi_bready),
        .m3_axi_araddr(m3_axi_araddr), .m3_axi_arprot(m3_axi_arprot), .m3_axi_arvalid(m3_axi_arvalid), .m3_axi_arready(m3_axi_arready),
        .m3_axi_rdata(m3_axi_rdata), .m3_axi_rresp(m3_axi_rresp), .m3_axi_rvalid(m3_axi_rvalid), .m3_axi_rready(m3_axi_rready),

        .m4_axi_awaddr(m4_axi_awaddr), .m4_axi_awprot(m4_axi_awprot), .m4_axi_awvalid(m4_axi_awvalid), .m4_axi_awready(m4_axi_awready),
        .m4_axi_wdata(m4_axi_wdata), .m4_axi_wstrb(m4_axi_wstrb), .m4_axi_wvalid(m4_axi_wvalid), .m4_axi_wready(m4_axi_wready),
        .m4_axi_bresp(m4_axi_bresp), .m4_axi_bvalid(m4_axi_bvalid), .m4_axi_bready(m4_axi_bready),
        .m4_axi_araddr(m4_axi_araddr), .m4_axi_arprot(m4_axi_arprot), .m4_axi_arvalid(m4_axi_arvalid), .m4_axi_arready(m4_axi_arready),
        .m4_axi_rdata(m4_axi_rdata), .m4_axi_rresp(m4_axi_rresp), .m4_axi_rvalid(m4_axi_rvalid), .m4_axi_rready(m4_axi_rready)
    );

    // ----------------------------------------------------
    // Slave 0: Main SoC Memory (64 KB SRAM L2 Scratchpad)
    // ----------------------------------------------------
    wire [9:0] m0_axi_awid, m0_axi_bid, m0_axi_arid, m0_axi_rid;
    
    axi_ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(16), // 64KB
        .ID_WIDTH(10),
        .INIT_FILE("../sw/firmware/firmware.hex")
    ) memory (
        .clk(clk),
        .rst(rst),
        .s_axi_awid(m0_axi_awid), .s_axi_awaddr(m0_axi_awaddr[15:0]), .s_axi_awlen(8'd0), .s_axi_awsize(3'b010), .s_axi_awburst(2'b01),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'd0), .s_axi_awprot(m0_axi_awprot), .s_axi_awvalid(m0_axi_awvalid), .s_axi_awready(m0_axi_awready),
        .s_axi_wdata(m0_axi_wdata), .s_axi_wstrb(m0_axi_wstrb), .s_axi_wlast(1'b1), .s_axi_wvalid(m0_axi_wvalid), .s_axi_wready(m0_axi_wready),
        .s_axi_bid(m0_axi_bid), .s_axi_bresp(m0_axi_bresp), .s_axi_bvalid(m0_axi_bvalid), .s_axi_bready(m0_axi_bready),
        .s_axi_arid(m0_axi_arid), .s_axi_araddr(m0_axi_araddr[15:0]), .s_axi_arlen(8'd0), .s_axi_arsize(3'b010), .s_axi_arburst(2'b01),
        .s_axi_arlock(1'b0), .s_axi_arcache(4'd0), .s_axi_arprot(m0_axi_arprot), .s_axi_arvalid(m0_axi_arvalid), .s_axi_arready(m0_axi_arready),
        .s_axi_rid(m0_axi_rid), .s_axi_rdata(m0_axi_rdata), .s_axi_rresp(m0_axi_rresp), .s_axi_rlast(), .s_axi_rvalid(m0_axi_rvalid), .s_axi_rready(m0_axi_rready)
    );

    // ----------------------------------------------------
    // Slave 3: Unified Attention Sequencer
    // ----------------------------------------------------
    wire [31:0] axis_out_tdata;
    wire        axis_out_tvalid;
    wire        axis_out_tready;

    attention_block attention_core (
        .clk(clk),
        .rstn(~rst),
        .s_axi_awaddr(m3_axi_awaddr), .s_axi_awprot(m3_axi_awprot), .s_axi_awvalid(m3_axi_awvalid), .s_axi_awready(m3_axi_awready),
        .s_axi_wdata(m3_axi_wdata), .s_axi_wstrb(m3_axi_wstrb), .s_axi_wvalid(m3_axi_wvalid), .s_axi_wready(m3_axi_wready),
        .s_axi_bresp(m3_axi_bresp), .s_axi_bvalid(m3_axi_bvalid), .s_axi_bready(m3_axi_bready),
        .s_axi_araddr(m3_axi_araddr), .s_axi_arprot(m3_axi_arprot), .s_axi_arvalid(m3_axi_arvalid), .s_axi_arready(m3_axi_arready),
        .s_axi_rdata(m3_axi_rdata), .s_axi_rresp(m3_axi_rresp), .s_axi_rvalid(m3_axi_rvalid), .s_axi_rready(m3_axi_rready),
        
        .s_axis_n_tdata(axis_n_tdata), .s_axis_n_tvalid(axis_n_tvalid), .s_axis_n_tready(axis_n_tready),
        
        .m_axis_out_tdata(axis_out_tdata), .m_axis_out_tvalid(axis_out_tvalid), .m_axis_out_tready(axis_out_tready)
    );

    // ----------------------------------------------------
    // Slave 4: Testbench Observability
    // ----------------------------------------------------
    assign axis_out_tready = 1'b1;

    // AXI-Lite Testbench Responder & Registers
    reg m4_aw_done, m4_w_done;
    reg [31:0] m4_awaddr_reg;
    reg [31:0] m4_wdata_reg;
    reg m4_bvalid_reg;
    reg m4_rvalid_reg;
    
    assign m4_axi_awready = !m4_aw_done && !m4_bvalid_reg;
    assign m4_axi_wready  = !m4_w_done && !m4_bvalid_reg;
    assign m4_axi_bvalid  = m4_bvalid_reg;
    assign m4_axi_bresp   = 2'b00;
    
    assign m4_axi_arready = 1'b1; // Simplified AR responder
    assign m4_axi_rvalid  = m4_rvalid_reg;
    assign m4_axi_rdata   = 32'b0;
    assign m4_axi_rresp   = 2'b00;

    always @(posedge clk) begin
        if (rst) begin
            test_done <= 1'b0;
            test_result <= 32'b0;
            m4_bvalid_reg <= 1'b0;
            m4_rvalid_reg <= 1'b0;
            m4_aw_done <= 1'b0;
            m4_w_done <= 1'b0;
        end else begin
            // Testbench AXI-Lite sink
            if (m4_axi_awvalid && m4_axi_awready) begin m4_awaddr_reg <= m4_axi_awaddr; m4_aw_done <= 1'b1; end
            if (m4_axi_wvalid && m4_axi_wready) begin m4_wdata_reg <= m4_axi_wdata; m4_w_done <= 1'b1; end
            
            if ((m4_aw_done || (m4_axi_awvalid && m4_axi_awready)) && 
                (m4_w_done || (m4_axi_wvalid && m4_axi_wready)) && !m4_bvalid_reg) begin
                
                m4_bvalid_reg <= 1'b1;
                m4_aw_done <= 1'b0;
                m4_w_done <= 1'b0;
                
                if ((m4_aw_done ? m4_awaddr_reg[15:0] : m4_axi_awaddr[15:0]) == 16'h0000) 
                    test_result <= (m4_w_done ? m4_wdata_reg : m4_axi_wdata);
                if ((m4_aw_done ? m4_awaddr_reg[15:0] : m4_axi_awaddr[15:0]) == 16'h0004) 
                    test_done <= (m4_w_done ? m4_wdata_reg[0] : m4_axi_wdata[0]);
            end
            else if (m4_axi_bready && m4_bvalid_reg) begin
                m4_bvalid_reg <= 1'b0;
            end
            
            // Also sink Attention Stream to test_result directly
            if (axis_out_tvalid) begin
                test_result <= axis_out_tdata;
                // Don't set test_done here automatically, let CPU set it
            end
            
            // Simplified Read Responder
            if (m4_axi_arvalid) m4_rvalid_reg <= 1'b1;
            else if (m4_axi_rready) m4_rvalid_reg <= 1'b0;
        end
    end
    
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, soc_top);
    end

endmodule
