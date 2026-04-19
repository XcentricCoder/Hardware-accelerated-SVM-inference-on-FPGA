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
    input  wire signed [WIDTH-1:0] rho_0,    // Intercept for Classifier 0
    input  wire signed [WIDTH-1:0] rho_1,    // Intercept for Classifier 1
    
    // Results
    output wire [1:0]        predicted_class,
    output wire              ready           // High when classification is done
);

    // Internal Signals
    wire signed [15:0] k_out;
    wire               k_valid;
    wire signed [31:0] score_0, score_1;
    wire               done_0, done_1;

    // 1. Shared RBF Kernel
    // This calculates exp(-gamma * ||x - sv||^2) once per SV
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

    // 2. Decision Engine for Classifier 0 (0 vs 1)
    svm_decision_engine #(
        .WIDTH(WIDTH),
        .N_SV(N_SV)
    ) engine_0 (
        .clk(clk),
        .rst(rst),
        .start(sample_start),
        .kernel_val(k_out),
        .kernel_valid(k_valid),
        .dual_coeff(alpha_0),
        .intercept(rho_0),
        .decision_out(score_0),
        .done(done_0)
    );

    // 3. Decision Engine for Classifier 1 (0 vs 2)
    svm_decision_engine #(
        .WIDTH(WIDTH),
        .N_SV(N_SV)
    ) engine_1 (
        .clk(clk),
        .rst(rst),
        .start(sample_start),
        .kernel_val(k_out),
        .kernel_valid(k_valid),
        .dual_coeff(alpha_1),
        .intercept(rho_1),
        .decision_out(score_1),
        .done(done_1)
    );

    // 4. Voting Logic (Argmax)
    // Simplified Voting based on your C logic
    // If score > 0, Class I wins. If score < 0, Class J wins.
    assign ready = done_0 & done_1;
    
    assign predicted_class = (score_0 > 0 && score_1 > 0) ? 2'd0 : // Class 0 wins both
                             (score_0 < 0)               ? 2'd1 : // Class 1 wins 0vs1
                                                           2'd2 ; // Class 2 wins 0vs2
endmodule