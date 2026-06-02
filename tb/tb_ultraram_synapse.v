/*
 * Native Self-Checking Verilog Testbench for ULTRARAM-Inspired Synapse
 */

`timescale 1ns / 1ps

module tb_ultraram_synapse;

    // Signals
    reg                     clk;
    reg                     rst;
    reg                     en;
    reg                     pulse;
    reg                     op_type;
    reg  [2:0]              pulse_amplitude;
    wire [7:0]              conductance;
    wire [31:0]             cycle_count;

    // Instantiate DUT
    ultraram_synapse dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .pulse(pulse),
        .op_type(op_type),
        .pulse_amplitude(pulse_amplitude),
        .conductance(conductance),
        .cycle_count(cycle_count)
    );

    // Clock Generator (100MHz clock)
    always #5 clk = ~clk;

    // Helper task to apply a programming/erasing pulse
    task apply_pulse(
        input       op,
        input [2:0] amp
    );
        begin
            op_type = op;
            pulse_amplitude = amp;
            pulse = 1'b1;
            @(posedge clk);
            #1; // Delay to resolve assignments
            pulse = 1'b0;
        end
    endtask

    integer i;
    initial begin
        $dumpfile("tb_ultraram_synapse.vcd");
        $dumpvars(0, tb_ultraram_synapse);

        // Initialize signals
        clk             = 1'b0;
        rst             = 1'b1;
        en              = 1'b1;
        pulse           = 1'b0;
        op_type         = 1'b0;
        pulse_amplitude = 3'd0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk);
        #1;

        // Check reset condition
        if (conductance !== 8'h00 || cycle_count !== 32'd0) begin
            $display("[FAIL] Initial state mismatch after reset: conductance=%d, cycles=%d", conductance, cycle_count);
            $finish;
        end
        $display("[PASS] Reset state verified.");

        // ==========================================
        // Test Case 1: Simple Potentiation (Program)
        // ==========================================
        $display("Test Case 1: Linear Potentiation (Program)");
        apply_pulse(1'b1, 3'd0); // Step size 1
        if (conductance !== 8'd1 || cycle_count !== 32'd1) begin
            $display("[FAIL] Expected conductance = 1, cycles = 1. Got cond=%d, cycles=%d", conductance, cycle_count);
            $finish;
        end
        
        apply_pulse(1'b1, 3'd5); // Step size 5
        if (conductance !== 8'd6 || cycle_count !== 32'd2) begin
            $display("[FAIL] Expected conductance = 6, cycles = 2. Got cond=%d, cycles=%d", conductance, cycle_count);
            $finish;
        end
        $display("[PASS] Basic potentiation verified. Conductance = %d", conductance);

        // ==========================================
        // Test Case 2: Simple Depression (Erase)
        // ==========================================
        $display("Test Case 2: Linear Depression (Erase)");
        apply_pulse(1'b0, 3'd2); // Step size 2
        if (conductance !== 8'd4 || cycle_count !== 32'd3) begin
            $display("[FAIL] Expected conductance = 4, cycles = 3. Got cond=%d, cycles=%d", conductance, cycle_count);
            $finish;
        end
        $display("[PASS] Basic depression verified. Conductance = %d", conductance);

        // ==========================================
        // Test Case 3: Saturation Limits (Clamping)
        // ==========================================
        $display("Test Case 3: Saturation Clamping (Overflow/Underflow)");
        
        // Underflow clamp
        apply_pulse(1'b0, 3'd7); // Erase by 7 from 4 -> Should clamp to 0
        if (conductance !== 8'd0) begin
            $display("[FAIL] Expected conductance to clamp to 0, got %d", conductance);
            $finish;
        end

        // Program to overflow clamp
        for (i = 0; i < 40; i = i + 1) begin
            apply_pulse(1'b1, 3'd7); // 40 * 7 = 280 -> Should clamp to 255
        end
        if (conductance !== 8'd255) begin
            $display("[FAIL] Expected conductance to clamp to 255, got %d", conductance);
            $finish;
        end
        $display("[PASS] Saturation clamping verified. (0 and 255 bounds met)");

        // ==========================================
        // Test Case 4: 10,000 Cycle High-Endurance Test
        // ==========================================
        $display("Test Case 4: 10,000-Cycle High-Endurance Test");
        
        // Move conductance to a known midpoint (e.g., 100)
        rst = 1'b1;
        @(posedge clk);
        #1;
        rst = 1'b0;
        @(posedge clk);
        #1;
        
        for (i = 0; i < 100; i = i + 1) begin
            apply_pulse(1'b1, 3'd0); // Step size 1 -> Accumulate to 100
        end
        if (conductance !== 8'd100) begin
            $display("[FAIL] Failed to pre-charge conductance to 100. Got %d", conductance);
            $finish;
        end
        
        // Execute 5,000 Program-Erase iterations (10,000 pulses total)
        // Verify that weight updates remain perfectly linear and zero degradation occurs
        $display("Running 10,000 program/erase operations...");
        for (i = 0; i < 5000; i = i + 1) begin
            // Program pulse
            op_type = 1'b1;
            pulse_amplitude = 3'd0;
            pulse = 1'b1;
            @(posedge clk);
            #1;
            if (conductance !== 8'd101) begin
                $display("[FAIL] Potentiation step failed at cycle %d. Expected 101, got %d", (i * 2) + 1, conductance);
                $finish;
            end
            
            // Erase pulse
            op_type = 1'b0;
            pulse_amplitude = 3'd0;
            pulse = 1'b1;
            @(posedge clk);
            #1;
            if (conductance !== 8'd100) begin
                $display("[FAIL] Depression step failed at cycle %d. Expected 100, got %d", (i * 2) + 2, conductance);
                $finish;
            end
        end
        
        pulse = 1'b0;
        
        // Verify that cycle count matches exactly (100 pre-charge + 10,000 endurance test)
        if (cycle_count !== 32'd10100) begin
            $display("[FAIL] Expected cycle count to be 10100, got %d", cycle_count);
            $finish;
        end

        // Verify final conductance value matches initial state exactly (no drift/degradation)
        if (conductance !== 8'd100) begin
            $display("[FAIL] End conductance value drift detected. Expected 100, got %d", conductance);
            $finish;
        end

        $display("[PASS] 10,000-cycle high-endurance test verified successfully.");
        $display("Final Conductance: %d, Lifetime Cycles: %d", conductance, cycle_count);

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
