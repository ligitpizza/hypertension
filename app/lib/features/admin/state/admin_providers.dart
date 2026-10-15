import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/providers/api_providers.dart';
import '../data/admin_repository.dart';

Duration? _noRetry(int _, Object _) => null;

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => ApiAdminRepository(ref.watch(apiClientProvider)),
);

/// (role filter, search text) -> users (UC11.1).
final adminUsersProvider = FutureProvider.autoDispose.family<List<AdminUser>, (UserRole?, String)>(
  (ref, k) => ref.watch(adminRepositoryProvider).users(role: k.$1, query: k.$2),
  retry: _noRetry,
);
