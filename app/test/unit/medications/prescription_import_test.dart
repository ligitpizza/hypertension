import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/medications/domain/med_schedule.dart';
import 'package:hypertension/features/medications/domain/prescription_import.dart';
import 'package:hypertension/features/provider_portal/presentation/dose_history.dart';
import 'package:hypertension/shared/models/health_models.dart';

// D-49: "Add to my reminders" from a prescription, and the doctor's dose-history counts.

void main() {
  group('draftFromPrescription (API format "{name} {dosage}, {frequency}[, for {duration}]")', () {
    for (final (details, name, dosage, schedule) in [
      ('Losartan 50mg, Once daily', 'Losartan', '50mg', '08:00'),
      ('Losartan 50mg, Once daily, morning', 'Losartan', '50mg', '08:00'),
      ('Atorvastatin 20mg, Once daily, evening, for 3 months', 'Atorvastatin', '20mg', '20:00'),
      ('Amlodipine 5 mg, Twice daily', 'Amlodipine', '5 mg', '08:00,20:00'),
      ('Metformin 500mg, Three times daily', 'Metformin', '500mg', '08:00,14:00,20:00'),
      ('Paracetamol 500mg, As needed', 'Paracetamol', '500mg', 'as_needed'),
      ('doctor side 2 tablet, Twice daily, for 12', 'doctor side', '2 tablet', '08:00,20:00'),
      ('Vitamin D, Once daily', 'Vitamin D', '', '08:00'),
    ]) {
      test(details, () {
        final d = draftFromPrescription(details);
        expect((d.name, d.dosage, d.schedule), (name, dosage, schedule));
        expect(() => parseSchedule(d.schedule), returnsNormally);
      });
    }

    test('already tracked ignores case', () {
      expect(alreadyTracked('Losartan 50mg, Once daily', ['losartan ']), isTrue);
      expect(alreadyTracked('Losartan 50mg, Once daily', ['Amlodipine']), isFalse);
    });
  });

  test('dose history counts taken, late and missed', () {
    final at = DateTime.utc(2026, 10, 13, 0);
    DoseLog log(String status, {Duration? after}) => DoseLog(
      id: '$status$after',
      medicationId: 'm1',
      scheduledTime: at,
      status: status,
      confirmedAt: after == null ? null : at.add(after),
    );
    final c = countDoses([
      log('taken', after: const Duration(minutes: 10)),
      log('taken', after: const Duration(hours: 3)), // after the 2 h window: late
      log('missed'),
    ]);
    expect(c, (taken: 2, late: 1, missed: 1));
  });
}
