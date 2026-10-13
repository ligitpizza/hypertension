import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/core/utils/risk_style.dart';
import 'package:hypertension/features/vitals/data/vitals_repository.dart';

// POST /api/v1/vitals response after Module 9 (FR-9.2, FR-9.4, UC9.1-UC9.3).
void main() {
  final now = DateTime(2026, 10, 13, 9);

  Map<String, dynamic> scores() => {
    for (final c in Complication.values) c.value: {'value': 0.004, 'level': 'low'},
    'stroke': {'value': 0.31, 'level': 'high'},
  };

  test('FR-9.2 parses the risk score, diagnosed conditions and tips', () {
    final r = LoggedReading.fromApi({
      'id': 'r1',
      'systolic': 150,
      'diastolic': 95,
      'heartRate': null,
      'category': 'stage2',
      'alertLevel': 'moderate',
      'risk': {
        'scoreId': 's1',
        'overallLevel': 'high',
        'scores': scores(),
        'lowConfidence': true,
        'missingInputs': ['heart_rate'],
        'diagnosed': ['t2d'],
      },
      'riskStatus': 'ok',
      'readingsUntilRisk': 0,
      'recommendations': ['Tip', 'Disclaimer'],
      'bookAppointmentPrompt': true,
    }, now);
    expect(r.risk!.overall, RiskLevel.high);
    expect(r.risk!.scores[Complication.stroke]!.value, 0.31);
    expect(r.risk!.scores[Complication.ckd]!.level, RiskLevel.low);
    expect(r.risk!.lowConfidence, isTrue);
    expect(r.risk!.diagnosed, {Complication.t2d});
    expect(r.recommendations, ['Tip', 'Disclaimer']);
    expect(r.bookAppointmentPrompt, isTrue);
  });

  test('UC9.1 before three readings there is no risk, only progress', () {
    final r = LoggedReading.fromApi({
      'id': 'r1',
      'systolic': 120,
      'diastolic': 80,
      'category': 'normal',
      'alertLevel': null,
      'risk': null,
      'riskStatus': 'not_enough_readings',
      'readingsUntilRisk': 2,
    }, now);
    expect(r.risk, isNull);
    expect(r.readingsUntilRisk, 2);
    expect(r.recommendations, isEmpty);
    expect(r.bookAppointmentPrompt, isFalse);
  });

  test('risk below half a percent shows as <1%', () {
    expect(riskPercent(0.004), '<1%');
    expect(riskPercent(0.005), '1%');
    expect(riskPercent(0.314), '31%');
  });
}
