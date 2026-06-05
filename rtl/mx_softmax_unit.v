/*
 * Row-Wise Softmax Unit
 * Computes softmax over an N-element row vector.
 * Uses PWL exponentiation and reciprocal modules in a 4-stage pipeline.
 */

`default_nettype none

module mx_softmax_unit #(
    parameter N = 4
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     en,
    input  wire                     start,
    input  wire signed [N*16-1:0]   in_flat,   // Q4.12 signed inputs
    output reg                      out_valid, // High when outputs are valid
    output reg  [N*16-1:0]          out_flat   // Q1.15 unsigned outputs
);

    // ----------------------------------------------------
    // Pipeline Registers
    // ----------------------------------------------------
    reg [2:0] pipe_counter;
    reg       pipe_active;

    // Stage 1 Registers
    reg signed [15:0] r_d [0:N-1];

    // Stage 2 Registers (Pipelined Exponents)
    reg [15:0] r_exp [0:N-1];

    // PWL Exponentiation Instantiations
    wire [15:0] exp_out [0:N-1];

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : exp_gen
            mx_pwl_exp exp0 (
                .clk(clk), .rst(rst), .en(en),
                .in_data(r_d[g]), .out_data(exp_out[g])
            );
        end
    endgenerate

    // Stage 3: Sum of Exponents & Reciprocal Instantiation
    reg  [15:0] r_sum_exp_q3_13;
    wire [15:0] recip_out;

    mx_pwl_recip recip0 (
        .clk(clk), .rst(rst), .en(en),
        .in_data(r_sum_exp_q3_13), .out_data(recip_out)
    );

    // ----------------------------------------------------
    // Pipeline Logic
    // ----------------------------------------------------
    
    // Stage 1: Max Finder & Difference Calculation
    reg signed [15:0] max_val;
    integer i, i_comb;
    always @(*) begin
        max_val = $signed(in_flat[0 +: 16]);
        for (i_comb = 1; i_comb < N; i_comb = i_comb + 1) begin
            if ($signed(in_flat[i_comb*16 +: 16]) > max_val) begin
                max_val = $signed(in_flat[i_comb*16 +: 16]);
            end
        end
    end

    // Stage 3 combinational sum of exponents
    // exp_out values are in Q1.15. Sum of N values can be up to N.
    // Shift right by 2 to get Q3.13. Clamp to 16'hFFFF to avoid overflow.
    reg [19:0] sum_exp_q1_15;
    always @(*) begin
        sum_exp_q1_15 = 20'd0;
        for (i_comb = 0; i_comb < N; i_comb = i_comb + 1) begin
            sum_exp_q1_15 = sum_exp_q1_15 + {4'd0, exp_out[i_comb]};
        end
    end

    /* verilator lint_off UNUSEDSIGNAL */
    wire [17:0] sum_exp_shifted = sum_exp_q1_15[19:2];
    /* verilator lint_on UNUSEDSIGNAL */
    wire [15:0] sum_exp_q3_13 = (sum_exp_shifted > 18'h0FFFF) ? 16'hFFFF : sum_exp_shifted[15:0];

    // Stage 4 Products: exp * recip
    // exp is Q1.15, recip is Q1.15. Product is Q2.30.
    // Shift by 15 to get Q1.15.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] prod [0:N-1];
    /* verilator lint_on UNUSEDSIGNAL */
    generate
        for (g = 0; g < N; g = g + 1) begin : prod_gen
            assign prod[g] = r_exp[g] * recip_out;
        end
    endgenerate

    wire [15:0] next_out [0:N-1];
    generate
        for (g = 0; g < N; g = g + 1) begin : next_out_gen
            assign next_out[g] = {1'b0, prod[g][29:15]};
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            pipe_counter      <= 3'd0;
            pipe_active       <= 1'b0;
            out_valid         <= 1'b0;
            out_flat          <= {N{16'h0000}};
            r_sum_exp_q3_13   <= 16'h0000;
            for (i = 0; i < N; i = i + 1) begin
                r_d[i]        <= 16'sd0;
                r_exp[i]      <= 16'h0000;
            end
        end else begin
            if (en) begin
                out_valid <= 1'b0;

                if (start) begin
                    pipe_active  <= 1'b1;
                    pipe_counter <= 3'd0;
                    
                    // Stage 1: Capture differences
                    for (i = 0; i < N; i = i + 1) begin
                        r_d[i] <= $signed(in_flat[i*16 +: 16]) - max_val;
                    end
                end else if (pipe_active) begin
                    pipe_counter <= pipe_counter + 3'd1;

                    case (pipe_counter)
                        3'd0, 3'd1, 3'd2: begin
                            // Wait for exponent module pipeline stages to complete (takes 2 cycles)
                            ;
                        end
                        3'd3: begin
                            // Capture exponents and feed sum to reciprocal module
                            for (i = 0; i < N; i = i + 1) begin
                                r_exp[i] <= exp_out[i];
                            end
                            r_sum_exp_q3_13 <= sum_exp_q3_13;
                        end
                        3'd4, 3'd5: begin
                            // Wait for reciprocal module pipeline stages to complete (takes 2 cycles)
                            ;
                        end
                        3'd6: begin
                            // Capture products into output registers
                            for (i = 0; i < N; i = i + 1) begin
                                out_flat[i*16 +: 16] <= next_out[i];
                            end
                            out_valid   <= 1'b1;
                            pipe_active <= 1'b0;
                        end
                        default: ;
                    endcase
                end
            end
        end
    end

endmodule
