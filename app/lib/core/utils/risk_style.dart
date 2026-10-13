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
