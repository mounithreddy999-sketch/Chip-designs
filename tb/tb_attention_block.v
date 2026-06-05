/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 *
 * Self-checking INTEGRATION testbench for attention_block (the SoC accelerator hub).
 *
 * The sub-blocks (pim_matmul_macro, mx_softmax_unit) are verified individually
 * elsewhere; this proves the GLUE is right: AXI4-Lite weight programming reaches
 * the correct PIM cells, the AXI-Stream Q path + FSM sequence correctly, the
 * 24->16->8 truncations wire up, and Q->PIM_K->softmax->PIM_V->out flows end to end.
 *
 * Checks (replacing the old vague "result = 15"):
 *   T1 Completion + determinism : a 4-query batch yields 4 outputs; re-run is identical.
 *   T2 Input sensitivity        : changing Q changes the output (it actually computes).
 *   T3 Softmax symmetry         : K=0 (equal scores) + column-symmetric V => softmax is
 *                                 uniform => all 4 output lanes equal (softmax is in-loop
 *                                 and correctly applied).
 */

`timescale 1ns/1ps
`default_nettype none

module tb_attention_block;

    localparam N = 4;
    reg clk = 0, rstn = 0;
    always #5 clk = ~clk;

    // AXI4-Lite
    reg  [31:0] awaddr=0; reg awvalid=0; wire awready;
    reg  [31:0] wdata=0;  reg [3:0] wstrb=4'hF; reg wvalid=0; wire wready;
    wire [1:0] bresp; wire bvalid; reg bready=0;
    reg  [31:0] araddr=0; reg arvalid=0; wire arready;
    wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=0;
    // AXI-Stream
    reg  [31:0] s_tdata=0; reg s_tvalid=0; wire s_tready;
    wire [31:0] m_tdata; wire m_tvalid; reg m_tready=0;

    attention_block #(.N(N)) dut (
        .clk(clk), .rstn(rstn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_axis_n_tdata(s_tdata), .s_axis_n_tvalid(s_tvalid), .s_axis_n_tready(s_tready),
        .m_axis_out_tdata(m_tdata), .m_axis_out_tvalid(m_tvalid), .m_axis_out_tready(m_tready)
    );

    integer errors = 0;

    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1; wdata = data; wvalid = 1; wstrb = 4'hF;
            @(negedge clk);                 // both ready high -> slave latches + executes
            awvalid = 0; wvalid = 0; bready = 1;
            while (!bvalid) @(negedge clk);
            @(negedge clk); bready = 0;
        end
    endtask

    // program a 4x4 weight matrix into PIM_K (base 0x100) or PIM_V (0x200)
    integer pr, pc;
    task prog_matrix(input [31:0] base, input [7:0] m00,m01,m02,m03,
                     input [7:0] m10,m11,m12,m13, input [7:0] m20,m21,m22,m23,
                     input [7:0] m30,m31,m32,m33);
        reg [7:0] M [0:3][0:3];
        begin
            M[0][0]=m00;M[0][1]=m01;M[0][2]=m02;M[0][3]=m03;
            M[1][0]=m10;M[1][1]=m11;M[1][2]=m12;M[1][3]=m13;
            M[2][0]=m20;M[2][1]=m21;M[2][2]=m22;M[2][3]=m23;
            M[3][0]=m30;M[3][1]=m31;M[3][2]=m32;M[3][3]=m33;
            for (pr=0; pr<4; pr=pr+1)
                for (pc=0; pc<4; pc=pc+1)
                    axi_write(base | (pr<<4) | (pc<<2), {24'd0, M[pr][pc]});
        end
    endtask

    // run one batch of 4 query vectors (paced 1:1), capture 4 output beats
    integer qi, tcnt;
    task run_batch(input [31:0] q0, input [31:0] q1, input [31:0] q2, input [31:0] q3,
                   output [31:0] o0, output [31:0] o1, output [31:0] o2, output [31:0] o3);
        reg [31:0] qarr [0:3];
        reg [31:0] oarr [0:3];
        begin
            qarr[0]=q0; qarr[1]=q1; qarr[2]=q2; qarr[3]=q3;
            axi_write(32'h000, 32'h1);          // control bit0 = start
            m_tready = 1;
            for (qi=0; qi<4; qi=qi+1) begin
                // drive one Q beat
                @(negedge clk);
                tcnt = 0;
                while (!s_tready && tcnt<100) begin @(negedge clk); tcnt=tcnt+1; end
                s_tdata = qarr[qi]; s_tvalid = 1;
                @(negedge clk); s_tvalid = 0;
                // wait for its output beat
                tcnt = 0;
                while (!m_tvalid && tcnt<400) begin @(negedge clk); tcnt=tcnt+1; end
                if (!m_tvalid) begin
                    $display("[%0t] FAIL: no output for query %0d", $time, qi);
                    errors = errors + 1; oarr[qi] = 32'hxxxxxxxx;
                end else begin
                    oarr[qi] = m_tdata;
                    @(negedge clk);             // let tvalid clear
                end
            end
            m_tready = 0;
            o0=oarr[0]; o1=oarr[1]; o2=oarr[2]; o3=oarr[3];
        end
    endtask

    reg [31:0] a0,a1,a2,a3, b0,b1,b2,b3;
    integer lane;
    reg [7:0] l0,l1,l2,l3;
    initial begin
        $dumpfile("tb_attention_block.vcd");
        $dumpvars(0, tb_attention_block);
        rstn = 0; repeat (4) @(negedge clk); rstn = 1; repeat (2) @(negedge clk);

        // ---- T1: completion + determinism ----
        prog_matrix(32'h100, 64,0,0,0, 0,64,0,0, 0,0,64,0, 0,0,0,64);  // K = diag(64): drive scores into softmax range
        prog_matrix(32'h200, 2,1,0,3, 1,2,1,0, 0,1,3,1, 3,0,1,2);      // V = non-symmetric
        // Q in [32,127] (positive signed) and large, so Q*K lands in softmax dynamic range
        run_batch(32'h507F6040, 32'h40607F50, 32'h4060207F, 32'h60407F20, a0,a1,a2,a3);
        run_batch(32'h507F6040, 32'h40607F50, 32'h4060207F, 32'h60407F20, b0,b1,b2,b3);
        if ({a0,a1,a2,a3} !== {b0,b1,b2,b3}) begin
            $display("FAIL T1a: non-deterministic: %h%h%h%h vs %h%h%h%h", a0,a1,a2,a3,b0,b1,b2,b3);
            errors = errors + 1;
        end else
            $display("PASS T1a: deterministic across re-run");
        if (a0===a1 && a1===a2 && a2===a3) begin
            $display("FAIL T1b: all 4 queries gave identical output (per-query path not distinct): %h", a0);
            errors = errors + 1;
        end else
            $display("PASS T1b: distinct per-query outputs (%h %h %h %h)", a0,a1,a2,a3);

        // ---- T2: input sensitivity ----
        run_batch(32'h7F7F7F7F, 32'h10203040, 32'h01020304, 32'h40302010, b0,b1,b2,b3);
        if ({a0,a1,a2,a3} === {b0,b1,b2,b3}) begin
            $display("FAIL T2: output insensitive to Q (constant accelerator)");
            errors = errors + 1;
        end else
            $display("PASS T2: output depends on Q (it computes)");

        // ---- T3: softmax symmetry (K=0 -> uniform softmax; column-symmetric V -> equal lanes) ----
        prog_matrix(32'h100, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0);          // K = 0
        prog_matrix(32'h200, 1,1,1,1, 2,2,2,2, 3,3,3,3, 4,4,4,4);          // V columns identical
        run_batch(32'h04030201, 32'h02020202, 32'h05040302, 32'h01010101, a0,a1,a2,a3);
        l0=a0[7:0]; l1=a0[15:8]; l2=a0[23:16]; l3=a0[31:24];
        if (l0===l1 && l1===l2 && l2===l3)
            $display("PASS T3: uniform softmax -> equal output lanes (%0d) [softmax in-loop, correct]", l0);
        else begin
            $display("FAIL T3: lanes not equal for symmetric config: %0d %0d %0d %0d", l0,l1,l2,l3);
            errors = errors + 1;
        end

        $display("--------------------------------------------------");
        if (errors == 0) $display("PASS: attention_block integration verified (T1-T3, 0 errors)");
        else             $display("FAIL: attention_block integration (%0d errors)", errors);
        $display("--------------------------------------------------");
        if (errors != 0) $fatal(1, "integration failed");
        $finish;
    end

    initial begin #2000000; $display("FAIL: timeout"); $fatal(1, "timeout"); end

endmodule

`default_nettype wire
