import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/core/utils/ic_number.dart';

// D-51 MyKad numbers; same rules as backend app/services/ic.py.

void main() {
  final today = DateTime(2026, 10, 14);

  test('date of birth, gender and format', () {
    final ic = parseIc('050315101234', today: today);
    expect(ic.value, '050315-10-1234');
    expect(ic.dateOfBirth, DateTime(2005, 3, 15));
    expect(ic.gender, Gender.female);
    expect(parseIc('650315 10 1235', today: today).dateOfBirth, DateTime(1965, 3, 15));
    expect(parseIc('650315-10-1235', today: today).gender, Gender.male);
  });

  for (final bad in ['', '12345', '901301-14-5677', '900230-14-5677', 'abcdefghijkl']) {
    test('rejects "$bad"', () => expect(() => parseIc(bad, today: today), throwsFormatException));
  }

  test('validator and mask', () {
    expect(validateIc('900101-14-5677'), isNull);
    expect(validateIc(''), 'Enter your IC number.');
    expect(validateIc('', required: false), isNull);
    expect(maskIc('900101-14-5677'), '900101-**-**77');
    expect(maskIc(null), '-');
  });

  test('input formatter adds dashes and stops at 12 digits', () {
    final f = IcInputFormatter();
    String type(String s) =>
        f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: s)).text;
    expect(type('9001'), '9001');
    expect(type('9001011'), '900101-1');
    expect(type('9001011456789999'), '900101-14-5678');
  });
}
