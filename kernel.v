`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/31/2026 11:28:14 PM
// Design Name: 
// Module Name: kernel
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
module kernel #(
    parameter WIDTH = 16,
    parameter N_FEATURES = 4
)(
    input wire clk,
    input wire rst,
    input wire start,
    
    input wire signed [WIDTH-1:0] x_in,   // Q4.12
    input wire signed [WIDTH-1:0] sv_in,  // Q4.12
    
    output wire signed [15:0] kernel_out, // Q4.12
    output wire valid_out
);

    // Internal Signals
    wire signed [31:0] squared_dist_q24; // Sum of (x-sv)^2 in Q8.24
    wire dist_done;
    
    reg signed [15:0] z_to_exp;
    reg z_valid;

    // 1. Instantiate Distance Calculator
    // Note: Ensure your dist_calc outputs the accumulated sum of squares
    dist_calc #(
        .N_FEATURES(N_FEATURES),
        .WIDTH(WIDTH)
    ) distance_inst (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x_in(x_in),
        .sv_in(sv_in),
        .dist_out(squared_dist_q24), 
        .done(dist_done)
    );

    // 2. Prepare z = -gamma * squared_dist
    // gamma = 0.25
    always @(posedge clk) begin
        if (rst) begin
            z_to_exp <= 16'd0;
            z_valid  <= 1'b0;
        end else if (dist_done) begin
            z_valid <= 1'b1;
            
            /* MATH BREAKDOWN:
               squared_dist_q24 is Q8.24.
               We want z = -(0.25 * squared_dist_q24) converted to Q4.12.
               
               Shift right by 2 for the 0.25 (gamma).
               Shift right by 12 to convert fractional bits from 24 to 12.
               Total arithmetic shift right = 14.
            */
            
            // Temporary 32-bit signed calculation to handle shift and negation
            begin : scaling_logic
                integer scaled_z;
                scaled_z = -(squared_dist_q24 >>> 14);
                
                // SATURATION LOGIC:
                // CORDIC input limit is approx -1.118 (16'shEE00 in Q4.12).
                // If the distance is too large, we force it to the floor 
                // so the exponential result is a clean small number (~0.33) 
                // or force even lower if your exp_ip supports it.
                
                if (scaled_z < -16'sh1100) begin // Approx -1.06
                    z_to_exp <= 16'shEE00;       // Near CORDIC convergence limit
                end else begin
                    z_to_exp <= scaled_z[15:0];
                end
            end
        end else begin
            z_valid <= 1'b0;
        end
    end

    // 3. Instantiate Exponential IP
    // This IP takes Q4.12 and returns Q4.12
    exp_ip exponential_inst (
        .clk(clk),
        .rst(rst),
        .z_in(z_to_exp),       
        .valid_in(z_valid),
        .exp_out(kernel_out),  
        .valid_out(valid_out)
    );

endmodule