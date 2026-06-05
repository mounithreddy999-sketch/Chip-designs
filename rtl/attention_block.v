/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Unified Attention Sequencer (Hybrid PIM Coprocessor)
 * Wraps two PIM macros (PIM_K and PIM_V) and a Softmax unit to autonomously compute Attention.
 * Interfaces: AXI4-Lite (Config/Weights), AXI-Stream (Q Data In), AXI-Stream (Result Data Out)
 */

`default_nettype none

module attention_block #(
    parameter N = 4,
    parameter ACT_W = 8,
    parameter W_W = 8,
    parameter OUT_W = 24
) (
    input  wire clk,
    input  wire rstn,

    // AXI4-Lite Config Slave
    input  wire [31:0] s_axi_awaddr,  input  wire [ 2:0] s_axi_awprot,  input  wire        s_axi_awvalid, output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,   input  wire [ 3:0] s_axi_wstrb,   input  wire        s_axi_wvalid,  output wire        s_axi_wready,
    output reg  [ 1:0] s_axi_bresp,   output reg         s_axi_bvalid,  input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,  input  wire [ 2:0] s_axi_arprot,  input  wire        s_axi_arvalid, output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,   output reg  [ 1:0] s_axi_rresp,   output reg         s_axi_rvalid,  input  wire        s_axi_rready,

    // AXI-Stream Input (Data In - Q Vectors)
    input  wire [31:0] s_axis_n_tdata, input  wire s_axis_n_tvalid, output wire s_axis_n_tready,
    
    // AXI-Stream Output (Attention Result)
    output reg  [31:0] m_axis_out_tdata, output reg m_axis_out_tvalid, input wire m_axis_out_tready
);

    // ----------------------------------------------------
    // Memory-Mapped IO & Configuration (AXI4-Lite)
    // ----------------------------------------------------
    reg aw_done, w_done;
    reg [31:0] awaddr_reg;
    reg [31:0] wdata_reg;
    
    assign s_axi_awready = !aw_done && !s_axi_bvalid;
    assign s_axi_wready  = !w_done && !s_axi_bvalid;

    // PIM programming interface
    reg        pim_k_wen;
    reg [1:0]  pim_k_row, pim_k_col;
    reg [7:0]  pim_k_wdata;

    reg        pim_v_wen;
    reg [1:0]  pim_v_row, pim_v_col;
    reg [7:0]  pim_v_wdata;

    // FSM Control
    reg        start_pipeline;
    reg        busy;

    always @(posedge clk) begin
        if (!rstn) begin
            s_axi_bvalid <= 0;
            aw_done <= 0; w_done <= 0;
            pim_k_wen <= 0; pim_v_wen <= 0;
            start_pipeline <= 0;
        end else begin
            pim_k_wen <= 0; pim_v_wen <= 0; start_pipeline <= 0;
            
            if (s_axi_awvalid && s_axi_awready) begin awaddr_reg <= s_axi_awaddr; aw_done <= 1; end
            if (s_axi_wvalid && s_axi_wready) begin wdata_reg <= s_axi_wdata; w_done <= 1; end
            
            if ((aw_done || (s_axi_awvalid && s_axi_awready)) && 
                (w_done || (s_axi_wvalid && s_axi_wready)) && !s_axi_bvalid) begin
                
                s_axi_bvalid <= 1; s_axi_bresp <= 0;
                aw_done <= 0; w_done <= 0;
                
                // CSR 0x000: Control
                if (((aw_done ? awaddr_reg : s_axi_awaddr) & 32'h00000FFF) == 32'h000) begin
                    if ((w_done ? wdata_reg : s_axi_wdata) & 1) start_pipeline <= 1;
                end
                
                // 0x100 - 0x13C: Write to PIM_K weights
                if (((aw_done ? awaddr_reg : s_axi_awaddr) & 32'h00000F00) == 32'h100) begin
                    pim_k_wen <= 1;
                    pim_k_row <= (aw_done ? awaddr_reg[5:4] : s_axi_awaddr[5:4]);
                    pim_k_col <= (aw_done ? awaddr_reg[3:2] : s_axi_awaddr[3:2]);
                    pim_k_wdata <= (w_done ? wdata_reg[7:0] : s_axi_wdata[7:0]);
                end

                // 0x200 - 0x23C: Write to PIM_V weights
                if (((aw_done ? awaddr_reg : s_axi_awaddr) & 32'h00000F00) == 32'h200) begin
                    pim_v_wen <= 1;
                    pim_v_row <= (aw_done ? awaddr_reg[5:4] : s_axi_awaddr[5:4]);
                    pim_v_col <= (aw_done ? awaddr_reg[3:2] : s_axi_awaddr[3:2]);
                    pim_v_wdata <= (w_done ? wdata_reg[7:0] : s_axi_wdata[7:0]);
                end
            end
            
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            
            // Read logic
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1; s_axi_rvalid <= 1; s_axi_rresp <= 0;
                if (s_axi_araddr[11:0] == 12'h000) s_axi_rdata <= {31'd0, busy};
                else s_axi_rdata <= 32'h0;
            end else s_axi_arready <= 0;
            if (s_axi_rready && s_axi_rvalid) s_axi_rvalid <= 0;
        end
    end

    // ----------------------------------------------------
    // FSM for Q streaming
    // ----------------------------------------------------
    localparam STATE_IDLE = 0;
    localparam STATE_STREAM = 1;
    reg [1:0] state;
    reg [2:0] stream_count;

    assign s_axis_n_tready = (state == STATE_STREAM);

    wire [N*ACT_W-1:0] q_vec = s_axis_n_tdata; // 32 bits = 4 * 8 bits
    wire q_valid = (state == STATE_STREAM) && s_axis_n_tvalid;

    always @(posedge clk) begin
        if (!rstn) begin
            state <= STATE_IDLE;
            stream_count <= 0;
            busy <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (start_pipeline) begin
                        state <= STATE_STREAM;
                        stream_count <= 0;
                        busy <= 1;
                    end
                end
                STATE_STREAM: begin
                    if (s_axis_n_tvalid && s_axis_n_tready) begin
                        stream_count <= stream_count + 1;
                        if (stream_count == 3) begin
                            state <= STATE_IDLE;
                            busy <= 0;
                        end
                    end
                end
            endcase
        end
    end

    // ----------------------------------------------------
    // PIM_K (Q x K^T -> Scores)
    // ----------------------------------------------------
    wire [N*OUT_W-1:0] pim_k_out; // 4 * 24 = 96 bits
    wire               pim_k_valid;

    pim_matmul_macro #(
        .N(N), .ACT_WIDTH(ACT_W), .W_WIDTH(W_W), .OUT_WIDTH(OUT_W)
    ) pim_k (
        .clk(clk), .rst(~rstn), .en(1'b1),
        .w_addr_row(pim_k_row), .w_addr_col(pim_k_col), .w_write_en(pim_k_wen), .w_data_in(pim_k_wdata),
        .in_valid(q_valid), .act_vector_in(q_vec),
        .out_vector(pim_k_out), .out_valid(pim_k_valid)
    );

    // ----------------------------------------------------
    // Softmax Unit
    // ----------------------------------------------------
    // Softmax expects 16-bit Q4.12 per element. PIM_K outputs 24-bit.
    // Let's extract the middle 16 bits of each 24-bit output to feed Softmax.
    wire [N*16-1:0] sm_in_flat;
    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : sm_in_gen
            // Simple truncation to fit 16-bit Softmax input
            assign sm_in_flat[i*16 +: 16] = pim_k_out[i*24 + 4 +: 16]; 
        end
    endgenerate

    wire [N*16-1:0] sm_out_flat;
    wire            sm_valid;

    mx_softmax_unit #(
        .N(N)
    ) softmax (
        .clk(clk), .rst(~rstn), .en(1'b1), .start(pim_k_valid),
        .in_flat(sm_in_flat),
        .out_valid(sm_valid),
        .out_flat(sm_out_flat)
    );

    // ----------------------------------------------------
    // PIM_V (Attn x V -> Result)
    // ----------------------------------------------------
    // Softmax output is N*16-bit (Q1.15 unsigned). We truncate it to 8-bit to feed PIM_V.
    wire [N*ACT_W-1:0] pim_v_in;
    generate
        for (i = 0; i < N; i = i + 1) begin : pim_v_in_gen
            // Softmax output is unsigned Q1.15 (range 0 to ~1.0).
            // Grab the MSBs (bits 14:7) to form an 8-bit Q0.8 value.
            assign pim_v_in[i*8 +: 8] = sm_out_flat[i*16 + 7 +: 8];
        end
    endgenerate

    wire [N*OUT_W-1:0] pim_v_out; // 4 * 24 = 96 bits
    wire               pim_v_valid;

    pim_matmul_macro #(
        .N(N), .ACT_WIDTH(ACT_W), .W_WIDTH(W_W), .OUT_WIDTH(OUT_W)
    ) pim_v (
        .clk(clk), .rst(~rstn), .en(1'b1),
        .w_addr_row(pim_v_row), .w_addr_col(pim_v_col), .w_write_en(pim_v_wen), .w_data_in(pim_v_wdata),
        .in_valid(sm_valid), .act_vector_in(pim_v_in),
        .out_vector(pim_v_out), .out_valid(pim_v_valid)
    );

    // ----------------------------------------------------
    // Output Formatting (24-bit -> 8-bit/32-bit AXI Out)
    // ----------------------------------------------------
    // We will truncate the 24-bit accumulation back to 8 bits for the AXI stream.
    // 4 elements * 8 bits = 32-bit output.
    wire [31:0] final_out_vec;
    generate
        for (i = 0; i < N; i = i + 1) begin : final_out_gen
            assign final_out_vec[i*8 +: 8] = pim_v_out[i*24 + 4 +: 8]; // Example truncation
        end
    endgenerate

    always @(posedge clk) begin
        if (!rstn) begin
            m_axis_out_tvalid <= 0;
            m_axis_out_tdata <= 0;
        end else begin
            if (pim_v_valid) begin
                m_axis_out_tdata <= final_out_vec;
                m_axis_out_tvalid <= 1'b1;
            end else if (m_axis_out_tready) begin
                m_axis_out_tvalid <= 1'b0;
            end
        end
    end

endmodule
