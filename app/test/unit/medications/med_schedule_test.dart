import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/medications/data/dose_reminders.dart';
import 'package:hypertension/features/medications/domain/med_schedule.dart';
import 'package:hypertension/shared/models/health_models.dart';

// Module 5 schedule rules (FR-5.1-5.4; UC5.2, UC5.3, UC5.5; D-43). Mirrors
// backend/tests/test_medications.py so the app and API agree on dose ids.

Medication med(String id, String schedule, {double? qty, int threshold = 7}) => Medication(
  id: id,
  patientId: 'p1',
  name: 'Amlodipine',
  dosage: '5mg',
  schedule: schedule,
  quantityOnHand: qty,
  refillThresholdDays: threshold,
);

void main() {
  group('D-43 schedule format', () {
    test('parses, sorts and de-duplicates dose times', () {
      expect(parseSchedule(' 20:00, 08:00 ,08:00'), const [DoseTime(8, 0), DoseTime(20, 0)]);
      expect(formatSchedule(parseSchedule('20:00,08:00')), '08:00,20:00');
      expect(parseSchedule('AS_NEEDED'), isNull);
      expect(formatSchedule(null), asNeeded);
    });

    for (final bad in ['', '8am', '24:00', '08:60']) {
      test('rejects "$bad"', () => expect(() => parseSchedule(bad), throwsFormatException));
    }

    test('describes times for people', () {
      expect(describeSchedule('08:00,20:30'), '8:00 AM, 8:30 PM');
      expect(describeSchedule('00:15'), '12:15 AM');
      expect(describeSchedule('as_needed'), 'As needed');
      expect(describeSchedule('Take with breakfast'), 'Take with breakfast');
    });
  });

  group('Malaysia time', () {
    test('dose moments are MYT whatever the instant', () {
      final now = DateTime.utc(2026, 10, 14, 3); // 11:00 MYT
      expect(doseMoment(now, const DoseTime(8, 0)), DateTime.utc(2026, 10, 14, 0));
      // 23:30 UTC on the 13th is already the 14th in Malaysia.
      expect(startOfMytDay(DateTime.utc(2026, 10, 13, 23, 30)), DateTime.utc(2026, 10, 13, 16));
    });

    test('dose id matches the API (medication + MYT yyyyMMddHHmm)', () {
      expect(doseId('m1', DateTime.utc(2026, 10, 14, 0)), 'm1_202610140800');
    });
  });

  group('UC5.3 today\'s doses', () {
    final now = DateTime.utc(2026, 10, 14, 4); // 12:00 MYT
    final meds = [med('m1', '08:00,12:30,20:00'), med('m2', 'as_needed')];

    test('state from dose_logs and the time of day', () {
      final logs = {
        'm1_202610140800': DoseLog(
          id: 'm1_202610140800',
          medicationId: 'm1',
          scheduledTime: DateTime.utc(2026, 10, 14, 0),
          status: 'taken',
          confirmedAt: DateTime.utc(2026, 10, 14, 0, 15),
        ),
      };
      final doses = todaysDoses(meds, logs, now);
      expect(doses.map((d) => d.state), [DoseState.taken, DoseState.due, DoseState.upcoming]);
      expect(doses.map((d) => d.period), [
        DosePeriod.morning,
        DosePeriod.afternoon,
        DosePeriod.evening,
      ]);
      expect(doses.first.confirmedAt, DateTime.utc(2026, 10, 14, 0, 15));
    });

    test('a missed log shows as missed; as-needed medicines have no slots', () {
      final logs = {
        'm1_202610140800': DoseLog(
          id: 'm1_202610140800',
          medicationId: 'm1',
          scheduledTime: DateTime.utc(2026, 10, 14, 0),
          status: 'missed',
        ),
      };
      final doses = todaysDoses(meds, logs, now);
      expect(doses.first.state, DoseState.missed);
      expect(doses.every((d) => d.medication.id == 'm1'), isTrue);
    });
  });

  group('UC5.2 refill threshold (D-05)', () {
    test('days of supply per dose time', () {
      expect(daysOfSupply(med('a', '08:00,20:00', qty: 14)), 7);
      expect(daysOfSupply(med('a', '08:00')), isNull);
      expect(daysOfSupply(med('a', 'as_needed', qty: 3)), isNull);
    });

    test('below the threshold needs a refill', () {
      expect(needsRefill(med('a', '08:00,20:00', qty: 13)), isTrue);
      expect(needsRefill(med('a', '08:00,20:00', qty: 14)), isFalse);
      expect(needsRefill(med('a', '08:00', qty: 9, threshold: 10)), isTrue);
    });
  });

  group('D-43 local reminders', () {
    test('one stable id per medication and dose time', () {
      final planned = plannedReminders([med('m1', '08:00,20:00'), med('m2', 'as_needed')]);
      expect(planned, hasLength(2));
      expect(planned.keys, contains(reminderId('m1', const DoseTime(8, 0))));
      expect(reminderId('m1', const DoseTime(8, 0)), reminderId('m1', const DoseTime(8, 0)));
      expect(
        reminderId('m1', const DoseTime(8, 0)),
        isNot(reminderId('m1', const DoseTime(20, 0))),
      );
      expect(reminderId('m1', const DoseTime(8, 0)), lessThan(0x40000000));
    });

    test('signed out (no medicines) plans nothing', () {
      expect(plannedReminders(const []), isEmpty);
    });
  });
}
