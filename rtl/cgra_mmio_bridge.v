/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Native Memory-Mapped I/O Bridge for CGRA Accelerator.
 * Translates 32-bit native memory transactions into VLIW instructions and boundary data.
 */

`default_nettype none

module cgra_mmio_bridge #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter INST_WIDTH = ROWS * COLS * 16
) (
    input  wire                     clk,
    input  wire                     rst,
    
    // Native Memory Interface
    input  wire                     mem_valid,
    output reg                      mem_ready,
    input  wire [31:0]              mem_addr,
    input  wire [31:0]              mem_wdata,
    input  wire [3:0]               mem_wstrb,
    output reg  [31:0]              mem_rdata,

    // CGRA Programming Interface
    output reg                      inst_write_en,
    output reg  [4:0]               inst_write_addr,
    output reg  [INST_WIDTH-1:0]    inst_write_data,
    
    // CGRA Control Interface
    output reg                      start,
    output reg                      stop,
    output reg                      step,
    output reg                      loop_en,
    input  wire [4:0]               pc,
    input  wire                     running,
    
    // CGRA Boundary Data Inputs
    output reg  [(COLS*8)-1:0]      data_n,
    output reg  [(COLS*8)-1:0]      data_s,
    output reg  [(ROWS*8)-1:0]      data_e,
    output reg  [(ROWS*8)-1:0]      data_w,
    output reg signed [7:0]         data_global,
    
    // CGRA Boundary Data Outputs
    input  wire [(COLS*8)-1:0]      out_n,
    input  wire [(COLS*8)-1:0]      out_s,
    input  wire [(ROWS*8)-1:0]      out_e,
    input  wire [(ROWS*8)-1:0]      out_w
);

    // Staging register for VLIW microcode (256 bits for 4x4)
    reg [INST_WIDTH-1:0] staging_inst;

    always @(posedge clk) begin
        if (rst) begin
            mem_ready <= 1'b0;
            mem_rdata <= 32'b0;
            
            inst_write_en <= 1'b0;
            inst_write_addr <= 5'b0;
            inst_write_data <= {INST_WIDTH{1'b0}};
            staging_inst <= {INST_WIDTH{1'b0}};
            
            start <= 1'b0;
            stop <= 1'b0;
            step <= 1'b0;
            loop_en <= 1'b0;
            
            data_n <= 0; data_s <= 0;
            data_e <= 0; data_w <= 0;
            data_global <= 0;
        end else begin
            // Default pulse signals to 0
            mem_ready <= 1'b0;
            inst_write_en <= 1'b0;
            start <= 1'b0;
            stop <= 1'b0;
            step <= 1'b0;

            if (mem_valid && !mem_ready) begin
                mem_ready <= 1'b1;

                if (mem_addr[31:16] == 16'h4000) begin
                    if (|mem_wstrb) begin
                        // ----------------- WRITE -----------------
                        if (mem_addr[15:8] == 8'h00) begin
                            // 0x4000_00XX: Staging Register Chunks
                            begin : stage_chunk
                                integer i;
                                for (i = 0; i < (INST_WIDTH/32); i = i + 1) begin
                                    if (mem_addr[7:2] == i) begin
                                        staging_inst[i*32 +: 32] <= mem_wdata;
                                    end
                                end
                            end
                        end else if (mem_addr[15:0] == 16'h1000) begin
                            // 0x4000_1000: CSR Write
                            start <= mem_wdata[0];
                            stop <= mem_wdata[1];
                            step <= mem_wdata[2];
                            loop_en <= mem_wdata[3];
                        end else if (mem_addr[15:0] == 16'h1004) begin
                            // 0x4000_1004: COMMIT INSTRUCTION
                            inst_write_addr <= mem_wdata[4:0];
                            inst_write_data <= staging_inst;
                            inst_write_en <= 1'b1;
                        end else if (mem_addr[15:0] == 16'h1100) begin
                            data_n <= mem_wdata[(COLS*8)-1:0];
                        end else if (mem_addr[15:0] == 16'h1104) begin
                            data_s <= mem_wdata[(COLS*8)-1:0];
                        end else if (mem_addr[15:0] == 16'h1108) begin
                            data_e <= mem_wdata[(ROWS*8)-1:0];
                        end else if (mem_addr[15:0] == 16'h110C) begin
                            data_w <= mem_wdata[(ROWS*8)-1:0];
                        end else if (mem_addr[15:0] == 16'h1110) begin
                            data_global <= mem_wdata[7:0];
                        end
                    end else begin
                        // ----------------- READ -----------------
                        if (mem_addr[15:0] == 16'h1000) begin
                            mem_rdata <= {27'b0, pc, running, loop_en, step, stop, start};
                        end else if (mem_addr[15:0] == 16'h1200) begin
                            mem_rdata <= {{(32-COLS*8){1'b0}}, out_n};
                        end else if (mem_addr[15:0] == 16'h1204) begin
                            mem_rdata <= {{(32-COLS*8){1'b0}}, out_s};
                        end else if (mem_addr[15:0] == 16'h1208) begin
                            mem_rdata <= {{(32-ROWS*8){1'b0}}, out_e};
                        end else if (mem_addr[15:0] == 16'h120C) begin
                            mem_rdata <= {{(32-ROWS*8){1'b0}}, out_w};
                        end else begin
                            mem_rdata <= 32'b0;
                        end
                    end
                end
            end
        end
    end
endmodule
