import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../../dashboard/state/dashboard_providers.dart';
import '../../medications/domain/med_schedule.dart' show toMyt;
import '../../settings/state/settings_providers.dart';
import '../data/admin_repository.dart';
import '../state/admin_providers.dart';

/// "DEACTIVATE_ACCOUNT" -> "Deactivate account".
String actionLabel(String action) {
  final words = action.toLowerCase().split('_');
  if (words.isEmpty || words.first.isEmpty) return action;
  return '${words.first[0].toUpperCase()}${words.first.substring(1)} ${words.skip(1).join(' ')}'
      .trim();
}

/// Security & Audit Logs (Fig 4.3.14.3; FR-1.5, FR-11.3, UC11.3; D-59).
class AuditLogsPage extends ConsumerStatefulWidget {
  const AuditLogsPage({super.key});

  @override
  ConsumerState<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends ConsumerState<AuditLogsPage> {
  final _search = TextEditingController();
  int _days = 7;
  String? _action;
  String _text = '';
  int _offset = 0;
  bool _exporting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AuditQuery _query() {
    final today = toMyt(ref.read(nowProvider)());
    final to = DateTime(today.year, today.month, today.day);
    return AuditQuery(
      from: to.subtract(Duration(days: _days - 1)),
      to: to,
      action: _action,
      text: _text,
      offset: _offset,
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(adminRepositoryProvider).auditCsv(_query());
      await ref
          .read(fileSharerProvider)
          .share(bytes, fileName: 'careflow-audit-log.csv', mimeType: 'text/csv');
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not export the log.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query();
    final page = ref.watch(auditLogsProvider(query));
    final theme = Theme.of(context);
    final actions = page.value?.actions ?? const <String>[];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Security & Audit Logs', style: theme.textTheme.headlineSmall),
                const Text('System activity, user actions and administrative changes.'),
              ],
            ),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<int>(
                  key: const Key('audit-range'),
                  value: _days,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Today')),
                    DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                    DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                    DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                  ],
                  onChanged: (v) => setState(() {
                    _days = v ?? 7;
                    _offset = 0;
                  }),
                ),
                DropdownButton<String?>(
                  key: const Key('audit-action'),
                  value: actions.contains(_action) ? _action : null,
                  items: [
                    const DropdownMenuItem(child: Text('All actions')),
                    for (final a in actions)
                      DropdownMenuItem(value: a, child: Text(actionLabel(a))),
                  ],
                  onChanged: (v) => setState(() {
                    _action = v;
                    _offset = 0;
                  }),
                ),
                FilledButton.icon(
                  key: const Key('audit-export'),
                  onPressed: _exporting ? null : _export,
                  icon: const Icon(Icons.download),
                  label: const Text('Export CSV'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (page.value case final p?) _Summary(summary: p.summary, days: _days),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 360,
                      child: TextField(
                        key: const Key('audit-search'),
                        controller: _search,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search logs by user, action, or ID…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (v) => setState(() {
                          _text = v.trim();
                          _offset = 0;
                        }),
                      ),
                    ),
                    const Spacer(),
                    if (page.value case final p?) ...[
                      Text(
                        p.total == 0
                            ? 'No entries'
                            : 'Showing ${_offset + 1}-${_offset + p.entries.length} of ${p.total}',
                        key: const Key('audit-count'),
                      ),
                      IconButton(
                        key: const Key('audit-prev'),
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _offset > 0
                            ? () => setState(() => _offset = (_offset - 15).clamp(0, _offset))
                            : null,
                      ),
                      IconButton(
                        key: const Key('audit-next'),
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _offset + 15 < p.total
                            ? () => setState(() => _offset += 15)
                            : null,
                      ),
                    ],
                  ],
                ),
                const Divider(),
                page.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => ListTile(
                    leading: const Icon(Icons.cloud_off),
                    title: const Text('Could not load the audit log.'),
                    trailing: TextButton(
                      onPressed: () => ref.invalidate(auditLogsProvider(query)),
                      child: const Text('Retry'),
                    ),
                  ),
                  data: (p) => p.entries.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No activity matches these filters.',
                            key: Key('audit-empty'),
                          ),
                        )
                      : Column(children: [for (final e in p.entries) _EntryRow(entry: e)]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary, required this.days});

  final Map<String, dynamic> summary;
  final int days;

  @override
  Widget build(BuildContext context) {
    final change = summary['changeFromPrevious'] as num?;
    Widget card(String key, String title, Object? value, String note, Color color) => SizedBox(
      width: 240,
      child: Card(
        key: Key(key),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelLarge),
              Text('${value ?? 0}', style: Theme.of(context).textTheme.displaySmall),
              Text(note),
            ],
          ),
        ),
      ),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        card(
          'sum-total',
          'Total events',
          summary['totalEvents'],
          change == null
              ? 'No earlier period to compare'
              : '${change >= 0 ? '↑' : '↓'} ${change.abs()}% from the previous $days days',
          Colors.blue.shade700,
        ),
        card(
          'sum-failed',
          'Failed logins',
          summary['failedLogins'],
          'Wrong password or blocked accounts',
          Colors.red.shade700,
        ),
        card(
          'sum-privilege',
          'Privilege changes',
          summary['privilegeChanges'],
          'Staff created, edited or (de)activated',
          Colors.brown,
        ),
        card(
          'sum-exports',
          'Data exports',
          summary['dataExports'],
          'Patient exports, reports and log exports',
          Colors.teal.shade700,
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final t = e.timestamp;
    final anonymous = e.userName == null && (e.userId == null || e.userId == 'anonymous');
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      key: Key('audit-${e.id}'),
      leading: SizedBox(
        width: 120,
        child: Text(t == null ? '-' : '${dateLabel(t)}\n${timeLabel(t)} MYT'),
      ),
      title: Text(
        actionLabel(e.action),
        style: e.isFailure ? TextStyle(color: error, fontWeight: FontWeight.w600) : null,
      ),
      subtitle: Text(
        '${anonymous ? 'Unauthenticated' : (e.userName ?? e.userId)}'
        '${e.role == null ? '' : ' · ${e.role}'}\n${e.details}',
      ),
      isThreeLine: true,
      trailing: Chip(label: Text(e.module), visualDensity: VisualDensity.compact),
    );
  }
}
