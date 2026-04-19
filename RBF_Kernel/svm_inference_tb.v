`timescale 1ns / 1ps

// svm_inference_tb.v - Fixed version
// Key fixes:
//  1. Loads dual_coef_row0.mem / dual_coef_row1.mem (split from dual_coef.mem).
//  2. Top module split 'start' into 'sample_start' and 'sv_start' to decouple sample accumulation reset
//     from the dist_calc feature trigger.
//  3. 'sv_start' stays HIGH for the entire first SV's feature stream (1 cycle per feature),
//     matching the new dist_calc which latches on the start pulse then counts internally.
//  4. After wait(ready), waits for ready to go low and adds an extra clock before next sample.
//  5. true_labels loop corrected to s < 30 (array is [0:29]).

module svm_inference_tb;

    parameter WIDTH      = 16;
    parameter N_FEATURES = 4;
    parameter N_SV       = 31;
    parameter N_SAMPLES  = 30;

    reg clk, rst, sample_start, sv_start;
    reg signed [WIDTH-1:0] x_in, sv_in;
    reg signed [WIDTH-1:0] alpha_0, alpha_1;
    reg signed [WIDTH-1:0] rho_0, rho_1, rho_2;

    wire [1:0] predicted_class;
    wire       ready;

    // Memories
    reg [WIDTH-1:0] test_mem   [0:N_SAMPLES*N_FEATURES-1];
    reg [WIDTH-1:0] sv_mem     [0:N_SV*N_FEATURES-1];
    reg [WIDTH-1:0] alpha0_mem [0:N_SV-1];
    reg [WIDTH-1:0] alpha1_mem [0:N_SV-1];
    reg [WIDTH-1:0] rho_mem    [0:2];

    // Ground truth labels  (fix: upper bound is 30, not 31)
    reg [1:0] true_labels [0:29];

    // DUT
    svm_top #(
        .WIDTH(WIDTH),
        .N_FEATURES(N_FEATURES),
        .N_SV(N_SV)
    ) uut (
        .clk(clk), .rst(rst), 
        .sample_start(sample_start), 
        .sv_start(sv_start),
        .x_in(x_in), .sv_in(sv_in),
        .alpha_0(alpha_0), .alpha_1(alpha_1),
        .rho_0(rho_0), .rho_1(rho_1), .rho_2(rho_2),
        .predicted_class(predicted_class),
        .ready(ready)
    );

    always #5 clk = ~clk;
    
    always @(*) begin
        alpha_0 = alpha0_mem[uut.engine_01.sv_count];
        alpha_1 = alpha1_mem[uut.engine_01.sv_count];
    end

    integer s, v, f;
    integer correct_count;
    real    accuracy;

    initial begin
        clk           = 0;
        rst           = 1;
        sample_start  = 0;
        sv_start      = 0;
        correct_count = 0;
        x_in          = 0;
        sv_in         = 0;
        alpha_0       = 0;
        alpha_1       = 0;
        rho_0         = 0;
        rho_1         = 0;
        rho_2         = 0;

        // ----------------------------------------------------------------
        // Load memories
        // ----------------------------------------------------------------
        $readmemh("test_data.mem",       test_mem);
        $readmemh("sv_data.mem",         sv_mem);
        $readmemh("dual_coef_row0.mem",  alpha0_mem);  // one value per line
        $readmemh("dual_coef_row1.mem",  alpha1_mem);
        $readmemh("intercepts.mem",      rho_mem);

        true_labels[0] = 2'd0;
        true_labels[1] = 2'd2;
        true_labels[2] = 2'd1;
        true_labels[3] = 2'd1;
        true_labels[4] = 2'd0;
        true_labels[5] = 2'd1;
        true_labels[6] = 2'd0;
        true_labels[7] = 2'd0;
        true_labels[8] = 2'd2;
        true_labels[9] = 2'd1;
        true_labels[10] = 2'd2;
        true_labels[11] = 2'd2;
        true_labels[12] = 2'd2;
        true_labels[13] = 2'd1;
        true_labels[14] = 2'd0;
        true_labels[15] = 2'd0;
        true_labels[16] = 2'd0;
        true_labels[17] = 2'd1;
        true_labels[18] = 2'd1;
        true_labels[19] = 2'd2;
        true_labels[20] = 2'd0;
        true_labels[21] = 2'd2;
        true_labels[22] = 2'd1;
        true_labels[23] = 2'd2;
        true_labels[24] = 2'd2;
        true_labels[25] = 2'd2;
        true_labels[26] = 2'd1;
        true_labels[27] = 2'd0;
        true_labels[28] = 2'd2;
        true_labels[29] = 2'd0;

        // ----------------------------------------------------------------
        // Reset sequence - hold for 10 clocks so CORDIC pipeline flushes
        // ----------------------------------------------------------------
        repeat (20) @(posedge clk);
        rst = 0;
        // Extra guard: wait another 30 cycles for CORDIC IP to be ready
        repeat (30) @(posedge clk);

        $display("--- SVM RTL INFERENCE START ---");

        for (s = 0; s < N_SAMPLES; s = s + 1) begin

            rho_0 = rho_mem[0];
            rho_1 = rho_mem[1];
            rho_2 = rho_mem[2];

            // ----------------------------------------------------------------
            // Signal a new sample to reset the decision engine accumulators
            // ----------------------------------------------------------------
            sample_start = 1;
            @(posedge clk);
            sample_start = 0;

            // Loop over all support vectors
            for (v = 0; v < N_SV; v = v + 1) begin

                // --------------------------------------------------------
                // Present all N_FEATURES features for this SV.
                // dist_calc latches on the rising edge of 'sv_start' (1 cycle),
                // then counts the remaining features autonomously.
                // So we pulse sv_start=1 on the first feature only.
                // --------------------------------------------------------
                for (f = 0; f < N_FEATURES; f = f + 1) begin
                    x_in  = test_mem[s * N_FEATURES + f];
                    sv_in = sv_mem [v * N_FEATURES + f];

                    if (f == 0)
                        sv_start = 1;  // pulse start on first feature
                    else
                        sv_start = 0;

                    @(posedge clk);
                end
                sv_start = 0;

                // Let dist_calc pipeline settle between SVs (1 extra cycle)
                @(posedge clk);
            end

            // Wait for both decision engines to finish
            wait (ready == 1'b1);

            if (predicted_class == true_labels[s])
                $display("Sample %0d: Pred=%0d, True=%0d | OK",    s, predicted_class, true_labels[s]);
            else
                $display("Sample %0d: Pred=%0d, True=%0d | WRONG", s, predicted_class, true_labels[s]);

            if (predicted_class == true_labels[s])
                correct_count = correct_count + 1;

            // Wait for ready to go low before driving the next sample
            @(posedge clk);
            wait (ready == 1'b0);
            @(posedge clk); // one more idle cycle
        end

        accuracy = (correct_count * 100.0) / N_SAMPLES;
        $display("---------------------------------");
        $display("Total Correct: %0d / %0d", correct_count, N_SAMPLES);
        $display("Final Accuracy: %f%%", accuracy);
        $display("---------------------------------");
        $finish;
    end

endmodule
