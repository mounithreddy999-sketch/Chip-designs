/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * Self-checking testbench for pim_matmul_macro (pipelined digital PIM MVM macro).
 *
 * Contract under test:
 *   - Vector-matrix multiply: out[c] = sum_r ( act[r] * W[r][c] )   (a^T * W)
 *   - Fixed pipeline LATENCY from in_valid -> out_valid (LAT cycles)
 *   - out_valid strobes exactly when out_vector carries a real result
 *
 * Strategy: program a known weight matrix, then stream activation vectors
 * (directed + randomized, one per cycle) while a deterministic scoreboard
 * compares every beat against a golden reference computed in the testbench.
 *
 * Timing model: all stimulus + scoreboard updates happen on negedge in a
 * single sequential process (step task). Each step first CHECKS the DUT
 * outputs (settled from the prior posedge), then SHIFTS/loads the scoreboard
 * and drives the next input. This ordering is race-free and pins the latency.
 */

`timescale 1ns/1ps
`default_nettype none

module tb_pim_matmul_macro;

    // ---- Parameters (small for fast, hand-verifiable sims) ----
`ifdef TB_N
    localparam integer N   = `TB_N; // Array dimension, override via -D TB_N=32
`else
    localparam integer N   = 4;    // Array dimension (NxN)
`endif
    localparam integer AW  = 8;    // Activation width (signed)
    localparam integer WW  = 8;    // Weight width (signed)
    localparam integer OW  = 24;   // Output accumulation width (signed)
    localparam integer LAT = 2;    // Expected pipeline latency (in_valid -> out_valid)
    localparam integer AW_IDX = (N <= 1) ? 1 : $clog2(N);

    // ---- DUT I/O ----
    reg                      clk = 1'b0;
    reg                      rst = 1'b1;
    reg                      en  = 1'b0;
    reg                      in_valid = 1'b0;
    reg  [AW_IDX-1:0]        w_addr_row = {AW_IDX{1'b0}};
    reg  [AW_IDX-1:0]        w_addr_col = {AW_IDX{1'b0}};
    reg                      w_write_en = 1'b0;
    reg  signed [WW-1:0]     w_data_in  = {WW{1'b0}};
    reg  signed [N*AW-1:0]   act_vector_in = {(N*AW){1'b0}};
    wire signed [N*OW-1:0]   out_vector;
    wire                     out_valid;

    // ---- Golden state ----
    reg signed [WW-1:0] gW [0:N-1][0:N-1];   // mirror of programmed weights
    reg signed [AW-1:0] cur_act [0:N-1];     // activation vector being driven this step

    // ---- Scoreboard pipeline (mirrors DUT latency) ----
    reg signed [OW-1:0] exp_pipe [0:LAT-1][0:N-1];
    reg                 exp_vld  [0:LAT-1];

    integer errors = 0;
    integer checks = 0;

    // ---- DUT (compile with -D TB_CG to exercise the clock-gated weight path) ----
`ifdef TB_CG
    localparam CGW = 1;
`else
    localparam CGW = 0;
`endif
    pim_matmul_macro #(
        .N(N), .ACT_WIDTH(AW), .W_WIDTH(WW), .OUT_WIDTH(OW), .CG_WEIGHTS(CGW)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .in_valid(in_valid),
        .w_addr_row(w_addr_row),
        .w_addr_col(w_addr_col),
        .w_write_en(w_write_en),
        .w_data_in(w_data_in),
        .act_vector_in(act_vector_in),
        .out_vector(out_vector),
        .out_valid(out_valid)
    );

    // ---- Clock: 100 MHz ----
    always #5 clk = ~clk;

    integer k, r, c;

    // Compare DUT outputs against the tail of the scoreboard pipeline.
    task check_outputs;
        reg signed [OW-1:0] got, want;
        begin
            if (out_valid !== exp_vld[LAT-1]) begin
                $display("[%0t] FAIL: out_valid=%b expected=%b", $time, out_valid, exp_vld[LAT-1]);
                errors = errors + 1;
            end else if (out_valid === 1'b1) begin
                for (c = 0; c < N; c = c + 1) begin
                    got  = $signed(out_vector[c*OW +: OW]);
                    want = exp_pipe[LAT-1][c];
                    checks = checks + 1;
                    if (got !== want) begin
                        $display("[%0t] FAIL: out[%0d] got=%0d want=%0d", $time, c, got, want);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    // Shift scoreboard by one stage and load stage 0 from cur_act/gW.
    task scoreboard_advance;
        input is_valid;
        integer acc;
        begin
            for (k = LAT-1; k > 0; k = k - 1) begin
                exp_vld[k] = exp_vld[k-1];
                for (r = 0; r < N; r = r + 1)
                    exp_pipe[k][r] = exp_pipe[k-1][r];
            end
            exp_vld[0] = is_valid;
            for (c = 0; c < N; c = c + 1) begin
                acc = 0;
                for (r = 0; r < N; r = r + 1)
                    acc = acc + (cur_act[r] * gW[r][c]);
                exp_pipe[0][c] = acc;
            end
        end
    endtask

    // One streaming cycle: check settled outputs, then advance + drive next input.
    task step;
        input do_valid;
        begin
            @(negedge clk);
            check_outputs();
            scoreboard_advance(do_valid);
            if (do_valid) begin
                for (k = 0; k < N; k = k + 1)
                    act_vector_in[k*AW +: AW] = cur_act[k];
                in_valid = 1'b1;
            end else begin
                in_valid = 1'b0;
            end
        end
    endtask

    // Program one weight (DUT) and mirror into the golden model. en held low.
    task write_weight;
        input integer wr, wc;
        input signed [WW-1:0] val;
        begin
            @(negedge clk);
            w_write_en = 1'b1;
            w_addr_row = wr[AW_IDX-1:0];
            w_addr_col = wc[AW_IDX-1:0];
            w_data_in  = val;
            gW[wr][wc] = val;
            @(negedge clk);
            w_write_en = 1'b0;
        end
    endtask

    integer i, j;
    initial begin
        $dumpfile("tb_pim_matmul_macro.vcd");
        $dumpvars(0, tb_pim_matmul_macro);

        for (k = 0; k < LAT; k = k + 1) exp_vld[k] = 1'b0;

        // reset
        rst = 1'b1; en = 1'b0; in_valid = 1'b0;
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // ---------- Test 1: identity weights => out == act ----------
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                write_weight(i, j, (i == j) ? 8'sd1 : 8'sd0);
        en = 1'b1;
        cur_act[0] = 8'sd1; cur_act[1] = 8'sd2; cur_act[2] = 8'sd3; cur_act[3] = 8'sd4;
        step(1'b1);
        step(1'b0); step(1'b0); step(1'b0);          // drain + check

        // ---------- Test 2: all-ones weights, back-to-back vectors ----------
        en = 1'b0;
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                write_weight(i, j, 8'sd1);
        en = 1'b1;
        cur_act[0] = 8'sd1; cur_act[1] = 8'sd2; cur_act[2] = 8'sd3; cur_act[3] = 8'sd4;
        step(1'b1);                                   // expect every column = 10
        cur_act[0] = -8'sd5; cur_act[1] = 8'sd10; cur_act[2] = -8'sd1; cur_act[3] = 8'sd7;
        step(1'b1);                                   // expect every column = 11
        step(1'b0); step(1'b0); step(1'b0);

        // ---------- Test 3: randomized streaming ----------
        en = 1'b0;
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                write_weight(i, j, $random);
        en = 1'b1;
        for (i = 0; i < 200; i = i + 1) begin
            for (j = 0; j < N; j = j + 1)
                cur_act[j] = $random;
            step(1'b1);                               // 1 vector/cycle
        end
        step(1'b0); step(1'b0); step(1'b0);

        // ---------- Summary ----------
        $display("--------------------------------------------------");
        if (errors == 0)
            $display("PASS: pim_matmul_macro  (%0d value checks, 0 errors)", checks);
        else
            $display("FAIL: pim_matmul_macro  (%0d errors over %0d checks)", errors, checks);
        $display("--------------------------------------------------");
        if (errors != 0) $fatal(1, "Testbench failed");
        $finish;
    end

    // safety timeout
    initial begin
        #500000;
        $display("FAIL: timeout");
        $fatal(1, "timeout");
    end

endmodule

`default_nettype wire
