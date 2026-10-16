/// Form validators shared by all entrypoints. Each returns an error message or null.
abstract final class Validators {
  /// D-28: patients must be at least 13 years old.
  static const minimumAge = 13;

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phone = RegExp(r'^\+?[0-9][0-9\s-]{6,18}[0-9]$');
  static final _letter = RegExp(r'[A-Za-z]');
  static final _digit = RegExp(r'[0-9]');

  static const passwordRule = 'At least 8 characters, including a letter and a number.';

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email address.';
    if (!_email.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  /// UC1.1 E2: password complexity.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.length < 8 || !_letter.hasMatch(v) || !_digit.hasMatch(v)) {
      return passwordRule;
    }
    return null;
  }

  static String? requiredText(String? value, {String label = 'This field'}) {
    return (value?.trim() ?? '').isEmpty ? '$label is required.' : null;
  }

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return 'Enter your full name.';
    if (v.length > 100) return 'Name is too long.';
    return null;
  }

  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter a phone number.';
    if (!_phone.hasMatch(v)) return 'Enter a valid phone number.';
    return null;
  }

  /// Numeric range check used by onboarding (height, weight, ...).
  static String? numberInRange(String? value, num min, num max, {required String label}) {
    final n = num.tryParse(value?.trim() ?? '');
    if (n == null) return '$label is required.';
    if (n < min || n > max) return '$label must be between $min and $max.';
    return null;
  }

  /// Latest date of birth allowed today (exactly [minimumAge] years ago).
  static DateTime latestAllowedDob(DateTime now) =>
      DateTime(now.year - minimumAge, now.month, now.day);

  /// Whole years between [dob] and [now].
  static int ageOn(DateTime dob, DateTime now) {
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    return age;
  }

  static String? dateOfBirth(DateTime? dob, DateTime now) {
    if (dob == null) return 'Date of birth is required.';
    if (ageOn(dob, now) < minimumAge) {
      return 'You must be at least $minimumAge years old to use Harvey.';
    }
    return null;
  }
}
