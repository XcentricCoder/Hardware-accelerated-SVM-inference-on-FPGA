`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/18/2026 01:14:59 AM
// Design Name: 
// Module Name: svm_classifier_single
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


module svm_classifier_single #(
    parameter WIDTH = 16,
    parameter N_FEATURES = 4,
    parameter N_SV = 31
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,         // Pulse to start a new test sample
    input  wire signed [WIDTH-1:0] x_in,    // Feature from test sample
    input  wire signed [WIDTH-1:0] sv_in,   // Feature from support vector
    input  wire signed [WIDTH-1:0] alpha,   // Dual coefficient for current SV
    input  wire signed [WIDTH-1:0] rho,     // Intercept/Bias for this classifier
    
    output wire signed [31:0] decision_out, // The Q8.24 final score
    output wire              done           // High when all 31 SVs are processed
);

    // Internal Wires connecting the two modules
    wire signed [15:0] kernel_to_engine_val;
    wire               kernel_to_engine_valid;

    // 1. Instance of your RBF Kernel logic
    kernel #(
        .WIDTH(WIDTH),
        .N_FEATURES(N_FEATURES)
    ) rbf_kernel_inst (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x_in(x_in),
        .sv_in(sv_in),
        .kernel_out(kernel_to_engine_val),
        .valid_out(kernel_to_engine_valid)
    );

    // 2. Instance of the Decision Engine (MAC unit)
    svm_decision_engine #(
        .WIDTH(WIDTH)
    ) decision_engine_inst (
        .clk(clk),
        .rst(rst),
        .start(start),
        .kernel_val(kernel_to_engine_val),
        .kernel_valid(kernel_to_engine_valid),
        .dual_coeff(alpha),
        .intercept(rho),
        .decision_out(decision_out),
        .done(done)
    );

endmodule