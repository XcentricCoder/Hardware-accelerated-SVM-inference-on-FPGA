`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/04/2026 07:37:08 PM
// Design Name: 
// Module Name: dist_calc
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
`timescale 1ns / 1ps
// dist_calc.v - Fixed version
// Key fixes:
//  1. 'start' is now an edge-triggered latch signal (active for 1 cycle to reset),
//     then the module counts features independently using 'x_in'/'sv_in' valid each cycle.
//  2. Removed dual-branch race: accumulate every cycle while counting, output on last feature.
//  3. feature_count resets cleanly on start pulse.

module dist_calc #(
    parameter N_FEATURES = 4,
    parameter WIDTH      = 16
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,        // Pulse HIGH for exactly 1 cycle to begin new SV

    input  wire signed [WIDTH-1:0] x_in,
    input  wire signed [WIDTH-1:0] sv_in,

    output reg signed [31:0] dist_out,
    output reg               done
);

    reg [2:0]         feature_count;
    reg signed [31:0] accumulator;
    reg               active;             // HIGH while collecting features

    wire signed [WIDTH-1:0]  diff   = x_in - sv_in;
    wire signed [31:0]        square = diff * diff;

    always @(posedge clk) begin
        if (rst) begin
            accumulator   <= 32'd0;
            dist_out      <= 32'd0;
            feature_count <= 3'd0;
            done          <= 1'b0;
            active        <= 1'b0;
        end else begin
            done <= 1'b0; // default: deassert each cycle

            if (start) begin
                // Latch first feature immediately on start pulse
                accumulator   <= square;
                feature_count <= 3'd1;
                active        <= 1'b1;
            end else if (active) begin
                if (feature_count < N_FEATURES - 1) begin
                    accumulator   <= accumulator + square;
                    feature_count <= feature_count + 1'b1;
                end else begin
                    // Last feature
                    dist_out      <= accumulator + square;
                    done          <= 1'b1;
                    feature_count <= 3'd0;
                    accumulator   <= 32'd0;
                    active        <= 1'b0;
                end
            end
        end
    end

endmodule