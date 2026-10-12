import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/locator.dart';
import '../services/api/api_client.dart';

/// The API client from get_it; overridden with a fake in tests.
final apiClientProvider = Provider<ApiClient>((ref) => locator<ApiClient>());

/// Result of `GET /api/v1/health`.
final apiHealthProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(apiClientProvider).health(),
);
