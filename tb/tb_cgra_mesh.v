/*
 * Native Self-Checking Verilog Testbench for 2D CGRA Mesh Accelerator
 */

`timescale 1ns / 1ps

module tb_cgra_mesh;

    // Testbench Signals
    reg                     clk;
    reg                     rst;
    reg                     en;
    reg  [1:0]              config_addr;
    reg  [15:0]             config_data;
    reg                     config_valid;
    
    reg  signed [7:0]        data_n_0;
    reg  signed [7:0]        data_n_1;
    reg  signed [7:0]        data_s_0;
    reg  signed [7:0]        data_s_1;
    reg  signed [7:0]        data_e_0;
    reg  signed [7:0]        data_e_1;
    reg  signed [7:0]        data_w_0;
    reg  signed [7:0]        data_w_1;
    
    reg  signed [7:0]        data_global;
    
    wire signed [7:0]       out_n_0;
    wire signed [7:0]       out_n_1;
    wire signed [7:0]       out_s_0;
    wire signed [7:0]       out_s_1;
    wire signed [7:0]       out_e_0;
    wire signed [7:0]       out_e_1;
    wire signed [7:0]       out_w_0;
    wire signed [7:0]       out_w_1;

    // Instantiate DUT (cgra_mesh)
    cgra_mesh dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .config_addr(config_addr),
        .config_data(config_data),
        .config_valid(config_valid),
        .data_n_0(data_n_0),
        .data_n_1(data_n_1),
        .data_s_0(data_s_0),
        .data_s_1(data_s_1),
        .data_e_0(data_e_0),
        .data_e_1(data_e_1),
        .data_w_0(data_w_0),
        .data_w_1(data_w_1),
        .data_global(data_global),
        .out_n_0(out_n_0),
        .out_n_1(out_n_1),
        .out_s_0(out_s_0),
        .out_s_1(out_s_1),
        .out_e_0(out_e_0),
        .out_e_1(out_e_1),
        .out_w_0(out_w_0),
        .out_w_1(out_w_1)
    );

    // Clock Generator (100MHz clock)
    always #5 clk = ~clk;

    // Helper task to write config to a specific PE address
    task write_pe_config(
        input [1:0]  addr,
        input [15:0] conf
    );
        begin
            config_addr  = addr;
            config_data  = conf;
            config_valid = 1'b1;
            @(posedge clk);
            #1;
            config_valid = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        // Setup waveforms dump
        $dumpfile("tb_cgra_mesh.vcd");
        $dumpvars(0, tb_cgra_mesh);

        // Initialize all inputs
        clk          = 1'b0;
        rst          = 1'b1;
        en           = 1'b0;
        config_addr  = 2'b00;
        config_data  = 16'h0000;
        config_valid = 1'b0;
        
        data_n_0     = 8'sd0;
        data_n_1     = 8'sd0;
        data_s_0     = 8'sd0;
        data_s_1     = 8'sd0;
        data_e_0     = 8'sd0;
        data_e_1     = 8'sd0;
        data_w_0     = 8'sd0;
        data_w_1     = 8'sd0;
        
        data_global  = 8'sd0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk);
        #1;

        // Verify initial reset output state
        if (out_n_0 !== 8'sd0 || out_s_0 !== 8'sd0 || out_e_0 !== 8'sd0 || out_w_0 !== 8'sd0 ||
            out_n_1 !== 8'sd0 || out_s_1 !== 8'sd0 || out_e_1 !== 8'sd0 || out_w_1 !== 8'sd0) begin
            $display("[FAIL] Initial mesh outputs are not zero after reset.");
            $finish;
        end
        $display("[PASS] Reset outputs verified.");

        // ==========================================
        // Test Case 1: Routing Pipeline
        // Configure a pipeline route:
        //   data_n_0 (North boundary of PE00)
        //   -> PE00: Pass North input to South output (config: dest=010 (South), op=10 (Pass A), src_a=000 (North) -> 16'h0280)
        //   -> PE10: Pass North input to East output  (config: dest=011 (East),  op=10 (Pass A), src_a=000 (North) -> 16'h0380)
        //   -> PE11: Pass West input to East output   (config: dest=011 (East),  op=10 (Pass A), src_a=011 (West)  -> 16'h0383)
        // Expected total latency: 3 cycles (1 per registered accumulator stage)
        // Output visible at boundary out_e_1 (PE11 East output)
        // ==========================================
        $display("Test Case 1: Routing Pipeline Configuration...");
        write_pe_config(2'b00, 16'h0280); // PE00 Config
        write_pe_config(2'b10, 16'h0380); // PE10 Config
        write_pe_config(2'b11, 16'h0383); // PE11 Config

        data_n_0 = 8'sd75; // Set boundary input on PE00 North
        en = 1'b1;         // Enable execution

        // Cycle 1: PE00 registers input 75, sets out_s = 75
        @(posedge clk);
        #1;
        $display("Cycle 1 complete: PE00 out_s=%d (Expected 75)", dut.pe00.out_s);
        if (dut.pe00.out_s !== 8'sd75) begin
            $display("[FAIL] PE00 out_s mismatch. Expected 75, got %d", dut.pe00.out_s);
            $finish;
        end

        // Cycle 2: PE10 registers input 75 from PE00, sets out_e = 75
        @(posedge clk);
        #1;
        $display("Cycle 2 complete: PE10 out_e=%d (Expected 75)", dut.pe10.out_e);
        if (dut.pe10.out_e !== 8'sd75) begin
            $display("[FAIL] PE10 out_e mismatch. Expected 75, got %d", dut.pe10.out_e);
            $finish;
        end

        // Cycle 3: PE11 registers input 75 from PE10, sets out_e_1 = 75
        @(posedge clk);
        #1;
        $display("Cycle 3 complete: Top-level out_e_1=%d (Expected 75)", out_e_1);
        if (out_e_1 !== 8'sd75) begin
            $display("[FAIL] Pipeline output out_e_1 mismatch. Expected 75, got %d", out_e_1);
            $finish;
        end

        en = 1'b0;
        $display("[PASS] Routing pipeline verification successful.");

        // ==========================================
        // Test Case 2: Parallel Multi-op and Saturation
        // Configure PE00 to perform addition on boundary inputs:
        //   PE00: add North and West inputs, route to West (config: dest=100 (West), op=01 (ADD), src_b=011 (West), src_a=000 (North) -> 16'h0458)
        // Configure PE01 to perform Multiply-Accumulate:
        //   PE01: acc + (North * East), route to North (config: dest=001 (North), op=00 (MAC), src_b=010 (East), src_a=000 (North) -> 16'h0110)
        // Configure PE11 to perform Addition and saturate:
        //   PE11: add East and South, route to South (config: dest=010 (South), op=01 (ADD), src_b=001 (South), src_a=010 (East) -> 16'h024a)
        // ==========================================
        $display("Test Case 2: Parallel Multi-op and Saturation...");
        
        // Reset accumulators
        rst = 1'b1;
        @(posedge clk);
        #1;
        rst = 1'b0;
        @(posedge clk);
        #1;

        write_pe_config(2'b00, 16'h0458); // PE00 config
        write_pe_config(2'b01, 16'h0110); // PE01 config
        write_pe_config(2'b11, 16'h024a); // PE11 config

        // Inputs for PE00
        data_n_0 = 8'sd30;
        data_w_0 = -8'sd12;
        // Expected addition output: 30 + (-12) = 18. Routed to out_w_0.

        // Inputs for PE01
        data_n_1 = 8'sd5;
        data_e_0 = 8'sd8;
        // Expected MAC output: 0 + (5 * 8) = 40. Routed to out_n_1.

        // Inputs for PE11
        data_e_1 = 8'sd100;
        data_s_1 = 8'sd50;
        // Expected Addition: 100 + 50 = 150. Saturated to 127. Routed to out_s_1.

        en = 1'b1;
        @(posedge clk);
        #1;
        en = 1'b0;

        // Assertions
        if (out_w_0 !== 8'sd18) begin
            $display("[FAIL] PE00 parallel Add failed. Expected 18, got %d", out_w_0);
            $finish;
        end
        $display("[PASS] PE00 Addition: %d", out_w_0);

        if (out_n_1 !== 8'sd40) begin
            $display("[FAIL] PE01 parallel MAC failed. Expected 40, got %d", out_n_1);
            $finish;
        end
        $display("[PASS] PE01 Multiply-Accumulate: %d", out_n_1);

        if (out_s_1 !== 8'sd127) begin
            $display("[FAIL] PE11 parallel Saturation failed. Expected 127, got %d", out_s_1);
            $finish;
        end
        $display("[PASS] PE11 Saturated Addition: %d", out_s_1);

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
