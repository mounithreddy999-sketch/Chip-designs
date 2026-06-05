/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * PicoRV32 Native to AXI4-Lite Master Wrapper
 * Converts the PicoRV32 Valid/Ready native memory interface
 * into an industry-standard AXI4-Lite Master interface.
 */

`default_nettype none

module picorv32_axi_wrapper (
    input  wire        clk,
    input  wire        rstn,
    
    // PicoRV32 Native Interface (Master)
    input  wire        mem_valid,
    input  wire        mem_instr,
    output reg         mem_ready,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [ 3:0] mem_wstrb,
    output reg  [31:0] mem_rdata,

    // AXI4-Lite Master Interface
    // Write Address Channel (AW)
    output reg  [31:0] m_axi_awaddr,
    output reg  [ 2:0] m_axi_awprot,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    
    // Write Data Channel (W)
    output reg  [31:0] m_axi_wdata,
    output reg  [ 3:0] m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    
    // Write Response Channel (B)
    input  wire [ 1:0] m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
    
    // Read Address Channel (AR)
    output reg  [31:0] m_axi_araddr,
    output reg  [ 2:0] m_axi_arprot,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    
    // Read Data Channel (R)
    input  wire [31:0] m_axi_rdata,
    input  wire [ 1:0] m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready
);

    // State machine for AXI translation
    localparam STATE_IDLE  = 3'd0;
    localparam STATE_WADDR = 3'd1;
    localparam STATE_WDATA = 3'd2;
    localparam STATE_WRESP = 3'd3;
    localparam STATE_RADDR = 3'd4;
    localparam STATE_RDATA = 3'd5;

    reg [2:0] state;
    
    wire is_write = |mem_wstrb;

    always @(posedge clk) begin
        if (!rstn) begin
            state <= STATE_IDLE;
            mem_ready <= 1'b0;
            mem_rdata <= 32'b0;
            
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
        end else begin
            mem_ready <= 1'b0;
            
            case (state)
                STATE_IDLE: begin
                    if (mem_valid && !mem_ready) begin
                        if (is_write) begin
                            m_axi_awaddr  <= mem_addr;
                            m_axi_awprot  <= 3'b000;
                            m_axi_awvalid <= 1'b1;
                            
                            m_axi_wdata   <= mem_wdata;
                            m_axi_wstrb   <= mem_wstrb;
                            m_axi_wvalid  <= 1'b1;
                            
                            m_axi_bready  <= 1'b1;
                            
                            state <= STATE_WADDR;
                        end else begin
                            m_axi_araddr  <= mem_addr;
                            m_axi_arprot  <= mem_instr ? 3'b100 : 3'b000;
                            m_axi_arvalid <= 1'b1;
                            m_axi_rready  <= 1'b1;
                            
                            state <= STATE_RADDR;
                        end
                    end
                end
                
                STATE_WADDR: begin
                    if (m_axi_awready && m_axi_awvalid) m_axi_awvalid <= 1'b0;
                    if (m_axi_wready && m_axi_wvalid) m_axi_wvalid <= 1'b0;
                    
                    if ((!m_axi_awvalid || m_axi_awready) && (!m_axi_wvalid || m_axi_wready)) begin
                        state <= STATE_WRESP;
                    end
                end
                
                STATE_WRESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        mem_ready <= 1'b1;
                        state <= STATE_IDLE;
                    end
                end
                
                STATE_RADDR: begin
                    if (m_axi_arready && m_axi_arvalid) begin
                        m_axi_arvalid <= 1'b0;
                        state <= STATE_RDATA;
                    end
                end
                
                STATE_RDATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 1'b0;
                        mem_rdata <= m_axi_rdata;
                        mem_ready <= 1'b1;
                        state <= STATE_IDLE;
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
