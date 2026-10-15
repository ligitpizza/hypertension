import 'dart:typed_data';

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

/// One audit entry (Fig 4.3.14.3).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.module,
    required this.details,
    this.timestamp,
    this.userId,
    this.userName,
    this.role,
    this.targetId,
  });

  final String id;
  final String action;
  final String module;
  final String details;
  final DateTime? timestamp;
  final String? userId;
  final String? userName;
  final String? role;
  final String? targetId;

  bool get isFailure => action == 'LOGIN_FAILED' || action == 'LOGIN_BLOCKED';

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    id: '${j['id']}',
    action: j['action'] as String? ?? '',
    module: j['module'] as String? ?? 'Other',
    details: j['details'] as String? ?? '',
    timestamp: j['timestamp'] == null ? null : DateTime.parse('${j['timestamp']}'),
    userId: j['userId'] as String?,
    userName: j['userName'] as String?,
    role: j['role'] as String?,
    targetId: j['targetId'] as String?,
  );
}

class AuditPage {
  const AuditPage({
    required this.entries,
    required this.total,
    required this.actions,
    required this.summary,
  });

  final List<AuditEntry> entries;
  final int total;
  final List<String> actions;
  final Map<String, dynamic> summary;
}

/// Filters for the audit viewer; dates are Malaysian calendar days.
class AuditQuery {
  const AuditQuery({
    required this.from,
    required this.to,
    this.action,
    this.text = '',
    this.offset = 0,
    this.limit = 15,
  });

  final DateTime from;
  final DateTime to;
  final String? action;
  final String text;
  final int offset;
  final int limit;

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toQuery({bool paged = true}) => {
    'from': _day(from),
    'to': _day(to),
    'action': ?action,
    if (text.isNotEmpty) 'q': text,
    if (paged) 'offset': offset,
    if (paged) 'limit': limit,
  };

  @override
  bool operator ==(Object other) =>
      other is AuditQuery &&
      other.from == from &&
      other.to == to &&
      other.action == action &&
      other.text == text &&
      other.offset == offset &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(from, to, action, text, offset, limit);
}

/// One service on System Health (Fig 4.3.14.7; D-59).
class ServiceHealth {
  const ServiceHealth({
    required this.key,
    required this.name,
    required this.status,
    this.latencyMs,
    this.uptime,
    this.note = '',
  });

  final String key;
  final String name;

  /// operational | degraded | down | simulated | not_configured
  final String status;
  final double? latencyMs;
  final double? uptime;
  final String note;

  factory ServiceHealth.fromJson(Map<String, dynamic> j) => ServiceHealth(
    key: '${j['key']}',
    name: j['name'] as String? ?? '',
    status: j['status'] as String? ?? 'down',
    latencyMs: (j['latencyMs'] as num?)?.toDouble(),
    uptime: (j['uptime'] as num?)?.toDouble(),
    note: j['note'] as String? ?? '',
  );
}

class SystemHealth {
  const SystemHealth({
    required this.overall,
    required this.services,
    this.checkedAt,
    this.uptime,
    this.averageLatencyMs,
  });

  final String overall;
  final List<ServiceHealth> services;
  final DateTime? checkedAt;
  final double? uptime;
  final double? averageLatencyMs;

  factory SystemHealth.fromJson(Map<String, dynamic> j) => SystemHealth(
    overall: j['overall'] as String? ?? 'down',
    services: [
      for (final s in (j['services'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
        ServiceHealth.fromJson(Map<String, dynamic>.from(s)),
    ],
    checkedAt: j['checkedAt'] == null ? null : DateTime.parse('${j['checkedAt']}'),
    uptime: (j['uptime'] as num?)?.toDouble(),
    averageLatencyMs: (j['averageLatencyMs'] as num?)?.toDouble(),
  );
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

  Future<AuditPage> auditLogs(AuditQuery query);

  Future<Uint8List> auditCsv(AuditQuery query);

  Future<SystemHealth> systemHealth();
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

  @override
  Future<AuditPage> auditLogs(AuditQuery query) async {
    final res = await _api.adminAuditLogs(query.toQuery());
    return AuditPage(
      entries: [
        for (final e in (res['entries'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
          AuditEntry.fromJson(Map<String, dynamic>.from(e)),
      ],
      total: (res['total'] as num?)?.toInt() ?? 0,
      actions: [for (final a in (res['actions'] as List? ?? const [])) '$a'],
      summary: Map<String, dynamic>.from(res['summary'] as Map? ?? const {}),
    );
  }

  @override
  Future<Uint8List> auditCsv(AuditQuery query) async =>
      Uint8List.fromList(await _api.adminAuditCsv(query.toQuery(paged: false)));

  @override
  Future<SystemHealth> systemHealth() async =>
      SystemHealth.fromJson(await _api.adminSystemHealth());
}
