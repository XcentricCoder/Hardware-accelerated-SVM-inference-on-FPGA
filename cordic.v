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
`define SCALE (16'd1<<`FRAC_BITS)
`define WIDTH 16

module cordic(
input wire clk,
input wire start,
input wire rst,
input wire signed [`WIDTH -1:0]zin,
output reg signed [`WIDTH -1:0]exp,
output reg done
    );
    
 reg signed [`WIDTH-1:0] x,y,z;
 reg signed [`WIDTH-1:0] x_next,y_next,z_next;   
 reg [3:0] i;
 reg running;
 
  reg signed [`WIDTH-1:0] atanh_table [0:7];

initial begin
    atanh_table[0] = 16'd5493;
    atanh_table[1] = 16'd2554;
    atanh_table[2] = 16'd1252;
    atanh_table[3] = 16'd626;
    atanh_table[4] = 16'd313;
    atanh_table[5] = 16'd156;
    atanh_table[6] = 16'd78;
    atanh_table[7] = 16'd39;
end
   
always @(*)begin
if(z>=0)
begin
    x_next = x+(y>>>i);
    y_next = y+(x>>>i);
    z_next = z-atanh_table[i];
end else begin
    x_next = x-(y>>>i);
    y_next = y-(x>>>i);
    z_next = z+atanh_table[i];
end
end


always @(posedge rst or posedge clk)begin
    if(rst)
        begin
        x<=0;
        y<=0;
        z<=0;
        i<=0;
        exp<=0;
        done<=0;
        running<=0;
        end 
    else 
        begin
            if(start && !running) begin
                  x<= (1<<`FRAC_BITS);
                  y<= 0;
                  z<= zin;
                  i<=0;
                  running<=1;
                  done<=0;
            end
            else if (running)
            begin
                  if(i<8)begin
                  x<=x_next;
                  y<=y_next;
                  z<=z_next;
                  i<=i+1;
                  end
                  else begin
                  exp<=x+y;
                  done<=1;
                  running<=0;
                  end
            end
        
        end

end

localparam signed [15:0] K_INV = 16'd3390;

reg signed [31:0] temp;

always @(posedge clk) begin
    if (i == 8 && running) begin
        temp = (x + y) * K_INV;
        exp <= temp >>> `FRAC_BITS;
    end
end


endmodule
