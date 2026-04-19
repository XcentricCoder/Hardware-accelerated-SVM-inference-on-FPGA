`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/17/2026 11:20:28 PM
// Design Name: 
// Module Name: svm_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module svm_top #(
    parameter WIDTH = 16,
    parameter N_FEATURES = 4,
    parameter N_SV = 31
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              sample_start,   // Start processing one test sample (resets decision engine)
    input  wire              sv_start,       // Start processing one support vector (starts dist_calc)
    
    // Memory Interface
    input  wire signed [WIDTH-1:0] x_in,     // Current feature of test sample
    input  wire signed [WIDTH-1:0] sv_in,    // Current feature of Support Vector
    input  wire signed [WIDTH-1:0] alpha_0,  // dual_coef[0][sv_idx]
    input  wire signed [WIDTH-1:0] alpha_1,  // dual_coef[1][sv_idx]
    
    // Intercepts (from intercepts.mem)
    input  wire signed [WIDTH-1:0] rho_0,    // Intercept for 0vs1
    input  wire signed [WIDTH-1:0] rho_1,    // Intercept for 0vs2
    input  wire signed [WIDTH-1:0] rho_2,    // Intercept for 1vs2
    
    // Results
    output wire [1:0]        predicted_class,
    output wire              ready           // High when classification is done
);

    // Internal Signals
    wire signed [15:0] k_out;
    wire               k_valid;
    wire signed [31:0] score_01, score_02, score_12;
    wire               done_01, done_02, done_12;
    
    // Multiplexed coefficients
    reg signed [15:0] coeff_01, coeff_02, coeff_12;
    wire [5:0] sv_idx = engine_01.sv_count;

    always @(*) begin
        if (sv_idx < 7) begin
            // Class 0 SVs
            coeff_01 = alpha_0;
            coeff_02 = alpha_1;
            coeff_12 = 16'd0;
        end else if (sv_idx < 20) begin
            // Class 1 SVs
            coeff_01 = alpha_0;
            coeff_02 = 16'd0;
            coeff_12 = alpha_1;
        end else begin
            // Class 2 SVs
            coeff_01 = 16'd0;
            coeff_02 = alpha_0;
            coeff_12 = alpha_1;
        end
    end

    // 1. Shared RBF Kernel
    kernel #(
        .WIDTH(WIDTH),
        .N_FEATURES(N_FEATURES)
    ) kernel_unit (
        .clk(clk),
        .rst(rst),
        .start(sv_start),
        .x_in(x_in),
        .sv_in(sv_in),
        .kernel_out(k_out),
        .valid_out(k_valid)
    );

    // 2. Decision Engine for 0 vs 1
    svm_decision_engine #(
        .WIDTH(WIDTH),
        .N_SV(N_SV)
    ) engine_01 (
        .clk(clk),
        .rst(rst),
        .start(sample_start),
        .kernel_val(k_out),
        .kernel_valid(k_valid),
        .dual_coeff(coeff_01),
        .intercept(rho_0),
        .decision_out(score_01),
        .done(done_01)
    );

    // 3. Decision Engine for 0 vs 2
    svm_decision_engine #(
        .WIDTH(WIDTH),
        .N_SV(N_SV)
    ) engine_02 (
        .clk(clk),
        .rst(rst),
        .start(sample_start),
        .kernel_val(k_out),
        .kernel_valid(k_valid),
        .dual_coeff(coeff_02),
        .intercept(rho_1),
        .decision_out(score_02),
        .done(done_02)
    );
    
    // 4. Decision Engine for 1 vs 2
    svm_decision_engine #(
        .WIDTH(WIDTH),
        .N_SV(N_SV)
    ) engine_12 (
        .clk(clk),
        .rst(rst),
        .start(sample_start),
        .kernel_val(k_out),
        .kernel_valid(k_valid),
        .dual_coeff(coeff_12),
        .intercept(rho_2),
        .decision_out(score_12),
        .done(done_12)
    );

    // 5. Voting Logic (Argmax)
    assign ready = done_01 & done_02 & done_12;
    
    wire [1:0] votes_0 = (score_01 > 0 ? 1 : 0) + (score_02 > 0 ? 1 : 0);
    wire [1:0] votes_1 = (score_01 <= 0 ? 1 : 0) + (score_12 > 0 ? 1 : 0);
    wire [1:0] votes_2 = (score_02 <= 0 ? 1 : 0) + (score_12 <= 0 ? 1 : 0);
    
    assign predicted_class = (votes_0 >= votes_1 && votes_0 >= votes_2) ? 2'd0 :
                             (votes_1 >= votes_0 && votes_1 >= votes_2) ? 2'd1 :
                                                                          2'd2;
endmodule