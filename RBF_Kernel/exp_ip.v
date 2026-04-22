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
    
    // FIFO to delay z_in to match CORDIC latency
    reg signed [15:0] z_fifo [0:31];
    reg [4:0] wr_ptr, rd_ptr;
    
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 5'd0;
            rd_ptr <= 5'd0;
        end else begin
            if (valid_in) begin
                z_fifo[wr_ptr] <= z_in;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (cordic_valid) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end
    
    wire signed [15:0] z_delayed = z_fifo[rd_ptr];
    
    // 2. Extract results (IP provides fix16_14 / Q2.14)
    wire signed [15:0] sinh = cordic_out[31:16];
    wire signed [15:0] cosh = cordic_out[15:0];
    
    // 3. Combinational Sum
    wire signed [16:0] sum = $signed(cosh) + $signed(sinh);
    
    
    // 4. Gain Compensation (1/An approx 0.8281 in Q15)
    localparam signed [15:0] K_INV = 16'h69ff;
    wire signed [32:0] scaled_result = sum * K_INV; // Q3.14 * Q0.15 = Q3.29 (33-bit result)
    
    always @(posedge clk) begin
        if (rst) begin
            exp_out   <= 16'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= cordic_valid;
            if (z_delayed <= 16'shEE00) begin 
                    exp_out <= 16'h0000; // Force to 0 because e^(-large) is approx 0
                end else 
                if (z_delayed > 16'sh11D0) begin
                    exp_out <= 16'h30ee;
                end else begin
                    exp_out <= scaled_result >>> 17; 
                end
        end
    end
    
endmodule
    
