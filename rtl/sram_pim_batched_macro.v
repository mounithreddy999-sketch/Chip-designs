/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * Near-Memory MVM Macro -- BATCHED weight reuse (single OpenRAM SRAM).
 *
 * Computes, for a batch of B activation vectors:
 *     out[b][c] = sum_r ( A[b][r] * W[r][c] )      b in [0,B), c in [0,N)
 *
 * Mid-frontier design: keeps the energy-killing fix of the 4-wide streaming
 * macro (sram_pim_macro) -- weights resident in ONE 32-bit SRAM (area win
 * preserved, 0.602 mm^2) -- but each 4-weight read is REUSED across all B
 * vectors of the batch. So one SRAM read feeds 4*B MACs instead of 4, and the
 * SRAM-read + control overhead (which dominated the 4-wide's 19 pJ/MAC)
 * amortizes over the batch. Throughput rises to 4*B MAC/cycle with one macro --
 * banking's throughput without banking's 4x area.
 *
 * Weight layout in SRAM is identical to sram_pim_macro: word address
 * = row*WORDS_PER_ROW + k holds columns [4k..4k+3] of that row.
 */

`default_nettype none

module sram_pim_batched_macro #(
    parameter N          = 16,   // array dimension (NxN)
    parameter B          = 4,    // batch size (vectors reusing each weight load)
    parameter ACT_WIDTH  = 8,
    parameter W_WIDTH    = 8,
    parameter OUT_WIDTH  = 24,
    parameter ADDR_WIDTH = 8
) (
    input  wire                            clk,
    input  wire                            rst,
    input  wire                            start,         // pulse: latch batch + run
    input  wire signed [B*N*ACT_WIDTH-1:0] act_vector_in, // B vectors, row-major

    // Weight programming (32-bit words into SRAM port 0)
    input  wire                            we,
    input  wire [ADDR_WIDTH-1:0]           w_word_addr,
    input  wire [31:0]                     w_word_data,

    output reg  signed [B*N*OUT_WIDTH-1:0] out_vector,
    output reg                             out_valid
);

    localparam integer WEIGHTS_PER_WORD = 32 / W_WIDTH;        // 4
    localparam integer WORDS_PER_ROW    = N / WEIGHTS_PER_WORD; // 4
    localparam integer TOTAL_WORDS      = N * WORDS_PER_ROW;    // 64
    localparam integer KW               = (WORDS_PER_ROW <= 1) ? 1 : $clog2(WORDS_PER_ROW);

    localparam [1:0] S_IDLE = 2'd0, S_STREAM = 2'd1, S_DONE = 2'd2;
    reg [1:0] state;

    reg signed [ACT_WIDTH-1:0] act_reg [0:B-1][0:N-1];  // batch of activation vectors
    reg signed [OUT_WIDTH-1:0] acc     [0:B-1][0:N-1];  // B*N output accumulators

    reg [ADDR_WIDTH-1:0] issue_cnt;
    reg                  cap_en;
    reg [ADDR_WIDTH-1:0] cap_idx;

    wire issuing = (state == S_STREAM) && (issue_cnt < TOTAL_WORDS[ADDR_WIDTH-1:0]);

    // SRAM read port (port 1)
    wire [ADDR_WIDTH-1:0] addr1 = issue_cnt;
    wire                  csb1  = ~issuing;
    wire [31:0]           dout1;

    // SRAM program port (port 0)
    wire        csb0   = ~we;
    wire        web0   = 1'b0;
    wire [3:0]  wmask0 = 4'hF;
    wire [31:0] dout0_unused;

    sky130_sram_1kbyte_1rw1r_32x256_8 u_sram (
        .clk0   (clk),
        .csb0   (csb0),
        .web0   (web0),
        .wmask0 (wmask0),
        .addr0  (w_word_addr),
        .din0   (w_word_data),
        .dout0  (dout0_unused),
        .clk1   (clk),
        .csb1   (csb1),
        .addr1  (addr1),
        .dout1  (dout1)
    );

    wire [ADDR_WIDTH-1:0] cap_row = cap_idx >> KW;       // r = idx / WORDS_PER_ROW
    wire [KW-1:0]         cap_k   = cap_idx[KW-1:0];      // k = idx % WORDS_PER_ROW

    integer i, b, j;
    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            out_valid  <= 1'b0;
            issue_cnt  <= {ADDR_WIDTH{1'b0}};
            cap_en     <= 1'b0;
            cap_idx    <= {ADDR_WIDTH{1'b0}};
            out_vector <= {(B*N*OUT_WIDTH){1'b0}};
            for (b = 0; b < B; b = b + 1)
                for (i = 0; i < N; i = i + 1)
                    acc[b][i] <= {OUT_WIDTH{1'b0}};
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        for (b = 0; b < B; b = b + 1)
                            for (i = 0; i < N; i = i + 1) begin
                                act_reg[b][i] <= act_vector_in[(b*N + i)*ACT_WIDTH +: ACT_WIDTH];
                                acc[b][i]     <= {OUT_WIDTH{1'b0}};
                            end
                        issue_cnt <= {ADDR_WIDTH{1'b0}};
                        cap_en    <= 1'b0;
                        out_valid <= 1'b0;
                        state     <= S_STREAM;
                    end
                end

                S_STREAM: begin
                    cap_en  <= issuing;
                    cap_idx <= issue_cnt;
                    if (issuing)
                        issue_cnt <= issue_cnt + 1'b1;

                    // One word read -> 4*B MACs (4 columns x B batch vectors).
                    if (cap_en) begin
                        for (b = 0; b < B; b = b + 1)
                            for (j = 0; j < WEIGHTS_PER_WORD; j = j + 1)
                                acc[b][cap_k * WEIGHTS_PER_WORD + j] <=
                                    acc[b][cap_k * WEIGHTS_PER_WORD + j]
                                    + act_reg[b][cap_row] * $signed(dout1[j*W_WIDTH +: W_WIDTH]);
                    end

                    if (!issuing && !cap_en)
                        state <= S_DONE;
                end

                S_DONE: begin
                    for (b = 0; b < B; b = b + 1)
                        for (i = 0; i < N; i = i + 1)
                            out_vector[(b*N + i)*OUT_WIDTH +: OUT_WIDTH] <= acc[b][i];
                    out_valid <= 1'b1;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
