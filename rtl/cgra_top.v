/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Top-level wrapper module for the programmable CGRA accelerator.
 * Combines the instruction sequencer and the generic NxM 2D mesh grid.
 */

`default_nettype none

module cgra_top #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter INST_WIDTH = ROWS * COLS * 16
) (
    input  wire                     clk,
    input  wire                     rst,
    
    // Instruction Programming Interface (from MMIO bridge)
    input  wire                     inst_write_en,
    input  wire [4:0]               inst_write_addr,
    input  wire [INST_WIDTH-1:0]    inst_write_data,
    
    // Sequencer Control Interface
    input  wire                     start,
    input  wire                     stop,
    input  wire                     step,
    input  wire                     loop_en,
    output wire [4:0]               pc,
    output wire                     running,
    
    // Boundary data inputs
    input  wire [(COLS*8)-1:0]      data_n,
    input  wire [(COLS*8)-1:0]      data_s,
    input  wire [(ROWS*8)-1:0]      data_e,
    input  wire [(ROWS*8)-1:0]      data_w,
    input  wire signed [7:0]        data_global,
    
    // Boundary data outputs
    output wire [(COLS*8)-1:0]      out_n,
    output wire [(COLS*8)-1:0]      out_s,
    output wire [(ROWS*8)-1:0]      out_e,
    output wire [(ROWS*8)-1:0]      out_w
);

    // Internal connection signals
    wire [$clog2(ROWS*COLS)-1:0] mesh_config_addr;
    wire [INST_WIDTH-1:0]        mesh_config_data;
    wire                         mesh_config_valid;
    wire                         mesh_en;

    // Instantiate CGRA instruction sequencer
    cgra_sequencer #(
        .ROWS(ROWS),
        .COLS(COLS)
    ) sequencer (
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

    // Instantiate CGRA mesh grid
    cgra_mesh #(
        .ROWS(ROWS),
        .COLS(COLS)
    ) mesh (
        .clk(clk),
        .rst(rst),
        .en(mesh_en),
        .config_addr(mesh_config_addr),
        .config_data(mesh_config_data),
        .config_valid(mesh_config_valid),
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

endmodule
