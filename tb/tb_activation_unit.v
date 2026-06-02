/*
 * Native Self-Checking Verilog Testbench for PWL Activation Unit
 */

`timescale 1ns / 1ps

module tb_activation_unit;

    // Signals
    reg                     clk;
    reg                     rst;
    reg                     en;
    reg                     mode;
    reg  signed [15:0]      in_data;
    wire signed [15:0]      out_data;

    // Instantiate DUT
    activation_unit dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .mode(mode),
        .in_data(in_data),
        .out_data(out_data)
    );

    // Clock Generator (100MHz clock)
    always #5 clk = ~clk;

    // Helper task to run a check
    task check_activation(
        input        m,
        input signed [15:0] val
    );
        begin
            mode    = m;
            in_data = val;
            en      = 1'b1;
            @(posedge clk);
            #1; // Delay to resolve assignments
            en      = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_activation_unit.vcd");
        $dumpvars(0, tb_activation_unit);

        // Initialize signals
        clk     = 1'b0;
        rst     = 1'b1;
        en      = 1'b0;
        mode    = 1'b0;
        in_data = 16'sd0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk);
        #1;

        // Check reset condition
        if (out_data !== 16'sd0) begin
            $display("[FAIL] Output not zero after reset. Got %d", out_data);
            $finish;
        end
        $display("[PASS] Reset state verified.");

        // ==========================================
        // Test Case 1: ReLU Mode (mode = 0)
        // ==========================================
        $display("Test Case 1: ReLU Mode");
        
        // Positive input
        check_activation(1'b0, 16'sd1000);
        if (out_data !== 16'sd1000) begin
            $display("[FAIL] ReLU positive path failed. Expected 1000, got %d", out_data);
            $finish;
        end
        
        // Negative input
        check_activation(1'b0, -16'sd50);
        if (out_data !== 16'sd0) begin
            $display("[FAIL] ReLU negative path failed. Expected 0, got %d", out_data);
            $finish;
        end
        $display("[PASS] ReLU mode verified.");

        // ==========================================
        // Test Case 2: Sigmoid Mode (mode = 1)
        // ==========================================
        $display("Test Case 2: Sigmoid Mode");

        // Input 0.0 -> Output 0.5 (represented as 16384 in Q1.15)
        check_activation(1'b1, 16'sd0);
        if (out_data !== 16'd16384) begin
            $display("[FAIL] Sigmoid(0) failed. Expected 16384, got %d", out_data);
            $finish;
        end
        $display("[PASS] Sigmoid(0.0) = 0.5 verified.");

        // Input 1.0 (4096 in Q4.12) -> Output approx 0.73 (23920 in Q1.15)
        check_activation(1'b1, 16'sd4096);
        if (out_data !== 16'd23920) begin
            $display("[FAIL] Sigmoid(1.0) failed. Expected 23920, got %d", out_data);
            $finish;
        end
        $display("[PASS] Sigmoid(1.0) = 0.73 verified.");

        // Input -1.0 (-4096 in Q4.12) -> Output approx 0.27 (8847 in Q1.15)
        check_activation(1'b1, -16'sd4096);
        if (out_data !== 16'd8847) begin
            $display("[FAIL] Sigmoid(-1.0) failed. Expected 8847, got %d", out_data);
            $finish;
        end
        $display("[PASS] Sigmoid(-1.0) = 0.27 verified.");

        // Input 4.0 (16384 in Q4.12) -> Output 1.0 (32767 in Q1.15)
        check_activation(1'b1, 16'sd16384);
        if (out_data !== 16'h7FFF) begin
            $display("[FAIL] Sigmoid(4.0) failed. Expected 32767, got %d", out_data);
            $finish;
        end
        $display("[PASS] Sigmoid(4.0) = 1.0 verified.");

        // Input -4.0 (-16384 in Q4.12) -> Output 0.0 (0 in Q1.15)
        check_activation(1'b1, -16'sd16384);
        if (out_data !== 16'd0) begin
            $display("[FAIL] Sigmoid(-4.0) failed. Expected 0, got %d", out_data);
            $finish;
        end
        $display("[PASS] Sigmoid(-4.0) = 0.0 verified.");

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
