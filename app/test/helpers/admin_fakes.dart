import 'dart:typed_data';

import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/admin/data/admin_repository.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

// Shared fake for the Module 11 admin screens.

AdminUser user(String uid, String name, UserRole role, {bool active = true, int? caseload}) =>
    AdminUser(
      uid: uid,
      name: name,
      email: '$uid@example.com',
      role: role,
      isActive: active,
      createdAt: DateTime(2026, 10, 1),
      specialty: role == UserRole.doctor ? 'Cardiology' : null,
      maxPatients: role == UserRole.doctor ? 30 : null,
      caseload: caseload,
    );

class FakeAdminRepository implements AdminRepository {
  List<AdminUser> all = [];
  final calls = <String>[];
  ApiException? error;
  AuditPage audit = const AuditPage(entries: [], total: 0, actions: [], summary: {});
  final auditQueries = <AuditQuery>[];

  @override
  Future<List<AdminUser>> users({UserRole? role, String? query}) async {
    calls.add('list:${role?.value}:$query');
    return [
      for (final u in all)
        if ((role == null || u.role == role) &&
            (query == null || query.isEmpty || u.name.toLowerCase().contains(query.toLowerCase())))
          u,
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
  }) async {
    if (error != null) throw error!;
    calls.add('update:$uid:$name:$specialty:$maxPatients:$isActive:$reason');
    return all.firstWhere((u) => u.uid == uid);
  }

  @override
  Future<AuditPage> auditLogs(AuditQuery query) async {
    auditQueries.add(query);
    return audit;
  }

  @override
  Future<Uint8List> auditCsv(AuditQuery query) async {
    calls.add('csv:${query.action}');
    return Uint8List.fromList('timestamp,userId'.codeUnits);
  }
}
