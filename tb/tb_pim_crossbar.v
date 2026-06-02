/*
 * Native Self-Checking Verilog Testbench for 4x4 PIM SRAM Crossbar
 */

`timescale 1ns / 1ps

module tb_pim_crossbar;

    // Parameters
    parameter ACT_WIDTH = 8;
    parameter W_WIDTH   = 8;
    parameter OUT_WIDTH = 16;

    // Signals
    reg                     clk;
    reg                     rst;
    reg                     en;
    reg  [1:0]              w_addr_row;
    reg  [1:0]              w_addr_col;
    reg                     w_write_en;
    reg  signed [W_WIDTH-1:0] w_data_in;
    
    reg  signed [ACT_WIDTH-1:0] act_0;
    reg  signed [ACT_WIDTH-1:0] act_1;
    reg  signed [ACT_WIDTH-1:0] act_2;
    reg  signed [ACT_WIDTH-1:0] act_3;
    
    wire signed [OUT_WIDTH-1:0] out_0;
    wire signed [OUT_WIDTH-1:0] out_1;
    wire signed [OUT_WIDTH-1:0] out_2;
    wire signed [OUT_WIDTH-1:0] out_3;

    // Instantiate DUT
    pim_crossbar #(
        .ACT_WIDTH(ACT_WIDTH),
        .W_WIDTH(W_WIDTH),
        .OUT_WIDTH(OUT_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .w_addr_row(w_addr_row),
        .w_addr_col(w_addr_col),
        .w_write_en(w_write_en),
        .w_data_in(w_data_in),
        .act_0(act_0),
        .act_1(act_1),
        .act_2(act_2),
        .act_3(act_3),
        .out_0(out_0),
        .out_1(out_1),
        .out_2(out_2),
        .out_3(out_3)
    );

    // Clock Generator (100MHz clock)
    always #5 clk = ~clk;

    // Helper task to program a single weight cell
    task program_weight(
        input [1:0] r,
        input [1:0] c,
        input signed [W_WIDTH-1:0] val
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
        $dumpfile("tb_pim_crossbar.vcd");
        $dumpvars(0, tb_pim_crossbar);

        // Initialize signals
        clk        = 1'b0;
        rst        = 1'b1;
        en         = 1'b0;
        w_addr_row = 2'd0;
        w_addr_col = 2'd0;
        w_write_en = 1'b0;
        w_data_in  = 8'sd0;
        act_0      = 8'sd0;
        act_1      = 8'sd0;
        act_2      = 8'sd0;
        act_3      = 8'sd0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk);
        #1;

        // Verify initial state
        if (out_0 !== 16'sd0 || out_1 !== 16'sd0 || out_2 !== 16'sd0 || out_3 !== 16'sd0) begin
            $display("[FAIL] Outputs not zero after reset.");
            $finish;
        end
        $display("[PASS] Reset state verified.");

        // ==========================================
        // Test Case 1: Write Weight Matrix
        // Program W:
        //   Row 0: [ 2,  3,  4,  5]
        //   Row 1: [-1,  2, -3,  1]
        //   Row 2: [ 4, -2,  6,  0]
        //   Row 3: [ 5,  1,  2, -4]
        // ==========================================
        $display("Test Case 1: Programming weight matrix...");
        program_weight(2'd0, 2'd0, 8'sd2);
        program_weight(2'd0, 2'd1, 8'sd3);
        program_weight(2'd0, 2'd2, 8'sd4);
        program_weight(2'd0, 2'd3, 8'sd5);

        program_weight(2'd1, 2'd0, -8'sd1);
        program_weight(2'd1, 2'd1, 8'sd2);
        program_weight(2'd1, 2'd2, -8'sd3);
        program_weight(2'd1, 2'd3, 8'sd1);

        program_weight(2'd2, 2'd0, 8'sd4);
        program_weight(2'd2, 2'd1, -8'sd2);
        program_weight(2'd2, 2'd2, 8'sd6);
        program_weight(2'd2, 2'd3, 8'sd0);

        program_weight(2'd3, 2'd0, 8'sd5);
        program_weight(2'd3, 2'd1, 8'sd1);
        program_weight(2'd3, 2'd2, 8'sd2);
        program_weight(2'd3, 2'd3, -8'sd4);

        // Quick internal readback assertion checking
        if (dut.r_weights[0][0] !== 8'sd2 || dut.r_weights[1][2] !== -8'sd3 || dut.r_weights[3][3] !== -8'sd4) begin
            $display("[FAIL] Weight programming failed.");
            $finish;
        end
        $display("[PASS] Weights successfully programmed.");

        // ==========================================
        // Test Case 2: Compute Matrix-Vector Multiplication
        // Activations input vector A = [10, -5, 20, 8]
        // Expected products along columns:
        //   Col 0 = (10*2) + (-5*-1) + (20*4) + (8*5) = 20 + 5 + 80 + 40 = 145
        //   Col 1 = (10*3) + (-5*2) + (20*-2) + (8*1) = 30 - 10 - 40 + 8 = -12
        //   Col 2 = (10*4) + (-5*-3) + (20*6) + (8*2) = 40 + 15 + 120 + 16 = 191
        //   Col 3 = (10*5) + (-5*1) + (20*0) + (8*-4) = 50 - 5 + 0 - 32 = 13
        // ==========================================
        $display("Test Case 2: Executing MVM computation...");
        act_0 = 8'sd10;
        act_1 = -8'sd5;
        act_2 = 8'sd20;
        act_3 = 8'sd8;
        
        en = 1'b1;
        @(posedge clk);
        #1;
        en = 1'b0;

        $display("Outputs: out_0=%d, out_1=%d, out_2=%d, out_3=%d", out_0, out_1, out_2, out_3);
        if (out_0 !== 16'sd145 || out_1 !== -16'sd12 || out_2 !== 16'sd191 || out_3 !== 16'sd13) begin
            $display("[FAIL] MVM outputs do not match expected calculations.");
            $finish;
        end
        $display("[PASS] Matrix-Vector Multiplication verified successfully.");

        // ==========================================
        // Test Case 3: Positive & Negative Saturation Limits
        // ==========================================
        $display("Test Case 3: Verifying Saturation Limits...");
        
        // Positive Saturation Setup
        program_weight(2'd0, 2'd0, 8'sd120);
        program_weight(2'd1, 2'd0, 8'sd120);
        program_weight(2'd2, 2'd0, 8'sd120);
        program_weight(2'd3, 2'd0, 8'sd120);
        
        act_0 = 8'sd100;
        act_1 = 8'sd100;
        act_2 = 8'sd100;
        act_3 = 8'sd100;
        // Sum = 120 * 100 * 4 = 48,000 (exceeds +32,767)
        
        en = 1'b1;
        @(posedge clk);
        #1;
        en = 1'b0;
        
        if (out_0 !== 16'sd32767) begin
            $display("[FAIL] Expected positive saturation clamp at 32767, got %d", out_0);
            $finish;
        end
        $display("[PASS] Positive saturation limits verified.");

        // Negative Saturation Setup
        program_weight(2'd0, 2'd0, -8'sd120);
        program_weight(2'd1, 2'd0, -8'sd120);
        program_weight(2'd2, 2'd0, -8'sd120);
        program_weight(2'd3, 2'd0, -8'sd120);
        // Sum = -120 * 100 * 4 = -48,000 (exceeds -32,768)

        en = 1'b1;
        @(posedge clk);
        #1;
        en = 1'b0;

        if (out_0 !== -16'sd32768) begin
            $display("[FAIL] Expected negative saturation clamp at -32768, got %d", out_0);
            $finish;
        end
        $display("[PASS] Negative saturation limits verified.");

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
