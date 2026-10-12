import '../../../../core/constants/enums.dart';

/// Plain-language labels for onboarding choices (NFR-3.1).
abstract final class OnboardingLabels {
  static String gender(Gender g) => switch (g) {
    Gender.male => 'Male',
    Gender.female => 'Female',
    Gender.other => 'Other',
  };

  static String condition(MedicalCondition c) => switch (c) {
    MedicalCondition.diabetes => 'Diabetes',
    MedicalCondition.chronicKidneyDisease => 'Kidney disease',
    MedicalCondition.heartDisease => 'Heart disease',
    MedicalCondition.heartFailure => 'Heart failure',
    MedicalCondition.stroke => 'Previous stroke',
    MedicalCondition.highCholesterol => 'High cholesterol',
  };

  static String family(FamilyHistoryCondition c) => switch (c) {
    FamilyHistoryCondition.hypertension => 'High blood pressure',
    FamilyHistoryCondition.heartDisease => 'Heart disease',
    FamilyHistoryCondition.stroke => 'Stroke',
    FamilyHistoryCondition.diabetes => 'Diabetes',
    FamilyHistoryCondition.kidneyDisease => 'Kidney disease',
  };

  static String smoking(SmokingStatus s) => switch (s) {
    SmokingStatus.never => 'Never smoked',
    SmokingStatus.former => 'Used to smoke',
    SmokingStatus.current => 'Smoke now',
  };

  static String alcohol(AlcoholUse a) => switch (a) {
    AlcoholUse.none => 'None',
    AlcoholUse.occasional => 'Occasionally',
    AlcoholUse.regular => 'Regularly',
  };

  static String salt(SaltIntake s) => switch (s) {
    SaltIntake.low => 'Low',
    SaltIntake.moderate => 'Moderate',
    SaltIntake.high => 'High',
  };
}
