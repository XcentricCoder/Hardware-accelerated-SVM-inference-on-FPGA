`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.02.2026 13:52:59
// Design Name: 
// Module Name: Inference
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


module Inference #(parameter numWeight = 3, dataWidth = 16, biasFile = "biasFile.mem", weightFile = "weightFile.mem") (
    input           clk,
    input           rst,
    input [dataWidth-1:0]    myinput,
    input           myinputValid,
    output[dataWidth-1:0]    out,
    output reg      outvalid
    );
    
    localparam addressWidth = $clog2(numWeight);
    
    wire        ren;
    reg [addressWidth:0]   r_addr;//read address has to reach until numWeight hence width is 1 bit more
    wire [dataWidth-1:0] w_out;
    reg [2*dataWidth-1:0]  mul; 
    reg [2*dataWidth-1:0]  sum;
    reg [2*dataWidth-1:0]  bias;
    reg [31:0]    biasReg[0:0];
    reg         weight_valid;
    reg         mult_valid;
    wire        mux_valid;
    reg         sigValid; 
    wire [2*dataWidth:0] comboAdd;
    wire [2*dataWidth:0] BiasAdd;
    reg  [dataWidth-1:0] myinputd;
    reg muxValid_d;
    reg muxValid_f;
    reg addr=0;
    
    
    
    assign mux_valid = mult_valid;
    assign comboAdd = mul + sum;
    assign BiasAdd = bias + sum;
    assign ren = myinputValid;
    
    always @(posedge clk)
    begin
        if(rst|outvalid)
            r_addr <= 0;
        else if(myinputValid)
            r_addr <= r_addr + 1;
    end
    
    
    always @(posedge clk)
    begin
        mul  <= $signed(myinputd) * $signed(w_out);
    end
        
    always @(posedge clk)
    begin
        if(rst|outvalid)
            sum <= 0;
        else if((r_addr == numWeight) & muxValid_f)
        begin
            if(!bias[2*dataWidth-1] &!sum[2*dataWidth-1] & BiasAdd[2*dataWidth-1]) //If bias and sum are positive and after adding bias to sum, if sign bit becomes 1, saturate
            begin
                sum[2*dataWidth-1] <= 1'b0;
                sum[2*dataWidth-2:0] <= {2*dataWidth-1{1'b1}};
            end
            else if(bias[2*dataWidth-1] & sum[2*dataWidth-1] &  !BiasAdd[2*dataWidth-1]) //If bias and sum are negative and after addition if sign bit is 0, saturate
            begin
                sum[2*dataWidth-1] <= 1'b1;
                sum[2*dataWidth-2:0] <= {2*dataWidth-1{1'b0}};
            end
            else
                sum <= BiasAdd; 
        end
        else if(mux_valid)
        begin
            if(!mul[2*dataWidth-1] & !sum[2*dataWidth-1] & comboAdd[2*dataWidth-1])
            begin
                sum[2*dataWidth-1] <= 1'b0;
                sum[2*dataWidth-2:0] <= {2*dataWidth-1{1'b1}};
            end
            else if(mul[2*dataWidth-1] & sum[2*dataWidth-1] & !comboAdd[2*dataWidth-1])
            begin
                sum[2*dataWidth-1] <= 1'b1;
                sum[2*dataWidth-2:0] <= {2*dataWidth-1{1'b0}};
            end
            else
                sum <= comboAdd; 
        end
    end    
    
    always @(posedge clk)
    begin
        myinputd <= myinput;
        weight_valid <= myinputValid;
        mult_valid <= weight_valid;
        sigValid <= ((r_addr == numWeight) & muxValid_f) ? 1'b1 : 1'b0;
        outvalid <= sigValid;
        muxValid_d <= mux_valid;
        muxValid_f <= !mux_valid & muxValid_d;
    end
    
    
    
    Weight_Memory #(.numWeight(numWeight),.addressWidth(addressWidth),.dataWidth(dataWidth),.weightFile(weightFile)) WM(
        .clk(clk),
        .ren(ren),
        .radd(r_addr),
        .wout(w_out)
    );
    
    initial
		begin
			$readmemb(biasFile,biasReg);
		end
	always @(posedge clk)
		begin
            bias <= {biasReg[addr][dataWidth-1:0],{dataWidth{1'b0}}};
        end    
    
    assign out = (sum[2*dataWidth-1]) ? 16'hFFFF : 16'h0001;
    
endmodule
