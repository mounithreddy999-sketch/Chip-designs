/*
 * Native Self-Checking Verilog Testbench for INT4 Dot Product PE
 */

`timescale 1ns / 1ps

module tb_dot_product_pe;

    // Signals
    reg         clk;
    reg         rst;
    reg         en;
    reg         valid_in;
    reg         clear_acc;
    reg  [15:0] vector_a;
    reg  [15:0] vector_b;
    wire signed [15:0] acc;
    wire        overflow;
    wire        underflow;

    // Instantiate DUT
    dot_product_pe dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .valid_in(valid_in),
        .clear_acc(clear_acc),
        .vector_a(vector_a),
        .vector_b(vector_b),
        .acc(acc),
        .overflow(overflow),
        .underflow(underflow)
    );

    // Clock Generator (100MHz clock)
    always #5 clk = ~clk;

    // Helper task to execute a dot product
    task run_pe(
        input [15:0] val_a,
        input [15:0] val_b
    );
        begin
            vector_a = val_a;
            vector_b = val_b;
            valid_in = 1'b1;
            @(posedge clk);
            #1; // Delay to resolve assignments
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

    // Main Test Loop
    integer i;
    initial begin
        $dumpfile("tb_dot_product_pe.vcd");
        $dumpvars(0, tb_dot_product_pe);

        // Initialize signals
        clk       = 1'b0;
        rst       = 1'b1;
        en        = 1'b1;
        valid_in  = 1'b0;
        clear_acc = 1'b0;
        vector_a  = 16'h0;
        vector_b  = 16'h0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk);
        #1;

        // Check reset condition
        if (acc !== 16'sd0 || overflow !== 1'b0 || underflow !== 1'b0) begin
            $display("[FAIL] Initial state mismatch after reset: acc=%d, ovf=%b, unf=%b", acc, overflow, underflow);
            $finish;
        end
        $display("[PASS] Reset state verified.");

        // Test Case 1: Positive inputs
        // Vector A: [2, 3, 1, 5] -> Packed: {5, 1, 3, 2} = 16'h5132
        // Vector B: [4, 2, 6, 1] -> Packed: {1, 6, 2, 4} = 16'h1624
        // Expected dot product: (2*4) + (3*2) + (1*6) + (5*1) = 8 + 6 + 6 + 5 = 25
        $display("Test Case 1: Positive Vector Dot Product");
        run_pe(16'h5132, 16'h1624);
        if (acc !== 16'sd25) begin
            $display("[FAIL] Expected acc to be 25, got %d", acc);
            $finish;
        end
        $display("[PASS] Positive dot product verified. Acc = %d", acc);

        // Test Case 2: Negative signed inputs
        // Vector A: [-3, 4, -1, -2] -> Packed: {-2, -1, 4, -3} (E= -2, F= -1, 4= 4, D= -3) = 16'hEF4D
        // Vector B: [2, -2, 5, -3]  -> Packed: {-3, 5, -2, 2}  (D= -3, 5= 5, E= -2, 2= 2)  = 16'hD5E2
        // Expected products:
        // a0*b0 = -3 * 2  = -6
        // a1*b1 = 4  * -2 = -8
        // a2*b2 = -1 * 5  = -5
        // a3*b3 = -2 * -3 = 6
        // Intermediate sum = -6 - 8 - 5 + 6 = -13
        // New Acc = 25 - 13 = 12
        $display("Test Case 2: Signed Mixed Vector Dot Product");
        run_pe(16'hEF4D, 16'hD5E2);
        if (acc !== 16'sd12) begin
            $display("[FAIL] Expected acc to be 12, got %d", acc);
            $finish;
        end
        $display("[PASS] Signed mixed dot product verified. Acc = %d", acc);

        // Test Case 3: Verify Clear
        $display("Test Case 3: Clear Accumulator");
        run_clear();
        if (acc !== 16'sd0 || overflow !== 1'b0 || underflow !== 1'b0) begin
            $display("[FAIL] Expected acc to clear to 0, got acc=%d, ovf=%b", acc, overflow);
            $finish;
        end
        $display("[PASS] Accumulator clear verified.");

        // Test Case 4: Positive Saturation (Overflow Limit)
        // Max value is +32,767.
        // Vector A: [7, 7, 7, 7] -> Packed: 16'h7777
        // Vector B: [7, 7, 7, 7] -> Packed: 16'h7777
        // Dot product: (7*7) * 4 = 49 * 4 = 196
        // 32,767 / 196 = 167.1 iterations. We run 170 iterations.
        $display("Test Case 4: Positive Saturation Overflow test");
        vector_a = 16'h7777;
        vector_b = 16'h7777;
        valid_in = 1'b1;
        for (i = 0; i < 170; i = i + 1) begin
            @(posedge clk);
        end
        #1;
        valid_in = 1'b0;

        if (acc !== 16'sd32767 || overflow !== 1'b1 || underflow !== 1'b0) begin
            $display("[FAIL] Expected saturation at 32767 with overflow high. Got acc=%d, ovf=%b, unf=%b", acc, overflow, underflow);
            $finish;
        end
        $display("[PASS] Positive saturation limits verified.");

        // Test Case 5: Negative Saturation (Underflow Limit)
        $display("Test Case 5: Negative Saturation Underflow test");
        run_clear();
        
        // Min value is -32,768.
        // Vector A: [-8, -8, -8, -8] -> Packed: 16'h8888
        // Vector B: [7, 7, 7, 7]    -> Packed: 16'h7777
        // Dot product: (-8*7) * 4 = -56 * 4 = -224
        // -32,768 / -224 = 146.2 iterations. We run 150 iterations.
        vector_a = 16'h8888;
        vector_b = 16'h7777;
        valid_in = 1'b1;
        for (i = 0; i < 150; i = i + 1) begin
            @(posedge clk);
        end
        #1;
        valid_in = 1'b0;

        if (acc !== -16'sd32768 || underflow !== 1'b1 || overflow !== 1'b0) begin
            $display("[FAIL] Expected saturation at -32768 with underflow high. Got acc=%d, ovf=%b, unf=%b", acc, overflow, underflow);
            $finish;
        end
        $display("[PASS] Negative saturation limits verified.");

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
