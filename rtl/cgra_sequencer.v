/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * VLIW Instruction Sequencer for CGRA Mesh
 * Stores up to 32 instructions of INST_WIDTH bits.
 * Each instruction configures the entire mesh simultaneously.
 */

`default_nettype none

module cgra_sequencer #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter INST_WIDTH = ROWS * COLS * 16
) (
    input  wire                     clk,
    input  wire                     rst,
    
    // Instruction Programming Interface
    input  wire                     inst_write_en,
    input  wire [4:0]               inst_write_addr,
    input  wire [INST_WIDTH-1:0]    inst_write_data,
    
    // Sequencer Control Interface
    input  wire                     start,
    input  wire                     stop,
    input  wire                     step,
    input  wire                     loop_en,
    output reg  [4:0]               pc,
    output reg                      running,
    
    // CGRA Mesh Control Interface
    output wire [$clog2(ROWS*COLS)-1:0] mesh_config_addr, // Not used in VLIW mode, keep for port compatibility
    output reg  [INST_WIDTH-1:0]    mesh_config_data,
    output reg                      mesh_config_valid,
    output reg                      mesh_en
);

    assign mesh_config_addr = 0; // Broadcasting to all PEs simultaneously

    // Instruction Memory Array: 32 words of INST_WIDTH
    reg [INST_WIDTH-1:0] inst_mem [31:0];

    // Weight/Instruction Programming
    always @(posedge clk) begin
        if (inst_write_en) begin
            inst_mem[inst_write_addr] <= inst_write_data;
        end
    end

    // State Machine States
    localparam [1:0] STATE_IDLE   = 2'd0;
    localparam [1:0] STATE_CFG    = 2'd1;
    localparam [1:0] STATE_EXEC   = 2'd2;
    localparam [1:0] STATE_NEXT   = 2'd3;

    reg [1:0] state;
    reg       step_mode;

    // Fetch the currently addressed microcode word
    wire [INST_WIDTH-1:0] current_instruction = inst_mem[pc];

    always @(posedge clk) begin
        if (rst) begin
            state             <= STATE_IDLE;
            pc                <= 5'd0;
            running           <= 1'b0;
            step_mode         <= 1'b0;
            mesh_config_data  <= {INST_WIDTH{1'b0}};
            mesh_config_valid <= 1'b0;
            mesh_en           <= 1'b0;
        end else begin
            // Default signals
            mesh_config_valid <= 1'b0;
            mesh_en           <= 1'b0;

            if (stop) begin
                state   <= STATE_IDLE;
                running <= 1'b0;
            end else begin
                case (state)
                    STATE_IDLE: begin
                        if (start) begin
                            pc        <= 5'd0;
                            running   <= 1'b1;
                            step_mode <= 1'b0;
                            state     <= STATE_CFG;
                        end else if (step) begin
                            running   <= 1'b1;
                            step_mode <= 1'b1;
                            state     <= STATE_CFG;
                        end
                    end

                    STATE_CFG: begin
                        mesh_config_data  <= current_instruction;
                        mesh_config_valid <= 1'b1;
                        state             <= STATE_EXEC;
                    end

                    STATE_EXEC: begin
                        mesh_en <= 1'b1; // Trigger calculation for 1 clock cycle
                        state   <= STATE_NEXT;
                    end

                    STATE_NEXT: begin
                        if (step_mode) begin
                            if (pc == 5'd31) begin
                                pc <= 5'd0;
                            end else begin
                                pc <= pc + 5'd1;
                            end
                            running <= 1'b0;
                            state <= STATE_IDLE;
                        end else if (running) begin
                            if (pc == 5'd31) begin
                                if (loop_en) begin
                                    pc    <= 5'd0;
                                    state <= STATE_CFG;
                                end else begin
                                    running <= 1'b0;
                                    state   <= STATE_IDLE;
                                end
                            end else begin
                                pc    <= pc + 5'd1;
                                state <= STATE_CFG;
                            end
                        end else begin
                            state <= STATE_IDLE;
                        end
                    end

                    default: state <= STATE_IDLE;
                endcase
            end
        end
    end

endmodule
