/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Simple Memory-to-Memory DMA Controller
 * Uses the native PicoRV32 memory interface.
 */

`default_nettype none

module soc_dma (
    input  wire        clk,
    input  wire        rst,
    
    // Slave Interface (Configuration from CPU)
    input  wire        s_mem_valid,
    output reg         s_mem_ready,
    input  wire [31:0] s_mem_addr,
    input  wire [31:0] s_mem_wdata,
    input  wire [ 3:0] s_mem_wstrb,
    output reg  [31:0] s_mem_rdata,
    
    // Master Interface (To Interconnect)
    output reg         m_mem_valid,
    input  wire        m_mem_ready,
    output reg  [31:0] m_mem_addr,
    output reg  [31:0] m_mem_wdata,
    output reg  [ 3:0] m_mem_wstrb,
    input  wire [31:0] m_mem_rdata,
    
    // Interrupt to CPU
    output wire        irq
);

    // Memory Mapped Registers
    reg [31:0] src_addr;
    reg [31:0] dst_addr;
    reg [31:0] xfer_len;
    reg        busy;
    reg        done;

    assign irq = done;

    // DMA FSM States
    localparam STATE_IDLE      = 3'd0;
    localparam STATE_READ_REQ  = 3'd1;
    localparam STATE_READ_ACK  = 3'd2;
    localparam STATE_WRITE_REQ = 3'd3;
    localparam STATE_WRITE_ACK = 3'd4;

    reg [2:0]  state;
    reg [31:0] current_src;
    reg [31:0] current_dst;
    reg [31:0] words_left;
    reg [31:0] temp_data;

    // ----------------------------------------------------
    // Slave Interface (MMIO)
    // ----------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            s_mem_ready <= 1'b0;
            s_mem_rdata <= 32'b0;
            src_addr    <= 32'b0;
            dst_addr    <= 32'b0;
            xfer_len    <= 32'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            state       <= STATE_IDLE;
            m_mem_valid <= 1'b0;
        end else begin
            // Default pulse responses
            s_mem_ready <= 1'b0;
            
            // Handle MMIO Configuration
            if (s_mem_valid && !s_mem_ready) begin
                s_mem_ready <= 1'b1;
                if (|s_mem_wstrb) begin
                    // Write
                    if (s_mem_addr[7:0] == 8'h00) src_addr <= s_mem_wdata;
                    if (s_mem_addr[7:0] == 8'h04) dst_addr <= s_mem_wdata;
                    if (s_mem_addr[7:0] == 8'h08) xfer_len <= s_mem_wdata;
                    if (s_mem_addr[7:0] == 8'h0C) begin
                        if (s_mem_wdata[0] && !busy) begin
                            busy <= 1'b1;
                            done <= 1'b0;
                        end
                        if (s_mem_wdata[1]) done <= 1'b0; // Clear IRQ
                    end
                end else begin
                    // Read
                    if (s_mem_addr[7:0] == 8'h00) s_mem_rdata <= src_addr;
                    if (s_mem_addr[7:0] == 8'h04) s_mem_rdata <= dst_addr;
                    if (s_mem_addr[7:0] == 8'h08) s_mem_rdata <= xfer_len;
                    if (s_mem_addr[7:0] == 8'h0C) s_mem_rdata <= {30'b0, done, busy};
                end
            end

            // ----------------------------------------------------
            // DMA Master FSM
            // ----------------------------------------------------
            case (state)
                STATE_IDLE: begin
                    if (busy) begin
                        current_src <= src_addr;
                        current_dst <= dst_addr;
                        words_left  <= xfer_len;
                        if (xfer_len > 0) begin
                            state <= STATE_READ_REQ;
                        end else begin
                            busy <= 1'b0;
                            done <= 1'b1;
                        end
                    end
                end

                STATE_READ_REQ: begin
                    m_mem_valid <= 1'b1;
                    m_mem_wstrb <= 4'b0000;
                    m_mem_addr  <= current_src;
                    if (m_mem_valid && m_mem_ready) begin
                        m_mem_valid <= 1'b0;
                        temp_data   <= m_mem_rdata;
                        state       <= STATE_WRITE_REQ;
                    end
                end

                STATE_WRITE_REQ: begin
                    m_mem_valid <= 1'b1;
                    m_mem_wstrb <= 4'b1111;
                    m_mem_addr  <= current_dst;
                    m_mem_wdata <= temp_data;
                    if (m_mem_valid && m_mem_ready) begin
                        m_mem_valid <= 1'b0;
                        current_src <= current_src + 4;
                        current_dst <= current_dst + 4;
                        words_left  <= words_left - 1;
                        if (words_left == 1) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            state <= STATE_IDLE;
                        end else begin
                            state <= STATE_READ_REQ;
                        end
                    end
                end
            endcase
        end
    end
endmodule
