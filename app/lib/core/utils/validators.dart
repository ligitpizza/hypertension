/// Form validators shared by all entrypoints. Each returns an error message or null.
abstract final class Validators {
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
}
