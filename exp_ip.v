`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/02/2026 08:57:32 AM
// Design Name: 
// Module Name: exp_ip
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

module exp_ip(
    input wire clk,
    input wire rst,
    
    input wire signed [15:0] z_in,     // Q4.12
    input wire valid_in,
    
    output reg signed [15:0] exp_out,  // Q4.12
    output reg valid_out
    ); 
    
    // 1. Convert Q4.12 to Q3.13 (fix16_13) 
    // z_in has 12 fractional bits, IP wants 13. Shift left by 1.
    wire signed [15:0] z_cordic = z_in <<< 1;
     
    wire [31:0] cordic_out;
    wire cordic_valid;
    
    // IP Instance
    cordic_0 cordic_inst(
        .aclk(clk),
        .s_axis_phase_tvalid(valid_in),
        .s_axis_phase_tdata(z_cordic),  // Fixed variable name here
        .m_axis_dout_tvalid(cordic_valid),
        .m_axis_dout_tdata(cordic_out) 
    );
    
    // 2. Extract results (IP provides fix16_14 / Q2.14)
    wire signed [15:0] sinh = cordic_out[31:16];
    wire signed [15:0] cosh = cordic_out[15:0];
    
    // 3. Combinational Sum
    wire signed [16:0] sum = $signed(cosh) + $signed(sinh);
 
    localparam signed [15:0] K_INV = 16'h69ff;
    wire signed [32:0] scaled_result = sum * K_INV; // Q2.14 * Q0.15 = Q2.29
    
    always @(posedge clk) begin
        if (rst) begin
            exp_out   <= 16'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= cordic_valid;
            if (cordic_valid) begin
                // Convert Q2.29 to Q4.12: Shift right by (29 - 12) = 17
                exp_out <= scaled_result >>> 17;
            end
        end
    end
    
endmodule
    
