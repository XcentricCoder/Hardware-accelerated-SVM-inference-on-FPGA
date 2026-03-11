#ifndef SVM_MODEL_H
#define SVM_MODEL_H

// Auto-generated SVM model parameters
// Feature order:
//   0: Number_of_times_pregnant
//   1: Plasma_glucose_concentration_a_2_hours_in_an_oral_glucose_tolerance_test
//   2: Diastolic_blood_pressure_mm_Hg
//   3: Triceps_skin_fold_thickness_mm
//   4: 2-Hour_serum_insulin_mu_U/ml
//   5: Body_mass_index_weight_in_kg/height_in_m^2
//   6: Diabetes_pedigree_function
//   7: Age_years

#define N_FEATURES 8

static const float svm_w[N_FEATURES] = {
    0.63916944f,
    1.51484106f,
    -0.12122639f,
    0.07918932f,
    0.16467443f,
    0.78282438f,
    0.47137621f,
    0.33427447f,
};

static const float svm_b = 2.33500000f;

#endif // SVM_MODEL_H
