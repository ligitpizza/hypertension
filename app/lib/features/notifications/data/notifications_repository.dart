import '../../../shared/services/api/api_client.dart';

/// D-77: one saved notification (the bell inbox).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.read,
    this.type,
    this.data = const {},
    this.urgent = false,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String? type;

  /// messages / alerts / appointments / orders / medication / other
  final String category;
  final Map<String, String> data;
  final bool urgent;
  final bool read;
  final DateTime? createdAt;

  factory AppNotification.fromApi(Map<String, dynamic> j) => AppNotification(
    id: '${j['id']}',
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
    type: j['type'] as String?,
    category: j['category'] as String? ?? 'other',
    data: {
      for (final e in (j['data'] as Map<String, dynamic>? ?? const {}).entries) e.key: '${e.value}',
    },
    urgent: j['urgent'] as bool? ?? false,
    read: j['read'] as bool? ?? false,
    createdAt: DateTime.tryParse('${j['createdAt']}'),
  );
}

class NotificationInbox {
  const NotificationInbox(this.items, this.unread);
  final List<AppNotification> items;
  final int unread;
}

/// Bell categories, in the order shown on the Settings page.
const bellCategories = {
  'messages': 'Messages',
  'alerts': 'Health and clinical alerts',
  'appointments': 'Appointments and assignments',
  'orders': 'Medication orders',
  'medication': 'Medicine reminders',
  'other': 'Everything else',
};

abstract interface class NotificationsRepository {
  Future<NotificationInbox> inbox();

  Future<void> markRead(String id);

  Future<void> markAllRead();

  Future<Map<String, bool>> prefs();

  Future<void> savePrefs(Map<String, bool> prefs);
}

class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository(this._api);
  final ApiClient _api;

  @override
  Future<NotificationInbox> inbox() async {
    final j = await _api.notifications();
    return NotificationInbox([
      for (final n in j['notifications'] as List<dynamic>? ?? const [])
        AppNotification.fromApi(n as Map<String, dynamic>),
    ], (j['unread'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<void> markRead(String id) => _api.readNotification(id);

  @override
  Future<void> markAllRead() => _api.readAllNotifications();

  @override
  Future<Map<String, bool>> prefs() async => {
    for (final e in (await _api.bellPrefs()).entries) e.key: e.value == true,
  };

  @override
  Future<void> savePrefs(Map<String, bool> prefs) => _api.updateBellPrefs(prefs);
}
