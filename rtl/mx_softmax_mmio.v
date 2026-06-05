/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Native Memory-Mapped I/O Bridge for MX Softmax Unit.
 */

`default_nettype none

module mx_softmax_mmio #(
    parameter N = 4
) (
    input  wire                     clk,
    input  wire                     rst,
    
    // Native Memory Interface
    input  wire                     mem_valid,
    output reg                      mem_ready,
    input  wire [31:0]              mem_addr,
    input  wire [31:0]              mem_wdata,
    input  wire [3:0]               mem_wstrb,
    output reg  [31:0]              mem_rdata
);

    reg  [63:0] in_data_reg;
    wire [63:0] out_data_wire;
    reg         start_pulse;
    wire        out_valid_wire;
    reg         busy;
    reg         result_ready;
    reg  [63:0] out_data_reg;

    mx_softmax_unit #(
        .N(N)
    ) softmax_core (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .start(start_pulse),
        .in_flat(in_data_reg),
        .out_valid(out_valid_wire),
        .out_flat(out_data_wire)
    );

    always @(posedge clk) begin
        if (rst) begin
            mem_ready    <= 1'b0;
            mem_rdata    <= 32'b0;
            in_data_reg  <= 64'b0;
            out_data_reg <= 64'b0;
            start_pulse  <= 1'b0;
            busy         <= 1'b0;
            result_ready <= 1'b0;
        end else begin
            mem_ready   <= 1'b0;
            start_pulse <= 1'b0;

            // Capture core output
            if (out_valid_wire) begin
                out_data_reg <= out_data_wire;
                result_ready <= 1'b1;
                busy         <= 1'b0;
            end

            if (mem_valid && !mem_ready) begin
                mem_ready <= 1'b1;
                
                if (|mem_wstrb) begin
                    // Write
                    if (mem_addr[7:0] == 8'h00) in_data_reg[31:0]  <= mem_wdata;
                    if (mem_addr[7:0] == 8'h04) in_data_reg[63:32] <= mem_wdata;
                    if (mem_addr[7:0] == 8'h08) begin
                        if (mem_wdata[0] && !busy) begin
                            start_pulse  <= 1'b1;
                            busy         <= 1'b1;
                            result_ready <= 1'b0;
                        end
                    end
                end else begin
                    // Read
                    if (mem_addr[7:0] == 8'h00) mem_rdata <= in_data_reg[31:0];
                    if (mem_addr[7:0] == 8'h04) mem_rdata <= in_data_reg[63:32];
                    if (mem_addr[7:0] == 8'h08) mem_rdata <= {30'b0, result_ready, busy};
                    if (mem_addr[7:0] == 8'h0C) mem_rdata <= out_data_reg[31:0];
                    if (mem_addr[7:0] == 8'h10) mem_rdata <= out_data_reg[63:32];
                end
            end
        end
    end
endmodule
