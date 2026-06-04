/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * NxN Compute-in-Memory (PIM) Matmul Macro  -- pipelined digital baseline.
 *
 * Computes a vector-matrix product:  out[c] = sum_r ( act[r] * W[r][c] ).
 *
 * Architecture (2-stage pipeline, LATENCY = 2):
 *   - Weights are stationary in an N x N standard-cell register file.
 *   - Stage 1: N*N signed products are computed and registered.
 *   - Stage 2: each column is reduced by a balanced (log2 depth) adder tree
 *              and registered to the output.
 *   - in_valid -> out_valid handshake tracks data through the pipeline.
 *
 * This is the *digital* PPA baseline against which a true in-/near-memory
 * (SRAM-resident weight) macro is to be compared. Storing weights in flops
 * and using explicit multipliers is intentionally the worst-case reference.
 *
 * Requirement: OUT_WIDTH >= ACT_WIDTH + W_WIDTH + clog2(N) to avoid truncation.
 */

`default_nettype none

module pim_matmul_macro #(
    parameter N          = 16,   // Array dimension (NxN)
    parameter ACT_WIDTH  = 8,    // Activation precision (signed)
    parameter W_WIDTH    = 8,    // Weight precision (signed)
    parameter OUT_WIDTH  = 24,   // Output accumulation precision (signed)
    parameter CG_WEIGHTS = 0     // 1 = clock-gate the stationary weight register file
) (
    input  wire                          clk,
    input  wire                          rst,
    input  wire                          en,            // Pipeline advance enable
    input  wire                          in_valid,      // act_vector_in is a valid beat

    // Weight Programming Interface
    input  wire [$clog2(N)-1:0]          w_addr_row,
    input  wire [$clog2(N)-1:0]          w_addr_col,
    input  wire                          w_write_en,
    input  wire signed [W_WIDTH-1:0]     w_data_in,

    // Input Activations (one element per row)
    input  wire signed [N*ACT_WIDTH-1:0] act_vector_in,

    // Column outputs (sum of products) + valid strobe
    output reg  signed [N*OUT_WIDTH-1:0] out_vector,
    output wire                          out_valid
);

    localparam integer PW      = ACT_WIDTH + W_WIDTH;        // product width
    localparam integer CLOG2N  = (N <= 1) ? 1 : $clog2(N);
    localparam integer SUM_W   = PW + CLOG2N;               // column-sum width
    localparam integer LATENCY = 2;

    // ----------------------------------------------------
    // Weight register file (N x N)
    //
    // Weights are stationary: they change only during programming (w_write_en)
    // or reset. With CG_WEIGHTS=1, the clock to this register file is gated off
    // during inference, removing the dominant clock-tree/flop switching power of
    // holding N*N stationary bits (the baseline clocks them every cycle for free
    // weights that never change).
    // ----------------------------------------------------
    reg signed [W_WIDTH-1:0] r_weights [0:N-1][0:N-1];

    wire wclk;
    generate
        if (CG_WEIGHTS) begin : g_wclk_gated
            // Pass the clock only when loading weights or resetting.
            clock_gate u_wcg (.clk(clk), .enable(w_write_en | rst), .gclk(wclk));
        end else begin : g_wclk_free
            assign wclk = clk;
        end
    endgenerate

    integer wr_i, wr_j;
    always @(posedge wclk) begin
        if (rst) begin
            for (wr_i = 0; wr_i < N; wr_i = wr_i + 1)
                for (wr_j = 0; wr_j < N; wr_j = wr_j + 1)
                    r_weights[wr_i][wr_j] <= {W_WIDTH{1'b0}};
        end else if (w_write_en) begin
            r_weights[w_addr_row][w_addr_col] <= w_data_in;
        end
    end

    // ----------------------------------------------------
    // Stage 1: combinational products, then register them
    // ----------------------------------------------------
    wire signed [PW-1:0] products [0:N-1][0:N-1];
    reg  signed [PW-1:0] r_products [0:N-1][0:N-1];

    genvar gr, gc;
    generate
        for (gr = 0; gr < N; gr = gr + 1) begin : row_gen
            // Operand Gating: Force activation to 0 to prevent multipliers from toggling when idle
            wire signed [ACT_WIDTH-1:0] act_r = (in_valid && en) ? act_vector_in[gr*ACT_WIDTH +: ACT_WIDTH] : {ACT_WIDTH{1'b0}};
            for (gc = 0; gc < N; gc = gc + 1) begin : col_gen
                assign products[gr][gc] = act_r * r_weights[gr][gc];
            end
        end
    endgenerate

    integer pr_i, pr_j;
    always @(posedge clk) begin
        if (rst) begin
            for (pr_i = 0; pr_i < N; pr_i = pr_i + 1)
                for (pr_j = 0; pr_j < N; pr_j = pr_j + 1)
                    r_products[pr_i][pr_j] <= {PW{1'b0}};
        end else if (en) begin
            for (pr_i = 0; pr_i < N; pr_i = pr_i + 1)
                for (pr_j = 0; pr_j < N; pr_j = pr_j + 1)
                    r_products[pr_i][pr_j] <= products[pr_i][pr_j];
        end
    end

    // ----------------------------------------------------
    // Stage 2: balanced adder tree per column, then register output
    // ----------------------------------------------------
    wire signed [SUM_W-1:0] col_sum [0:N-1];

    genvar tc, tr;
    generate
        for (tc = 0; tc < N; tc = tc + 1) begin : tree_gen
            wire signed [N*PW-1:0] col_in;
            for (tr = 0; tr < N; tr = tr + 1) begin : pack_gen
                assign col_in[tr*PW +: PW] = r_products[tr][tc];
            end
            pim_adder_tree #(
                .IN_W(PW), .NIN(N)
            ) u_tree (
                .in_flat(col_in),
                .sum(col_sum[tc])
            );
        end
    endgenerate

    integer oc;
    always @(posedge clk) begin
        if (rst) begin
            out_vector <= {(N*OUT_WIDTH){1'b0}};
        end else if (en) begin
            for (oc = 0; oc < N; oc = oc + 1)
                // SUM_W <= OUT_WIDTH by requirement; signed assignment sign-extends.
                out_vector[oc*OUT_WIDTH +: OUT_WIDTH] <= col_sum[oc];
        end
    end

    // ----------------------------------------------------
    // Valid pipeline: in_valid -> out_valid after LATENCY cycles.
    // out_valid is a combinational tap of the shift register so its
    // latency matches the 2-stage data path exactly (no extra flop).
    // ----------------------------------------------------
    reg [LATENCY-1:0] valid_sr;
    always @(posedge clk) begin
        if (rst)
            valid_sr <= {LATENCY{1'b0}};
        else if (en)
            valid_sr <= {valid_sr[LATENCY-2:0], in_valid};
    end

    assign out_valid = valid_sr[LATENCY-1];

endmodule


// ========================================================
// Balanced (log2-depth) signed adder-reduction tree.
// Pads NIN up to a power of two with zeros; every node is
// widened to OUT_W = IN_W + clog2(NIN) so no level overflows.
// ========================================================
module pim_adder_tree #(
    parameter IN_W = 16,
    parameter NIN  = 16
) (
    input  wire signed [NIN*IN_W-1:0]                                in_flat,
    output wire signed [IN_W + ((NIN<=1) ? 0 : $clog2(NIN)) - 1 : 0] sum
);
    localparam integer LEVELS = (NIN <= 1) ? 0 : $clog2(NIN);
    localparam integer OUT_W  = IN_W + LEVELS;
    localparam integer NP2    = (1 << LEVELS);   // padded power-of-two leaf count

    wire signed [OUT_W-1:0] node [0:LEVELS][0:NP2-1];

    genvar i, l;
    generate
        // Level 0: sign-extend real leaves, pad the rest with zero.
        for (i = 0; i < NP2; i = i + 1) begin : leaf_gen
            if (i < NIN)
                assign node[0][i] = $signed(in_flat[i*IN_W +: IN_W]);
            else
                assign node[0][i] = {OUT_W{1'b0}};
        end
        // Reduction levels: pairwise signed add.
        for (l = 0; l < LEVELS; l = l + 1) begin : level_gen
            for (i = 0; i < (NP2 >> (l+1)); i = i + 1) begin : add_gen
                assign node[l+1][i] = node[l][2*i] + node[l][2*i+1];
            end
        end
    endgenerate

    assign sum = node[LEVELS][0];

endmodule

`default_nettype wire
