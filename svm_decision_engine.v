`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/17/2026 11:03:19 PM
// Design Name: 
// Module Name: svm_decision_engine
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

module svm_decision_engine #(
    parameter WIDTH = 16,
    parameter FRAC = 12,
    parameter N_SV = 31
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,         // Pulsed when starting a new sample
    input  wire signed [15:0] kernel_val,    // From rbf_kernel (Q4.12)
    input  wire              kernel_valid,  // Valid pulse from rbf_kernel
    input  wire signed [15:0] dual_coeff,    // From coefficient ROM (Q4.12)
    input  wire signed [15:0] intercept,     // The bias for this classifier (Q4.12)
    
    output reg signed [31:0]  decision_out,  // Final score (Q8.24)
    output reg               done           // Pulsed when all SVs summed
);

    // Internal Accumulator
    // Multiplied result (Q4.12 * Q4.12) = Q8.24
    reg signed [31:0] accumulator;
    reg [5:0]         sv_count;
    // N_SV is now in the module parameter list
    // Explicitly compute the product to ensure proper 32-bit signed evaluation
    wire signed [31:0] product = $signed(dual_coeff) * $signed(kernel_val);

    always @(posedge clk) begin
        if (rst) begin
            sv_count     <= 6'd0;
            done         <= 1'b0;
            decision_out <= 32'd0;
            accumulator  <= 32'd0;
        end else if (start) begin
            // Convert Q4.12 to Q8.24: sign-extend by 4 bits and pad 12 zeros
            accumulator  <= { {4{intercept[15]}}, intercept, 12'd0 };
            sv_count     <= 6'd0;
            done         <= 1'b0;
        end else if (kernel_valid) begin
            accumulator <= accumulator + product;
            
            if (sv_count == (N_SV - 1)) begin
                done         <= 1'b1; 
                decision_out <= accumulator + product;
                sv_count     <= 6'd0; 
            end else begin
                sv_count     <= sv_count + 1;
                done         <= 1'b0;
            end
        end else begin
            done <= 1'b0; // Ensure done pulses for only one cycle
        end
    end

endmodule