import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/bp_classifier.dart';
import '../admin/data/admin_repository.dart';
import '../admin/state/admin_providers.dart';
import '../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../appointments/state/appointment_providers.dart';
import '../auth/state/auth_providers.dart';
import '../notifications/data/notifications_repository.dart';
import '../notifications/state/notification_providers.dart';
import '../orders/data/order_models.dart';
import '../orders/state/orders_providers.dart';
import '../provider_portal/state/portal_providers.dart';
import 'admin_center.dart';

/// D-77: a live dashboard as each portal role's home page. Cards summarise what needs
/// attention today and link to the page that handles it.

DateTime _startOfDay(DateTime now) => DateTime(now.year, now.month, now.day);

String _greeting(DateTime now) => now.hour < 12
    ? 'Good morning'
    : now.hour < 18
    ? 'Good afternoon'
    : 'Good evening';

/// Header with greeting and today's date.
class _DashHeader extends ConsumerWidget {
  const _DashHeader({required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUserProvider).value?.name ?? '';
    final now = DateTime.now();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_greeting(now)}, $name', style: theme.textTheme.headlineSmall),
          Text('${dateLabel(now)} · $subtitle', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A coloured number tile.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 5)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                foregroundColor: color,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A titled card with a "View all" link.
class DashCard extends StatelessWidget {
  const DashCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.path,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? path;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 440,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                if (path != null)
                  TextButton(onPressed: () => context.go(path!), child: const Text('View all')),
              ],
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    ),
  );
}

Widget _empty(String text) =>
    Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(text));

Widget _async<T>(AsyncValue<T> v, Widget Function(T) data) => v.when(
  skipLoadingOnRefresh: true,
  loading: () =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
  error: (_, _) => _empty('Could not load.'),
  data: data,
);

/// Simple horizontal bars (label, value, colour).
class MiniBars extends StatelessWidget {
  const MiniBars(this.bars, {super.key});
  final List<(String, int, Color)> bars;

  @override
  Widget build(BuildContext context) {
    final biggest = bars.fold<int>(0, (m, b) => b.$2 > m ? b.$2 : m);
    if (biggest == 0) return _empty('No data yet.');
    return Column(
      children: [
        for (final (label, value, color) in bars)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 96, child: Text(label)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 14,
                        width: value == 0 ? 2 : c.maxWidth * value / biggest,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.right)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The latest notifications (the bell inbox), shared by every dashboard.
class _RecentNotifications extends ConsumerWidget {
  const _RecentNotifications();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationInboxProvider);
    final role = ref.watch(currentUserProvider).value?.role;
    return DashCard(
      key: const Key('dash-notifications'),
      title:
          'Notifications${(inbox.value?.unread ?? 0) > 0 ? ' (${inbox.value!.unread} new)' : ''}',
      icon: Icons.notifications_none,
      child: _async<NotificationInbox>(inbox, (box) {
        if (box.items.isEmpty) return _empty("You're all caught up.");
        return Column(
          children: [
            for (final n in box.items.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  n.read ? Icons.notifications_none : Icons.circle,
                  size: n.read ? 20 : 10,
                  color: n.read ? null : Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  n.title,
                  style: n.read ? null : const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(n.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: n.createdAt == null ? null : Text(timeLabel(n.createdAt!)),
                onTap: () async {
                  if (!n.read) {
                    await ref.read(notificationsRepositoryProvider).markRead(n.id);
                    ref.invalidate(notificationInboxProvider);
                  }
                  final route = notificationRoute(n.type, n.data, role);
                  if (route != null && context.mounted) context.go(route);
                },
              ),
          ],
        );
      }),
    );
  }
}

Widget _layout(List<Widget> stats, List<Widget> cards) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Wrap(spacing: 12, runSpacing: 12, children: stats),
    const SizedBox(height: 16),
    Wrap(spacing: 16, runSpacing: 16, children: cards),
  ],
);

// ---------------------------------------------------------------- doctor

