/*
 * svm_rbf_main.c — Vitis bare-metal application for SVM RBF HW inference
 *
 * Packs test data + model parameters into the DMA TX buffer using the
 * format expected by svm_axi_wrapper.v, fires the DMA, and reads back
 * the classification results.
 *
 * ════════════════════════════════════════════════════════════════════
 *  TX BUFFER FORMAT (per sample — 97 × 32-bit words = 388 bytes)
 * ════════════════════════════════════════════════════════════════════
 *  Word  0:  x[0]       | x[1]         (test features, Q4.12)
 *  Word  1:  x[2]       | x[3]
 *  Word  2:  rho_0      | rho_1        (intercepts, Q4.12)
 *  Word  3:  rho_2      | 0x0000       (padding)
 *  --- For each SV (sv = 0..30), 3 words: ---
 *  Word 4+sv*3:  sv[sv][0] | sv[sv][1]
 *  Word 5+sv*3:  sv[sv][2] | sv[sv][3]
 *  Word 6+sv*3:  alpha_0[sv] | alpha_1[sv]
 *
 * ════════════════════════════════════════════════════════════════════
 *  RX BUFFER FORMAT (per sample — 1 × 32-bit word = 4 bytes)
 * ════════════════════════════════════════════════════════════════════
 *  Word 0:  {30'b0, predicted_class[1:0]}
 */

#include "xaxidma.h"
#include "xparameters.h"
#include "xil_cache.h"
#include "xil_printf.h"

/* ── Model & Data Parameters ──────────────────────────────────────── */
#define NUM_FEATURES        4
#define NUM_SV              31
#define NUM_CLASSIFIERS     3
#define NUM_TEST_SAMPLES    30

/* ── DMA Buffer Sizing ────────────────────────────────────────────── */
#define WORDS_PER_SAMPLE    (4 + NUM_SV * 3)            /* 4 header + 31*3 SV = 97 words */
#define TX_BUFFER_SIZE      (NUM_TEST_SAMPLES * WORDS_PER_SAMPLE * 4)  /* bytes */
#define RX_BUFFER_SIZE      (NUM_TEST_SAMPLES * 4)                     /* bytes */

/* ── Memory Addresses ─────────────────────────────────────────────── */
#define TX_MEM_ADDR         0x10000000
#define RX_MEM_ADDR         0x11000000

/* ────────────────────────────────────────────────────────────────────
 *  Q4.12 QUANTIZED MODEL PARAMETERS
 *  (from svm_model_quantized.h — embedded directly to avoid
 *   header dependency issues in Vitis bare-metal)
 * ──────────────────────────────────────────────────────────────────── */

/* Support vectors [31][4] in Q4.12 */
static const int16_t q_sv[31][4] = {
    {  -2160,   3225,  -5280,  -4342 },
    {   -693,  12395,  -5280,  -4342 },
    {  -6073,   3225,  -5512,  -4881 },
    {  -6562,  -6863,  -5745,  -4881 },
    {  -1671,   4142,  -5745,  -5420 },
    {  -3628,   2308,  -4814,  -3802 },
    {  -7541,   -443,  -6210,  -5959 },
    {    774,  -1360,   1698,   1591 },
    {  -4117,  -9614,   -628,  -1106 },
    {   2242,  -5028,   2628,   1591 },
    {  -3139,  -3194,    302,   1052 },
    {    285,   1391,   2396,   3209 },
    {   5666,   1391,   2163,   1052 },
    {    774,  -3194,   3093,   2130 },
    {  -1182,   -443,   1698,   1591 },
    {   3220,  -2277,   1930,   1591 },
    {    774,   3225,   1698,   2130 },
    {   1753,  -7780,   1698,   1591 },
    {  -3628,  -5028,  -1791,   -566 },
    {   5177,    474,   2628,   1591 },
    {  -4606,  -5028,   1698,   2670 },
    {   2242,  -2277,   3093,   1591 },
    {  10068,   6893,   6117,   4288 },
    {   1753,   3225,   3791,   5906 },
    {    285,   -443,   3093,   3209 },
    {    774,  -7780,   2861,   1591 },
    {   6644,   -443,   4721,   2130 },
    {   2242,  -3194,   2628,   3209 },
    {   3220,   1391,   3093,   4288 },
    {   9090,  -4111,   7280,   5906 },
    {   1753,  -2277,   2396,   3209 }
};

