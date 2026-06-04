/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * Self-checking testbench for sram_pim_batched_macro:
 * near-memory MVM with BATCHED weight reuse (one SRAM macro).
 *
 * Contract:
 *   - Weights resident in ONE OpenRAM SRAM (same layout as sram_pim_macro).
 *   - A `start` pulse latches a BATCH of B activation vectors and computes
 *       out[b][c] = sum_r A[b][r] * W[r][c]   for all b in [0,B), c in [0,N).
 *   - Each 4-weight SRAM read feeds 4*B MACs (reused across the batch), so the
 *     read + control overhead amortizes over B vectors -> better pJ/MAC, same area.
 *   - out_valid rises when the whole batch result is ready.
 */

`timescale 1ns/1ps
`default_nettype none

module tb_sram_pim_batched_macro;

    localparam integer N    = 16;
    localparam integer B    = 4;     // batch size (vectors reusing each weight load)
    localparam integer AW   = 8;
    localparam integer WW   = 8;
    localparam integer OW   = 24;
    localparam integer ADDR = 8;
    localparam integer WPW  = 32 / WW;   // weights per word = 4
    localparam integer WPR  = N / WPW;   // words per row = 4
    localparam integer TOTAL = N * WPR;  // 64 words

    reg                          clk = 1'b0;
    reg                          rst = 1'b1;
    reg                          start = 1'b0;
    reg                          we = 1'b0;
    reg  [ADDR-1:0]              w_word_addr = {ADDR{1'b0}};
    reg  [31:0]                  w_word_data = 32'd0;
    reg  signed [B*N*AW-1:0]     act_vector_in = {(B*N*AW){1'b0}};
    wire signed [B*N*OW-1:0]     out_vector;
    wire                         out_valid;

    reg signed [WW-1:0] gW [0:N-1][0:N-1];
    reg signed [AW-1:0] cur_act [0:B-1][0:N-1];
    integer errors = 0;
    integer checks = 0;

    sram_pim_batched_macro #(
        .N(N), .B(B), .ACT_WIDTH(AW), .W_WIDTH(WW), .OUT_WIDTH(OW), .ADDR_WIDTH(ADDR)
    ) dut (
        .clk(clk), .rst(rst), .start(start),
        .act_vector_in(act_vector_in),
        .we(we), .w_word_addr(w_word_addr), .w_word_data(w_word_data),
        .out_vector(out_vector), .out_valid(out_valid)
    );

    always #5 clk = ~clk;

    integer pr, pk, pj;
    reg [31:0] word;
    task program_weights;
        begin
            for (pr = 0; pr < N; pr = pr + 1)
                for (pk = 0; pk < WPR; pk = pk + 1) begin
                    word = 32'd0;
                    for (pj = 0; pj < WPW; pj = pj + 1)
                        word[pj*WW +: WW] = gW[pr][pk*WPW + pj];
                    @(negedge clk);
                    we = 1'b1;
                    w_word_addr = pr*WPR + pk;
                    w_word_data = word;
                    @(negedge clk);
                    we = 1'b0;
                end
        end
    endtask

    integer bb, mc, mr, timeout;
    integer acc;
    reg signed [OW-1:0] got, want;
    task run_batch;
        begin
            for (bb = 0; bb < B; bb = bb + 1)
                for (mc = 0; mc < N; mc = mc + 1)
                    act_vector_in[(bb*N + mc)*AW +: AW] = cur_act[bb][mc];
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            timeout = 0;
            while (out_valid !== 1'b1 && timeout < 3*TOTAL + 32) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (out_valid !== 1'b1) begin
                $display("[%0t] FAIL: timeout waiting for out_valid", $time);
                errors = errors + 1;
            end else begin
                for (bb = 0; bb < B; bb = bb + 1)
                    for (mc = 0; mc < N; mc = mc + 1) begin
                        acc = 0;
                        for (mr = 0; mr < N; mr = mr + 1)
                            acc = acc + (cur_act[bb][mr] * gW[mr][mc]);
                        got  = $signed(out_vector[(bb*N + mc)*OW +: OW]);
                        want = acc;
                        checks = checks + 1;
                        if (got !== want) begin
                            $display("[%0t] FAIL: out[b%0d][%0d] got=%0d want=%0d",
                                     $time, bb, mc, got, want);
                            errors = errors + 1;
                        end
                    end
            end
        end
    endtask

    integer i, j, t;
    initial begin
        $dumpfile("tb_sram_pim_batched_macro.vcd");

        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // ---- Test 1: identity weights => out[b][c] == A[b][c] ----
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                gW[i][j] = (i == j) ? 8'sd1 : 8'sd0;
        program_weights();
        for (i = 0; i < B; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                cur_act[i][j] = (i + 1) * (j + 1);   // distinct per batch element
        run_batch();

        // ---- Test 2: randomized weights + batches ----
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                gW[i][j] = $random;
        program_weights();
        for (t = 0; t < 20; t = t + 1) begin
            for (i = 0; i < B; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                    cur_act[i][j] = $random;
            run_batch();
        end

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("PASS: sram_pim_batched_macro  (%0d value checks, 0 errors)", checks);
        else
            $display("FAIL: sram_pim_batched_macro  (%0d errors over %0d checks)", errors, checks);
        $display("--------------------------------------------------");
        if (errors != 0) $fatal(1, "Testbench failed");
        $finish;
    end

    initial begin
        #5000000;
        $display("FAIL: global timeout");
        $fatal(1, "timeout");
    end

endmodule

`default_nettype wire
