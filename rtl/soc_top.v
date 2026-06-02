/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * System-on-Chip (SoC) Top-Level Module.
 * Integrates the PicoRV32 processor, Block RAM (soc_mem), and the
 * CGRA accelerator (via cgra_mmio_bridge).
 */

`default_nettype none

module soc_top (
    input  wire clk,
    input  wire rst,
    output wire trap,
    
    // Testbench observability ports
    output reg        test_done,
    output reg [31:0] test_result
);

    // ----------------------------------------------------
    // PicoRV32 Native Memory Interface
    // ----------------------------------------------------
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wstrb;
    wire [31:0] mem_rdata;

    picorv32 #(
        .COMPRESSED_ISA(1),
        .ENABLE_MUL(1),
        .ENABLE_DIV(1),
        .ENABLE_IRQ(0)
    ) cpu (
        .clk         (clk),
        .resetn      (~rst),
        .trap        (trap),
        .mem_valid   (mem_valid),
        .mem_instr   (mem_instr),
        .mem_ready   (mem_ready),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb),
        .mem_rdata   (mem_rdata)
    );

    // ----------------------------------------------------
    // Address Decoding
    // ----------------------------------------------------
    wire slave_mem_sel  = (mem_addr[31:16] == 16'h0000);
    wire slave_cgra_sel = (mem_addr[31:16] == 16'h4000);
    wire slave_test_sel = (mem_addr[31:16] == 16'h8000);

    wire slave_mem_valid  = mem_valid && slave_mem_sel;
    wire slave_cgra_valid = mem_valid && slave_cgra_sel;
    wire slave_test_valid = mem_valid && slave_test_sel;

    wire        slave_mem_ready;
    wire [31:0] slave_mem_rdata;

    wire        slave_cgra_ready;
    wire [31:0] slave_cgra_rdata;
    
    reg         slave_test_ready;

    assign mem_ready = slave_mem_sel  ? slave_mem_ready  :
                       slave_cgra_sel ? slave_cgra_ready : 
                       slave_test_sel ? slave_test_ready : 1'b0;

    assign mem_rdata = slave_mem_sel  ? slave_mem_rdata  :
                       slave_cgra_sel ? slave_cgra_rdata : 32'b0;

    // ----------------------------------------------------
    // Slave 2: Testbench MMIO
    // ----------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            slave_test_ready <= 1'b0;
            test_done <= 1'b0;
            test_result <= 32'b0;
        end else begin
            slave_test_ready <= 1'b0;
            if (slave_test_valid && !slave_test_ready) begin
                slave_test_ready <= 1'b1;
                if (|mem_wstrb) begin
                    if (mem_addr[15:0] == 16'h0000) test_result <= mem_wdata;
                    if (mem_addr[15:0] == 16'h0004) test_done <= mem_wdata[0];
                end
            end
        end
    end

    // ----------------------------------------------------
    // Slave 0: Main SoC Memory (64 KB)
    // ----------------------------------------------------
    soc_mem #(
        .MEM_SIZE(16384) // 16K x 32-bit = 64KB
    ) memory (
        .clk        (clk),
        .mem_valid  (slave_mem_valid),
        .mem_ready  (slave_mem_ready),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_wstrb  (mem_wstrb),
        .mem_rdata  (slave_mem_rdata)
    );

    // ----------------------------------------------------
    // Slave 1: CGRA Accelerator Subsystem
    // ----------------------------------------------------
    
    // CGRA Programming Interface
    wire        cgra_inst_write_en;
    wire [4:0]  cgra_inst_write_addr;
    wire [255:0] cgra_inst_write_data;
    
    // CGRA Control Interface
    wire        cgra_start;
    wire        cgra_stop;
    wire        cgra_step;
    wire        cgra_loop_en;
    wire [4:0]  cgra_pc;
    wire        cgra_running;
    
    // CGRA Boundary Data
    wire [31:0] cgra_data_n, cgra_data_s, cgra_data_e, cgra_data_w;
    wire [31:0] cgra_out_n, cgra_out_s, cgra_out_e, cgra_out_w;
    wire signed [7:0] cgra_data_global;

    cgra_mmio_bridge cgra_bridge (
        .clk(clk),
        .rst(rst),
        .mem_valid(slave_cgra_valid),
        .mem_ready(slave_cgra_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(slave_cgra_rdata),
        
        .inst_write_en(cgra_inst_write_en),
        .inst_write_addr(cgra_inst_write_addr),
        .inst_write_data(cgra_inst_write_data),
        
        .start(cgra_start),
        .stop(cgra_stop),
        .step(cgra_step),
        .loop_en(cgra_loop_en),
        .pc(cgra_pc),
        .running(cgra_running),
        
        .data_n(cgra_data_n),
        .data_s(cgra_data_s),
        .data_e(cgra_data_e),
        .data_w(cgra_data_w),
        .data_global(cgra_data_global),
        
        .out_n(cgra_out_n),
        .out_s(cgra_out_s),
        .out_e(cgra_out_e),
        .out_w(cgra_out_w)
    );

    cgra_top cgra_core (
        .clk(clk),
        .rst(rst),
        
        .inst_write_en(cgra_inst_write_en),
        .inst_write_addr(cgra_inst_write_addr),
        .inst_write_data(cgra_inst_write_data),
        
        .start(cgra_start),
        .stop(cgra_stop),
        .step(cgra_step),
        .loop_en(cgra_loop_en),
        .pc(cgra_pc),
        .running(cgra_running),
        
        .data_n(cgra_data_n),
        .data_s(cgra_data_s),
        .data_e(cgra_data_e),
        .data_w(cgra_data_w),
        .data_global(cgra_data_global),
        
        .out_n(cgra_out_n),
        .out_s(cgra_out_s),
        .out_e(cgra_out_e),
        .out_w(cgra_out_w)
    );

endmodule
