/*
 * Native Self-Checking Verilog Testbench for 3x3 Systolic Array
 */

`timescale 1ns / 1ps

module tb_systolic_array;

    // Signals
    reg                     clk;
    reg                     rst;
    reg                     en;
    
    reg  [1:0]              w_addr_row;
    reg  [1:0]              w_addr_col;
    reg                     w_write_en;
    reg  signed [7:0]       w_data_in;
    
    reg  signed [7:0]       act_in_row0;
    reg  signed [7:0]       act_in_row1;
    reg  signed [7:0]       act_in_row2;
    
    reg  signed [23:0]      partial_sum_in_col0;
    reg  signed [23:0]      partial_sum_in_col1;
    reg  signed [23:0]      partial_sum_in_col2;
    
    wire signed [23:0]      out_col0;
    wire signed [23:0]      out_col1;
    wire signed [23:0]      out_col2;

    // Instantiate DUT
    systolic_array dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .w_addr_row(w_addr_row),
        .w_addr_col(w_addr_col),
        .w_write_en(w_write_en),
        .w_data_in(w_data_in),
        .act_in_row0(act_in_row0),
        .act_in_row1(act_in_row1),
        .act_in_row2(act_in_row2),
        .partial_sum_in_col0(partial_sum_in_col0),
        .partial_sum_in_col1(partial_sum_in_col1),
        .partial_sum_in_col2(partial_sum_in_col2),
        .out_col0(out_col0),
        .out_col1(out_col1),
        .out_col2(out_col2)
    );

    // Clock Generator (100MHz clock)
    always #5 clk = ~clk;

    // Helper task to program a single weight cell
    task program_weight(
        input [1:0] r,
        input [1:0] c,
        input signed [7:0] val
    );
        begin
            w_addr_row = r;
            w_addr_col = c;
            w_data_in  = val;
            w_write_en = 1'b1;
            @(posedge clk);
            #1;
            w_write_en = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);

        // Initialize signals
        clk                 = 1'b0;
        rst                 = 1'b1;
        en                  = 1'b0;
        w_addr_row          = 2'd0;
        w_addr_col          = 2'd0;
        w_write_en          = 1'b0;
        w_data_in           = 8'sd0;
        act_in_row0         = 8'sd0;
        act_in_row1         = 8'sd0;
        act_in_row2         = 8'sd0;
        partial_sum_in_col0 = 24'sd0;
        partial_sum_in_col1 = 24'sd0;
        partial_sum_in_col2 = 24'sd0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk);
        #1;

        // Check reset condition
        if (out_col0 !== 24'sd0 || out_col1 !== 24'sd0 || out_col2 !== 24'sd0) begin
            $display("[FAIL] Outputs not zero after reset.");
            $finish;
        end
        $display("[PASS] Reset state verified.");

        // ==========================================
        // Test Case 1: Program Weights
        // Program Weight Matrix W:
        //   [ 1,  2,  3 ]
        //   [-1,  1,  2 ]
        //   [ 2, -1,  1 ]
        // ==========================================
        $display("Programming weight matrix...");
        program_weight(2'd0, 2'd0, 8'sd1);
        program_weight(2'd0, 2'd1, 8'sd2);
        program_weight(2'd0, 2'd2, 8'sd3);

        program_weight(2'd1, 2'd0, -8'sd1);
        program_weight(2'd1, 2'd1, 8'sd1);
        program_weight(2'd1, 2'd2, 8'sd2);

        program_weight(2'd2, 2'd0, 8'sd2);
        program_weight(2'd2, 2'd1, -8'sd1);
        program_weight(2'd2, 2'd2, 8'sd1);

        $display("[PASS] Weights programmed successfully.");

        // ==========================================
        // Test Case 2: Skewed Activation Stream
        // Matrix X:
        //   [ 2,  1,  0 ]
        //   [-1,  2,  1 ]
        //   [ 3,  0,  1 ]
        //
        // Row-skewed timing schedule:
        // Cycle 0: Row0=2, Row1=0,  Row2=0
        // Cycle 1: Row0=1, Row1=-1, Row2=0
        // Cycle 2: Row0=0, Row1=2,  Row2=3
        // Cycle 3: Row0=0, Row1=1,  Row2=0
        // Cycle 4: Row0=0, Row1=0,  Row2=1
        // Cycle 5: Row0=0, Row1=0,  Row2=0 (shifting remainder out)
        // ==========================================
        $display("Streaming activations...");
        en = 1'b1;

        // Cycle 0
        act_in_row0 = 8'sd2;
        act_in_row1 = 8'sd0;
        act_in_row2 = 8'sd0;
        @(posedge clk); #1;

        // Cycle 1
        act_in_row0 = 8'sd1;
        act_in_row1 = -8'sd1;
        act_in_row2 = 8'sd0;
        @(posedge clk); #1;

        // Cycle 2
        act_in_row0 = 8'sd0;
        act_in_row1 = 8'sd2;
        act_in_row2 = 8'sd3;
        @(posedge clk); #1;

        // Cycle 3
        act_in_row0 = 8'sd0;
        act_in_row1 = 8'sd1;
        act_in_row2 = 8'sd0;
        // Output at Col0 should be valid now: Y_00 = 9
        $display("Cycle 3: Col0=%d (Expected 9)", out_col0);
        if (out_col0 !== 24'sd9) begin
            $display("[FAIL] Col0 mismatch at cycle 3. Expected 9, got %d", out_col0);
            $finish;
        end
        @(posedge clk); #1;

        // Cycle 4
        act_in_row0 = 8'sd0;
        act_in_row1 = 8'sd0;
        act_in_row2 = 8'sd1; // X_22 is 1
        // Outputs valid: Col0 = Y_10 = -1, Col1 = Y_01 = 0
        $display("Cycle 4: Col0=%d (Expected -1), Col1=%d (Expected 0)", out_col0, out_col1);
        if (out_col0 !== -24'sd1 || out_col1 !== 24'sd0) begin
            $display("[FAIL] Output mismatch at cycle 4. Got Col0=%d, Col1=%d", out_col0, out_col1);
            $finish;
        end
        @(posedge clk); #1;

        // Cycle 5
        act_in_row0 = 8'sd0;
        act_in_row1 = 8'sd0;
        act_in_row2 = 8'sd0; 
        // Outputs valid: Col0 = Y_20 = 1, Col1 = Y_11 = 4, Col2 = Y_02 = 7
        $display("Cycle 5: Col0=%d (Expected 1), Col1=%d (Expected 4), Col2=%d (Expected 7)", out_col0, out_col1, out_col2);
        if (out_col0 !== 24'sd1 || out_col1 !== 24'sd4 || out_col2 !== 24'sd7) begin
            $display("[FAIL] Output mismatch at cycle 5. Got Col0=%d, Col1=%d, Col2=%d", out_col0, out_col1, out_col2);
            $finish;
        end
        @(posedge clk); #1;

        // Cycle 6
        act_in_row0 = 8'sd0;
        act_in_row1 = 8'sd0;
        act_in_row2 = 8'sd0;
        // Outputs valid: Col1 = Y_21 = 0, Col2 = Y_12 = 7
        $display("Cycle 6: Col1=%d (Expected 0), Col2=%d (Expected 7)", out_col1, out_col2);
        if (out_col1 !== 24'sd0 || out_col2 !== 24'sd7) begin
            $display("[FAIL] Output mismatch at cycle 6. Got Col1=%d, Col2=%d", out_col1, out_col2);
            $finish;
        end
        @(posedge clk); #1;

        // Cycle 7
        // Outputs valid: Col2 = Y_22 = 3
        $display("Cycle 7: Col2=%d (Expected 3)", out_col2);
        if (out_col2 !== 24'sd3) begin
            $display("[FAIL] Col2 mismatch at cycle 7. Expected 3, got %d", out_col2);
            $finish;
        end

        en = 1'b0;

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
