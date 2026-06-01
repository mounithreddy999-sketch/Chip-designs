/*
 * Native Self-Checking Verilog Testbench for Parameterized MAC Unit
 */

`timescale 1ns / 1ps

module tb_mac;

    // Parameters
    parameter OP_WIDTH  = 8;
    parameter ACC_WIDTH = 24;

    // Testbench Signals
    reg                     clk;
    reg                     rst;
    reg                     en;
    reg                     valid_in;
    reg                     clear_acc;
    reg signed [OP_WIDTH-1:0]  a;
    reg signed [OP_WIDTH-1:0]  b;
    wire signed [ACC_WIDTH-1:0] acc;
    wire                    overflow;
    wire                    underflow;

    // Instantiate Design Under Test (DUT)
    mac #(
        .OP_WIDTH(OP_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .valid_in(valid_in),
        .clear_acc(clear_acc),
        .a(a),
        .b(b),
        .acc(acc),
        .overflow(overflow),
        .underflow(underflow)
    );

    // Clock Generator (100MHz clock)
    always #5 clk = ~clk;

    // Helper task to run a single cycle MAC accumulation
    task run_mac(
        input signed [OP_WIDTH-1:0] operand_a,
        input signed [OP_WIDTH-1:0] operand_b
    );
        begin
            a = operand_a;
            b = operand_b;
            valid_in = 1'b1;
            @(posedge clk);
            #1; // Delay to let state update resolve
            valid_in = 1'b0;
        end
    endtask

    // Helper task to clear accumulator
    task run_clear;
        begin
            clear_acc = 1'b1;
            @(posedge clk);
            #1;
            clear_acc = 1'b0;
        end
    endtask

    // Main Test Sequence
    integer i;
    initial begin
        // Open dump file for waveforms
        $dumpfile("tb_mac.vcd");
        $dumpvars(0, tb_mac);

        // Initialize Signals
        clk       = 1'b0;
        rst       = 1'b1;
        en        = 1'b1;
        valid_in  = 1'b0;
        clear_acc = 1'b0;
        a         = 8'sd0;
        b         = 8'sd0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk);
        #1;

        // Assert initial reset state
        if (acc !== 24'sd0 || overflow !== 1'b0 || underflow !== 1'b0) begin
            $display("[FAIL] Initial state mismatch after reset: acc=%d, ovf=%b, unf=%b", acc, overflow, underflow);
            $finish;
        end
        $display("[PASS] Reset state verified.");

        // Test Case 1: 5 * -3 = -15
        $display("Test Case 1: 5 * -3");
        run_mac(8'sd5, -8'sd3);
        if (acc !== -24'sd15) begin
            $display("[FAIL] Expected acc to be -15, got %d", acc);
            $finish;
        end
        $display("[PASS] 5 * -3 accumulated successfully.");

        // Test Case 2: Accumulate 12 * 10 = 120 (total should be 105)
        $display("Test Case 2: + (12 * 10)");
        run_mac(8'sd12, 8'sd10);
        if (acc !== 24'sd105) begin
            $display("[FAIL] Expected acc to be 105, got %d", acc);
            $finish;
        end
        $display("[PASS] 12 * 10 accumulated successfully. Total = %d", acc);

        // Test Case 3: Verify clear_acc functionality
        $display("Test Case 3: Clear Accumulator");
        run_clear();
        if (acc !== 24'sd0 || overflow !== 1'b0 || underflow !== 1'b0) begin
            $display("[FAIL] Expected accumulator to clear, got acc=%d, ovf=%b", acc, overflow);
            $finish;
        end
        $display("[PASS] Accumulator clear verified.");

        // Test Case 4: Positive Saturation (Overflow Limit)
        // Max value is +8,388,607.
        // 127 * 127 = 16,129 per accumulation.
        // 8,388,607 / 16,129 = 520.1 iterations. We run 525 iterations.
        $display("Test Case 4: Positive Saturation Overflow test");
        a = 8'sd127;
        b = 8'sd127;
        valid_in = 1'b1;
        for (i = 0; i < 525; i = i + 1) begin
            @(posedge clk);
        end
        #1;
        valid_in = 1'b0;

        if (acc !== 24'sd8388607 || overflow !== 1'b1 || underflow !== 1'b0) begin
            $display("[FAIL] Expected saturation at 8388607 with overflow high. Got acc=%d, ovf=%b, unf=%b", acc, overflow, underflow);
            $finish;
        end
        $display("[PASS] Positive saturation limits verified.");

        // Test Case 5: Negative Saturation (Underflow Limit)
        $display("Test Case 5: Negative Saturation Underflow test");
        run_clear();
        
        // Min value is -8,388,608.
        // -128 * 127 = -16,256 per accumulation.
        // -8,388,608 / -16,256 = 516 iterations. We run 520 iterations.
        a = -8'sd128;
        b = 8'sd127;
        valid_in = 1'b1;
        for (i = 0; i < 520; i = i + 1) begin
            @(posedge clk);
        end
        #1;
        valid_in = 1'b0;

        if (acc !== -24'sd8388608 || underflow !== 1'b1 || overflow !== 1'b0) begin
            $display("[FAIL] Expected saturation at -8388608 with underflow high. Got acc=%d, ovf=%b, unf=%b", acc, overflow, underflow);
            $finish;
        end
        $display("[PASS] Negative saturation limits verified.");

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
