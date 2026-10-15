import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/providers/api_providers.dart';
import '../data/admin_repository.dart';
import '../data/analytics_models.dart';

Duration? _noRetry(int _, Object _) => null;

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => ApiAdminRepository(ref.watch(apiClientProvider)),
);

/// (role filter, search text) -> users (UC11.1).
final adminUsersProvider = FutureProvider.autoDispose.family<List<AdminUser>, (UserRole?, String)>(
  (ref, k) => ref.watch(adminRepositoryProvider).users(role: k.$1, query: k.$2),
  retry: _noRetry,
);

/// UC11.3 audit viewer page.
final auditLogsProvider = FutureProvider.autoDispose.family<AuditPage, AuditQuery>(
  (ref, q) => ref.watch(adminRepositoryProvider).auditLogs(q),
  retry: _noRetry,
);

/// Fig 4.3.14.7; refreshed by invalidating.
final systemHealthProvider = FutureProvider.autoDispose<SystemHealth>(
  (ref) => ref.watch(adminRepositoryProvider).systemHealth(),
  retry: _noRetry,
);

final hospitalAnalyticsProvider = FutureProvider.autoDispose<HospitalAnalytics>(
  (ref) => ref.watch(adminRepositoryProvider).hospitalAnalytics(),
  retry: _noRetry,
);

/// days -> usage analytics.
final systemAnalyticsProvider = FutureProvider.autoDispose.family<SystemAnalytics, int>(
  (ref, days) => ref.watch(adminRepositoryProvider).systemAnalytics(days: days),
  retry: _noRetry,
);
