import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/dashboard/domain/dashboard_logic.dart';
import 'package:hypertension/shared/models/health_models.dart';

VitalReading r(int sys, DateTime t) =>
    VitalReading(id: '$sys', patientId: 'p', systolic: sys, diastolic: 80, timestamp: t);

void main() {
  final now = DateTime(2026, 10, 12, 9, 30);

  test('FR-2.1 greeting follows time of day', () {
    expect(greetingFor(DateTime(2026, 1, 1, 8)), 'Good Morning');
    expect(greetingFor(DateTime(2026, 1, 1, 13)), 'Good Afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 20)), 'Good Evening');
  });

  group('FR-2.1 latest BP change from yesterday', () {
    test('compares with the latest reading from an earlier day', () {
      final list = [
        r(128, now),
        r(130, now.subtract(const Duration(hours: 2))), // same day: ignored
        r(132, DateTime(2026, 10, 11, 21)),
        r(150, DateTime(2026, 10, 10, 8)),
      ];
      expect(systolicChangeFromPreviousDay(list), -4);
    });

    test('null when there is no earlier day or no readings', () {
      expect(systolicChangeFromPreviousDay([]), isNull);
      expect(systolicChangeFromPreviousDay([r(120, now), r(125, now)]), isNull);
    });
  });

  test('time ago labels', () {
    expect(timeAgo(now.subtract(const Duration(seconds: 20)), now), 'just now');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
    expect(timeAgo(now.subtract(const Duration(hours: 2)), now), '2 hours ago');
    expect(timeAgo(now.subtract(const Duration(hours: 30)), now), 'yesterday');
    expect(timeAgo(now.subtract(const Duration(days: 3)), now), '3 days ago');
  });

  test('UC2.3 appointment labels', () {
    expect(appointmentLabel(DateTime(2026, 10, 13, 10, 30), now), 'Tomorrow, 10:30 AM');
    expect(appointmentLabel(DateTime(2026, 10, 12, 15, 5), now), 'Today, 3:05 PM');
    expect(appointmentLabel(DateTime(2026, 10, 20, 0, 0), now), '20 Oct, 12:00 AM');
  });

  group('D-03 risk score parsing', () {
    test('overall level is the highest complication level', () {
      final score = RiskScore.fromFirestore('s1', {
        'patientId': 'p',
        'modelUsed': 'stroke:XGBoost v1',
        'generatedAt': Timestamp.fromDate(now),
        'scores': {
          'stroke': {'value': 0.2, 'level': 'low'},
          'cad': {'value': 0.6, 'level': 'high'},
          'heartFailure': {'value': 0.4, 'level': 'moderate'},
          'unknownThing': {'value': 0.9, 'level': 'critical'}, // ignored
        },
      });
      expect(score.overallLevel, RiskLevel.high);
      expect(score.scores.length, 3);
      expect(score.generatedAt, now);
    });

    test('empty scores default to low', () {
      final score = RiskScore.fromFirestore('s', {'patientId': 'p', 'scores': {}});
      expect(score.overallLevel, RiskLevel.low);
    });
  });

  test('UC2.3 only booked or rescheduled appointments are upcoming', () {
    Appointment a(String status) => Appointment.fromFirestore('a', {
      'patientId': 'p',
      'dateTime': Timestamp.fromDate(now),
      'status': status,
    });
    expect(a('booked').isActive, isTrue);
    expect(a('rescheduled').isActive, isTrue);
    expect(a('cancelled').isActive, isFalse);
    expect(a('completed').isActive, isFalse);
  });

  test('vital reading parses optional heart rate and note', () {
    final v = VitalReading.fromFirestore('v', {
      'patientId': 'p',
      'systolic': 128.0,
      'diastolic': 82,
      'heartRate': 71,
      'timestamp': Timestamp.fromDate(now),
    });
    expect((v.systolic, v.diastolic, v.heartRate, v.note), (128, 82, 71, null));
  });
}
