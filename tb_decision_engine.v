module tb_decision_engine;

    parameter WIDTH = 16;
    parameter N_SV = 31;

    reg clk;
    reg rst;
    reg start;
    reg signed [15:0] kernel_val;
    reg               kernel_valid;
    reg signed [15:0] dual_coeff;
    reg signed [15:0] intercept;

    wire signed [31:0] decision_out;
    wire               done;

    // Memory to hold test vectors (using your uploaded values)
    reg [15:0] alpha_mem [0:N_SV-1];
    reg [15:0] k_results_mem [0:N_SV-1]; // Simulated output from kernel.v
    
    integer file_ptr;
    integer i;

    // Instantiate the Unit Under Test (UUT)
    svm_decision_engine #(
        .WIDTH(WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .kernel_val(kernel_val),
        .kernel_valid(kernel_valid),
        .dual_coeff(dual_coeff),
        .intercept(intercept),
        .decision_out(decision_out),
        .done(done)
    );

    // Clock Generation
    always #5 clk = ~clk;

    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        start = 0;
        kernel_valid = 0;
        kernel_val = 0;
        dual_coeff = 0;
        
        // Use the first intercept from your file (019d)
        intercept = 16'h019d; 

        // Load your data
        $readmemh("/home/sonan/rbf-kernel_inference/rbf-kernel_inference.srcs/sources_1/new/dual_coef_row0.mem", alpha_mem);
        // Note: You can point this to the kernel_output_results.mem we generated earlier
        // For this TB, I'm assuming a file exists with just the 31 hex kernel results
        $readmemh("/home/sonan/rbf-kernel_inference/rbf-kernel_inference.srcs/sources_1/new/kernel_hex_only.mem", k_results_mem); 

        // Open output file
        file_ptr = $fopen("/home/sonan/rbf-kernel_inference/rbf-kernel_inference.srcs/sources_1/new/decision_trace_results.mem", "w");
        $fdisplay(file_ptr, "// SV_Idx | Alpha | Kernel | Current_Accumulation (Q24)");

        #100 rst = 0;
        #20;

        // --- Start Classification for 1 Sample ---
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        for (i = 0; i < N_SV; i = i + 1) begin
            // Simulate the delay between kernel results
            repeat(5) @(posedge clk); 
            
            dual_coeff = alpha_mem[i];
            kernel_val = k_results_mem[i];
            kernel_valid = 1;
            
            @(posedge clk);
            kernel_valid = 0;
            
            // Log the state after each accumulation
            // Accessing internal accumulator for debugging
            $fdisplay(file_ptr, "%d | %h | %h | %h", i, dual_coeff, kernel_val, uut.accumulator);
        end

        // Wait for final done signal
        wait(done);
        $fdisplay(file_ptr, "// FINAL DECISION SCORE: %h", decision_out);
        $display("Inference Complete. Final Score: %h", decision_out);

        #100;
        $fclose(file_ptr);
        $finish;
    end

endmodule
