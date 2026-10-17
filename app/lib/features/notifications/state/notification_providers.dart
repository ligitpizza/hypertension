import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/providers/api_providers.dart';
import '../data/notifications_repository.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => ApiNotificationsRepository(ref.watch(apiClientProvider)),
);

/// D-77 the bell inbox; refreshed by the bell every minute and when it opens.
final notificationInboxProvider = FutureProvider<NotificationInbox>(
  (ref) => ref.watch(notificationsRepositoryProvider).inbox(),
  retry: (_, _) => null,
);

final bellPrefsProvider = FutureProvider.autoDispose<Map<String, bool>>(
  (ref) => ref.watch(notificationsRepositoryProvider).prefs(),
  retry: (_, _) => null,
);

/// Where a notification leads, from its push data; null = nowhere (just mark it read).
String? notificationRoute(String? type, Map<String, String> data, UserRole? role) {
  final staffBase = switch (role) {
    UserRole.doctor => '/doctor',
    UserRole.pharmacist => '/pharmacy',
    UserRole.admin => '/admin',
    _ => null,
  };
  final id = data['id'];
  final from = data['from'];
  if (staffBase == null) {
    // Patient app.
    return switch (type) {
      'message' => from == null ? '/chat' : '/chat/$from',
      'conversation' => id == null ? '/chat' : '/conversation/$id',
      'pharmacy_chat' => '/pharmacy-chat',
      'weekly_summary' => '/ai-agent',
      'order' => '/orders',
      'appointment' || 'assignment' => '/appointments',
      'dose' || 'refill' => '/medications',
      'bp_alert' || 'risk' || 'triage' => '/dashboard',
      'family_link' || 'family_request' => '/family-requests',
      'record_shared' => '/records',
      _ => null,
    };
  }
  return switch (type) {
    'message' when role == UserRole.doctor =>
      from == null ? '/doctor/messages' : '/doctor/messages/$from',
    'conversation' when id != null =>
      role == UserRole.admin ? '/admin/messages/$id' : '$staffBase/messages/team/$id',
    'pharmacy_chat' when role == UserRole.pharmacist => '/pharmacy/messages',
    'order' when role == UserRole.pharmacist => '/pharmacy',
    'order' when role == UserRole.admin => '/admin/orders',
    'clinical_alert' ||
    'escalation' ||
    'bp_alert' ||
    'risk' ||
    'triage' ||
    'emergency_alert' when role == UserRole.doctor => '/doctor',
    'appointment' when role == UserRole.doctor => '/doctor/calendar',
    'appointment' when role == UserRole.admin => '/admin/appointments',
    'assignment' when role == UserRole.admin => '/admin/assignments',
    _ => null,
  };
}
