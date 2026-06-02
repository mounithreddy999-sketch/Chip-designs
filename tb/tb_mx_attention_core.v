/*
 * Native Self-Checking Verilog Testbench for MXINT4/MXFP4/MXFP8 Attention Core Subsystem
 */

`timescale 1ns / 1ps

module tb_mx_attention_core;

    // Inputs
    reg                     clk;
    reg                     rst;
    reg                     en;
    reg                     start;
    reg                     dataflow_mode_sel;
    reg  [1:0]              format_mode;
    
    reg                     q_write_en;
    reg  [6:0]              q_write_addr;
    reg  [31:0]             q_write_data;
    reg                     k_write_en;
    reg  [6:0]              k_write_addr;
    reg  [31:0]             k_write_data;
    
    reg                     w_write_en;
    reg  [1:0]              w_addr_row;
    reg  [1:0]              w_addr_col;
    reg  signed [7:0]       w_data_in;
    
    reg  signed [7:0]       scale_act;
    reg  signed [7:0]       scale_weight;

    // Outputs
    wire                    busy;
    wire                    done;
    wire                    out_valid;
    
    wire signed [15:0]      result_00; wire signed [15:0]      result_01;
    wire signed [15:0]      result_02; wire signed [15:0]      result_03;
    wire signed [15:0]      result_10; wire signed [15:0]      result_11;
    wire signed [15:0]      result_12; wire signed [15:0]      result_13;
    wire signed [15:0]      result_20; wire signed [15:0]      result_21;
    wire signed [15:0]      result_22; wire signed [15:0]      result_23;
    wire signed [15:0]      result_30; wire signed [15:0]      result_31;
    wire signed [15:0]      result_32; wire signed [15:0]      result_33;

    // Instantiate DUT
    mx_attention_core uut (
        .clk(clk), .rst(rst), .en(en),
        .start(start), .dataflow_mode_sel(dataflow_mode_sel), .format_mode(format_mode),
        .busy(busy), .done(done), .out_valid(out_valid),
        .q_write_en(q_write_en), .q_write_addr(q_write_addr), .q_write_data(q_write_data),
        .k_write_en(k_write_en), .k_write_addr(k_write_addr), .k_write_data(k_write_data),
        .w_write_en(w_write_en), .w_addr_row(w_addr_row), .w_addr_col(w_addr_col), .w_data_in(w_data_in),
        .scale_act(scale_act), .scale_weight(scale_weight),
        .result_00(result_00), .result_01(result_01), .result_02(result_02), .result_03(result_03),
        .result_10(result_10), .result_11(result_11), .result_12(result_12), .result_13(result_13),
        .result_20(result_20), .result_21(result_21), .result_22(result_22), .result_23(result_23),
        .result_30(result_30), .result_31(result_31), .result_32(result_32), .result_33(result_33)
    );

    // Clock generator (100MHz)
    always #5 clk = ~clk;

    // Helper task to program a single weight cell (WS mode)
    task program_ws_weight(
        input [1:0] r,
        input [1:0] c,
        input signed [7:0] val
    );
        begin
            w_addr_row = r;
            w_addr_col = c;
            w_data_in  = val;
            w_write_en = 1'b1;
            @(posedge clk); #1;
            w_write_en = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_mx_attention_core.vcd");
        $dumpvars(0, tb_mx_attention_core);

        // Initialize signals
        clk               = 1'b0;
        rst               = 1'b1;
        en                = 1'b1;
        start             = 1'b0;
        dataflow_mode_sel = 1'b0;
        format_mode       = 2'b00; // MXINT4
        q_write_en        = 1'b0;
        q_write_addr      = 7'd0;
        q_write_data      = 32'd0;
        k_write_en        = 1'b0;
        k_write_addr      = 7'd0;
        k_write_data      = 32'd0;
        w_write_en        = 1'b0;
        w_addr_row        = 2'd0;
        w_addr_col        = 2'd0;
        w_data_in         = 8'sd0;
        scale_act         = 8'sd0;
        scale_weight      = 8'sd0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk); #1;

        // Check reset condition
        if (busy !== 1'b0 || done !== 1'b0 || result_00 !== 16'sd0) begin
            $display("[FAIL] Reset state verification failed.");
            $finish;
        end
        $display("[PASS] Reset state verified successfully.");

        // ==========================================
        // Load Q and K matrices into Scratchpad SRAM (aligned to 8-bit slots)
        // Q matrix elements:
        //   Row 0: 2 (02), -1 (FF), 3 (03), 0 (00) -> 32'h0003FF02
        //   Row 1: 1 (01), 2 (02), 0 (00), -2 (FE) -> 32'hFE000201
        //   Row 2: 0 (00), 1 (01), 1 (01), 3 (03)  -> 32'h03010100
        //   Row 3: -3 (FD), 0 (00), 2 (02), 1 (01) -> 32'h010200FD
        // K matrix elements:
        //   Row 0: 1 (01), 2 (02), 0 (00), 1 (01)  -> 32'h01000201
        //   Row 1: -2 (FE), 1 (01), 3 (03), 0 (00) -> 32'h000301FE
        //   Row 2: 0 (00), -1 (FF), 2 (02), -3 (FD)-> 32'hFD02FF00
        //   Row 3: 3 (03), 0 (00), -1 (FF), 2 (02) -> 32'h02FF0003
        // ==========================================
        $display("Writing Q and K matrices to SRAM...");
        
        q_write_addr = 7'd0; q_write_data = 32'h0003FF02; q_write_en = 1'b1; @(posedge clk); #1;
        q_write_addr = 7'd1; q_write_data = 32'hFE000201; q_write_en = 1'b1; @(posedge clk); #1;
        q_write_addr = 7'd2; q_write_data = 32'h03010100; q_write_en = 1'b1; @(posedge clk); #1;
        q_write_addr = 7'd3; q_write_data = 32'h010200FD; q_write_en = 1'b1; @(posedge clk); #1;
        q_write_en = 1'b0;

        k_write_addr = 7'd0; k_write_data = 32'h01000201; k_write_en = 1'b1; @(posedge clk); #1;
        k_write_addr = 7'd1; k_write_data = 32'h000301FE; k_write_en = 1'b1; @(posedge clk); #1;
        k_write_addr = 7'd2; k_write_data = 32'hFD02FF00; k_write_en = 1'b1; @(posedge clk); #1;
        k_write_addr = 7'd3; k_write_data = 32'h02FF0003; k_write_en = 1'b1; @(posedge clk); #1;
        k_write_en = 1'b0;

        $display("[PASS] SRAM write completed.");

        // ==========================================
        // Test Case 1: Weight-Stationary Mode Execution
        // Program PE weights with the K matrix.
        // We set microscaling scale factors:
        //   scale_act = 2, scale_weight = -1 (Total shift = +1, which multiplies by 2)
        // ==========================================
        $display("\n--- Test Case 1: Weight-Stationary Mode ---");
        dataflow_mode_sel = 1'b0;
        format_mode       = 2'b00; // MXINT4
        scale_act         = 8'sd2;
        scale_weight      = -8'sd1;

        $display("Programming PE weights for WS mode...");
        program_ws_weight(2'd0, 2'd0, 8'sd1);
        program_ws_weight(2'd0, 2'd1, 8'sd2);
        program_ws_weight(2'd0, 2'd2, 8'sd0);
        program_ws_weight(2'd0, 2'd3, 8'sd1);
        
        program_ws_weight(2'd1, 2'd0, -8'sd2);
        program_ws_weight(2'd1, 2'd1, 8'sd1);
        program_ws_weight(2'd1, 2'd2, 8'sd3);
        program_ws_weight(2'd1, 2'd3, 8'sd0);
        
        program_ws_weight(2'd2, 2'd0, 8'sd0);
        program_ws_weight(2'd2, 2'd1, -8'sd1);
        program_ws_weight(2'd2, 2'd2, 8'sd2);
        program_ws_weight(2'd2, 2'd3, -8'sd3);
        
        program_ws_weight(2'd3, 2'd0, 8'sd3);
        program_ws_weight(2'd3, 2'd1, 8'sd0);
        program_ws_weight(2'd3, 2'd2, -8'sd1);
        program_ws_weight(2'd3, 2'd3, 8'sd2);
        $display("PE weights programmed.");

        // Start execution
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;

        // Wait for execution completion
        while (!done) begin
            @(posedge clk);
        end
        #1;

        $display("WS Results:");
        $display("  [%d, %d, %d, %d]", result_00, result_01, result_02, result_03);
        $display("  [%d, %d, %d, %d]", result_10, result_11, result_12, result_13);
        $display("  [%d, %d, %d, %d]", result_20, result_21, result_22, result_23);
        $display("  [%d, %d, %d, %d]", result_30, result_31, result_32, result_33);

        if (result_00 !== 16'd8176  || result_01 !== 16'd8212 || result_02 !== 16'd8214 || result_03 !== 16'd8189 ||
            result_10 !== 16'd8187  || result_11 !== 16'd8197 || result_12 !== 16'd8220 || result_13 !== 16'd8190 ||
            result_20 !== 16'd8207  || result_21 !== 16'd8197 || result_22 !== 16'd8184 || result_23 !== 16'd8195 ||
            result_30 !== 16'd8220  || result_31 !== 16'd8190 || result_32 !== 16'd8200 || result_33 !== 16'd8185) begin
            $display("[FAIL] WS Mode result verification mismatch.");
            $finish;
        end
        $display("[PASS] Weight-Stationary Mode outputs verified.");

        // ==========================================
        // Test Case 2: Output-Stationary Mode Execution
        // Run with the same Q and K matrices.
        // We set microscaling scale factors:
        //   scale_act = 1, scale_weight = 1 (Total shift = +2, which multiplies by 4)
        // ==========================================
        $display("\n--- Test Case 2: Output-Stationary Mode ---");
        dataflow_mode_sel = 1'b1;
        format_mode       = 2'b00; // MXINT4
        scale_act         = 8'sd1;
        scale_weight      = 8'sd1;

        // Start execution
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;

        // Wait for execution completion
        while (!done) begin
            @(posedge clk);
        end
        #1;

        $display("OS Results:");
        $display("  [%d, %d, %d, %d]", result_00, result_01, result_02, result_03);
        $display("  [%d, %d, %d, %d]", result_10, result_11, result_12, result_13);
        $display("  [%d, %d, %d, %d]", result_20, result_21, result_22, result_23);
        $display("  [%d, %d, %d, %d]", result_30, result_31, result_32, result_33);

        if (result_00 !== 16'd8219  || result_01 !== 16'd8199 || result_02 !== 16'd8214 || result_03 !== 16'd8164 ||
            result_10 !== 16'd8160  || result_11 !== 16'd8226 || result_12 !== 16'd8246 || result_13 !== 16'd8190 ||
            result_20 !== 16'd8219  || result_21 !== 16'd8184 || result_22 !== 16'd8194 || result_23 !== 16'd8199 ||
            result_30 !== 16'd8217  || result_31 !== 16'd8176 || result_32 !== 16'd8232 || result_33 !== 16'd8181) begin
            $display("[FAIL] OS Mode result verification mismatch.");
            $finish;
        end
        $display("[PASS] Output-Stationary Mode outputs verified.");

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
