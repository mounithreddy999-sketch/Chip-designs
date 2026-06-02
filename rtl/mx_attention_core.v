/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Parameterized NxN Microscaled Attention Core Subsystem (Reconfigurable Floating Point Support)
 * Integrates:
 *   - Scratchpad SRAM (scratchpad_sram)
 *   - NxN Systolic Array Grid (mx_systolic_mesh)
 * Controls matrix loading, skewed streaming, dynamic dataflow routing,
 * exponent boundary alignment, shift-out logic, and boundary microscaling.
 */

`default_nettype none

module mx_attention_core #(
    parameter N = 4,
    parameter ADDR_W = (N > 1) ? $clog2(N) : 1
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     en,
    
    // Control interface
    input  wire                     start,             // Start execution pulse
    input  wire                     dataflow_mode_sel, // 0 = Weight-Stationary, 1 = Output-Stationary
    input  wire [1:0]               format_mode,       // 00 = MXINT4, 01 = MXFP4 (E2M1), 10 = MXFP8 (E4M3), 11 = MXFP8 (E5M2)
    output reg                      busy,              // High during active computation
    output reg                      done,              // High for 1 cycle on completion
    output reg                      out_valid,         // High when output matrix is valid
    
    // Scratchpad SRAM programming interface
    input  wire                     q_write_en,
    input  wire [6:0]               q_write_addr,
    input  wire [N*8-1:0]           q_write_data,
    input  wire                     k_write_en,
    input  wire [6:0]               k_write_addr,
    input  wire [N*8-1:0]           k_write_data,
    
    // Systolic weight programming interface (WS mode)
    input  wire                     w_write_en,
    input  wire [ADDR_W-1:0]        w_addr_row,
    input  wire [ADDR_W-1:0]        w_addr_col,
    input  wire signed [7:0]        w_data_in,
    
    // Shared exponents for microscaling scale factor
    input  wire signed [7:0]        scale_act,
    input  wire signed [7:0]        scale_weight,
    
    // Final NxN Output Matrix
    output wire signed [N*N*16-1:0] result_flat,
    
    // Backward-compatible individual 4x4 Output Matrix pins
    output wire signed [15:0]       result_00, output wire signed [15:0]       result_01,
    output wire signed [15:0]       result_02, output wire signed [15:0]       result_03,
    output wire signed [15:0]       result_10, output wire signed [15:0]       result_11,
    output wire signed [15:0]       result_12, output wire signed [15:0]       result_13,
    output wire signed [15:0]       result_20, output wire signed [15:0]       result_21,
    output wire signed [15:0]       result_22, output wire signed [15:0]       result_23,
    output wire signed [15:0]       result_30, output wire signed [15:0]       result_31,
    output wire signed [15:0]       result_32, output wire signed [15:0]       result_33
);

    // State definitions
    localparam STATE_IDLE    = 3'd0;
    localparam STATE_LOAD    = 3'd1;
    localparam STATE_RUN     = 3'd2;
    localparam STATE_SOFTMAX = 3'd3;
    localparam STATE_DONE    = 3'd4;

    reg [2:0] state;
    reg [4:0] load_counter;
    reg [5:0] run_counter;

    // Registers to hold tiles locally during execution (tiled buffer, expanded to 8-bit slots)
    reg [N*8-1:0] r_q_buffer [0:N-1];
    reg [N*8-1:0] r_k_buffer [0:N-1];
    
    // Final output storage matrix
    reg signed [15:0] r_result_matrix [0:N-1][0:N-1];

    // Generate flat output result
    genvar rg, cg;
    generate
        for (rg = 0; rg < N; rg = rg + 1) begin : flat_rg
            for (cg = 0; cg < N; cg = cg + 1) begin : flat_cg
                assign result_flat[(rg*N + cg)*16 +: 16] = r_result_matrix[rg][cg];
            end
        end
    endgenerate

    // Connect traditional individual pins to r_result_matrix if N >= 4, else to 0
    assign result_00 = (N >= 4) ? r_result_matrix[0][0] : 16'sd0;
    assign result_01 = (N >= 4) ? r_result_matrix[0][1] : 16'sd0;
    assign result_02 = (N >= 4) ? r_result_matrix[0][2] : 16'sd0;
    assign result_03 = (N >= 4) ? r_result_matrix[0][3] : 16'sd0;
    
    assign result_10 = (N >= 4) ? r_result_matrix[1][0] : 16'sd0;
    assign result_11 = (N >= 4) ? r_result_matrix[1][1] : 16'sd0;
    assign result_12 = (N >= 4) ? r_result_matrix[1][2] : 16'sd0;
    assign result_13 = (N >= 4) ? r_result_matrix[1][3] : 16'sd0;
    
    assign result_20 = (N >= 4) ? r_result_matrix[2][0] : 16'sd0;
    assign result_21 = (N >= 4) ? r_result_matrix[2][1] : 16'sd0;
    assign result_22 = (N >= 4) ? r_result_matrix[2][2] : 16'sd0;
    assign result_23 = (N >= 4) ? r_result_matrix[2][3] : 16'sd0;
    
    assign result_30 = (N >= 4) ? r_result_matrix[3][0] : 16'sd0;
    assign result_31 = (N >= 4) ? r_result_matrix[3][1] : 16'sd0;
    assign result_32 = (N >= 4) ? r_result_matrix[3][2] : 16'sd0;
    assign result_33 = (N >= 4) ? r_result_matrix[3][3] : 16'sd0;

    // SRAM internal read control
    reg  q_read_en;
    reg  k_read_en;
    reg  [6:0] q_read_addr;
    reg  [6:0] k_read_addr;
    wire [N*8-1:0] q_read_data;
    wire [N*8-1:0] k_read_data;

    // Instantiate Scratchpad SRAM (expanded to N*8)
    scratchpad_sram #(.N(N), .DATA_WIDTH(N*8)) sram (
        .clk(clk),
        .q_write_en(q_write_en),
        .q_write_addr(q_write_addr),
        .q_write_data(q_write_data),
        .q_read_en(q_read_en),
        .q_read_addr(q_read_addr),
        .q_read_data(q_read_data),
        .k_write_en(k_write_en),
        .k_write_addr(k_write_addr),
        .k_write_data(k_write_data),
        .k_read_en(k_read_en),
        .k_read_addr(k_read_addr),
        .k_read_data(k_read_data)
    );

    // Mesh control signals
    reg  mesh_en;
    reg  mesh_rst;
    reg  shift_en;
    wire [4:0] buf_idx = load_counter - 5'd1;

    // Skewed inputs (expanded to 8-bit)
    reg signed [7:0] act_in [0:N-1];
    reg signed [7:0] weight_in [0:N-1];
    
    wire signed [N*8-1:0] act_in_flat;
    wire signed [N*8-1:0] weight_in_flat;
    
    generate
        for (rg = 0; rg < N; rg = rg + 1) begin : act_flat_gen
            assign act_in_flat[rg*8 +: 8] = act_in[rg];
            assign weight_in_flat[rg*8 +: 8] = weight_in[rg];
        end
    endgenerate

    // ====================================================
    // West Boundary Exponent Alignment (Activations)
    // ====================================================
    reg [7:0] act_elem [0:N-1];
    reg       act_active [0:N-1];
    
    integer r_idx_e;
    always @(*) begin
        for (r_idx_e = 0; r_idx_e < N; r_idx_e = r_idx_e + 1) begin
            if (state == STATE_RUN && run_counter >= r_idx_e && run_counter <= r_idx_e + N - 1) begin
                act_elem[r_idx_e]   = r_q_buffer[r_idx_e][(run_counter - r_idx_e)*8 +: 8];
                act_active[r_idx_e] = 1'b1;
            end else begin
                act_elem[r_idx_e]   = 8'd0;
                act_active[r_idx_e] = 1'b0;
            end
        end
    end

    reg       elem_sign [0:N-1];
    reg [4:0] elem_exp  [0:N-1];
    reg [3:0] elem_mant [0:N-1];
    reg [4:0] bias;

    integer dec_idx;
    always @(*) begin
        bias = 5'd0;
        case (format_mode)
            2'b01:   bias = 5'd1;  // MXFP4
            2'b10:   bias = 5'd7;  // MXFP8 (E4M3)
            2'b11:   bias = 5'd15; // MXFP8 (E5M2)
            default: bias = 5'd0;
        endcase

        for (dec_idx = 0; dec_idx < N; dec_idx = dec_idx + 1) begin
            if (act_active[dec_idx]) begin
                case (format_mode)
                    2'b01: begin // MXFP4 (E2M1)
                        elem_sign[dec_idx] = act_elem[dec_idx][3];
                        elem_exp[dec_idx]  = {3'd0, act_elem[dec_idx][2:1]};
                        if (act_elem[dec_idx][2:1] == 2'b00) begin
                            elem_mant[dec_idx] = {3'b000, act_elem[dec_idx][0]}; // Subnormal
                        end else begin
                            elem_mant[dec_idx] = {3'b001, act_elem[dec_idx][0]}; // Normal
                        end
                    end
                    2'b10: begin // MXFP8 (E4M3)
                        elem_sign[dec_idx] = act_elem[dec_idx][7];
                        elem_exp[dec_idx]  = {1'b0, act_elem[dec_idx][6:3]};
                        if (act_elem[dec_idx][6:3] == 4'b0000) begin
                            elem_mant[dec_idx] = {1'b0, act_elem[dec_idx][2:0]}; // Subnormal
                        end else begin
                            elem_mant[dec_idx] = {1'b1, act_elem[dec_idx][2:0]}; // Normal
                        end
                    end
                    2'b11: begin // MXFP8 (E5M2)
                        elem_sign[dec_idx] = act_elem[dec_idx][7];
                        elem_exp[dec_idx]  = act_elem[dec_idx][6:2];
                        if (act_elem[dec_idx][6:2] == 5'b00000) begin
                            elem_mant[dec_idx] = {2'b00, act_elem[dec_idx][1:0]}; // Subnormal
                        end else begin
                            elem_mant[dec_idx] = {2'b01, act_elem[dec_idx][1:0]}; // Normal
                        end
                    end
                    default: begin // MXINT4
                        elem_sign[dec_idx] = act_elem[dec_idx][3];
                        elem_exp[dec_idx]  = 5'd0;
                        if (act_elem[dec_idx][3]) begin
                            elem_mant[dec_idx] = -act_elem[dec_idx][3:0];
                        end else begin
                            elem_mant[dec_idx] = act_elem[dec_idx][3:0];
                        end
                    end
                endcase
            end else begin
                elem_sign[dec_idx] = 1'b0;
                elem_exp[dec_idx]  = 5'd0;
                elem_mant[dec_idx] = 4'd0;
            end
        end
    end

    // Compute max exponent across active vector elements
    reg [4:0] e_max_act;
    integer e_idx;
    always @(*) begin
        e_max_act = 5'd0;
        for (e_idx = 0; e_idx < N; e_idx = e_idx + 1) begin
            if (act_active[e_idx] && elem_exp[e_idx] > e_max_act) begin
                e_max_act = elem_exp[e_idx];
            end
        end
    end

    // Align active elements to e_max_act
    integer a_idx;
    reg [3:0] shifted_mant;
    always @(*) begin
        for (a_idx = 0; a_idx < N; a_idx = a_idx + 1) begin
            if (act_active[a_idx]) begin
                if (format_mode == 2'b00) begin
                    act_in[a_idx] = act_elem[a_idx]; // Bypass
                end else begin
                    shifted_mant = elem_mant[a_idx] >> (e_max_act - elem_exp[a_idx]);
                    act_in[a_idx] = elem_sign[a_idx] ? -{4'd0, shifted_mant} : {4'd0, shifted_mant};
                end
            end else begin
                act_in[a_idx] = 8'sd0;
            end
        end
    end

    // Dynamic activation scale factor
    wire signed [7:0] scale_act_eff = (format_mode == 2'b00) ? scale_act : 
                                      (scale_act + $signed({3'd0, e_max_act}) - $signed({3'd0, bias}));

    // ====================================================
    // Column-Skewed Weight Generation (OS mode)
    // ====================================================
    integer ci;
    always @(*) begin
        for (ci = 0; ci < N; ci = ci + 1) begin
            if (state == STATE_RUN && dataflow_mode_sel && run_counter >= ci && run_counter <= ci + N - 1) begin
                weight_in[ci] = r_k_buffer[run_counter - ci][ci*8 +: 8];
            end else begin
                weight_in[ci] = 8'sd0;
            end
        end
    end

    // Output sums from the Southern mesh border
    wire signed [N*16-1:0] mesh_out_flat;

    // Instantiate NxN Systolic Mesh
    mx_systolic_mesh #(.N(N), .ADDR_W(ADDR_W)) mesh (
        .clk(clk),
        .rst(rst),
        .clear(mesh_rst),
        .en(mesh_en || w_write_en),
        .shift_en(shift_en),
        .dataflow_mode_sel(dataflow_mode_sel),
        .w_write_en(w_write_en),
        .format_mode(format_mode),
        .w_addr_row(w_addr_row),
        .w_addr_col(w_addr_col),
        .w_data_in(w_data_in),
        .act_in_flat(act_in_flat),
        .weight_in_flat(weight_in_flat),
        .psum_in_flat({N{16'sd0}}),
        .scale_act(scale_act_eff),
        .scale_weight(scale_weight),
        .out_flat(mesh_out_flat)
    );

    // ====================================================
    // State Machine and Control Logic
    // ====================================================
    integer r_idx, c_idx;
    always @(posedge clk) begin
        if (rst) begin
            state         <= STATE_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            out_valid     <= 1'b0;
            load_counter  <= 5'd0;
            run_counter   <= 6'd0;
            q_read_en     <= 1'b0;
            k_read_en     <= 1'b0;
            q_read_addr   <= 7'd0;
            k_read_addr   <= 7'd0;
            mesh_en       <= 1'b0;
            mesh_rst      <= 1'b1;
            shift_en      <= 1'b0;
            softmax_start <= 1'b0;

            // Clear buffers on reset
            for (r_idx = 0; r_idx < N; r_idx = r_idx + 1) begin
                r_q_buffer[r_idx] <= {N{8'd0}};
                r_k_buffer[r_idx] <= {N{8'd0}};
                for (c_idx = 0; c_idx < N; c_idx = c_idx + 1) begin
                    r_result_matrix[r_idx][c_idx] <= 16'sd0;
                end
            end
        end else begin
            case (state)
                
                STATE_IDLE: begin
                    done          <= 1'b0;
                    shift_en      <= 1'b0;
                    mesh_en       <= 1'b0;
                    mesh_rst      <= 1'b0;
                    softmax_start <= 1'b0;
                    
                    if (en && start) begin
                        busy         <= 1'b1;
                        out_valid    <= 1'b0;
                        load_counter <= 5'd0;
                        state        <= STATE_LOAD;
                        
                        // Setup first read address
                        q_read_en    <= 1'b1;
                        k_read_en    <= 1'b1;
                        q_read_addr  <= 7'd0;
                        k_read_addr  <= 7'd0;
                        
                        // Pulse mesh reset to clear PE accumulators
                        mesh_rst     <= 1'b1;
                    end
                end
                
                STATE_LOAD: begin
                    mesh_rst <= 1'b0; // Release mesh reset
                    
                    // Increment address reads to load SRAM data into registers
                    load_counter <= load_counter + 5'd1;
                    q_read_addr  <= q_read_addr + 7'd1;
                    k_read_addr  <= k_read_addr + 7'd1;
                    
                    // Store read outputs
                    if (load_counter >= 5'd1 && load_counter <= N) begin
                        r_q_buffer[buf_idx] <= q_read_data;
                        r_k_buffer[buf_idx] <= k_read_data;
                    end
                    
                    if (load_counter == N) begin
                        // SRAM data loaded in buffers, stop reading
                        q_read_en   <= 1'b0;
                        k_read_en   <= 1'b0;
                        run_counter <= 6'd0;
                        state       <= STATE_RUN;
                        mesh_en     <= 1'b1;
                    end
                end
                
                STATE_RUN: begin
                    run_counter <= run_counter + 6'd1;

                    if (dataflow_mode_sel == 1'b0) begin
                        // ----------------------------------------------------
                        // Weight-Stationary Mode Execution
                        // ----------------------------------------------------
                        
                        // Capture column outputs at their respective valid cycles (shifted by +1 due to registered mesh output)
                        for (r_idx = 0; r_idx < N; r_idx = r_idx + 1) begin
                            for (c_idx = 0; c_idx < N; c_idx = c_idx + 1) begin
                                if (run_counter == N + r_idx + c_idx + 6'd1) begin
                                    r_result_matrix[r_idx][c_idx] <= mesh_out_flat[c_idx*16 +: 16];
                                end
                            end
                        end

                        if (run_counter == 3*N - 1) begin
                            state         <= STATE_SOFTMAX;
                            mesh_en       <= 1'b0;
                            softmax_start <= 1'b1;
                        end
                    end else begin
                        // ----------------------------------------------------
                        // Output-Stationary Mode Execution
                        // ----------------------------------------------------
                        
                        // Dynamic accumulation completes after 3N-2 cycles (0 to 3N-3)
                        // Then we shift outputs down the columns (run_counter 3N-2 to 4N-3)
                        if (run_counter == 3*N - 3) begin
                            shift_en <= 1'b1;
                        end
                        
                        // Shift-out outputs arrive at the boundary 1 cycle later (3N-1 to 4N-2)
                        if (run_counter >= 3*N - 1 && run_counter <= 4*N - 2) begin
                            // Shifting row results from the southern boundary
                            for (c_idx = 0; c_idx < N; c_idx = c_idx + 1) begin
                                r_result_matrix[4*N - 2 - run_counter][c_idx] <= mesh_out_flat[c_idx*16 +: 16];
                            end
                            
                            if (run_counter == 4*N - 2) begin
                                state         <= STATE_SOFTMAX;
                                mesh_en       <= 1'b0;
                                shift_en      <= 1'b0;
                                softmax_start <= 1'b1;
                            end
                        end
                    end
                end
                
                STATE_SOFTMAX: begin
                    softmax_start <= 1'b0;
                    if (softmax_out_valid) begin
                        for (r_idx = 0; r_idx < N; r_idx = r_idx + 1) begin
                            for (c_idx = 0; c_idx < N; c_idx = c_idx + 1) begin
                                r_result_matrix[r_idx][c_idx] <= $signed(softmax_out_flat[(r_idx*N + c_idx)*16 +: 16]);
                            end
                        end
                        state <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    busy      <= 1'b0;
                    done      <= 1'b1;
                    out_valid <= 1'b1;
                    state     <= STATE_IDLE;
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

    // ----------------------------------------------------
    // Row-Wise Softmax Subsystem Integration
    // ----------------------------------------------------
    reg  softmax_start;
    wire softmax_out_valid;
    
    wire [N-1:0] softmax_out_valids;
    wire [N*N*16-1:0] softmax_in_flat;
    wire [N*N*16-1:0] softmax_out_flat;
    
    // Flatten result matrix row-wise for softmax input
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : softmax_flat_rg
            for (genvar c = 0; c < N; c = c + 1) begin : softmax_flat_cg
                assign softmax_in_flat[(g*N + c)*16 +: 16] = r_result_matrix[g][c];
            end
        end
    endgenerate
    
    // We only need one output valid flag, e.g. from the first unit, as they run in lockstep
    assign softmax_out_valid = softmax_out_valids[0];
    
    /* verilator lint_off UNUSEDSIGNAL */
    wire [N-1:0] unused_softmax_valids = softmax_out_valids;
    /* verilator lint_on UNUSEDSIGNAL */
    
    generate
        for (g = 0; g < N; g = g + 1) begin : softmax_gen
            mx_softmax_unit #(.N(N)) softmax_inst (
                .clk(clk), .rst(rst), .en(en), .start(softmax_start),
                .in_flat(softmax_in_flat[g*N*16 +: N*16]),
                .out_valid(softmax_out_valids[g]),
                .out_flat(softmax_out_flat[g*N*16 +: N*16])
            );
        end
    endgenerate

endmodule
