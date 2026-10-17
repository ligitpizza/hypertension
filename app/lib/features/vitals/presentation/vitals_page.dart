import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../core/utils/risk_style.dart';
import '../../../shared/models/health_models.dart';
import '../../../shared/providers/api_providers.dart';
import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../../dashboard/domain/dashboard_logic.dart';
import '../../dashboard/state/dashboard_providers.dart';

/// D-78 testing aid: whether the backend allows deleting readings (DEV_VITALS_TOOLS).
final vitalsDevToolsProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return (await ref.watch(apiClientProvider).vitalsDevTools())['enabled'] == true;
  } catch (_) {
    return false;
  }
}, retry: (_, _) => null);

/// Vitals tab (Fig 4.3.3.1 empty state; latest reading and history once data exists).
/// D-78: colour by BP category, risk card by level, day-grouped history.
class VitalsPage extends ConsumerWidget {
  const VitalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(recentReadingsProvider);
    final now = ref.watch(nowProvider)();
    final dev = ref.watch(vitalsDevToolsProvider).value ?? false;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vitals Tracking')),
      body: readings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load your readings.'),
              TextButton(
                onPressed: () => ref.invalidate(recentReadingsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Latest Readings', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            _LatestCard(readings: list, now: now),
            const SizedBox(height: 20),
            Text('Insights', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            _RiskCard(count: list.length),
            const SizedBox(height: 20),
            Text('Quick Actions', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    key: const Key('vitals-log-bp'),
                    icon: Icons.favorite,
                    label: 'Log BP',
                    color: Colors.red.shade600,
                    onTap: () => context.push('/vitals/log'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.medication_outlined,
                    label: 'Add Meds',
                    color: Colors.teal.shade600,
                    onTap: () => context.go('/medications'),
                  ),
                ),
              ],
            ),
            if (list.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Text('Recent readings', style: theme.textTheme.titleLarge)),
                  TextButton(
                    onPressed: () => context.push('/trends'),
                    child: const Text('View Trends'),
                  ),
                ],
              ),
              if (dev) _DevBar(count: list.length),
              ..._grouped(list.take(15).toList(), now, dev),
            ],
          ],
        ),
      ),
    );
  }

  /// Readings under "Today" / "Yesterday" / date headers.
  static List<Widget> _grouped(List<VitalReading> list, DateTime now, bool dev) {
    String day(DateTime t) {
      final l = t.toLocal();
      final today = DateTime(now.year, now.month, now.day);
      final d = DateTime(l.year, l.month, l.day);
      final diff = today.difference(d).inDays;
      return diff == 0
          ? 'Today'
          : diff == 1
          ? 'Yesterday'
          : dateLabel(t);
    }

    final out = <Widget>[];
    String? current;
    for (final r in list) {
      final d = day(r.timestamp);
      if (d != current) {
        current = d;
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(d, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      }
      out.add(_ReadingTile(reading: r, dev: dev));
    }
    return out;
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            CircleAvatar(backgroundColor: color, foregroundColor: Colors.white, child: Icon(icon)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.readings, required this.now});

  final List<VitalReading> readings;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = readings.firstOrNull;
    final category = r == null ? null : BpClassifier.classify(r.systolic, r.diastolic);
    final color = category == null ? scheme.outline : BpClassifier.color(category);
    final change = systolicChangeFromPreviousDay(readings);
    return Container(
      key: const Key('vitals-latest'),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, color: color),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('LATEST BP READING', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (category != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    BpClassifier.label(category),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r == null ? '-- / --  mmHg' : '${r.systolic} / ${r.diastolic}  mmHg',
            key: const Key('vitals-latest-value'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: r == null ? scheme.outline : color,
            ),
          ),
          if (r != null)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(timeAgo(r.timestamp, now)),
                if (change != null && change != 0)
                  Chip(
                    key: const Key('vitals-change'),
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      change > 0 ? Icons.trending_up : Icons.trending_down,
                      size: 16,
                      color: change > 0 ? Colors.red.shade600 : Colors.green.shade600,
                    ),
                    label: Text('${change > 0 ? '+' : ''}$change from yesterday'),
                  ),
                if (r.heartRate != null) Text('Heart rate ${r.heartRate} bpm (estimate)'),
              ],
            ),
          if (category == BpCategory.crisis)
            Container(
              key: const Key('vitals-crisis'),
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Crisis range. If you have chest pain, breathlessness, weakness or '
                      'confusion, call 999 now.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (r == null) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('vitals-empty'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add_circle_outline),
                  SizedBox(width: 8),
                  Expanded(child: Text('Log your first reading to see data.')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RiskCard extends ConsumerWidget {
  const _RiskCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = count.clamp(0, minReadingsForRisk);
    final unlocked = count >= minReadingsForRisk;
    final level = ref.watch(latestRiskProvider).value?.overallLevel;
    final color = level == null ? Theme.of(context).colorScheme.primary : riskColor(level);
    return Container(
      key: const Key('vitals-risk-unlock'),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined, color: color),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('AI RISK ASSESSMENT', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              Icon(unlocked ? Icons.lock_open : Icons.lock_outline, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          if (unlocked && level != null) ...[
            Text(
              'Overall risk: ${riskLabel(level)}',
              key: const Key('vitals-risk-level'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
            const Text('See the details and ask the AI Health Agent on your Home page.'),
          ] else ...[
            Text(
              unlocked ? 'Risk assessment unlocked' : 'Unlock your risk score',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              unlocked
                  ? 'Your personalised risk insights appear on your dashboard.'
                  : 'Log ${minReadingsForRisk - shown} more '
                        '${minReadingsForRisk - shown == 1 ? 'reading' : 'readings'} '
                        'to enable personalised AI insights.',
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: shown / minReadingsForRisk,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            Text('$shown/$minReadingsForRisk readings', key: const Key('vitals-risk-progress')),
          ],
        ],
      ),
    );
  }
}

class _ReadingTile extends ConsumerWidget {
  const _ReadingTile({required this.reading, required this.dev});

  final VitalReading reading;
  final bool dev;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this reading?'),
        content: Text(
          '${reading.systolic}/${reading.diastolic} mmHg will be removed and your risk '
          'score recalculated. (Testing tool)',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteReading(reading.id);
      ref
        ..invalidate(recentReadingsProvider)
        ..invalidate(latestRiskProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not delete the reading.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BpClassifier.classify(reading.systolic, reading.diastolic);
    final color = BpClassifier.color(c);
    return Card(
      key: Key('reading-${reading.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 5)),
        ),
        child: ListTile(
          title: Text(
            '${reading.systolic}/${reading.diastolic} mmHg'
            '${reading.heartRate == null ? '' : ' · ${reading.heartRate} bpm'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              BpClassifier.label(c),
              timeLabel(reading.timestamp),
              if (reading.note != null) reading.note!,
            ].join(' · '),
          ),
          trailing: dev
              ? IconButton(
                  key: Key('delete-reading-${reading.id}'),
                  tooltip: 'Delete (testing)',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(context, ref),
                )
              : Icon(Icons.circle, size: 12, color: color),
        ),
      ),
    );
  }
}

/// D-78: "Clear all readings" while DEV_VITALS_TOOLS is on.
class _DevBar extends ConsumerWidget {
  const _DevBar({required this.count});
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    key: const Key('vitals-dev-bar'),
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.amber.shade100,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(Icons.build_outlined, size: 18, color: Colors.brown.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Testing tools are on', style: TextStyle(color: Colors.brown.shade800)),
        ),
        TextButton(
          key: const Key('vitals-clear-all'),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Clear all readings?'),
                content: Text(
                  'All your blood pressure readings and your risk score will be deleted. '
                  '(Testing tool)',
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  FilledButton(
                    key: const Key('vitals-clear-confirm'),
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Clear all'),
                  ),
                ],
              ),
            );
            if (ok != true) return;
            try {
              await ref.read(apiClientProvider).clearReadings();
              ref
                ..invalidate(recentReadingsProvider)
                ..invalidate(latestRiskProvider);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Could not clear the readings.')));
              }
            }
          },
          child: Text('Clear all ($count shown)'),
        ),
      ],
    ),
  );
}
