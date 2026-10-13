import '../../../core/constants/enums.dart';

/// The signed-in user's `users` document (docs/04 Table 4.2.3.1), as much as
/// the auth flow needs.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.isActive,
    this.onboardingComplete,
    this.linkCode,
    this.assignedDoctorId,
  });

  final String uid;
  final String email;
  final String name;
  final UserRole role;
  final bool isActive;

  /// Patients only.
  final bool? onboardingComplete;

  /// Patients only (D-06): shared with family members to link.
  final String? linkCode;

  /// Patients only: the doctor they can message (FR-10.1); null until assigned (UC7.3).
  final String? assignedDoctorId;

  bool get needsOnboarding => role == UserRole.patient && onboardingComplete != true;

  factory AppUser.fromFirestore(String uid, Map<String, dynamic> data) => AppUser(
    uid: uid,
    email: data['email'] as String? ?? '',
    name: data['name'] as String? ?? '',
    role: UserRole.fromValue(data['role'] as String),
    isActive: data['isActive'] as bool? ?? true,
    onboardingComplete: data['onboardingComplete'] as bool?,
    linkCode: data['linkCode'] as String?,
    assignedDoctorId: data['assignedDoctorId'] as String?,
  );
}
