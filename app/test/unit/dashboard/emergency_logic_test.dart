import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/dashboard/domain/dashboard_logic.dart';
import 'package:hypertension/shared/models/health_models.dart';

// D-37: dashboard one-tap emergency call while an emergency is active.
void main() {
  final now = DateTime(2026, 10, 13, 12);
  VitalReading r(int sys, int dia, Duration ago) => VitalReading(
    id: 'r',
    patientId: 'p',
    systolic: sys,
    diastolic: dia,
    timestamp: now.subtract(ago),
  );

  bool active({VitalReading? reading, TriageOutcome? triage, Duration? triageAgo}) =>
      activeEmergency(
        latestReading: reading,
        latestTriage: triage,
        latestTriageAt: triageAgo == null ? null : now.subtract(triageAgo),
        now: now,
      );

  test('crisis reading within 6 h (boundary inclusive)', () {
    expect(active(reading: r(180, 90, const Duration(hours: 6))), isTrue);
    expect(active(reading: r(140, 120, const Duration(hours: 1))), isTrue);
    expect(active(reading: r(186, 122, const Duration(hours: 6, minutes: 1))), isFalse);
  });

  test('non-crisis readings never activate it', () {
    expect(active(reading: r(179, 119, const Duration(minutes: 1))), isFalse);
  });

  test('emergency symptom check within 6 h; other outcomes do not', () {
    expect(
      active(triage: TriageOutcome.seekEmergencyCare, triageAgo: const Duration(hours: 2)),
      isTrue,
    );
    expect(
      active(triage: TriageOutcome.seekEmergencyCare, triageAgo: const Duration(hours: 7)),
      isFalse,
    );
    expect(
      active(triage: TriageOutcome.contactDoctor, triageAgo: const Duration(minutes: 5)),
      isFalse,
    );
  });
}
