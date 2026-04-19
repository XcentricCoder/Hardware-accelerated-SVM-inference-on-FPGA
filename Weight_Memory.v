`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.02.2026 16:34:16
// Design Name: 
// Module Name: Weight_Memory
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


module Weight_Memory #(parameter numWeight = 1, addressWidth = 1, dataWidth = 1, weightFile = "") (
    input clk,
    input ren,
    input [addressWidth-1:0] radd,
    output reg [dataWidth-1:0] wout
    );
    
     reg [dataWidth-1:0] mem [numWeight-1:0];
     
        initial
		begin
	        $readmemb(weightFile, mem);
	    end
	    
	    always @ (posedge clk)
	    begin
            if (ren)
                wout <= mem[radd];
        end
endmodule