/* Dual coefficients [2][31] in Q4.12 */
static const int16_t q_dual_coef[2][31] = {
    {      0,   3087,      0,   7412,      0,   4675,      0,      0,
       -3306,      0,      0,      0,  -2278,      0,      0,      0,
       -2991,      0,  -6599,      0,  -3486,      0,  -2689,  -1952,
           0,  -1416,      0,      0,      0,  -2491,      0 },
    {    669,   3948,    867,   4415,     91,   1709,    336,   4584,
        4409,  32767,  10482,  32767,      0,  32767,   3902,  14388,
           0,  26664,      0,  32767, -13349, -32768,  -4261,      0,
       -32768, -32768, -22346, -13632, -10840,      0, -32768 }
};

/* Intercepts [3] in Q4.12 */
static const int16_t q_intercept[3] = { 413, -525, 593 };

/* ── Q4.12 Scaled Test Features [30][4] ───────────────────────────── */
static const int16_t q_test[30][4] = {
    {  -7052,   -443,  -5745,  -5420 },
    {   1264,   -443,   2628,   3209 },
    {  -4606,  -5946,  -1093,  -1106 },
    {  -4117,  -6863,  -1093,  -1106 },
    {  -7052,   1391,  -5745,  -5420 },
    {   2242,   2308,   2163,   2130 },
    {  -6073,   5059,  -6442,  -5420 },
    {  -2160,   3225,  -4814,  -5420 },
    {   3220,   -443,   3326,   4288 },
    {  -2160,   -443,   1698,   1591 },
    {   7133,  -1360,   5884,   3209 },
    {   5177,    474,   3093,   5906 },
    {   3220,   -443,   4721,   5366 },
    {   2731,   1391,   1698,   1591 },
    {  -4117,   3225,  -5280,  -5420 },
    {  -4117,   2308,  -5512,  -5420 },
    {   -204,   8727,  -5977,  -5420 },
    {  -1182,  -5028,    302,   -566 },
    {   1264,  -1360,   2163,   1052 },
    {    774,   -443,   2396,   3209 },
    {  -2160,   5976,  -5280,  -5420 },
    {   4198,    474,   4256,   6445 },
    {   3709,  -1360,   1930,    512 },
    {   1264,  -4111,   4256,   1052 },
    {   2731,  -2277,   4256,   5366 },
    {   4198,   -443,   2861,   2670 },
    {   3709,   -443,   1465,   1052 },
    {   -693,   6893,  -4814,  -4881 },
    {   3220,   -443,   4024,   3209 },
    {  -3139,   3225,  -5512,  -5420 }
};

/* Ground-truth labels */
static const int test_labels[30] = {
    0, 2, 1, 1, 0, 1, 0, 0, 2, 1, 2, 2, 2, 1, 0, 0, 0, 1, 1, 2, 0, 2, 1, 2, 2, 1, 1, 0, 2, 0
};

static const char * const class_names[3] = { "setosa", "versicolor", "virginica" };

/* ────────────────────────────────────────────────────────────────────
 *  HELPER: Pack two 16-bit values into one 32-bit word
 *          {high16, low16}
 * ──────────────────────────────────────────────────────────────────── */
static inline uint32_t pack16(int16_t low, int16_t high)
{
    return ((uint32_t)(uint16_t)high << 16) | (uint32_t)(uint16_t)low;
}

/* ────────────────────────────────────────────────────────────────────
 *  HELPER: Pack one sample's data into the TX buffer
 *          Returns pointer to the next word after this sample.
 * ──────────────────────────────────────────────────────────────────── */
static uint32_t *pack_sample(uint32_t *buf, int sample_idx)
{
    const int16_t *x = q_test[sample_idx];

    /* ── Header (4 words) ── */
    *buf++ = pack16(x[0], x[1]);                            /* Word 0: x[0] | x[1]   */
    *buf++ = pack16(x[2], x[3]);                            /* Word 1: x[2] | x[3]   */
    *buf++ = pack16(q_intercept[0], q_intercept[1]);        /* Word 2: rho_0 | rho_1  */
    *buf++ = pack16(q_intercept[2], 0);                     /* Word 3: rho_2 | pad    */

    /* ── Per-SV data (3 words × 31 SVs) ── */
    for (int sv = 0; sv < NUM_SV; sv++) {
        *buf++ = pack16(q_sv[sv][0], q_sv[sv][1]);          /* sv_feat[0] | sv_feat[1]     */
        *buf++ = pack16(q_sv[sv][2], q_sv[sv][3]);          /* sv_feat[2] | sv_feat[3]     */
        *buf++ = pack16(q_dual_coef[0][sv], q_dual_coef[1][sv]); /* alpha_0 | alpha_1      */
    }

    return buf;  /* pointer to start of next sample */
}

