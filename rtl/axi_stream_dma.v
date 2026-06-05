/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Simple AXI-Stream DMA
 * - AXI4-Lite Slave for MMIO Configuration
 * - AXI4 Master for Memory Reads
 * - AXI4-Stream Master for streaming data out
 */

`default_nettype none

module axi_stream_dma (
    input  wire clk,
    input  wire rstn,

    // AXI4-Lite Slave (Config)
    input  wire [31:0] s_axi_awaddr,
    input  wire [ 2:0] s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [ 3:0] s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output reg  [ 1:0] s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire [ 2:0] s_axi_arprot,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [ 1:0] s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // AXI4 Master (Read Only)
    output reg  [31:0] m_axi_araddr,
    output wire [ 7:0] m_axi_arlen,
    output wire [ 2:0] m_axi_arsize,
    output wire [ 1:0] m_axi_arburst,
    output wire [ 2:0] m_axi_arprot,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata,
    input  wire [ 1:0] m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    // AXI-Stream Master
    output reg  [31:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,
    
    output reg         irq
);

    assign m_axi_arlen   = 8'd0; // Single beats for simplicity
    assign m_axi_arsize  = 3'b010; // 4 bytes
    assign m_axi_arburst = 2'b01; // INCR
    assign m_axi_arprot  = 3'b000;

    reg [31:0] src_addr;
    reg [31:0] length;
    reg busy;
    reg done;

    // ----------------------------------------------------
    // AXI-Lite Slave (Config Registers)
    // 0x0: SRC_ADDR
    // 0x4: LENGTH
    // 0x8: STATUS/CTRL (bit 0 = start, bit 1 = busy, bit 2 = done)
    // ----------------------------------------------------
    reg [31:0] awaddr_reg;
    reg [31:0] wdata_reg;
    reg aw_done, w_done;
    
    assign s_axi_awready = !aw_done && !s_axi_bvalid;
    assign s_axi_wready  = !w_done && !s_axi_bvalid;

    always @(posedge clk) begin
        if (!rstn) begin
            s_axi_bvalid  <= 0;
            s_axi_arready <= 0;
            s_axi_rvalid  <= 0;
            src_addr      <= 0;
            length        <= 0;
            irq           <= 0;
            aw_done <= 0; w_done <= 0;
        end else begin
            // Write
            if (s_axi_awvalid && s_axi_awready) begin awaddr_reg <= s_axi_awaddr; aw_done <= 1; end
            if (s_axi_wvalid && s_axi_wready) begin wdata_reg <= s_axi_wdata; w_done <= 1; end
            
            if ((aw_done || (s_axi_awvalid && s_axi_awready)) && 
                (w_done || (s_axi_wvalid && s_axi_wready)) && !s_axi_bvalid) begin
                
                s_axi_bvalid <= 1;
                s_axi_bresp  <= 0;
                aw_done <= 0; w_done <= 0;
                
                if ((aw_done ? awaddr_reg[7:0] : s_axi_awaddr[7:0]) == 8'h0) src_addr <= (w_done ? wdata_reg : s_axi_wdata);
                if ((aw_done ? awaddr_reg[7:0] : s_axi_awaddr[7:0]) == 8'h4) length   <= (w_done ? wdata_reg : s_axi_wdata);
            end
            
            if (s_axi_bready && s_axi_bvalid) s_axi_bvalid <= 0;
            
            // Read
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1;
                s_axi_rvalid  <= 1;
                s_axi_rresp   <= 0;
                if (s_axi_araddr[7:0] == 8'h0) s_axi_rdata <= src_addr;
                if (s_axi_araddr[7:0] == 8'h4) s_axi_rdata <= length;
                if (s_axi_araddr[7:0] == 8'h8) s_axi_rdata <= {29'd0, done, busy, 1'b0};
            end else begin
                s_axi_arready <= 0;
            end
            
            if (s_axi_rready && s_axi_rvalid) s_axi_rvalid <= 0;
        end
    end

    // ----------------------------------------------------
    // DMA Engine (Read from AXI, Write to AXI-Stream)
    // ----------------------------------------------------
    wire start_pulse = ((aw_done || (s_axi_awvalid && s_axi_awready)) && (w_done || (s_axi_wvalid && s_axi_wready)) && !s_axi_bvalid) &&
                       ((aw_done ? awaddr_reg[7:0] : s_axi_awaddr[7:0]) == 8'h8) && ((w_done ? wdata_reg : s_axi_wdata) & 1);
    wire clear_pulse = ((aw_done || (s_axi_awvalid && s_axi_awready)) && (w_done || (s_axi_wvalid && s_axi_wready)) && !s_axi_bvalid) &&
                       ((aw_done ? awaddr_reg[7:0] : s_axi_awaddr[7:0]) == 8'h8) && ((w_done ? wdata_reg : s_axi_wdata) & 2);

    localparam S_IDLE  = 0;
    localparam S_AR    = 1;
    localparam S_R     = 2;
    localparam S_STREAM= 3;
    
    reg [2:0] state;
    reg [31:0] current_addr;
    reg [31:0] words_left;
    reg [31:0] rdata_buf;

    assign m_axi_rready = (state == S_R);

    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_IDLE;
            busy  <= 0;
            done  <= 0;
            m_axi_arvalid <= 0;
            m_axis_tvalid <= 0;
        end else begin
            if (clear_pulse) done <= 0;
            
            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        current_addr <= src_addr;
                        words_left   <= length;
                        busy <= 1;
                        done <= 0;
                        if (length > 0) state <= S_AR;
                        else begin
                            busy <= 0;
                            done <= 1;
                        end
                    end
                end
                
                S_AR: begin
                    m_axi_araddr <= current_addr;
                    m_axi_arvalid <= 1;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 0;
                        state <= S_R;
                    end
                end
                
                S_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rdata_buf <= m_axi_rdata;
                        state <= S_STREAM;
                    end
                end
                
                S_STREAM: begin
                    m_axis_tdata <= rdata_buf;
                    m_axis_tlast <= (words_left == 1);
                    m_axis_tvalid <= 1;
                    
                    if (m_axis_tvalid && m_axis_tready) begin
                        m_axis_tvalid <= 0;
                        current_addr <= current_addr + 4;
                        words_left <= words_left - 1;
                        if (words_left == 1) begin
                            state <= S_IDLE;
                            busy <= 0;
                            done <= 1;
                        end else begin
                            state <= S_AR;
                        end
                    end
                end
            endcase
        end
    end

endmodule
