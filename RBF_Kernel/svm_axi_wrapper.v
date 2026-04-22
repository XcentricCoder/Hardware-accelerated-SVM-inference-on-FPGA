`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: svm_axi_wrapper
// 
// Description: AXI4-Stream wrapper for the SVM RBF inference engine (svm_top).
//              Receives test sample data via AXI-Stream slave (from DMA MM2S)
//              and outputs the predicted class via AXI-Stream master (to DMA S2MM).
//
// ════════════════════════════════════════════════════════════════════════
//  DMA INPUT BUFFER FORMAT  (32-bit AXI words, little-endian packing)
//  Two 16-bit Q4.12 values packed per 32-bit word: {high16, low16}
// ════════════════════════════════════════════════════════════════════════
//
//  ┌─── Header (4 words) ──────────────────────────────────────────────┐
//  │ Word  0:  x[0]          | x[1]           test features           │
//  │ Word  1:  x[2]          | x[3]                                   │
//  │ Word  2:  rho_0         | rho_1          intercepts              │
//  │ Word  3:  rho_2         | 0x0000         (padding)               │
//  └───────────────────────────────────────────────────────────────────┘
//  ┌─── Per SV (3 words × 31 SVs = 93 words) ─────────────────────────┐
//  │ Word  4+sv*3:  sv[sv][0] | sv[sv][1]     SV features             │      
//  │ Word  5+sv*3:  sv[sv][2] | sv[sv][3]                             │
//  │ Word  6+sv*3:  alpha_0    | alpha_1       dual coefficients       │
//  └───────────────────────────────────────────────────────────────────┘
//  Total: 4 + 93 = 97 words per sample = 388 bytes
//
// ════════════════════════════════════════════════════════════════════════
//  DMA OUTPUT FORMAT  (32-bit AXI word)
// ════════════════════════════════════════════════════════════════════════
//  Word 0: {30'b0, predicted_class[1:0]}
//  Single word per sample, m_axis_tlast mirrors captured s_axis_tlast.
//
// ════════════════════════════════════════════════════════════════════════
//  LATENCY  (approximate, CORDIC latency ≈ 21 cycles)
// ════════════════════════════════════════════════════════════════════════
//  Per SV:  3 (DMA load) + 4 (feature feed) + ~23 (kernel pipeline) ≈ 30 cycles
//  Per sample: 4 (header) + 31 × ~30 + 2 (output) ≈ 936 cycles
//
//////////////////////////////////////////////////////////////////////////////////

module svm_axi_wrapper #(
    parameter WIDTH     = 16,
    parameter N_FEATURES = 4,
    parameter N_SV      = 31,
    parameter C_S_AXIS_TDATA_WIDTH = 32,
    parameter C_M_AXIS_TDATA_WIDTH = 32
)(
    // System Signals (active-low reset from Zynq PS)
    input  wire axi_clk,
    input  wire axi_reset_n,

    // AXI4-Stream Slave Interface (DMA MM2S → PL)
    input  wire [C_S_AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
    input  wire                            s_axis_tvalid,
    output wire                            s_axis_tready,
    input  wire                            s_axis_tlast,

    // AXI4-Stream Master Interface (PL → DMA S2MM)
    output wire [C_M_AXIS_TDATA_WIDTH-1:0] m_axis_tdata,
    output reg                             m_axis_tvalid,
    input  wire                            m_axis_tready,
    output reg                             m_axis_tlast
);

    // ─── Reset Inversion ────────────────────────────────────────────
    wire rst = ~axi_reset_n;

    // ─── FSM State Encoding ─────────────────────────────────────────
    localparam [3:0]
        S_IDLE        = 4'd0,   // Idle — ready to accept DMA data
        S_LOAD_HDR    = 4'd1,   // Loading header words (x features + intercepts)
        S_LOAD_SV     = 4'd2,   // Loading current SV data (features + coefficients)
        S_FEED_F0     = 4'd3,   // Present feature[0], pulse sv_start (& sample_start)
        S_FEED_F1     = 4'd4,   // Present feature[1]
        S_FEED_F2     = 4'd5,   // Present feature[2]
        S_FEED_F3     = 4'd6,   // Present feature[3]
        S_WAIT_KERNEL = 4'd7,   // Wait for kernel output valid (CORDIC latency)
        S_DONE_WAIT   = 4'd8,   // Wait for decision engines to signal ready
        S_OUTPUT      = 4'd9;   // Present result on master, await handshake

    reg [3:0] state;

    // ─── Internal Storage Registers ─────────────────────────────────
    // Test sample features — loaded once, reused for all 31 SVs
    reg signed [15:0] x_reg [0:N_FEATURES-1];
    
    // Current support vector data — reloaded per SV from DMA
    reg signed [15:0] sv_reg [0:N_FEATURES-1];
    reg signed [15:0] alpha0_reg;       // dual_coef[0][current_sv]
    reg signed [15:0] alpha1_reg;       // dual_coef[1][current_sv]
    
    // Intercepts — loaded once from header
    reg signed [15:0] rho_reg [0:2];

    // ─── FSM Counters ───────────────────────────────────────────────
    reg [1:0] hdr_cnt;          // Header word index (0–3)
    reg [1:0] sv_word_cnt;      // SV word index per SV (0–2)
    reg [5:0] sv_idx;           // Support vector index (0 to N_SV-1) 
    reg       first_sv_flag;    // High for first SV of each sample (triggers sample_start)
    reg       tlast_captured;   // Captured s_axis_tlast for m_axis_tlast forwarding

    // ─── svm_top Interface Signals ──────────────────────────────────
    reg              sample_start_r;    // Pulse: resets decision engines
    reg              sv_start_r;        // Pulse: starts kernel for one SV
    reg signed [15:0] x_in_r;           // Test feature (one per clock)
    reg signed [15:0] sv_in_r;          // SV feature (one per clock)

    wire [1:0] predicted_class;         // Final 3-class prediction
    wire       svm_ready;               // High when all decision engines done
    wire       k_valid;                 // Kernel output valid for current SV

    // ─── AXI-Stream Slave Handshake ─────────────────────────────────
    // Combinational tready: accept data only during loading states
    assign s_axis_tready = (state == S_IDLE) 
                         | (state == S_LOAD_HDR) 
                         | (state == S_LOAD_SV);

    wire axis_handshake = s_axis_tvalid & s_axis_tready;

    // ─── AXI-Stream Master Data ─────────────────────────────────────
    assign m_axis_tdata = {30'd0, predicted_class};

    // ─── Main FSM ───────────────────────────────────────────────────
    always @(posedge axi_clk) begin
        if (rst) begin
            state          <= S_IDLE;
            hdr_cnt        <= 2'd0;
            sv_word_cnt    <= 2'd0;
            sv_idx         <= 6'd0;
            first_sv_flag  <= 1'b0;
            tlast_captured <= 1'b0;
            sample_start_r <= 1'b0;
            sv_start_r     <= 1'b0;
            m_axis_tvalid  <= 1'b0;
            m_axis_tlast   <= 1'b0;
            x_in_r         <= 16'd0;
            sv_in_r        <= 16'd0;
            alpha0_reg     <= 16'd0;
            alpha1_reg     <= 16'd0;
        end else begin
            // ── Default: deassert one-cycle pulses ──
            sample_start_r <= 1'b0;
            sv_start_r     <= 1'b0;

            case (state)

                // ─────────────────────────────────────────────────
                // IDLE: Wait for first DMA word
                // ─────────────────────────────────────────────────
                S_IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    if (axis_handshake) begin
                        // Word 0: x[0] (bits [15:0]) | x[1] (bits [31:16])
                        x_reg[0] <= s_axis_tdata[15:0];
                        x_reg[1] <= s_axis_tdata[31:16];
                        hdr_cnt  <= 2'd1;
                        state    <= S_LOAD_HDR;
                    end
                end

                // ─────────────────────────────────────────────────
                // LOAD_HDR: Receive words 1–3 of header
                // ─────────────────────────────────────────────────
                S_LOAD_HDR: begin
                    if (axis_handshake) begin
                        case (hdr_cnt)
                            2'd1: begin
                                // Word 1: x[2] | x[3]
                                x_reg[2] <= s_axis_tdata[15:0];
                                x_reg[3] <= s_axis_tdata[31:16];
                                hdr_cnt  <= 2'd2;
                            end
                            2'd2: begin
                                // Word 2: rho_0 | rho_1
                                rho_reg[0] <= s_axis_tdata[15:0];
                                rho_reg[1] <= s_axis_tdata[31:16];
                                hdr_cnt    <= 2'd3;
                            end
                            2'd3: begin
                                // Word 3: rho_2 | padding (ignored)
                                rho_reg[2]    <= s_axis_tdata[15:0];
                                // Prepare for SV processing
                                sv_idx        <= 6'd0;
                                first_sv_flag <= 1'b1;
                                sv_word_cnt   <= 2'd0;
                                hdr_cnt       <= 2'd0;
                                state         <= S_LOAD_SV;
                            end
                            default: ;
                        endcase
                    end
                end

                // ─────────────────────────────────────────────────
                // LOAD_SV: Receive 3 words for current SV
                //   Word 0: sv_feat[0] | sv_feat[1]
                //   Word 1: sv_feat[2] | sv_feat[3]
                //   Word 2: alpha_0    | alpha_1
                // ─────────────────────────────────────────────────
                S_LOAD_SV: begin
                    if (axis_handshake) begin
                        case (sv_word_cnt)
                            2'd0: begin
                                sv_reg[0]   <= s_axis_tdata[15:0];
                                sv_reg[1]   <= s_axis_tdata[31:16];
                                sv_word_cnt <= 2'd1;
                            end
                            2'd1: begin
                                sv_reg[2]   <= s_axis_tdata[15:0];
                                sv_reg[3]   <= s_axis_tdata[31:16];
                                sv_word_cnt <= 2'd2;
                            end
                            2'd2: begin
                                alpha0_reg  <= s_axis_tdata[15:0];
                                alpha1_reg  <= s_axis_tdata[31:16];
                                sv_word_cnt <= 2'd0;
                                // Capture tlast for forwarding to master
                                if (s_axis_tlast)
                                    tlast_captured <= 1'b1;
                                // Begin feeding features to svm_top
                                state <= S_FEED_F0;
                            end
                            default: ;
                        endcase
                    end
                end

                // ─────────────────────────────────────────────────
                // FEED_F0: Pulse sv_start + feature[0]
                //          Also pulse sample_start on first SV
                // ─────────────────────────────────────────────────
                S_FEED_F0: begin
                    sv_start_r     <= 1'b1;
                    sample_start_r <= first_sv_flag;
                    first_sv_flag  <= 1'b0;
                    x_in_r         <= x_reg[0];
                    sv_in_r        <= sv_reg[0];
                    state          <= S_FEED_F1;
                end

                // ─────────────────────────────────────────────────
                // FEED_F1–F3: Stream remaining features
                // ─────────────────────────────────────────────────
                S_FEED_F1: begin
                    x_in_r  <= x_reg[1];
                    sv_in_r <= sv_reg[1];
                    state   <= S_FEED_F2;
                end

                S_FEED_F2: begin
                    x_in_r  <= x_reg[2];
                    sv_in_r <= sv_reg[2];
                    state   <= S_FEED_F3;
                end

                S_FEED_F3: begin
                    x_in_r  <= x_reg[3];
                    sv_in_r <= sv_reg[3];
                    state   <= S_WAIT_KERNEL;
                end

                // ─────────────────────────────────────────────────
                // WAIT_KERNEL: Wait for kernel pipeline to finish
                //              (dist_calc → gamma → CORDIC → exp)
                // ─────────────────────────────────────────────────
                S_WAIT_KERNEL: begin
                    if (k_valid) begin
                        if (sv_idx == N_SV - 1) begin
                            // All support vectors processed
                            state <= S_DONE_WAIT;
                        end else begin
                            // Load next SV from DMA
                            sv_idx <= sv_idx + 1'b1;
                            state  <= S_LOAD_SV;
                        end
                    end
                end

                // ─────────────────────────────────────────────────
                // DONE_WAIT: All SVs done, wait for ready
                //            (decision engines assert done)
                // ─────────────────────────────────────────────────
                S_DONE_WAIT: begin
                    if (svm_ready) begin
                        // Assert master valid — prediction is stable
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= tlast_captured;
                        state         <= S_OUTPUT;
                    end
                end

                // ─────────────────────────────────────────────────
                // OUTPUT: Hold valid until downstream ready
                // ─────────────────────────────────────────────────
                S_OUTPUT: begin
                    if (m_axis_tready) begin
                        // Handshake complete — result transferred
                        m_axis_tvalid  <= 1'b0;
                        m_axis_tlast   <= 1'b0;
                        tlast_captured <= 1'b0;
                        state          <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

    // ─── svm_top Instantiation ──────────────────────────────────────
    svm_top #(
        .WIDTH(WIDTH),
        .N_FEATURES(N_FEATURES),
        .N_SV(N_SV)
    ) svm_inst (
        .clk           (axi_clk),
        .rst           (rst),
        .sample_start  (sample_start_r),
        .sv_start      (sv_start_r),
        .x_in          (x_in_r),
        .sv_in         (sv_in_r),
        .alpha_0       (alpha0_reg),
        .alpha_1       (alpha1_reg),
        .rho_0         (rho_reg[0]),
        .rho_1         (rho_reg[1]),
        .rho_2         (rho_reg[2]),
        .predicted_class (predicted_class),
        .ready         (svm_ready),
        .k_valid_out   (k_valid)
    );

endmodule
