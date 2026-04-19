`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/31/2026 11:42:26 PM
// Design Name: 
// Module Name: cordic
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
`define FRAC_BITS 12
`define WIDTH 16

module cordic(
    input wire clk,
    input wire start,
    input wire rst,
    input wire signed [`WIDTH -1:0] z_in,
    output reg signed [`WIDTH -1:0] exp_out,
    output reg done
);

    reg signed [`WIDTH-1:0] x, y, z;
    reg [3:0] i;
    reg running;
    reg repeated;
    
    // For Q4.12: 1/K (Hyperbolic) for i=1 to 8 (with 4 repeated) is ~1.257
    // 1.257 * 4096 = 5149
    localparam signed [15:0] K_INV = 16'd5149; 
    
    reg signed [`WIDTH-1:0] atanh_table [1:8];

    initial begin
        atanh_table[1] = 16'd2250; // atanh(2^-1)
        atanh_table[2] = 16'd1046; // atanh(2^-2)
        atanh_table[3] = 16'd514;  
        atanh_table[4] = 16'd256;  
        atanh_table[5] = 16'd128;  
        atanh_table[6] = 16'd64;   
        atanh_table[7] = 16'd32;   
        atanh_table[8] = 16'd16;
    end

    // Temporary wires for the multiplication stage
    wire signed [16:0] sum_xy = x + y; 
    wire signed [32:0] full_product = sum_xy * K_INV;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x <= 0; y <= 0; z <= 0;
            i <= 1;
            exp_out <= 0;
            done <= 0;
            running <= 0;
            repeated <= 0;
        end 
        else begin
            if (start && !running) begin
                x <= 16'h1000; // 1.0 in Q4.12
                y <= 0;
                z <= z_in;
                i <= 1;        // Start at 1 for hyperbolic
                running <= 1;
                done <= 0;
                repeated <= 0;
            end 
            else if (running) begin
                if (i <= 8) begin
                    if (z >= 0) begin
                        x <= x + (y >>> i);
                        y <= y + (x >>> i);
                        z <= z - atanh_table[i];
                    end else begin
                        x <= x - (y >>> i);
                        y <= y - (x >>> i);
                        z <= z + atanh_table[i];
                    end

                    // Proper repetition logic for i=4
                    if (i == 4 && !repeated) begin
                        repeated <= 1;
                        // Note: i does NOT increment here
                    end else begin
                        repeated <= 0;
                        i <= i + 1;
                    end
                end 
                else begin
                    // Final scaling: exp(z) = (cosh + sinh) * (1/K)
                    // We use the wires declared above for a single-cycle finish
                    exp_out <= full_product[27:12]; 
                    done <= 1;
                    running <= 0;
                end
            end else begin
                done <= 0; // Clear done when not running
            end
        end
    end
endmodule