import 'dart:ui' show Color;

import '../constants/enums.dart';
import '../theme/app_theme.dart';

/// BP classification, threshold alert level and plausible range (docs/06 §E, FR-9.1).
/// Dart mirror of backend/app/services/bp.py; both are tested against
/// docs/fixtures/bp_cases.json.
abstract final class BpClassifier {
  static const systolicMin = 70;
  static const systolicMax = 250;
  static const diastolicMin = 40;
  static const diastolicMax = 150;
  static const heartRateMin = 30;
  static const heartRateMax = 220;

  /// First match, top-down.
  static BpCategory classify(int systolic, int diastolic) {
    if (systolic >= 180 || diastolic >= 120) return BpCategory.crisis;
    if (systolic >= 140 || diastolic >= 90) return BpCategory.stage2;
    if (systolic >= 130 || diastolic >= 80) return BpCategory.stage1;
    if (systolic >= 120) return BpCategory.elevated;
    return BpCategory.normal;
  }

  /// Mild / Moderate / Emergency threshold alert, or null for normal and elevated.
  static AlertLevel? alertLevel(BpCategory c) => switch (c) {
    BpCategory.stage1 => AlertLevel.mild,
    BpCategory.stage2 => AlertLevel.moderate,
    BpCategory.crisis => AlertLevel.emergency,
    _ => null,
  };

  /// UC3.1 E1: a user-facing reason when the reading is implausible, or null.
  static String? plausibilityError(int systolic, int diastolic, {int? heartRate}) {
    if (systolic < systolicMin || systolic > systolicMax) {
      return 'Systolic must be between $systolicMin and $systolicMax mmHg.';
    }
    if (diastolic < diastolicMin || diastolic > diastolicMax) {
      return 'Diastolic must be between $diastolicMin and $diastolicMax mmHg.';
    }
    if (systolic <= diastolic) {
      return 'Systolic (top number) must be higher than diastolic (bottom number).';
    }
    if (heartRate != null && (heartRate < heartRateMin || heartRate > heartRateMax)) {
      return 'Heart rate must be between $heartRateMin and $heartRateMax bpm.';
    }
    return null;
  }

  static String label(BpCategory c) => switch (c) {
    BpCategory.normal => 'Normal',
    BpCategory.elevated => 'Elevated',
    BpCategory.stage1 => 'High — Stage 1',
    BpCategory.stage2 => 'High — Stage 2',
    BpCategory.crisis => 'Hypertensive Crisis',
  };

  static Color color(BpCategory c) => switch (c) {
    BpCategory.normal => BpColors.normal,
    BpCategory.elevated => BpColors.elevated,
    BpCategory.stage1 => BpColors.stage1,
    BpCategory.stage2 => BpColors.stage2,
    BpCategory.crisis => BpColors.crisis,
  };
}