class DoctorHomeDashboard extends ConsumerWidget {
  const DoctorHomeDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final rows = ref.watch(patientRowsProvider);
    final alerts = ref.watch(openAlertsProvider);
    final today = _startOfDay(DateTime.now());
    final appts = me == null
        ? const AsyncValue<List<Never>>.data([])
        : ref.watch(doctorAppointmentsProvider((me, today, today.add(const Duration(days: 1)))));
    final todays = [
      for (final a in appts.value ?? const [])
        if (a.isActive) a,
    ]..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final patients = rows.value ?? const [];
    final highRisk = [
      for (final r in patients)
        if (r.emergency || r.riskLevel == RiskLevel.high || r.riskLevel == RiskLevel.critical) r,
    ];
    final names = {for (final r in patients) r.patient.uid: r.patient.name};
    final unread = ref.watch(notificationInboxProvider).value?.unread ?? 0;

    return ListView(
      key: const Key('doctor-dashboard'),
      padding: const EdgeInsets.all(24),
      children: [
        const _DashHeader(subtitle: "Here's what needs you today."),
        _layout(
          [
            StatTile(
              icon: Icons.people_outline,
              color: Colors.blue.shade600,
              label: 'My patients',
              value: '${patients.length}',
              onTap: () => context.go('/doctor'),
            ),
            StatTile(
              icon: Icons.priority_high,
              color: Colors.red.shade600,
              label: 'High or critical risk',
              value: '${highRisk.length}',
              onTap: () => context.go('/doctor'),
            ),
            StatTile(
              icon: Icons.warning_amber_rounded,
              color: Colors.orange.shade700,
              label: 'Open alerts',
              value: '${alerts.value?.length ?? 0}',
              onTap: () => context.go('/doctor'),
            ),
            StatTile(
              icon: Icons.event,
              color: Colors.purple.shade400,
              label: "Today's appointments",
              value: '${todays.length}',
              onTap: () => context.go('/doctor/calendar'),
            ),
            StatTile(
              icon: Icons.notifications_none,
              color: Colors.teal.shade600,
              label: 'Unread notifications',
              value: '$unread',
            ),
          ],
          [
            DashCard(
              key: const Key('dash-appointments'),
              title: "Today's appointments",
              icon: Icons.event,
              path: '/doctor/calendar',
              child: todays.isEmpty
                  ? _empty('No appointments today.')
                  : Column(
                      children: [
                        for (final a in todays.take(6))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Text(timeLabel(a.dateTime)),
                            title: Text(names[a.patientId] ?? 'Patient'),
                            subtitle: Text(a.type.label),
                            onTap: () => context.go('/doctor/patient/${a.patientId}'),
                          ),
                      ],
                    ),
            ),
            DashCard(
              key: const Key('dash-alerts'),
              title: 'Open clinical alerts',
              icon: Icons.warning_amber_rounded,
              path: '/doctor',
              child: _async(alerts, (list) {
                if (list.isEmpty) return _empty('No open alerts.');
                return Column(
                  children: [
                    for (final a in list.take(5))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.circle, size: 12, color: _riskColor(a.severity)),
                        title: Text(names[a.patientId] ?? 'Patient'),
                        subtitle: Text(a.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => context.go('/doctor/patient/${a.patientId}'),
                      ),
                  ],
                );
              }),
            ),
            DashCard(
              key: const Key('dash-high-risk'),
              title: 'Patients to watch',
              icon: Icons.monitor_heart_outlined,
              path: '/doctor',
              child: highRisk.isEmpty
                  ? _empty('No patients at high risk.')
                  : Column(
                      children: [
                        for (final r in highRisk.take(5))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.circle,
                              size: 12,
                              color: _riskColor(r.riskLevel ?? RiskLevel.critical),
                            ),
                            title: Text(r.patient.name),
                            subtitle: Text(
                              [
                                if (r.emergency) 'Emergency alert',
                                if (r.riskLevel != null) 'Risk ${r.riskLevel!.value}',
                                if (r.latestReading != null)
                                  'Last ${r.latestReading!.systolic}/${r.latestReading!.diastolic}',
                              ].join(' · '),
                            ),
                            onTap: () => context.go('/doctor/patient/${r.patient.uid}'),
                          ),
                      ],
                    ),
            ),
            const _RecentNotifications(),
          ],
        ),
      ],
    );
  }
}

