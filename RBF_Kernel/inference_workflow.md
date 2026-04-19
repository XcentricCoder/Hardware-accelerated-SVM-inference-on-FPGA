# Hardware SVM Inference Workflow Report

This document outlines the step-by-step data flow and architectural execution of the RBF-Kernel Support Vector Machine (SVM) inference pipeline designed in your RTL.

---

## 1. Input Streaming & Top-Level Control (`svm_top.v`)
The inference process is triggered sequentially by the testbench or host controller.
1. **Sample Initialization:** The host pulses the `sample_start` signal. This tells the system that a new prediction is beginning, which resets the accumulators inside the decision engines to their starting intercept boundaries.
2. **Feature Streaming:** The SVM model contains 31 Support Vectors (SVs), and each SV has 4 features (dimensions). The host streams these features one by one, 1 feature per clock cycle.
3. **SV Synchronization:** On the very first feature of each Support Vector, the host pulses `sv_start`. This signals the downstream distance calculator to begin a new accumulation.

## 2. Squared Euclidean Distance Calculation (`dist_calc.v`)
As the features stream in, they immediately enter the distance calculator.
1. **Difference & Square:** For the current feature dimension, the module computes the subtraction `(x_in - sv_in)` and multiplies the result by itself `(x_in - sv_in)^2`.
2. **Accumulation:** The squared differences are accumulated internally over 4 clock cycles (since $N\_FEATURES=4$).
3. **Completion:** On the 4th cycle, the total squared Euclidean distance $||x - sv||^2$ is finalized, and a valid pulse is sent to the next stage.

## 3. RBF Kernel Evaluation (`kernel.v` & `cordic_exp.v`)
The heart of the non-linear SVM is the Radial Basis Function (RBF) kernel: $K(x, y) = \exp(-\gamma ||x - y||^2)$.
1. **Gamma Scaling:** The squared distance is first scaled by the gamma parameter. In this fixed-point design, gamma is optimized into a bitwise right-shift operations (essentially $z = -(sq\_dist \gg 14)$).
2. **Underflow Protection:** If the negative distance is too large (e.g., $z < -4352$), the output is clamped to `0`. This prevents catastrophic wrap-around errors that can occur when dealing with extremely small fractional numbers in fixed-point representation.
3. **CORDIC Exponential:** If the value is within range, it is fed into the CORDIC pipeline. Over multiple clock cycles, the CORDIC mathematically approximates $e^z$, outputting the final Kernel similarity score (a `Q4.12` value) between the test sample and the current Support Vector.

## 4. Decision Engines & Multiclass OvO logic (`svm_decision_engine.v`)
Because scikit-learn uses a One-vs-One (OvO) approach for multiclass problems, a 3-class problem (Setosa, Versicolor, Virginica) requires 3 separate binary classifiers.
1. **Three Parallel Engines:** `svm_top.v` instantiates three decision engines:
   - `engine_01`: Decides between Class 0 and Class 1
   - `engine_02`: Decides between Class 0 and Class 2
   - `engine_12`: Decides between Class 1 and Class 2
2. **Accumulator Initialization:** When `sample_start` is pulsed, each engine initializes its internal 32-bit accumulator to `-intercept` ($-rho$).
3. **Coefficient Multiplexing:** As the kernel values emerge from the CORDIC, a multiplexer checks the current SV index and routes the correct dual coefficients (`alpha_0` and `alpha_1`) to the appropriate engines:
   - SVs 0-6 (Class 0): routed to `engine_01` and `engine_02`.
   - SVs 7-19 (Class 1): routed to `engine_01` and `engine_12`.
   - SVs 20-30 (Class 2): routed to `engine_02` and `engine_12`.
4. **Multiply & Accumulate:** Each engine multiplies the shared `kernel_val` by its routed `dual_coeff` and adds it to the running sum.

## 5. Voting and Classification (Argmax)
1. **Final Decision:** Once all 31 Support Vectors have been streamed and processed, the 3 decision engines simultaneously assert their `done` flags.
2. **Score Extraction:** The final accumulated values (`score_01`, `score_02`, `score_12`) represent the confidence of the pairwise binary decisions.
3. **Tallying Votes:** The logic converts the continuous scores into discrete votes:
   - If `score_01 > 0`, Class 0 gets 1 vote. Otherwise, Class 1 gets 1 vote.
   - If `score_02 > 0`, Class 0 gets 1 vote. Otherwise, Class 2 gets 1 vote.
   - If `score_12 > 0`, Class 1 gets 1 vote. Otherwise, Class 2 gets 1 vote.
4. **Argmax Output:** The class with the maximum number of votes is declared the winner. `predicted_class` is updated with this index (0, 1, or 2), and the top-level `ready` flag is set high, successfully completing the inference pipeline for the sample.
