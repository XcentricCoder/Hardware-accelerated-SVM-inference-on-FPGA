`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.02.2026 23:01:10
// Design Name: 
// Module Name: TopMod
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


module TopMod#(
    parameter NUM_FEATURES = 8,
    parameter DATA_WIDTH = 16,
    parameter ACCUM_WIDTH = (2*DATA_WIDTH),
    parameter NUM_LAYERS = $clog2(NUM_FEATURES) 
)(
    input clk,
    input rst,
  //  input signed [DATA_WIDTH-1:0] in_features [0:NUM_FEATURES-1],
    input signed [(NUM_FEATURES * DATA_WIDTH)-1:0] in_features_flat,
    input valid_in,
    output reg [15:0] out_pred,
    output reg valid_out
);
    
    // Create the internal array that your multipliers expect
    wire signed [DATA_WIDTH-1:0] in_features [0:NUM_FEATURES-1];

    genvar k;
    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : unpack_inputs
            // Slices the flat bus into 16-bit chunks
            assign in_features[k] = in_features_flat[ ((k+1)*DATA_WIDTH)-1 : k*DATA_WIDTH ];
        end
    endgenerate
    
    
    // INTERNAL WEIGHT & BIAS MEMORY (ROM)
    reg signed [DATA_WIDTH-1:0] weight_rom [0:NUM_FEATURES-1];
    reg signed [ACCUM_WIDTH-1:0] bias_rom   [0:0]; 

    // Vivado will load these files during Synthesis to bake the constants into the FPGA
    initial begin
        $readmemb("weights.mem", weight_rom);
        $readmemb("bias.mem", bias_rom);
    end

    // Extract the bias value for easy reading
    wire signed [ACCUM_WIDTH-1:0] bias_val = bias_rom[0];

    // THE PIPELINE REGISTERS (The 2D Grid)
    reg signed [ACCUM_WIDTH-1:0] pipe_regs [0:NUM_LAYERS][0:NUM_FEATURES-1];
    //reg [NUM_LAYERS+1:0] valid_pipe;
    reg [NUM_LAYERS:0] valid_pipe;
    genvar i, j;
    generate
        //STAGE 0: The Multipliers
        for (i = 0; i < NUM_FEATURES; i = i + 1) begin : mult_stage
            wire signed [ACCUM_WIDTH-1:0] mult_wire;
            
            SignedMultiplier #(
                .IN_WIDTH(DATA_WIDTH)
            ) mult_inst (
                .in_a(in_features[i]), 
                .in_b(weight_rom[i]), // READING FROM INTERNAL ROM HERE
                .out_p(mult_wire)
            );
            
            always @(posedge clk) begin
                if (rst) pipe_regs[0][i] <= 0;
                else pipe_regs[0][i] <= mult_wire;
            end
        end

        // STAGES 1 to NUM_LAYERS: The Adder Tree
        for (i = 1; i <= NUM_LAYERS; i = i + 1) begin : tree_layers
            localparam ADDS_IN_LAYER = NUM_FEATURES / (2**i);
            
            for (j = 0; j < ADDS_IN_LAYER; j = j + 1) begin : adders
                wire signed [ACCUM_WIDTH-1:0] sum_wire;
                
                SaturatingAdder #(.WIDTH(ACCUM_WIDTH)) adder_inst (
                    .in_a(pipe_regs[i-1][2*j]),    
                    .in_b(pipe_regs[i-1][2*j+1]),  
                    .out_sum(sum_wire)
                );

                always @(posedge clk) begin
                    if (rst) pipe_regs[i][j] <= 0;
                    else pipe_regs[i][j] <= sum_wire;
                end
            end
        end
    endgenerate

    // FINAL STAGE: Bias Subtraction & Output
    wire signed [ACCUM_WIDTH-1:0] bias_wire;
    reg  signed [ACCUM_WIDTH-1:0] final_sum;
    
    // Subtract bias from the final dot product
    SaturatingAdder #(.WIDTH(ACCUM_WIDTH)) bias_sub (
        .in_a(pipe_regs[NUM_LAYERS][0]), 
        .in_b(-(bias_val << 16)), //USING INTERNAL BIAS HERE
        .out_sum(bias_wire)
    );

    always @(posedge clk) begin
        if (rst) begin
            final_sum  <= 0;
            valid_pipe <= 0;
            valid_out  <= 0;
            out_pred   <= 0;
        end else begin
            final_sum  <= bias_wire;
            
            //valid_pipe <= {valid_pipe[NUM_LAYERS:0], valid_in};
            valid_pipe <= {valid_pipe[NUM_LAYERS-1:0], valid_in};
            //valid_out  <= valid_pipe[NUM_LAYERS+1];
            valid_out  <= valid_pipe[NUM_LAYERS];
            
            out_pred   <= (bias_wire[ACCUM_WIDTH-1]) ? 16'h0000 : 16'h0001;
        end
    end

endmodule