Color _riskColor(RiskLevel l) => switch (l) {
  RiskLevel.low => Colors.green.shade600,
  RiskLevel.moderate => Colors.amber.shade700,
  RiskLevel.high => Colors.orange.shade700,
  RiskLevel.critical => BpClassifier.color(BpCategory.crisis),
};

// ---------------------------------------------------------------- pharmacist

class PharmacyDashboardPage extends ConsumerWidget {
  const PharmacyDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(pharmacyQueueProvider);
    final stock = ref.watch(stockProvider);
    final chats = ref.watch(pharmacyConversationsProvider);
    final orders = queue.value?.orders ?? const <MedicationOrder>[];
    int count(bool Function(MedicationOrder) test) => orders.where(test).length;
    final toPrepare = count(
      (o) => o.status == Fulfilment.preparing || o.status == Fulfilment.outOfStock,
    );
    final ready = count(
      (o) =>
          (o.status == Fulfilment.readyForCollection || o.status == Fulfilment.readyForDelivery) &&
          o.deliveryStatus == null,
    );
    final onTheWay = count(
      (o) => o.deliveryStatus == 'dispatched' || o.deliveryStatus == 'in_transit',
    );
    final items = stock.value ?? const <StockItem>[];
    final low = [
      for (final s in items)
        if (s.low || s.units == 0) s,
    ]..sort((a, b) => a.units.compareTo(b.units));
    final waiting = [
      for (final c in chats.value ?? const <PharmacyConversation>[])
        if (!c.last.fromPharmacy) c,
    ];

