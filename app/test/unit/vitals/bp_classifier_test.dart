import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/core/utils/bp_classifier.dart';

/// Objective 1: alert thresholds verified by unit tests. Same fixture as backend/tests/test_bp.py.
void main() {
  final fixture =
      jsonDecode(File('../docs/fixtures/bp_cases.json').readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
  final implausible = (fixture['implausible'] as List).cast<Map<String, dynamic>>();
  final plausible = fixture['plausible'] as Map<String, dynamic>;

  for (final c in cases) {
    test('FR-9.1 ${c['sys']}/${c['dia']} -> ${c['category']} (${c['why']})', () {
      final category = BpClassifier.classify(c['sys'] as int, c['dia'] as int);
      expect(category, BpCategory.fromValue(c['category'] as String));
      final alert = c['alert'] as String?;
      expect(BpClassifier.alertLevel(category), alert == null ? null : AlertLevel.fromValue(alert));
      expect(BpClassifier.plausibilityError(c['sys'] as int, c['dia'] as int), isNull);
    });
  }

  for (final c in implausible) {
    test('UC3.1 E1 rejects ${c['sys']}/${c['dia']} (${c['why']})', () {
      expect(BpClassifier.plausibilityError(c['sys'] as int, c['dia'] as int), isNotNull);
    });
  }

  test('UC3.3 heart rate range matches the fixture', () {
    final lo = plausible['heartRateMin'] as int;
    final hi = plausible['heartRateMax'] as int;
    expect(BpClassifier.plausibilityError(120, 80, heartRate: lo), isNull);
    expect(BpClassifier.plausibilityError(120, 80, heartRate: hi), isNull);
    expect(BpClassifier.plausibilityError(120, 80, heartRate: lo - 1), isNotNull);
    expect(BpClassifier.plausibilityError(120, 80, heartRate: hi + 1), isNotNull);
  });

  test('plausible limits match the fixture', () {
    expect(
      (BpClassifier.systolicMin, BpClassifier.systolicMax),
      (plausible['systolicMin'], plausible['systolicMax']),
    );
    expect(
      (BpClassifier.diastolicMin, BpClassifier.diastolicMax),
      (plausible['diastolicMin'], plausible['diastolicMax']),
    );
  });

  test('every category has a label and a colour', () {
    for (final c in BpCategory.values) {
      expect(BpClassifier.label(c), isNotEmpty);
      expect(BpClassifier.color(c), isNotNull);
    }
  });
}
