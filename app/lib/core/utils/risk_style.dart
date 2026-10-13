import 'dart:ui' show Color;

import '../constants/enums.dart';
import '../theme/app_theme.dart';

/// Colour and label for a risk level (FR-9.3), shared by dashboard, trends and portal.
Color riskColor(RiskLevel level) => switch (level) {
  RiskLevel.low => BpColors.normal,
  RiskLevel.moderate => BpColors.elevated,
  RiskLevel.high => BpColors.stage2,
  RiskLevel.critical => BpColors.crisis,
};

String riskLabel(RiskLevel level) => switch (level) {
  RiskLevel.low => 'Low Risk',
  RiskLevel.moderate => 'Moderate Risk',
  RiskLevel.high => 'High Risk',
  RiskLevel.critical => 'Critical Risk',
};

/// Probability as a whole percentage; values that round to 0 show as "<1%".
String riskPercent(double value) {
  final pct = (value * 100).round();
  return pct < 1 ? '<1%' : '$pct%';
}

/// D-40: short labels for model inputs shown as contributing factors.
const factorLabels = {
  'age': 'Age',
  'female': 'Sex',
  'systolic': 'Systolic BP',
  'diastolic': 'Diastolic BP',
  'heart_rate': 'Heart rate',
  'bmi': 'BMI',
  'smoking': 'Smoking',
  'family_history': 'Family history',
  'hypertension': 'Hypertension',
  'high_cholesterol': 'High cholesterol',
  'bp_medication': 'BP medication',
  'medication_count': 'Number of medicines',
  'stroke': 'Previous stroke',
  'cad': 'Coronary artery disease',
  'heartFailure': 'Heart failure',
  'ckd': 'Kidney disease',
  't2d': 'Diabetes',
};

String factorLabel(String key) => factorLabels[key] ?? key;
