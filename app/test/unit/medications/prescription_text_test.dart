import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/prescriptions/domain/prescription_text.dart';

// D-50: editing a recorded prescription starts from its stored medicationDetails line.

void main() {
  test('splits name, dosage, frequency, duration and clinic', () {
    final p = parsePrescription(
      'Metformin 500mg, Once daily, evening, for 3 months, from Klinik Kesihatan Setapak',
    );
    expect(p.name, 'Metformin');
    expect(p.dosage, '500mg');
    expect(p.frequency, 'Once daily, evening');
    expect(p.duration, '3 months');
    expect(p.clinic, 'Klinik Kesihatan Setapak');
  });

  test('optional parts may be missing', () {
    final p = parsePrescription('Losartan 50mg, Twice daily');
    expect(
      (p.name, p.dosage, p.frequency, p.duration, p.clinic),
      ('Losartan', '50mg', 'Twice daily', null, null),
    );
  });

  test('an unknown frequency is left for the patient to choose', () {
    expect(parsePrescription('Aspirin 100mg, every other day').frequency, isNull);
  });
}
