/*
 * Native Self-Checking Verilog Testbench for Reconfigurable CGRA PE Node
 */

`timescale 1ns / 1ps

module tb_cgra_pe;

    // Signals
    reg                     clk;
    reg                     rst;
    reg                     en;
    reg  [15:0]             config_data;
    reg                     config_valid;
    reg  signed [7:0]       data_n;
    reg signed [7:0]        data_s;
    reg signed [7:0]        data_e;
    reg signed [7:0]        data_w;
    reg signed [7:0]        data_global;
    wire signed [7:0]       out_n;
    wire signed [7:0]       out_s;
    wire signed [7:0]       out_e;
    wire signed [7:0]       out_w;

    // Instantiate DUT
    cgra_pe dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .config_data(config_data),
        .config_valid(config_valid),
        .data_n(data_n),
        .data_s(data_s),
        .data_e(data_e),
        .data_w(data_w),
        .data_global(data_global),
        .out_n(out_n),
        .out_s(out_s),
        .out_e(out_e),
        .out_w(out_w)
    );

    // Clock Generator (100MHz clock)
    always #5 clk = ~clk;

    // Helper task to write a configuration to the node
    task write_config(input [15:0] conf);
        begin
            config_data = conf;
            config_valid = 1'b1;
            @(posedge clk);
            #1;
            config_valid = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    // Main Test Sequence
    initial begin
        $dumpfile("tb_cgra_pe.vcd");
        $dumpvars(0, tb_cgra_pe);

        // Initialize signals
        clk          = 1'b0;
        rst          = 1'b1;
        en           = 1'b0;
        config_data  = 16'h0;
        config_valid = 1'b0;
        data_n       = 8'sd0;
        data_s       = 8'sd0;
        data_e       = 8'sd0;
        data_w       = 8'sd0;
        data_global  = 8'sd0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk);
        #1;

        // Verify initial reset output state
        if (out_n !== 8'sd0 || out_s !== 8'sd0 || out_e !== 8'sd0 || out_w !== 8'sd0) begin
            $display("[FAIL] Initial outputs are not zero. out_n=%d", out_n);
            $finish;
        end
        $display("[PASS] Reset outputs verified.");

        // Test Case 1: Simple Addition and East Routing
        // Config: src_a=North(000), src_b=South(001), op=ADD(01), dest_route=East(011)
        // Binary: 00000_011_01_001_000 = 16'h0348
        $display("Test Case 1: Load config to add North and South, routing output to East");
        write_config(16'h0348);

        data_n = 8'sd42;
        data_s = -8'sd12;
        en = 1'b1;
        @(posedge clk);
        #1;
        en = 1'b0;

        if (out_e !== 8'sd30 || out_n !== 8'sd0 || out_s !== 8'sd0 || out_w !== 8'sd0) begin
            $display("[FAIL] Expected out_e = 30, got out_e=%d, out_n=%d", out_e, out_n);
            $finish;
        end
        $display("[PASS] Addition and East routing verified.");

        // Test Case 2: Multiply-Accumulate and South Routing
        // Previous accumulator holds 30.
        // Config: src_a=West(011), src_b=East(010), op=MAC(00), dest_route=South(010)
        // Binary: 00000_010_00_010_011 = 16'h0213
        $display("Test Case 2: Load config to Multiply West and East, accumulate, routing output to South");
        write_config(16'h0213);

        data_w = 8'sd4;
        data_e = 8'sd5;
        en = 1'b1;
        @(posedge clk);
        #1;
        en = 1'b0;

        // Expected output: 30 + (4 * 5) = 50
        if (out_s !== 8'sd50 || out_e !== 8'sd0 || out_n !== 8'sd0 || out_w !== 8'sd0) begin
            $display("[FAIL] Expected out_s = 50, got out_s=%d, out_e=%d", out_s, out_e);
            $finish;
        end
        $display("[PASS] Multiply-Accumulate and South routing verified.");

        // Test Case 3: Output Saturation and North Routing
        // Previous accumulator holds 50.
        // Config: src_a=West(011), src_b=East(010), op=MAC(00), dest_route=North(001)
        // Binary: 00000_001_00_010_011 = 16'h0113
        $display("Test Case 3: Verify Output Saturation (Overflow clamping to 127) routing to North");
        write_config(16'h0113);

        data_w = 8'sd120;
        data_e = 8'sd2;
        en = 1'b1;
        // MAC increment: 120 * 2 = 240. Total: 50 + 240 = 290. Should saturate to 127.
        @(posedge clk);
        #1;
        en = 1'b0;

        if (out_n !== 8'sd127 || out_s !== 8'sd0) begin
            $display("[FAIL] Expected out_n to saturate at 127, got out_n=%d, out_s=%d", out_n, out_s);
            $finish;
        end
        $display("[PASS] Output saturation clamping verified.");

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
