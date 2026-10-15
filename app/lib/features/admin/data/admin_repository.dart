import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';

/// One row of User Management (Fig 4.3.14.1; FR-11.1; D-59).
class AdminUser {
  const AdminUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    this.createdAt,
    this.deletionRequested = false,
    this.specialty,
    this.maxPatients,
    this.caseload,
    this.assignedDoctorId,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole? role;
  final bool isActive;
  final DateTime? createdAt;
  final bool deletionRequested;

  /// Doctor only.
  final String? specialty;
  final int? maxPatients;
  final int? caseload;

  /// Patient only.
  final String? assignedDoctorId;

  bool get isDoctor => role == UserRole.doctor;

  factory AdminUser.fromJson(Map<String, dynamic> j) {
    final role = j['role'] as String?;
    return AdminUser(
      uid: '${j['uid']}',
      name: j['name'] as String? ?? '',
      email: j['email'] as String? ?? '',
      role: role == null ? null : UserRole.fromValue(role),
      isActive: j['isActive'] != false,
      createdAt: j['createdAt'] == null ? null : DateTime.parse('${j['createdAt']}'),
      deletionRequested: j['deletionRequested'] == true,
      specialty: j['specialty'] as String?,
      maxPatients: (j['maxPatients'] as num?)?.toInt(),
      caseload: (j['caseload'] as num?)?.toInt(),
      assignedDoctorId: j['assignedDoctorId'] as String?,
    );
  }
}

/// Module 11 admin data, all through FastAPI (aggregation and audit logging live there).
abstract interface class AdminRepository {
  Future<List<AdminUser>> users({UserRole? role, String? query});

  Future<AdminUser> updateUser(
    String uid, {
    String? name,
    String? specialty,
    int? maxPatients,
    bool? isActive,
    String? reason,
  });
}

class ApiAdminRepository implements AdminRepository {
  ApiAdminRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<AdminUser>> users({UserRole? role, String? query}) async {
    final res = await _api.adminUsers(role: role?.value, query: query);
    return [
      for (final u in (res['users'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
        AdminUser.fromJson(Map<String, dynamic>.from(u)),
    ];
  }

  @override
  Future<AdminUser> updateUser(
    String uid, {
    String? name,
    String? specialty,
    int? maxPatients,
    bool? isActive,
    String? reason,
  }) async => AdminUser.fromJson(
    await _api.updateUser(uid, {
      'name': ?name,
      'specialty': ?specialty,
      'maxPatients': ?maxPatients,
      'isActive': ?isActive,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    }),
  );
}