/* ════════════════════════════════════════════════════════════════════
 *  MAIN
 * ════════════════════════════════════════════════════════════════════ */
int main()
{
    XAxiDma_Config *dma_config;
    XAxiDma         dma_inst;
    int             status;

    /* ── Initialize DMA ──────────────────────────────────────────── */
    dma_config = XAxiDma_LookupConfig(XPAR_AXI_DMA_0_DEVICE_ID);
    if (!dma_config) {
        xil_printf("ERROR: DMA config lookup failed.\r\n");
        return -1;
    }

    status = XAxiDma_CfgInitialize(&dma_inst, dma_config);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: DMA init failed (status=%d).\r\n", status);
        return -1;
    }

    /* Disable interrupts — we're polling */
    XAxiDma_IntrDisable(&dma_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&dma_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    xil_printf("═══════════════════════════════════════════════════\r\n");
    xil_printf("  SVM RBF Hardware Inference — %d samples\r\n", NUM_TEST_SAMPLES);
    xil_printf("  TX buffer: %d words/sample × %d samples = %d bytes\r\n",
               WORDS_PER_SAMPLE, NUM_TEST_SAMPLES, TX_BUFFER_SIZE);
    xil_printf("═══════════════════════════════════════════════════\r\n\r\n");

    /* ── Pack all test samples into the TX buffer ────────────────── */
    uint32_t *tx_buf = (uint32_t *)TX_MEM_ADDR;
    uint32_t *ptr    = tx_buf;

    for (int i = 0; i < NUM_TEST_SAMPLES; i++) {
        ptr = pack_sample(ptr, i);
    }

    xil_printf("Packed %d samples (%d words) at 0x%08X\r\n",
               NUM_TEST_SAMPLES, (int)(ptr - tx_buf), TX_MEM_ADDR);

    /* ── Flush TX buffer from cache to DDR ───────────────────────── */
    Xil_DCacheFlushRange(TX_MEM_ADDR, TX_BUFFER_SIZE);

    /* ── Arm RX DMA (S2MM) first ─────────────────────────────────── */
    xil_printf("Arming RX DMA at 0x%08X (%d bytes)...\r\n", RX_MEM_ADDR, RX_BUFFER_SIZE);
    status = XAxiDma_SimpleTransfer(&dma_inst, RX_MEM_ADDR, RX_BUFFER_SIZE, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: RX DMA transfer setup failed.\r\n");
        return -1;
    }

    /* ── Fire TX DMA (MM2S) ──────────────────────────────────────── */
    xil_printf("Firing TX DMA from 0x%08X (%d bytes)...\r\n", TX_MEM_ADDR, TX_BUFFER_SIZE);
    status = XAxiDma_SimpleTransfer(&dma_inst, TX_MEM_ADDR, TX_BUFFER_SIZE, XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: TX DMA transfer setup failed.\r\n");
        return -1;
    }

    /* ── Poll until both channels complete ───────────────────────── */
    xil_printf("Waiting for DMA completion...\r\n");
    while (XAxiDma_Busy(&dma_inst, XAXIDMA_DMA_TO_DEVICE))  {}
    while (XAxiDma_Busy(&dma_inst, XAXIDMA_DEVICE_TO_DMA))  {}

    /* ── Invalidate RX buffer cache to read fresh data from DDR ──── */
    Xil_DCacheInvalidateRange(RX_MEM_ADDR, RX_BUFFER_SIZE);

    /* ── Read back and display results ───────────────────────────── */
    xil_printf("\r\n════════════════════════════════════════════════\r\n");
    xil_printf("  RESULTS\r\n");
    xil_printf("════════════════════════════════════════════════\r\n");

    volatile uint32_t *rx_buf = (volatile uint32_t *)RX_MEM_ADDR;
    int correct = 0;

    for (int i = 0; i < NUM_TEST_SAMPLES; i++) {
        int predicted = rx_buf[i] & 0x3;     /* 2-bit class from wrapper */
        int expected  = test_labels[i];

        if (predicted == expected) correct++;

        xil_printf("Sample %2d | true=%-11s | pred=%-11s | %s\r\n",
                   i,
                   class_names[expected],
                   class_names[predicted],
                   (predicted == expected) ? "OK" : "WRONG");
    }

    xil_printf("\r\nAccuracy: %d/%d\r\n", correct, NUM_TEST_SAMPLES);
    xil_printf("Hardware inference complete.\r\n");

    return 0;
}
