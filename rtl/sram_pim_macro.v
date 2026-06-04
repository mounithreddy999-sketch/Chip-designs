/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * Near-Memory MVM Macro -- output-stationary, weight-streaming.
 *
 * Computes out[c] = sum_r ( act[r] * W[r][c] ) with the weight matrix RESIDENT
 * in an OpenRAM SRAM (sky130_sram_1kbyte_1rw1r_32x256_8) instead of a flop array.
 *
 * Why this is the near-memory design (vs pim_matmul_macro, the flop baseline):
 *   - No N*N weight register file and no N*N multiplier array.
 *   - Weights stream out of dense 6T SRAM, WEIGHTS_PER_WORD at a time, into a
 *     small lane of multipliers; products accumulate into N output registers.
 *   - Throughput is TOTAL_WORDS cycles/MVM (1 word/cycle) but energy/MAC drops
 *     sharply: the dominant flop + clock-tree power of the baseline is gone.
 *
 * Memory layout: word address = row*WORDS_PER_ROW + k holds columns [4k..4k+3]
 * of that row, byte-lane j -> column (4k + j).
 *
 * SRAM read latency is 1 cycle; the issued word index is pipelined so the
 * returning data accumulates into the correct output column group.
 */

`default_nettype none

module sram_pim_macro #(
    parameter N          = 16,   // array dimension (NxN); must be a multiple of WEIGHTS_PER_WORD
    parameter ACT_WIDTH  = 8,
    parameter W_WIDTH    = 8,
    parameter OUT_WIDTH  = 24,
    parameter ADDR_WIDTH = 8     // SRAM address width (256 words)
) (
    input  wire                          clk,
    input  wire                          rst,

    input  wire                          start,         // pulse: latch act + run one MVM
    input  wire signed [N*ACT_WIDTH-1:0] act_vector_in,

    // Weight programming (32-bit words straight into SRAM port 0)
    input  wire                          we,
    input  wire [ADDR_WIDTH-1:0]         w_word_addr,
    input  wire [31:0]                   w_word_data,

    output reg  signed [N*OUT_WIDTH-1:0] out_vector,
    output reg                           out_valid
);

    localparam integer WEIGHTS_PER_WORD = 32 / W_WIDTH;        // 4
    localparam integer WORDS_PER_ROW    = N / WEIGHTS_PER_WORD; // 4
    localparam integer TOTAL_WORDS      = N * WORDS_PER_ROW;    // 64
    localparam integer KW               = (WORDS_PER_ROW <= 1) ? 1 : $clog2(WORDS_PER_ROW);

    // ---- FSM ----
    localparam [1:0] S_IDLE = 2'd0, S_STREAM = 2'd1, S_DONE = 2'd2;
    reg [1:0] state;

    // ---- Activation register (latched at start) ----
    reg signed [ACT_WIDTH-1:0] act_reg [0:N-1];

    // ---- Output accumulators ----
    reg signed [OUT_WIDTH-1:0] acc [0:N-1];

    // ---- Read issue / capture pipeline (1-cycle SRAM latency) ----
    reg [ADDR_WIDTH-1:0] issue_cnt;
    reg                  cap_en;     // a read was issued last cycle
    reg [ADDR_WIDTH-1:0] cap_idx;    // word index of that read

    wire issuing = (state == S_STREAM) && (issue_cnt < TOTAL_WORDS[ADDR_WIDTH-1:0]);

    // ---- SRAM port 1 (read) drive ----
    wire [ADDR_WIDTH-1:0] addr1 = issue_cnt;
    wire                  csb1  = ~issuing;          // active low
    wire [31:0]           dout1;

    // ---- SRAM port 0 (program) drive ----
    wire        csb0   = ~we;                        // select only when writing
    wire        web0   = 1'b0;                       // write when selected
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

    // Decode the captured word index into row r and column-group k.
    wire [ADDR_WIDTH-1:0] cap_row = cap_idx >> KW;           // r = idx / WORDS_PER_ROW
    wire [KW-1:0]         cap_k   = cap_idx[KW-1:0];          // k = idx % WORDS_PER_ROW
    wire signed [ACT_WIDTH-1:0] cap_act = act_reg[cap_row];

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            out_valid <= 1'b0;
            issue_cnt <= {ADDR_WIDTH{1'b0}};
            cap_en    <= 1'b0;
            cap_idx   <= {ADDR_WIDTH{1'b0}};
            out_vector <= {(N*OUT_WIDTH){1'b0}};
            for (i = 0; i < N; i = i + 1) acc[i] <= {OUT_WIDTH{1'b0}};
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        for (i = 0; i < N; i = i + 1) begin
                            act_reg[i] <= act_vector_in[i*ACT_WIDTH +: ACT_WIDTH];
                            acc[i]     <= {OUT_WIDTH{1'b0}};
                        end
                        issue_cnt <= {ADDR_WIDTH{1'b0}};
                        cap_en    <= 1'b0;
                        out_valid <= 1'b0;
                        state     <= S_STREAM;
                    end
                end

                S_STREAM: begin
                    // Issue side: advance the read address.
                    cap_en  <= issuing;
                    cap_idx <= issue_cnt;
                    if (issuing)
                        issue_cnt <= issue_cnt + 1'b1;

                    // Capture side: accumulate the word that returned this cycle.
                    // Column base of word k is k*WEIGHTS_PER_WORD; byte lane i -> column base+i.
                    if (cap_en) begin
                        for (i = 0; i < WEIGHTS_PER_WORD; i = i + 1)
                            acc[cap_k * WEIGHTS_PER_WORD + i] <=
                                acc[cap_k * WEIGHTS_PER_WORD + i]
                                + cap_act * $signed(dout1[i*W_WIDTH +: W_WIDTH]);
                    end

                    // Done when nothing left to issue and the last word is captured.
                    if (!issuing && !cap_en)
                        state <= S_DONE;
                end

                S_DONE: begin
                    for (i = 0; i < N; i = i + 1)
                        out_vector[i*OUT_WIDTH +: OUT_WIDTH] <= acc[i];
                    out_valid <= 1'b1;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