    return ListView(
      key: const Key('pharmacy-dashboard'),
      padding: const EdgeInsets.all(24),
      children: [
        const _DashHeader(subtitle: 'Orders, stock and messages at a glance.'),
        _layout(
          [
            StatTile(
              icon: Icons.medication_outlined,
              color: Colors.blue.shade600,
              label: 'To prepare',
              value: '$toPrepare',
              onTap: () => context.go('/pharmacy'),
            ),
            StatTile(
              icon: Icons.inventory_outlined,
              color: Colors.green.shade600,
              label: 'Ready for collection or courier',
              value: '$ready',
              onTap: () => context.go('/pharmacy'),
            ),
            StatTile(
              icon: Icons.local_shipping_outlined,
              color: Colors.purple.shade400,
              label: 'Out for delivery',
              value: '$onTheWay',
              onTap: () => context.go('/pharmacy/tracking'),
            ),
            StatTile(
              icon: Icons.warning_amber_rounded,
              color: Colors.orange.shade700,
              label: 'Low or out of stock',
              value: '${low.length}',
              onTap: () => context.go('/pharmacy/inventory'),
            ),
            StatTile(
              icon: Icons.chat_bubble_outline,
              color: Colors.teal.shade600,
              label: 'Patients awaiting a reply',
              value: '${waiting.length}',
              onTap: () => context.go('/pharmacy/messages'),
            ),
          ],
          [
            DashCard(
              key: const Key('dash-queue'),
              title: 'Order queue',
              icon: Icons.receipt_long_outlined,
              path: '/pharmacy',
              child: _async(queue, (q) {
                final active = [
                  for (final o in q.orders)
                    if (o.status == Fulfilment.preparing ||
                        o.status == Fulfilment.outOfStock ||
                        o.status == Fulfilment.awaitingPayment)
                      o,
                ];
                return Column(
                  children: [
                    if (q.needsPrice.isNotEmpty)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.new_releases_outlined),
                        title: Text('${q.needsPrice.length} new prescription(s) to price'),
                        onTap: () => context.go('/pharmacy'),
                      ),
                    if (active.isEmpty && q.needsPrice.isEmpty) _empty('Nothing waiting.'),
                    for (final o in active.take(5))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${o.ref} · ${o.patientName ?? 'Patient'}'),
                        subtitle: Text(o.status.label),
                        onTap: () => context.go('/pharmacy'),
                      ),
                  ],
                );
              }),
            ),
            DashCard(
              key: const Key('dash-stock'),
              title: 'Stock to reorder',
              icon: Icons.inventory_2_outlined,
              path: '/pharmacy/inventory',
              child: _async(stock, (_) {
                if (low.isEmpty) return _empty('Stock levels are fine.');
                return Column(
                  children: [
                    for (final s in low.take(6))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.circle,
                          size: 12,
                          color: s.units == 0 ? Colors.red.shade600 : Colors.orange.shade700,
                        ),
                        title: Text(s.name),
                        trailing: Text(s.units == 0 ? 'Out' : '${s.units} left'),
                      ),
                  ],
                );
              }),
            ),
            DashCard(
              key: const Key('dash-pharmacy-messages'),
              title: 'Patient messages',
              icon: Icons.chat_bubble_outline,
              path: '/pharmacy/messages',
              child: _async(chats, (_) {
                if (waiting.isEmpty) return _empty('No one is waiting for a reply.');
                return Column(
                  children: [
                    for (final c in waiting.take(5))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.patientName ?? 'Patient'),
                        subtitle: Text(c.last.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => context.go('/pharmacy/messages/${c.last.patientId}'),
                      ),
                  ],
                );
              }),
            ),
            const _RecentNotifications(),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- admin

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = _startOfDay(now);
    final requests = ref.watch(pendingAssignmentRequestsProvider);
    final appts = ref.watch(allAppointmentsProvider((today, today.add(const Duration(days: 7)))));
    final changeRequests = [
      for (final a in appts.value ?? const [])
        if (a.pendingChange != null) a,
    ];
    final todayCount = (appts.value ?? const [])
        .where((a) => a.isActive && a.dateTime.isBefore(today.add(const Duration(days: 1))))
        .length;
    final deliveries = ref.watch(deliveriesProvider);
    final audit = ref.watch(
      auditLogsProvider(
        AuditQuery(
          from: today.subtract(const Duration(days: 1)),
          to: today.add(const Duration(days: 1)),
          limit: 6,
        ),
      ),
    );
    final hospital = ref.watch(hospitalAnalyticsProvider);
    final usage = ref.watch(systemAnalyticsProvider(7));
    final orders = deliveries.value?.orders ?? const <MedicationOrder>[];
    int byDelivery(String s) => orders.where((o) => o.deliveryStatus == s).length;

    return ListView(
      key: const Key('admin-dashboard'),
      padding: const EdgeInsets.all(24),
      children: [
        const _DashHeader(subtitle: 'Requests, deliveries and system activity.'),
        _layout(
          [
            StatTile(
              icon: Icons.assignment_ind_outlined,
              color: Colors.blue.shade600,
              label: 'Doctor requests waiting',
              value: '${requests.value?.length ?? 0}',
              onTap: () => context.go('/admin/assignments'),
            ),
            StatTile(
              icon: Icons.event_note_outlined,
              color: Colors.purple.shade400,
              label: 'Appointment change requests',
              value: '${changeRequests.length}',
              onTap: () => context.go('/admin/appointments'),
            ),
            StatTile(
              key: const Key('stat-staff-requests'),
              icon: Icons.support_agent,
              color: Colors.deepOrange.shade400,
              label: 'Open staff requests',
              value:
                  '${(ref.watch(staffRequestsProvider).value ?? const <StaffRequest>[]).where((r) => r.status != 'done').length}',
              onTap: () => context.go('/admin/requests'),
            ),
            StatTile(
              icon: Icons.event,
              color: Colors.indigo.shade400,
              label: 'Appointments today',
              value: '$todayCount',
              onTap: () => context.go('/admin/calendar'),
            ),
            StatTile(
              icon: Icons.local_shipping_outlined,
              color: Colors.green.shade600,
              label: 'Deliveries on the way',
              value: '${byDelivery('dispatched') + byDelivery('in_transit')}',
              onTap: () => context.go('/admin/deliveries'),
            ),
            StatTile(
              icon: Icons.notifications_none,
              color: Colors.teal.shade600,
              label: 'Unread notifications',
              value: '${ref.watch(notificationInboxProvider).value?.unread ?? 0}',
            ),
          ],
          [
            DashCard(
              key: const Key('dash-requests'),
              title: 'Appointment and doctor requests',
              icon: Icons.inbox_outlined,
              path: '/admin/appointments',
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.assignment_ind_outlined),
                    title: Text('${requests.value?.length ?? 0} doctor assignment request(s)'),
                    onTap: () => context.go('/admin/assignments'),
                  ),
                  if (changeRequests.isEmpty)
                    _empty('No appointment changes waiting.')
                  else
                    for (final a in changeRequests.take(4))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.edit_calendar_outlined),
                        title: Text('${a.pendingChange!.kind} request'),
                        subtitle: Text(
                          '${dateLabel(a.dateTime)}, ${timeLabel(a.dateTime)} · ${a.pendingChange!.reason}',
                        ),
                        onTap: () => context.go('/admin/appointments'),
                      ),
                ],
              ),
            ),
            const _RecentNotifications(),
            DashCard(
              key: const Key('dash-audit'),
              title: 'Recent activity (audit log)',
              icon: Icons.policy_outlined,
              path: '/admin/audit-logs',
              child: _async<AuditPage>(audit, (page) {
                if (page.entries.isEmpty) return _empty('No activity today.');
                return Column(
                  children: [
                    for (final e in page.entries.take(6))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          e.isFailure ? Icons.error_outline : Icons.history,
                          color: e.isFailure ? Colors.red.shade600 : null,
                        ),
                        title: Text(e.action.replaceAll('_', ' ').toLowerCase()),
                        subtitle: Text(
                          '${e.userName ?? e.role ?? 'System'} · ${e.details}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: e.timestamp == null ? null : Text(timeLabel(e.timestamp!)),
                      ),
                  ],
                );
              }),
            ),
            DashCard(
              key: const Key('dash-deliveries'),
              title: 'Deliveries',
              icon: Icons.local_shipping_outlined,
              path: '/admin/deliveries',
              child: _async(
                deliveries,
                (_) => MiniBars([
                  ('Dispatched', byDelivery('dispatched'), Colors.blue.shade400),
                  ('In transit', byDelivery('in_transit'), Colors.purple.shade300),
                  ('Delivered', byDelivery('delivered'), Colors.green.shade600),
                  ('Failed', byDelivery('failed'), Colors.red.shade600),
                ]),
              ),
            ),
            DashCard(
              key: const Key('dash-hospital'),
              title: 'Hospital analytics: patient risk',
              icon: Icons.insights_outlined,
              path: '/admin/analytics/hospital',
              child: _async(
                hospital,
                (h) => MiniBars([
                  for (final l in RiskLevel.values)
                    (
                      '${l.value[0].toUpperCase()}${l.value.substring(1)}',
                      h.risk.counts[l] ?? 0,
                      _riskColor(l),
                    ),
                ]),
              ),
            ),
            DashCard(
              key: const Key('dash-usage'),
              title: 'Usage analytics (last 7 days)',
              icon: Icons.query_stats,
              path: '/admin/analytics/system',
              child: _async(
                usage,
                (u) => MiniBars([
                  ('Users', u.totalUsers, Colors.blueGrey),
                  ('Clinicians', u.activeClinicians, Colors.blue.shade400),
                  ('Messages', u.messagesSent, Colors.teal.shade400),
                  ('Critical', u.unresolvedCritical, Colors.red.shade400),
                ]),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
