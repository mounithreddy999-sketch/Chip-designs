/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * 2D Coarse-Grained Reconfigurable Architecture (CGRA) Mesh Accelerator
 * Instantiates a ROWS x COLS grid of cgra_pe nodes.
 */

`default_nettype none

module cgra_mesh #(
    parameter ROWS = 4,
    parameter COLS = 4
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     en,
    input  wire [$clog2(ROWS*COLS)-1:0] config_addr,
    input  wire [(ROWS*COLS*16)-1:0] config_data,   // 16-bits per PE, flattened
    input  wire                     config_valid,
    
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

    // Wires for inter-PE routing
    wire [7:0] pe_out_n [0:ROWS-1][0:COLS-1];
    wire [7:0] pe_out_s [0:ROWS-1][0:COLS-1];
    wire [7:0] pe_out_e [0:ROWS-1][0:COLS-1];
    wire [7:0] pe_out_w [0:ROWS-1][0:COLS-1];

    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : row
            for (c = 0; c < COLS; c = c + 1) begin : col
                // PE Configuration
                wire pe_config_valid = config_valid; // In a VLIW architecture, all PEs configure simultaneously
                wire [15:0] pe_config_data = config_data[((r*COLS + c)*16) +: 16];

                // Input Muxes for boundaries
                wire [7:0] in_n = (r == 0)        ? data_n[(c*8) +: 8] : pe_out_s[r-1][c];
                wire [7:0] in_s = (r == ROWS-1)   ? data_s[(c*8) +: 8] : pe_out_n[r+1][c];
                wire [7:0] in_e = (c == COLS-1)   ? data_e[(r*8) +: 8] : pe_out_w[r][c+1];
                wire [7:0] in_w = (c == 0)        ? data_w[(r*8) +: 8] : pe_out_e[r][c-1];

                cgra_pe pe (
                    .clk(clk),
                    .rst(rst),
                    .en(en),
                    .config_data(pe_config_data),
                    .config_valid(pe_config_valid),
                    
                    .data_n(in_n),
                    .data_s(in_s),
                    .data_e(in_e),
                    .data_w(in_w),
                    .data_global(data_global),
                    
                    .out_n(pe_out_n[r][c]),
                    .out_s(pe_out_s[r][c]),
                    .out_e(pe_out_e[r][c]),
                    .out_w(pe_out_w[r][c])
                );
            end
        end
    endgenerate

    // Assign Boundary Outputs
    generate
        for (c = 0; c < COLS; c = c + 1) begin : out_cols
            assign out_n[(c*8) +: 8] = pe_out_n[0][c];
            assign out_s[(c*8) +: 8] = pe_out_s[ROWS-1][c];
        end
        for (r = 0; r < ROWS; r = r + 1) begin : out_rows
            assign out_w[(r*8) +: 8] = pe_out_w[r][0];
            assign out_e[(r*8) +: 8] = pe_out_e[r][COLS-1];
        end
    endgenerate

endmodule
