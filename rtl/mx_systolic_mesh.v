/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Parameterized NxN Microscaled Systolic Array Grid
 * Instantiates N*N Processing Elements (PEs) in a grid using generate loops.
 * Supports 8-bit data propagation and propagates the reconfigurable formatting modes.
 */

`default_nettype none

module mx_systolic_mesh #(
    parameter N = 4,
    parameter ADDR_W = (N > 1) ? $clog2(N) : 1
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     clear,
    input  wire                     en,
    input  wire                     shift_en,
    input  wire                     dataflow_mode_sel,
    input  wire                     w_write_en,
    input  wire [1:0]               format_mode,
    
    // Weight programming coordinates (WS mode)
    input  wire [ADDR_W-1:0]        w_addr_row,
    input  wire [ADDR_W-1:0]        w_addr_col,
    input  wire signed [7:0]        w_data_in,
    
    // Activation inputs from the West boundary (aligned 8-bit)
    input  wire signed [N*8-1:0]    act_in_flat,
    
    // Weight inputs from the North boundary (OS mode)
    input  wire signed [N*8-1:0]    weight_in_flat,
    
    // Partial sum inputs from the North boundary (usually zeroed)
    input  wire signed [N*16-1:0]   psum_in_flat,
    
    // Shared exponents/scale factors for microscaling boundary calculation
    input  wire signed [7:0]        scale_act,
    input  wire signed [7:0]        scale_weight,
    
    // Boundary outputs exiting from the South
    output wire signed [N*16-1:0]   out_flat
);

    /* verilator lint_off UNUSEDSIGNAL */
    // Interconnect wires for activations (horizontal propagation, 8-bit)
    wire signed [7:0]  act_wire  [0:N-1][0:N];
    // Interconnect wires for weights (vertical propagation, 8-bit)
    wire signed [7:0]  wt_wire   [0:N][0:N-1];
    /* verilator lint_on UNUSEDSIGNAL */

    // Interconnect wires for partial sums (vertical propagation)
    wire signed [15:0] psum_wire [0:N][0:N-1];

    // Connect boundary inputs to wire grids
    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : boundary_gen
            assign act_wire[i][0]    = act_in_flat[i*8 +: 8];
            assign wt_wire[0][i]     = weight_in_flat[i*8 +: 8];
            assign psum_wire[0][i]   = psum_in_flat[i*16 +: 16];
        end
    endgenerate

    // 2D grid instantiations of PEs
    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : row_gen
            for (c = 0; c < N; c = c + 1) begin : col_gen
                wire w_en = w_write_en && (w_addr_row == r) && (w_addr_col == c);
                
                mx_pe pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .clear(clear),
                    .en(en),
                    .shift_en(shift_en),
                    .dataflow_mode_sel(dataflow_mode_sel),
                    .w_write_en(w_en),
                    .format_mode(format_mode),
                    .w_data_in(w_data_in),
                    .act_in(act_wire[r][c]),
                    .weight_in(wt_wire[r][c]),
                    .partial_sum_in(psum_wire[r][c]),
                    .act_out(act_wire[r][c+1]),
                    .weight_out(wt_wire[r+1][c]),
                    .partial_sum_out(psum_wire[r+1][c])
                );
            end
        end
    endgenerate

    // ----------------------------------------------------
    // Boundary Microscaling arithmetic shift & saturation logic
    // ----------------------------------------------------
    
    function signed [15:0] scale_and_saturate(
        input signed [15:0] val,
        input signed [7:0]  shift_val
    );
        reg signed [31:0] temp_val;
        begin
            temp_val = {{16{val[15]}}, val};
            if (shift_val >= 8'sd0) begin
                temp_val = temp_val <<< shift_val;
            end else begin
                temp_val = temp_val >>> (-shift_val);
            end
            
            // Saturation clamping to signed 16-bit limits: [-32768, 32767]
            if (temp_val > 32'sd32767) begin
                scale_and_saturate = 16'sd32767;
            end else if (temp_val < -32'sd32768) begin
                scale_and_saturate = -16'sd32768;
            end else begin
                scale_and_saturate = temp_val[15:0];
            end
        end
    endfunction

    // Sum of shared exponents/scale factors
    wire signed [7:0] total_exponent = scale_act + scale_weight;

    // Connect final bottom row of partial sums to registered boundary outputs
    reg signed [N*16-1:0] r_out_flat;
    integer out_idx;
    always @(posedge clk) begin
        if (rst) begin
            r_out_flat <= {N*16{1'b0}};
        end else if (en) begin
            for (out_idx = 0; out_idx < N; out_idx = out_idx + 1) begin
                r_out_flat[out_idx*16 +: 16] <= scale_and_saturate(psum_wire[N][out_idx], total_exponent);
            end
        end
    end

    assign out_flat = r_out_flat;

endmodule
