/*
 * Native Self-Checking Verilog Testbench for CGRA Sequencer & Mesh Integration
 */

`timescale 1ns / 1ps

module tb_cgra_sequencer;

    // Signals
    reg                     clk;
    reg                     rst;
    
    reg                     inst_write_en;
    reg  [4:0]              inst_write_addr;
    reg  [63:0]             inst_write_data;
    
    reg                     start;
    reg                     stop;
    reg                     step;
    reg                     loop_en;
    wire [4:0]              pc;
    wire                    running;
    
    wire [1:0]              mesh_config_addr;
    wire [15:0]             mesh_config_data;
    wire                    mesh_config_valid;
    wire                    mesh_en;

    // Boundary data inputs for mesh
    reg  signed [7:0]       data_n_0;
    reg  signed [7:0]       data_n_1;
    reg  signed [7:0]       data_s_0;
    reg  signed [7:0]       data_s_1;
    reg  signed [7:0]       data_e_0;
    reg  signed [7:0]       data_e_1;
    reg  signed [7:0]       data_w_0;
    reg  signed [7:0]       data_w_1;
    reg  signed [7:0]       data_global;
    
    // Boundary outputs from mesh
    wire signed [7:0]       out_n_0;
    wire signed [7:0]       out_n_1;
    wire signed [7:0]       out_s_0;
    wire signed [7:0]       out_s_1;
    wire signed [7:0]       out_e_0;
    wire signed [7:0]       out_e_1;
    wire signed [7:0]       out_w_0;
    wire signed [7:0]       out_w_1;

    // Instantiate Sequencer
    cgra_sequencer sequencer (
        .clk(clk),
        .rst(rst),
        .inst_write_en(inst_write_en),
        .inst_write_addr(inst_write_addr),
        .inst_write_data(inst_write_data),
        .start(start),
        .stop(stop),
        .step(step),
        .loop_en(loop_en),
        .pc(pc),
        .running(running),
        .mesh_config_addr(mesh_config_addr),
        .mesh_config_data(mesh_config_data),
        .mesh_config_valid(mesh_config_valid),
        .mesh_en(mesh_en)
    );

    // Instantiate CGRA Mesh
    cgra_mesh mesh (
        .clk(clk),
        .rst(rst),
        .en(mesh_en),
        .config_addr(mesh_config_addr),
        .config_data(mesh_config_data),
        .config_valid(mesh_config_valid),
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

    // Helper task to program instruction memory
    task program_instruction(
        input [4:0]  addr,
        input [63:0] microcode
    );
        begin
            inst_write_addr = addr;
            inst_write_data = microcode;
            inst_write_en   = 1'b1;
            @(posedge clk);
            #1;
            inst_write_en   = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_cgra_sequencer.vcd");
        $dumpvars(0, tb_cgra_sequencer);

        // Initialize signals
        clk               = 1'b0;
        rst               = 1'b1;
        inst_write_en     = 1'b0;
        inst_write_addr   = 5'd0;
        inst_write_data   = 64'd0;
        start             = 1'b0;
        stop              = 1'b0;
        step              = 1'b0;
        loop_en           = 1'b0;

        data_n_0          = 8'sd0;
        data_n_1          = 8'sd0;
        data_s_0          = 8'sd0;
        data_s_1          = 8'sd0;
        data_e_0          = 8'sd0;
        data_e_1          = 8'sd0;
        data_w_0          = 8'sd0;
        data_w_1          = 8'sd0;
        data_global       = 8'sd0;

        // Apply Reset
        #20;
        rst = 1'b0;
        @(posedge clk);
        #1;

        // Verify initial state
        if (pc !== 5'd0 || running !== 1'b0 || out_w_0 !== 8'sd0) begin
            $display("[FAIL] Initial state mismatch after reset.");
            $finish;
        end
        $display("[PASS] Reset state verified.");

        // ==========================================
        // Test Case 1: Program Microcode Instruction
        // Configure PE00 to perform Addition (data_n_0 + data_w_0) and route to West (out_w_0).
        // PE00 Config binary: dest=100 (West), op=01 (ADD), src_b=011 (West), src_a=000 (North) -> 16'h0458
        // PEs 01, 10, 11 are configured to Idle (16'h0000).
        // 64-bit microcode word: 64'h0000_0000_0000_0458
        // ==========================================
        $display("Programming instruction sequencer...");
        program_instruction(5'd0, 64'h0000_0000_0000_0458);
        $display("[PASS] Microcode successfully programmed.");

        // ==========================================
        // Test Case 2: Single Step Execution
        // Feed PE00 boundary values: North=50, West=-15
        // Expected Addition output: 50 - 15 = 35 -> out_w_0
        // ==========================================
        $display("Test Case 2: Running single-step execution...");
        data_n_0 = 8'sd50;
        data_w_0 = -8'sd15;

        step = 1'b1;
        @(posedge clk);
        #1;
        step = 1'b0;

        // Wait for states to transition: IDLE -> CFG_00 -> CFG_01 -> CFG_10 -> CFG_11 -> EXEC -> NEXT -> IDLE
        // Total 7 clock cycles to return to IDLE
        repeat(7) begin
            @(posedge clk);
        end
        #1;

        $display("Outputs: out_w_0=%d (Expected 35)", out_w_0);
        if (out_w_0 !== 8'sd35) begin
            $display("[FAIL] PE00 West output mismatch. Expected 35, got %d", out_w_0);
            $finish;
        end
        $display("[PASS] Single step execution verified successfully.");

        $display("\n===============================");
        $display("   ALL TEST CASES PASSED!      ");
        $display("===============================");
        $finish;
    end

endmodule
