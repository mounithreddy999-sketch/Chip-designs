/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * AXI4 System Interconnect Wrapper
 * Wraps the alexforencich/verilog-axi crossbar for our 3x5 architecture.
 */

`default_nettype none

`include "soc_memory_map.vh"

module soc_interconnect_axi (
    input  wire clk,
    input  wire rstn,

    // -----------------------------------------
    // Slave Interfaces (From Masters to Crossbar)
    // -----------------------------------------
    // S0: PicoRV32 (CPU)
    input  wire [31:0] s0_axi_awaddr,  input  wire [ 2:0] s0_axi_awprot,  input  wire        s0_axi_awvalid, output wire        s0_axi_awready,
    input  wire [31:0] s0_axi_wdata,   input  wire [ 3:0] s0_axi_wstrb,   input  wire        s0_axi_wvalid,  output wire        s0_axi_wready,
    output wire [ 1:0] s0_axi_bresp,   output wire        s0_axi_bvalid,  input  wire        s0_axi_bready,
    input  wire [31:0] s0_axi_araddr,  input  wire [ 2:0] s0_axi_arprot,  input  wire        s0_axi_arvalid, output wire        s0_axi_arready,
    output wire [31:0] s0_axi_rdata,   output wire [ 1:0] s0_axi_rresp,   output wire        s0_axi_rvalid,  input  wire        s0_axi_rready,

    // S1: DMA Controller North
    input  wire [31:0] s1_axi_awaddr,  input  wire [ 2:0] s1_axi_awprot,  input  wire        s1_axi_awvalid, output wire        s1_axi_awready,
    input  wire [31:0] s1_axi_wdata,   input  wire [ 3:0] s1_axi_wstrb,   input  wire        s1_axi_wvalid,  output wire        s1_axi_wready,
    output wire [ 1:0] s1_axi_bresp,   output wire        s1_axi_bvalid,  input  wire        s1_axi_bready,
    input  wire [31:0] s1_axi_araddr,  input  wire [ 2:0] s1_axi_arprot,  input  wire        s1_axi_arvalid, output wire        s1_axi_arready,
    output wire [31:0] s1_axi_rdata,   output wire [ 1:0] s1_axi_rresp,   output wire        s1_axi_rvalid,  input  wire        s1_axi_rready,

    // S2: DMA Controller West
    input  wire [31:0] s2_axi_awaddr,  input  wire [ 2:0] s2_axi_awprot,  input  wire        s2_axi_awvalid, output wire        s2_axi_awready,
    input  wire [31:0] s2_axi_wdata,   input  wire [ 3:0] s2_axi_wstrb,   input  wire        s2_axi_wvalid,  output wire        s2_axi_wready,
    output wire [ 1:0] s2_axi_bresp,   output wire        s2_axi_bvalid,  input  wire        s2_axi_bready,
    input  wire [31:0] s2_axi_araddr,  input  wire [ 2:0] s2_axi_arprot,  input  wire        s2_axi_arvalid, output wire        s2_axi_arready,
    output wire [31:0] s2_axi_rdata,   output wire [ 1:0] s2_axi_rresp,   output wire        s2_axi_rvalid,  input  wire        s2_axi_rready,

    // -----------------------------------------
    // Master Interfaces (From Crossbar to Slaves)
    // -----------------------------------------
    // M0: L2 SRAM
    output wire [31:0] m0_axi_awaddr,  output wire [ 2:0] m0_axi_awprot,  output wire        m0_axi_awvalid, input  wire        m0_axi_awready,
    output wire [31:0] m0_axi_wdata,   output wire [ 3:0] m0_axi_wstrb,   output wire        m0_axi_wvalid,  input  wire        m0_axi_wready,
    input  wire [ 1:0] m0_axi_bresp,   input  wire        m0_axi_bvalid,  output wire        m0_axi_bready,
    output wire [31:0] m0_axi_araddr,  output wire [ 2:0] m0_axi_arprot,  output wire        m0_axi_arvalid, input  wire        m0_axi_arready,
    input  wire [31:0] m0_axi_rdata,   input  wire [ 1:0] m0_axi_rresp,   input  wire        m0_axi_rvalid,  output wire        m0_axi_rready,

    // M1: DMA MMIO (North)
    output wire [31:0] m1_axi_awaddr,  output wire [ 2:0] m1_axi_awprot,  output wire        m1_axi_awvalid, input  wire        m1_axi_awready,
    output wire [31:0] m1_axi_wdata,   output wire [ 3:0] m1_axi_wstrb,   output wire        m1_axi_wvalid,  input  wire        m1_axi_wready,
    input  wire [ 1:0] m1_axi_bresp,   input  wire        m1_axi_bvalid,  output wire        m1_axi_bready,
    output wire [31:0] m1_axi_araddr,  output wire [ 2:0] m1_axi_arprot,  output wire        m1_axi_arvalid, input  wire        m1_axi_arready,
    input  wire [31:0] m1_axi_rdata,   input  wire [ 1:0] m1_axi_rresp,   input  wire        m1_axi_rvalid,  output wire        m1_axi_rready,

    // M2: DMA MMIO (West)
    output wire [31:0] m2_axi_awaddr,  output wire [ 2:0] m2_axi_awprot,  output wire        m2_axi_awvalid, input  wire        m2_axi_awready,
    output wire [31:0] m2_axi_wdata,   output wire [ 3:0] m2_axi_wstrb,   output wire        m2_axi_wvalid,  input  wire        m2_axi_wready,
    input  wire [ 1:0] m2_axi_bresp,   input  wire        m2_axi_bvalid,  output wire        m2_axi_bready,
    output wire [31:0] m2_axi_araddr,  output wire [ 2:0] m2_axi_arprot,  output wire        m2_axi_arvalid, input  wire        m2_axi_arready,
    input  wire [31:0] m2_axi_rdata,   input  wire [ 1:0] m2_axi_rresp,   input  wire        m2_axi_rvalid,  output wire        m2_axi_rready,

    // M3: Attention Sequencer MMIO
    output wire [31:0] m3_axi_awaddr,  output wire [ 2:0] m3_axi_awprot,  output wire        m3_axi_awvalid, input  wire        m3_axi_awready,
    output wire [31:0] m3_axi_wdata,   output wire [ 3:0] m3_axi_wstrb,   output wire        m3_axi_wvalid,  input  wire        m3_axi_wready,
    input  wire [ 1:0] m3_axi_bresp,   input  wire        m3_axi_bvalid,  output wire        m3_axi_bready,
    output wire [31:0] m3_axi_araddr,  output wire [ 2:0] m3_axi_arprot,  output wire        m3_axi_arvalid, input  wire        m3_axi_arready,
    input  wire [31:0] m3_axi_rdata,   input  wire [ 1:0] m3_axi_rresp,   input  wire        m3_axi_rvalid,  output wire        m3_axi_rready,

    // M4: Testbench MMIO
    output wire [31:0] m4_axi_awaddr,  output wire [ 2:0] m4_axi_awprot,  output wire        m4_axi_awvalid, input  wire        m4_axi_awready,
    output wire [31:0] m4_axi_wdata,   output wire [ 3:0] m4_axi_wstrb,   output wire        m4_axi_wvalid,  input  wire        m4_axi_wready,
    input  wire [ 1:0] m4_axi_bresp,   input  wire        m4_axi_bvalid,  output wire        m4_axi_bready,
    output wire [31:0] m4_axi_araddr,  output wire [ 2:0] m4_axi_arprot,  output wire        m4_axi_arvalid, input  wire        m4_axi_arready,
    input  wire [31:0] m4_axi_rdata,   input  wire [ 1:0] m4_axi_rresp,   input  wire        m4_axi_rvalid,  output wire        m4_axi_rready,
    
    // M0 ID ports (for axi_ram)
    output wire [9:0] m0_axi_awid,
    input  wire [9:0] m0_axi_bid,
    output wire [9:0] m0_axi_arid,
    input  wire [9:0] m0_axi_rid
);

    // Concatenate S buses
    wire [3*32-1:0] s_axi_awaddr  = {s2_axi_awaddr, s1_axi_awaddr, s0_axi_awaddr};
    wire [3*3-1:0]  s_axi_awprot  = {s2_axi_awprot, s1_axi_awprot, s0_axi_awprot};
    wire [3-1:0]    s_axi_awvalid = {s2_axi_awvalid, s1_axi_awvalid, s0_axi_awvalid};
    wire [3-1:0]    s_axi_awready;
    
    wire [3*32-1:0] s_axi_wdata   = {s2_axi_wdata, s1_axi_wdata, s0_axi_wdata};
    wire [3*4-1:0]  s_axi_wstrb   = {s2_axi_wstrb, s1_axi_wstrb, s0_axi_wstrb};
    wire [3-1:0]    s_axi_wvalid  = {s2_axi_wvalid, s1_axi_wvalid, s0_axi_wvalid};
    wire [3-1:0]    s_axi_wready;
    
    wire [3*2-1:0]  s_axi_bresp;
    wire [3-1:0]    s_axi_bvalid;
    wire [3-1:0]    s_axi_bready  = {s2_axi_bready, s1_axi_bready, s0_axi_bready};
    
    wire [3*32-1:0] s_axi_araddr  = {s2_axi_araddr, s1_axi_araddr, s0_axi_araddr};
    wire [3*3-1:0]  s_axi_arprot  = {s2_axi_arprot, s1_axi_arprot, s0_axi_arprot};
    wire [3-1:0]    s_axi_arvalid = {s2_axi_arvalid, s1_axi_arvalid, s0_axi_arvalid};
    wire [3-1:0]    s_axi_arready;
    
    wire [3*32-1:0] s_axi_rdata;
    wire [3*2-1:0]  s_axi_rresp;
    wire [3-1:0]    s_axi_rvalid;
    wire [3-1:0]    s_axi_rready  = {s2_axi_rready, s1_axi_rready, s0_axi_rready};

    // Split S ready/resp
    assign s0_axi_awready = s_axi_awready[0]; assign s1_axi_awready = s_axi_awready[1]; assign s2_axi_awready = s_axi_awready[2];
    assign s0_axi_wready  = s_axi_wready[0];  assign s1_axi_wready  = s_axi_wready[1];  assign s2_axi_wready  = s_axi_wready[2];
    assign s0_axi_bresp   = s_axi_bresp[1:0]; assign s1_axi_bresp   = s_axi_bresp[3:2]; assign s2_axi_bresp   = s_axi_bresp[5:4];
    assign s0_axi_bvalid  = s_axi_bvalid[0];  assign s1_axi_bvalid  = s_axi_bvalid[1];  assign s2_axi_bvalid  = s_axi_bvalid[2];
    assign s0_axi_arready = s_axi_arready[0]; assign s1_axi_arready = s_axi_arready[1]; assign s2_axi_arready = s_axi_arready[2];
    assign s0_axi_rdata   = s_axi_rdata[31:0]; assign s1_axi_rdata  = s_axi_rdata[63:32]; assign s2_axi_rdata = s_axi_rdata[95:64];
    assign s0_axi_rresp   = s_axi_rresp[1:0]; assign s1_axi_rresp   = s_axi_rresp[3:2]; assign s2_axi_rresp   = s_axi_rresp[5:4];
    assign s0_axi_rvalid  = s_axi_rvalid[0];  assign s1_axi_rvalid  = s_axi_rvalid[1];  assign s2_axi_rvalid  = s_axi_rvalid[2];

    // Concatenate M buses
    wire [5*32-1:0] m_axi_awaddr;
    wire [5*3-1:0]  m_axi_awprot;
    wire [5-1:0]    m_axi_awvalid;
    wire [5-1:0]    m_axi_awready = {m4_axi_awready, m3_axi_awready, m2_axi_awready, m1_axi_awready, m0_axi_awready};
    
    wire [5*32-1:0] m_axi_wdata;
    wire [5*4-1:0]  m_axi_wstrb;
    wire [5-1:0]    m_axi_wvalid;
    wire [5-1:0]    m_axi_wready  = {m4_axi_wready, m3_axi_wready, m2_axi_wready, m1_axi_wready, m0_axi_wready};
    
    wire [5*2-1:0]  m_axi_bresp   = {m4_axi_bresp, m3_axi_bresp, m2_axi_bresp, m1_axi_bresp, m0_axi_bresp};
    wire [5-1:0]    m_axi_bvalid  = {m4_axi_bvalid, m3_axi_bvalid, m2_axi_bvalid, m1_axi_bvalid, m0_axi_bvalid};
    wire [5-1:0]    m_axi_bready;
    
    wire [5*32-1:0] m_axi_araddr;
    wire [5*3-1:0]  m_axi_arprot;
    wire [5-1:0]    m_axi_arvalid;
    wire [5-1:0]    m_axi_arready = {m4_axi_arready, m3_axi_arready, m2_axi_arready, m1_axi_arready, m0_axi_arready};
    
    wire [5*32-1:0] m_axi_rdata   = {m4_axi_rdata, m3_axi_rdata, m2_axi_rdata, m1_axi_rdata, m0_axi_rdata};
    wire [5*2-1:0]  m_axi_rresp   = {m4_axi_rresp, m3_axi_rresp, m2_axi_rresp, m1_axi_rresp, m0_axi_rresp};
    wire [5-1:0]    m_axi_rvalid  = {m4_axi_rvalid, m3_axi_rvalid, m2_axi_rvalid, m1_axi_rvalid, m0_axi_rvalid};
    wire [5-1:0]    m_axi_rready;

    // Split M reqs
    assign m0_axi_awaddr  = m_axi_awaddr[31:0];
    assign m1_axi_awaddr  = m_axi_awaddr[63:32];
    assign m2_axi_awaddr  = m_axi_awaddr[95:64];
    assign m3_axi_awaddr  = m_axi_awaddr[127:96];
    assign m4_axi_awaddr  = m_axi_awaddr[159:128];
    
    assign m0_axi_awprot  = m_axi_awprot[2:0];
    assign m1_axi_awprot  = m_axi_awprot[5:3];
    assign m2_axi_awprot  = m_axi_awprot[8:6];
    assign m3_axi_awprot  = m_axi_awprot[11:9];
    assign m4_axi_awprot  = m_axi_awprot[14:12];
    
    assign m0_axi_awvalid = m_axi_awvalid[0];
    assign m1_axi_awvalid = m_axi_awvalid[1];
    assign m2_axi_awvalid = m_axi_awvalid[2];
    assign m3_axi_awvalid = m_axi_awvalid[3];
    assign m4_axi_awvalid = m_axi_awvalid[4];
    
    assign m0_axi_wdata   = m_axi_wdata[31:0];
    assign m1_axi_wdata   = m_axi_wdata[63:32];
    assign m2_axi_wdata   = m_axi_wdata[95:64];
    assign m3_axi_wdata   = m_axi_wdata[127:96];
    assign m4_axi_wdata   = m_axi_wdata[159:128];
    
    assign m0_axi_wstrb   = m_axi_wstrb[3:0];
    assign m1_axi_wstrb   = m_axi_wstrb[7:4];
    assign m2_axi_wstrb   = m_axi_wstrb[11:8];
    assign m3_axi_wstrb   = m_axi_wstrb[15:12];
    assign m4_axi_wstrb   = m_axi_wstrb[19:16];
    
    assign m0_axi_wvalid  = m_axi_wvalid[0];
    assign m1_axi_wvalid  = m_axi_wvalid[1];
    assign m2_axi_wvalid  = m_axi_wvalid[2];
    assign m3_axi_wvalid  = m_axi_wvalid[3];
    assign m4_axi_wvalid  = m_axi_wvalid[4];
    
    assign m0_axi_bready  = m_axi_bready[0];
    assign m1_axi_bready  = m_axi_bready[1];
    assign m2_axi_bready  = m_axi_bready[2];
    assign m3_axi_bready  = m_axi_bready[3];
    assign m4_axi_bready  = m_axi_bready[4];
    
    assign m0_axi_araddr  = m_axi_araddr[31:0];
    assign m1_axi_araddr  = m_axi_araddr[63:32];
    assign m2_axi_araddr  = m_axi_araddr[95:64];
    assign m3_axi_araddr  = m_axi_araddr[127:96];
    assign m4_axi_araddr  = m_axi_araddr[159:128];
    
    assign m0_axi_arprot  = m_axi_arprot[2:0];
    assign m1_axi_arprot  = m_axi_arprot[5:3];
    assign m2_axi_arprot  = m_axi_arprot[8:6];
    assign m3_axi_arprot  = m_axi_arprot[11:9];
    assign m4_axi_arprot  = m_axi_arprot[14:12];
    
    assign m0_axi_arvalid = m_axi_arvalid[0];
    assign m1_axi_arvalid = m_axi_arvalid[1];
    assign m2_axi_arvalid = m_axi_arvalid[2];
    assign m3_axi_arvalid = m_axi_arvalid[3];
    assign m4_axi_arvalid = m_axi_arvalid[4];
    
    assign m0_axi_rready  = m_axi_rready[0];
    assign m1_axi_rready  = m_axi_rready[1];
    assign m2_axi_rready  = m_axi_rready[2];
    assign m3_axi_rready  = m_axi_rready[3];
    assign m4_axi_rready  = m_axi_rready[4];
    
    // ID Registers for MMIO Slaves (1, 2, 3, 4)
    // axi_crossbar defaults to S_ID_WIDTH=8, M_ID_WIDTH=10 (for 3 slaves, clog2(3)=2)
    wire [5*10-1:0] m_axi_awid_out;
    wire [5*10-1:0] m_axi_arid_out;
    
    // Pass full 10 bits to m0
    assign m0_axi_awid = m_axi_awid_out[9:0]; 
    assign m0_axi_arid = m_axi_arid_out[9:0]; 
    
    // Register AWID on AWVALID & AWREADY
    reg [9:0] m1_awid_r, m2_awid_r, m3_awid_r, m4_awid_r;
    reg [9:0] m1_arid_r, m2_arid_r, m3_arid_r, m4_arid_r;
    
    always @(posedge clk) begin
        if (!rstn) begin
            m1_awid_r <= 0; m2_awid_r <= 0; m3_awid_r <= 0; m4_awid_r <= 0;
            m1_arid_r <= 0; m2_arid_r <= 0; m3_arid_r <= 0; m4_arid_r <= 0;
        end else begin
            if (m1_axi_awvalid && m1_axi_awready) m1_awid_r <= m_axi_awid_out[19:10];
            if (m2_axi_awvalid && m2_axi_awready) m2_awid_r <= m_axi_awid_out[29:20];
            if (m3_axi_awvalid && m3_axi_awready) m3_awid_r <= m_axi_awid_out[39:30];
            if (m4_axi_awvalid && m4_axi_awready) m4_awid_r <= m_axi_awid_out[49:40];
            
            if (m1_axi_arvalid && m1_axi_arready) m1_arid_r <= m_axi_arid_out[19:10];
            if (m2_axi_arvalid && m2_axi_arready) m2_arid_r <= m_axi_arid_out[29:20];
            if (m3_axi_arvalid && m3_axi_arready) m3_arid_r <= m_axi_arid_out[39:30];
            if (m4_axi_arvalid && m4_axi_arready) m4_arid_r <= m_axi_arid_out[49:40];
        end
    end

    // Instantiate AXI Crossbar
    // Since we are using AXI4-Lite effectively, we tie off burst, lock, cache, etc.
    axi_crossbar #(
        .S_COUNT(3),
        .M_COUNT(5),
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .M_BASE_ADDR({
            32'h8000_0000,      // M4: Testbench
            32'h4000_0000,      // M3: Attention Sequencer
            32'h3000_1000,      // M2: DMA West Config
            32'h3000_0000,      // M1: DMA North Config
            32'h0000_0000       // M0: L2 SRAM
        }),
        .M_ADDR_WIDTH({
            32'd12, // M4
            32'd16, // M3
            32'd12, // M2
            32'd12, // M1
            32'd16  // M0
        })
    ) axi_crossbar_inst (
        .clk(clk),
        .rst(~rstn), // AXI crossbar uses active high reset
        
        .s_axi_awid(24'd0),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(24'd0),
        .s_axi_awsize(9'd0),
        .s_axi_awburst(6'd0),
        .s_axi_awlock(3'd0),
        .s_axi_awcache(12'd0),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awqos(12'd0),
        .s_axi_awuser(3'd0),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(3'b111),
        .s_axi_wuser(3'd0),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_buser(),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        
        .s_axi_arid(24'd0),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(24'd0),
        .s_axi_arsize(9'd0),
        .s_axi_arburst(6'd0),
        .s_axi_arlock(3'd0),
        .s_axi_arcache(12'd0),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arqos(12'd0),
        .s_axi_aruser(3'd0),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid(),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(),
        .s_axi_ruser(),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        
        .m_axi_awid(m_axi_awid_out),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(),
        .m_axi_awsize(),
        .m_axi_awburst(),
        .m_axi_awlock(),
        .m_axi_awcache(),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(),
        .m_axi_awregion(),
        .m_axi_awuser(),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(),
        .m_axi_wuser(),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid({m4_awid_r, m3_awid_r, m2_awid_r, m1_awid_r, m0_axi_bid}),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_buser(5'd0),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        
        .m_axi_arid(m_axi_arid_out),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(),
        .m_axi_arsize(),
        .m_axi_arburst(),
        .m_axi_arlock(),
        .m_axi_arcache(),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arqos(),
        .m_axi_arregion(),
        .m_axi_aruser(),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid({m4_arid_r, m3_arid_r, m2_arid_r, m1_arid_r, m0_axi_rid}),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(5'b11111),
        .m_axi_ruser(5'd0),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

endmodule
