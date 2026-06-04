/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * Activity / power-stimulus workload for pim_matmul_macro.
 *
 * Generates a VCD that reflects the REALISTIC inference duty cycle so that
 * VCD-driven power analysis (OpenROAD read_vcd + report_power) reveals the
 * clock-gating benefit:
 *
 *   Phase A (VCD OFF): reset, then program the N*N weight matrix once.
 *   Phase B (VCD ON) : stream WORKLOAD_VECTORS activation vectors, one per
 *                      cycle, with w_write_en held LOW the whole time.
 *
 * In Phase B the weights are stationary: with CG_WEIGHTS=1 the gated weight
 * clock is OFF, so those 2*N*N flops (and their clock branch) stop toggling.
 * The VCD therefore captures the steady state where the gating actually pays.
 *
 * Build:
 *   iverilog -g2012 [-D TB_CG] [-D WORKLOAD_VECTORS=2000] \
 *            rtl/pim_matmul_macro.v rtl/clock_gate.v tb/tb_pim_matmul_macro_workload.v
 *
 * The run is self-checking (golden MVM scoreboard) so the activity is known to
 * be correct work, not random toggling.
 */

`timescale 1ns/1ps
`default_nettype none

`ifndef WORKLOAD_VECTORS
`define WORKLOAD_VECTORS 2000
`endif

module tb_pim_matmul_macro_workload;

`ifdef TB_N
    localparam integer N      = `TB_N;   // override via -D TB_N=32
`else
    localparam integer N      = 16;
`endif
    localparam integer AW     = 8;
    localparam integer WW     = 8;
    localparam integer OW     = 24;
    localparam integer LAT    = 2;
    localparam integer AW_IDX = (N <= 1) ? 1 : $clog2(N);
    localparam integer M      = `WORKLOAD_VECTORS;

`ifdef TB_CG
    localparam integer CGW = 1;
`else
    localparam integer CGW = 0;
`endif

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

    reg signed [WW-1:0] gW [0:N-1][0:N-1];
    reg signed [AW-1:0] cur_act [0:N-1];
    reg signed [OW-1:0] exp_pipe [0:LAT-1][0:N-1];
    reg                 exp_vld  [0:LAT-1];
    integer errors = 0;
    integer checks = 0;

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

    always #5 clk = ~clk;

    integer k, r, c;

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

    // One inference cycle: check settled outputs, then drive the next vector.
    // w_write_en stays low here (weights stationary) -- the gated-clock regime.
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

    integer i, j, v;
    initial begin
        $dumpfile("tb_pim_matmul_macro_workload.vcd");

        for (k = 0; k < LAT; k = k + 1) exp_vld[k] = 1'b0;

        // ---------- Phase A: reset + one-time weight load (NOT captured) ----------
        rst = 1'b1; en = 1'b0; in_valid = 1'b0;
        repeat (4) @(negedge clk);
        rst = 1'b0;

        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                gW[i][j] = $random;
                write_weight(i, j, gW[i][j]);
            end

        // ---------- Phase B: steady-state inference (VCD ON) ----------
        $display("CG_WEIGHTS=%0d : capturing %0d inference cycles to VCD", CGW, M);
        $dumpvars(0, dut);            // start capturing at inference onset
        en = 1'b1;

        for (v = 0; v < M; v = v + 1) begin
            for (k = 0; k < N; k = k + 1)
                cur_act[k] = $random;
            step(1'b1);              // 1 valid vector/cycle, w_write_en low
        end
        step(1'b0); step(1'b0); step(1'b0);

        $dumpoff;

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("PASS: workload (CG_WEIGHTS=%0d)  %0d checks, 0 errors, VCD captured",
                     CGW, checks);
        else
            $display("FAIL: workload (CG_WEIGHTS=%0d)  %0d errors over %0d checks",
                     CGW, errors, checks);
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
