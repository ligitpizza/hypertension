import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../../auth/state/auth_providers.dart';
import '../data/notifications_repository.dart';
import '../state/notification_providers.dart';

/// D-77: the bell. Shows the unread count; on the portal it opens a panel under the top
/// bar, on the phone the Notifications page. Checks for new ones every minute.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key, this.panel = false, this.color});

  /// true on the web portal (panel), false on the phone (full page).
  final bool panel;
  final Color? color;

  static const refreshEvery = Duration(minutes: 1);

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(
      NotificationBell.refreshEvery,
      (_) => ref.invalidate(notificationInboxProvider),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    ref.invalidate(notificationInboxProvider);
    if (!widget.panel) {
      await context.push('/notifications');
      return;
    }
    final route = await showDialog<String>(
      context: context,
      barrierColor: Colors.black12,
      builder: (_) => const Dialog(
        alignment: Alignment.topRight,
        insetPadding: EdgeInsets.only(top: 56, right: 12, left: 12, bottom: 24),
        child: SizedBox(width: 420, height: 560, child: NotificationsPanel(closeOnOpen: true)),
      ),
    );
    if (route != null && mounted) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(notificationInboxProvider).value?.unread ?? 0;
    return IconButton(
      key: const Key('notification-bell'),
      tooltip: 'Notifications',
      color: widget.color,
      onPressed: _open,
      icon: Badge(
        key: const Key('bell-badge'),
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(unread > 0 ? Icons.notifications_active : Icons.notifications_none),
      ),
    );
  }
}

/// The list of saved notifications with "Mark all read".
class NotificationsPanel extends ConsumerWidget {
  const NotificationsPanel({super.key, this.closeOnOpen = false});

  /// In the portal panel: pop with the route to open instead of navigating here.
  final bool closeOnOpen;

  Future<void> _tap(BuildContext context, WidgetRef ref, AppNotification n) async {
    final role = ref.read(currentUserProvider).value?.role;
    final route = notificationRoute(n.type, n.data, role);
    if (!n.read) {
      try {
        await ref.read(notificationsRepositoryProvider).markRead(n.id);
      } catch (_) {
        // Still open it; the badge catches up on the next refresh.
      }
      ref.invalidate(notificationInboxProvider);
    }
    if (!context.mounted) return;
    if (closeOnOpen) {
      Navigator.of(context).pop(route);
    } else if (route != null) {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationInboxProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text('Notifications', style: theme.textTheme.titleMedium)),
              TextButton(
                key: const Key('notifications-read-all'),
                onPressed: (inbox.value?.unread ?? 0) == 0
                    ? null
                    : () async {
                        await ref.read(notificationsRepositoryProvider).markAllRead();
                        ref.invalidate(notificationInboxProvider);
                      },
                child: const Text('Mark all read'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: inbox.when(
            skipLoadingOnRefresh: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(notificationInboxProvider),
                child: const Text('Could not load notifications. Retry'),
              ),
            ),
            data: (box) => box.items.isEmpty
                ? const Center(
                    key: Key('notifications-empty'),
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text("You're all caught up.", textAlign: TextAlign.center),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(notificationInboxProvider.future),
                    child: ListView.separated(
                      itemCount: box.items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final n = box.items[i];
                        return _NotificationTile(n: n, onTap: () => _tap(context, ref, n));
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  static (IconData, Color) look(String category, bool urgent) {
    if (urgent) return (Icons.warning_amber_rounded, Colors.red.shade700);
    return switch (category) {
      'messages' => (Icons.chat_bubble_outline, Colors.blue.shade600),
      'alerts' => (Icons.monitor_heart_outlined, Colors.deepOrange.shade600),
      'appointments' => (Icons.event_outlined, Colors.purple.shade400),
      'orders' => (Icons.local_pharmacy_outlined, Colors.green.shade600),
      'medication' => (Icons.medication_outlined, Colors.teal.shade600),
      _ => (Icons.notifications_none, Colors.blueGrey),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = look(n.category, n.urgent);
    final theme = Theme.of(context);
    final when = n.createdAt == null
        ? ''
        : '${dateLabel(n.createdAt!)}, ${timeLabel(n.createdAt!)}';
    return ListTile(
      key: Key('notification-${n.id}'),
      onTap: onTap,
      tileColor: n.read ? null : theme.colorScheme.primary.withValues(alpha: 0.06),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        child: Icon(icon),
      ),
      title: Text(n.title, style: n.read ? null : const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (n.body.isNotEmpty) Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(when, style: theme.textTheme.labelSmall),
        ],
      ),
      trailing: n.read
          ? null
          : Container(
              key: Key('unread-dot-${n.id}'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
            ),
    );
  }
}

/// Phone: the Notifications page (from the bell on Home).
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: const NotificationsPanel(),
  );
}
