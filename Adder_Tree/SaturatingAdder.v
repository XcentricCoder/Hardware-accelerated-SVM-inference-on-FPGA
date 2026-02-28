`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.02.2026 22:25:20
// Design Name: 
// Module Name: SaturatingAdder
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


module SaturatingAdder #(parameter WIDTH = 32) (
    input  signed [WIDTH-1:0] in_a,
    input  signed [WIDTH-1:0] in_b,
    output reg signed [WIDTH-1:0] out_sum
);
    wire signed [WIDTH:0] full_sum;
    assign full_sum = {in_a[WIDTH-1], in_a} + {in_b[WIDTH-1], in_b};
    
    wire sign_a = in_a[WIDTH-1];
    wire sign_b = in_b[WIDTH-1];
    wire sign_res = full_sum[WIDTH-1]; 

    localparam signed [WIDTH-1:0] MAX_POS = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MAX_NEG = {1'b1, {(WIDTH-1){1'b0}}};

    always @(*) begin
        if (sign_a == 0 && sign_b == 0 && sign_res == 1)
            out_sum = MAX_POS; 
            
        else if (sign_a == 1 && sign_b == 1 && sign_res == 0)
            out_sum = MAX_NEG;
            
        else
            out_sum = full_sum[WIDTH-1:0]; 
    end
endmodule