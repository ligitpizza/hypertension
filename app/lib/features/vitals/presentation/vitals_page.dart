import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/bp_classifier.dart';
import '../../../shared/models/health_models.dart';
import '../../dashboard/domain/dashboard_logic.dart';
import '../../dashboard/state/dashboard_providers.dart';

/// Vitals tab (Fig 4.3.3.1 empty state; latest reading and history once data exists).
class VitalsPage extends ConsumerWidget {
  const VitalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(recentReadingsProvider);
    final now = ref.watch(nowProvider)();
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
            Text('Latest Readings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _LatestCard(latest: list.firstOrNull, now: now),
            const SizedBox(height: 24),
            Text('Insights', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _RiskUnlockCard(count: list.length),
            const SizedBox(height: 24),
            Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('vitals-log-bp'),
                    onPressed: () => context.push('/vitals/log'),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Log BP'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.go('/medications'),
                    icon: const Icon(Icons.medication_outlined),
                    label: const Text('Add Meds'),
                  ),
                ),
              ],
            ),
            if (list.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('Recent readings', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  TextButton(
                    onPressed: () => context.push('/trends'),
                    child: const Text('View Trends'),
                  ),
                ],
              ),
              for (final r in list.take(10)) _ReadingTile(reading: r, now: now),
            ],
          ],
        ),
      ),
    );
  }
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.latest, required this.now});

  final VitalReading? latest;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = latest;
    final category = r == null ? null : BpClassifier.classify(r.systolic, r.diastolic);
    return Card(
      key: const Key('vitals-latest'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('LATEST BP READING')),
                if (category != null)
                  Chip(
                    avatar: CircleAvatar(backgroundColor: BpClassifier.color(category), radius: 5),
                    label: Text(BpClassifier.label(category)),
                  ),
              ],
            ),
            Text(
              r == null ? '-- / --  mmHg' : '${r.systolic} / ${r.diastolic}  mmHg',
              key: const Key('vitals-latest-value'),
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: r == null ? scheme.outline : null),
            ),
            if (r != null) Text(timeAgo(r.timestamp, now)),
            if (r?.heartRate != null) Text('Heart rate ${r!.heartRate} bpm (estimate)'),
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
      ),
    );
  }
}

class _RiskUnlockCard extends StatelessWidget {
  const _RiskUnlockCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final shown = count.clamp(0, minReadingsForRisk);
    final unlocked = count >= minReadingsForRisk;
    return Card(
      key: const Key('vitals-risk-unlock'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('AI RISK ASSESSMENT')),
                Icon(unlocked ? Icons.lock_open : Icons.lock_outline, size: 18),
              ],
            ),
            const SizedBox(height: 8),
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
            LinearProgressIndicator(value: shown / minReadingsForRisk),
            const SizedBox(height: 4),
            Text('$shown/$minReadingsForRisk readings', key: const Key('vitals-risk-progress')),
          ],
        ),
      ),
    );
  }
}

class _ReadingTile extends StatelessWidget {
  const _ReadingTile({required this.reading, required this.now});

  final VitalReading reading;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = BpClassifier.classify(reading.systolic, reading.diastolic);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: BpClassifier.color(c), radius: 8),
      title: Text(
        '${reading.systolic}/${reading.diastolic} mmHg'
        '${reading.heartRate == null ? '' : ' · ${reading.heartRate} bpm'}',
      ),
      subtitle: Text(
        [
          BpClassifier.label(c),
          timeAgo(reading.timestamp, now),
          if (reading.note != null) reading.note!,
        ].join(' · '),
      ),
    );
  }
}
