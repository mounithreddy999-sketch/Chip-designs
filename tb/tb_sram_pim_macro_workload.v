/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * Activity / power-stimulus workload for sram_pim_macro (near-memory streaming).
 *
 *   Phase A (VCD OFF): reset, then program the weight matrix into the SRAM once.
 *   Phase B (VCD ON) : run WORKLOAD_MVMS back-to-back matrix-vector multiplies,
 *                      weights resident in SRAM, activations streamed.
 *
 * The captured VCD reflects steady-state inference: SRAM reads + the 4-wide MAC
 * lane + accumulators churning, with NO weight reprogramming. Feed it to
 * report_power (with the SRAM .lib) to get the design's true dynamic energy.
 *
 * Build:
 *   iverilog -g2012 [-D WORKLOAD_MVMS=50] rtl/sram_pim_macro.v \
 *       tb/sky130_sram_1kbyte_1rw1r_32x256_8.v tb/tb_sram_pim_macro_workload.v
 *
 * Self-checking (golden MVM) so the activity is known-correct work.
 */

`timescale 1ns/1ps
`default_nettype none

`ifndef WORKLOAD_MVMS
`define WORKLOAD_MVMS 50
`endif

module tb_sram_pim_macro_workload;

    localparam integer N    = 16;
    localparam integer AW   = 8;
    localparam integer WW   = 8;
    localparam integer OW   = 24;
    localparam integer ADDR = 8;
    localparam integer WPW  = 32 / WW;   // weights per word = 4
    localparam integer WPR  = N / WPW;   // words per row = 4
    localparam integer TOTAL = N * WPR;  // 64 words
    localparam integer M    = `WORKLOAD_MVMS;

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

    integer i, j, v;
    initial begin
        $dumpfile("tb_sram_pim_macro_workload.vcd");

        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // ---------- Phase A: one-time weight load (NOT captured) ----------
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                gW[i][j] = $random;
        program_weights();

        // ---------- Phase B: steady-state inference burst (VCD ON) ----------
        $display("Near-memory: capturing %0d back-to-back MVMs to VCD", M);
        $dumpvars(0, dut);
        for (v = 0; v < M; v = v + 1) begin
            for (j = 0; j < N; j = j + 1)
                cur_act[j] = $random;
            run_mvm();
        end
        $dumpoff;

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("PASS: sram workload  %0d checks, 0 errors, VCD captured", checks);
        else
            $display("FAIL: sram workload  %0d errors over %0d checks", errors, checks);
        $display("--------------------------------------------------");
        if (errors != 0) $fatal(1, "Workload testbench failed");
        $finish;
    end

    initial begin
        #50000000;
        $display("FAIL: global timeout");
        $fatal(1, "timeout");
    end

endmodule

`default_nettype wire
