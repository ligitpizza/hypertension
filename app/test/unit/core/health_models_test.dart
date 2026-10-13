import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/core/utils/risk_style.dart';
import 'package:hypertension/shared/models/health_models.dart';

// D-40: contributing factors stored in risk_scores.scores entries.
void main() {
  test('risk score parses factors; older scores without them still load', () {
    final s = RiskScore.fromFirestore('s', {
      'patientId': 'p',
      'modelUsed': 'XGBoost v1',
      'scores': {
        'stroke': {
          'value': 0.3,
          'level': 'high',
          'factors': ['systolic', 'age'],
        },
        'ckd': {'value': 0.1, 'level': 'moderate'},
      },
    });
    expect(s.scores[Complication.stroke]!.factors, ['systolic', 'age']);
    expect(s.scores[Complication.ckd]!.factors, isEmpty);
  });

  test('factor labels', () {
    expect(factorLabel('heart_rate'), 'Heart rate');
    expect(factorLabel('t2d'), 'Diabetes');
    expect(factorLabel('unknown_input'), 'unknown_input');
  });
}
