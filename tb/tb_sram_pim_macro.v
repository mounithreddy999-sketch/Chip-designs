/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * Self-checking testbench for sram_pim_macro:
 * output-stationary, weight-streaming near-memory MVM.
 *
 * Contract under test:
 *   - Weights are programmed into an OpenRAM SRAM as 32-bit words (4 INT8 each),
 *     word address = row*WORDS_PER_ROW + k, holding columns [4k .. 4k+3].
 *   - A `start` pulse latches the activation vector and runs one MVM.
 *   - out_valid rises when out_vector = a^T * W is complete and holds until next start.
 *
 * The golden reference (sum_r act[r]*W[r][c]) is computed in the testbench and
 * compared for directed (identity, all-ones) and randomized vectors.
 */

`timescale 1ns/1ps
`default_nettype none

module tb_sram_pim_macro;

    localparam integer N    = 16;
    localparam integer AW   = 8;
    localparam integer WW   = 8;
    localparam integer OW   = 24;
    localparam integer ADDR = 8;
    localparam integer WPW  = 32 / WW;   // weights per 32-bit word = 4
    localparam integer WPR  = N / WPW;   // words per row = 4
    localparam integer TOTAL = N * WPR;  // 64 words for a 16x16 matrix

    reg                     clk = 1'b0;
    reg                     rst = 1'b1;
    reg                     start = 1'b0;
    reg                     we = 1'b0;
    reg  [ADDR-1:0]         w_word_addr = {ADDR{1'b0}};
    reg  [31:0]             w_word_data = 32'd0;
    reg  signed [N*AW-1:0]  act_vector_in = {(N*AW){1'b0}};
    wire signed [N*OW-1:0]  out_vector;
    wire                    out_valid;

    reg signed [WW-1:0] gW [0:N-1][0:N-1];
    reg signed [AW-1:0] cur_act [0:N-1];
    integer errors = 0;
    integer checks = 0;

    sram_pim_macro #(
        .N(N), .ACT_WIDTH(AW), .W_WIDTH(WW), .OUT_WIDTH(OW), .ADDR_WIDTH(ADDR)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .act_vector_in(act_vector_in),
        .we(we),
        .w_word_addr(w_word_addr),
        .w_word_data(w_word_data),
        .out_vector(out_vector),
        .out_valid(out_valid)
    );

    always #5 clk = ~clk;

    // Pack gW into 32-bit words and program the SRAM through the macro.
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

    // Drive one MVM and check every output against the golden reference.
    integer mc, mr, timeout;
    integer acc;
    reg signed [OW-1:0] got, want;
    task run_mvm;
        begin
            for (mc = 0; mc < N; mc = mc + 1)
                act_vector_in[mc*AW +: AW] = cur_act[mc];
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
                for (mc = 0; mc < N; mc = mc + 1) begin
                    acc = 0;
                    for (mr = 0; mr < N; mr = mr + 1)
                        acc = acc + (cur_act[mr] * gW[mr][mc]);
                    got  = $signed(out_vector[mc*OW +: OW]);
                    want = acc;
                    checks = checks + 1;
                    if (got !== want) begin
                        $display("[%0t] FAIL: out[%0d] got=%0d want=%0d", $time, mc, got, want);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    integer i, j;
    initial begin
        $dumpfile("tb_sram_pim_macro.vcd");
        $dumpvars(0, tb_sram_pim_macro);

        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // ---- Test 1: identity weights => out == act ----
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                gW[i][j] = (i == j) ? 8'sd1 : 8'sd0;
        program_weights();
        for (i = 0; i < N; i = i + 1) cur_act[i] = i + 1;   // out[c] should be c+1
        run_mvm();

        // ---- Test 2: all-ones weights => out[c] == sum(act) ----
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                gW[i][j] = 8'sd1;
        program_weights();
        for (i = 0; i < N; i = i + 1) cur_act[i] = i + 1;   // sum 1..16 = 136
        run_mvm();

        // ---- Test 3: randomized weights + activations ----
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                gW[i][j] = $random;
        program_weights();
        for (i = 0; i < 20; i = i + 1) begin
            for (j = 0; j < N; j = j + 1)
                cur_act[j] = $random;
            run_mvm();
        end

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("PASS: sram_pim_macro  (%0d value checks, 0 errors)", checks);
        else
            $display("FAIL: sram_pim_macro  (%0d errors over %0d checks)", errors, checks);
        $display("--------------------------------------------------");
        if (errors != 0) $fatal(1, "Testbench failed");
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: global timeout");
        $fatal(1, "timeout");
    end

endmodule

`default_nettype wire
