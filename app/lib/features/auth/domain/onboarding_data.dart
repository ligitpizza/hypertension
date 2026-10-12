import '../../../core/constants/enums.dart';

/// Onboarding health profile (UC1.4), shaped as agreed in D-25.
/// Mutable on purpose: the multi-step form fills it in and saves drafts.
class OnboardingData {
  OnboardingData();

  // Personal information
  DateTime? dateOfBirth;
  Gender? gender;
  double? heightCm;
  double? weightKg;
  String phone = '';
  String emergencyName = '';
  String emergencyPhone = '';
  String emergencyRelationship = '';

  // Medical history
  int? hypertensionDiagnosedYear;
  Set<MedicalCondition> conditions = {};
  Set<FamilyHistoryCondition> familyHistory = {};
  String allergies = '';
  String notes = '';

  // Lifestyle
  SmokingStatus? smokingStatus;
  AlcoholUse? alcohol;
  int? exerciseDaysPerWeek;
  SaltIntake? saltIntake;

  bool get hasEmergencyContact =>
      emergencyName.trim().isNotEmpty ||
      emergencyPhone.trim().isNotEmpty ||
      emergencyRelationship.trim().isNotEmpty;

  /// Request body for POST /api/v1/auth/onboarding.
  Map<String, dynamic> toApiJson() => {
    'dateOfBirth': _isoDate(dateOfBirth!),
    'gender': gender!.value,
    'personalInfo': {
      'heightCm': heightCm,
      'weightKg': weightKg,
      'phone': phone.trim(),
      if (hasEmergencyContact)
        'emergencyContact': {
          'name': emergencyName.trim(),
          'phone': emergencyPhone.trim(),
          'relationship': emergencyRelationship.trim(),
        },
    },
    'medicalHistory': {
      'hypertensionDiagnosedYear': hypertensionDiagnosedYear,
      'conditions': conditions.map((e) => e.value).toList(),
      'familyHistory': familyHistory.map((e) => e.value).toList(),
      'allergies': allergies.trim(),
      'notes': notes.trim(),
    },
    'lifestyleFactors': {
      'smokingStatus': smokingStatus!.value,
      'alcohol': alcohol!.value,
      'exerciseDaysPerWeek': exerciseDaysPerWeek,
      'saltIntake': saltIntake!.value,
    },
  };

  /// Draft persisted on the device so onboarding can resume (UC1.4 A1).
  Map<String, dynamic> toDraftJson() => {
    'dateOfBirth': dateOfBirth == null ? null : _isoDate(dateOfBirth!),
    'gender': gender?.value,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'phone': phone,
    'emergencyName': emergencyName,
    'emergencyPhone': emergencyPhone,
    'emergencyRelationship': emergencyRelationship,
    'hypertensionDiagnosedYear': hypertensionDiagnosedYear,
    'conditions': conditions.map((e) => e.value).toList(),
    'familyHistory': familyHistory.map((e) => e.value).toList(),
    'allergies': allergies,
    'notes': notes,
    'smokingStatus': smokingStatus?.value,
    'alcohol': alcohol?.value,
    'exerciseDaysPerWeek': exerciseDaysPerWeek,
    'saltIntake': saltIntake?.value,
  };

  factory OnboardingData.fromDraftJson(Map<String, dynamic> j) {
    T? opt<T>(Object? v, T Function(String) parse) => v is String ? parse(v) : null;
    return OnboardingData()
      ..dateOfBirth = opt(j['dateOfBirth'], DateTime.parse)
      ..gender = opt(j['gender'], Gender.fromValue)
      ..heightCm = (j['heightCm'] as num?)?.toDouble()
      ..weightKg = (j['weightKg'] as num?)?.toDouble()
      ..phone = j['phone'] as String? ?? ''
      ..emergencyName = j['emergencyName'] as String? ?? ''
      ..emergencyPhone = j['emergencyPhone'] as String? ?? ''
      ..emergencyRelationship = j['emergencyRelationship'] as String? ?? ''
      ..hypertensionDiagnosedYear = j['hypertensionDiagnosedYear'] as int?
      ..conditions = {
        for (final v in (j['conditions'] as List? ?? const [])) MedicalCondition.fromValue('$v'),
      }
      ..familyHistory = {
        for (final v in (j['familyHistory'] as List? ?? const []))
          FamilyHistoryCondition.fromValue('$v'),
      }
      ..allergies = j['allergies'] as String? ?? ''
      ..notes = j['notes'] as String? ?? ''
      ..smokingStatus = opt(j['smokingStatus'], SmokingStatus.fromValue)
      ..alcohol = opt(j['alcohol'], AlcoholUse.fromValue)
      ..exerciseDaysPerWeek = j['exerciseDaysPerWeek'] as int?
      ..saltIntake = opt(j['saltIntake'], SaltIntake.fromValue);
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
