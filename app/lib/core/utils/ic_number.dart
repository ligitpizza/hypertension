import 'package:flutter/services.dart';

import '../constants/enums.dart';

/// Malaysian IC (MyKad) numbers (D-51): YYMMDD-PB-####. Mirrors backend app/services/ic.py.
class IcInfo {
  const IcInfo(this.value, this.dateOfBirth, this.gender);

  /// Formatted "YYMMDD-PB-####".
  final String value;
  final DateTime dateOfBirth;
  final Gender gender;
}

/// Throws [FormatException] with a message fit to show the patient.
IcInfo parseIc(String raw, {DateTime? today}) {
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^\d{12}$').hasMatch(digits)) {
    throw const FormatException('Enter a 12-digit IC number, e.g. 900101-14-5678.');
  }
  final now = today ?? DateTime.now();
  final yy = int.parse(digits.substring(0, 2));
  final mm = int.parse(digits.substring(2, 4));
  final dd = int.parse(digits.substring(4, 6));
  // Born this century unless that would be in the future.
  final year = (2000 + yy <= now.year ? 2000 : 1900) + yy;
  final born = DateTime(year, mm, dd);
  if (mm < 1 || mm > 12 || born.month != mm || born.day != dd) {
    throw const FormatException('The first six digits must be a real date of birth (YYMMDD).');
  }
  if (born.isAfter(now)) {
    throw const FormatException('The date of birth in the IC number is in the future.');
  }
  final gender = int.parse(digits[11]).isOdd ? Gender.male : Gender.female;
  return IcInfo(
    '${digits.substring(0, 6)}-${digits.substring(6, 8)}-${digits.substring(8)}',
    born,
    gender,
  );
}

/// Form validator; [required] false allows an empty field.
String? validateIc(String? v, {bool required = true}) {
  if ((v ?? '').trim().isEmpty) return required ? 'Enter your IC number.' : null;
  try {
    parseIc(v!);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

/// 900101-14-5678 -> 900101-**-**78 (staff screens).
String maskIc(String? value) => value == null || value.length != 14
    ? '-'
    : '${value.substring(0, 6)}-**-**${value.substring(12)}';

/// Types digits only and inserts the dashes: 900101145678 -> 900101-14-5678.
class IcInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 12 ? digits.substring(0, 12) : digits;
    final out = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 6 || i == 8) out.write('-');
      out.write(d[i]);
    }
    final text = out.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
