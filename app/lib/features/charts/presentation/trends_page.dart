import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../shared/models/health_models.dart';
import '../../auth/state/auth_providers.dart';
import '../../dashboard/domain/dashboard_logic.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../domain/trend_logic.dart';
import '../state/trends_providers.dart';
import 'bp_trend_chart.dart';
import 'risk_trend_card.dart';

/// Fig 4.3.4.1 Health Trends / Fig 4.3.4.2 empty state (FR-4.1-4.3, UC4.1-UC4.4,
/// Fig 4.1.1.4). Shows the signed-in patient; the doctor portal passes [patientId].
class TrendsPage extends ConsumerStatefulWidget {
  const TrendsPage({super.key, this.patientId});

  final String? patientId;

  @override
  ConsumerState<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends ConsumerState<TrendsPage> {
  TrendRange _range = TrendRange.week;
  bool _compareHeartRate = false;

  @override
  Widget build(BuildContext context) {
    final patientId = widget.patientId ?? ref.watch(authUidProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Health Trends')),
      body: patientId == null
          ? const Center(child: CircularProgressIndicator())
          : _body(context, patientId),
    );
  }

  Widget _body(BuildContext context, String patientId) {
    final now = ref.watch(nowProvider)();
    // "Enough data" is judged over the last year (Fig 4.3.4.2: log 3+ readings).
    final yearAsync = ref.watch(readingsInRangeProvider((patientId, TrendRange.year)));
    final rangeAsync = ref.watch(readingsInRangeProvider((patientId, _range)));
    final riskAsync = ref.watch(riskHistoryProvider(patientId));

    return yearAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ErrorRetry(
        message: 'Could not load your readings.',
        onRetry: () => ref.invalidate(readingsInRangeProvider((patientId, TrendRange.year))),
      ),
      data: (all) {
        if (all.length < minReadingsForRisk) {
          return _NotEnoughData(readings: all, own: widget.patientId == null);
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _LatestReadingCard(latest: all.first, now: now),
            const SizedBox(height: 16),
            _TrendCard(
              range: _range,
              compareHeartRate: _compareHeartRate,
              now: now,
              readings: rangeAsync,
              onRange: (r) => setState(() => _range = r),
              onCompare: (v) => setState(() => _compareHeartRate = v),
              onRetry: () => ref.invalidate(readingsInRangeProvider((patientId, _range))),
            ),
            const SizedBox(height: 16),
            riskAsync.when(
              data: (scores) => RiskTrendCard(scores: scores),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _ErrorRetry(
                message: 'Could not load your risk history.',
                onRetry: () => ref.invalidate(riskHistoryProvider(patientId)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _LatestReadingCard extends StatelessWidget {
  const _LatestReadingCard({required this.latest, required this.now});

  final VitalReading latest;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = BpClassifier.classify(latest.systolic, latest.diastolic);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: BpClassifier.color(c), width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Latest Reading', style: Theme.of(context).textTheme.titleMedium),
                Text(timeAgo(latest.timestamp, now)),
                const SizedBox(height: 8),
                Text.rich(
                  key: const Key('trends-latest'),
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${latest.systolic}',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      TextSpan(
                        text: '/${latest.diastolic}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const TextSpan(text: ' mmHg'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Chip(
            avatar: CircleAvatar(backgroundColor: BpClassifier.color(c), radius: 5),
            label: Text(BpClassifier.label(c)),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.range,
    required this.compareHeartRate,
    required this.now,
    required this.readings,
    required this.onRange,
    required this.onCompare,
    required this.onRetry,
  });

  final TrendRange range;
  final bool compareHeartRate;
  final DateTime now;
  final AsyncValue<List<VitalReading>> readings;
  final ValueChanged<TrendRange> onRange;
  final ValueChanged<bool> onCompare;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Blood Pressure Trends', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<TrendRange>(
              key: const Key('trend-range'),
              showSelectedIcon: false,
              segments: [
                for (final r in TrendRange.values) ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {range},
              onSelectionChanged: (s) => onRange(s.first),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const Key('compare-hr'),
                avatar: const Icon(Icons.favorite_border, size: 18),
                label: const Text('Compare heart rate'),
                selected: compareHeartRate,
                onSelected: onCompare,
              ),
            ),
            const SizedBox(height: 8),
            readings.when(
              loading: () =>
                  const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
              error: (_, _) => _ErrorRetry(message: 'Could not load this range.', onRetry: onRetry),
              data: (list) => _chartAndStats(context, list),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartAndStats(BuildContext context, List<VitalReading> list) {
    final points = buildPoints(list, range, now);
    final stats = computeStats(list, range, now);
    if (points.isEmpty || stats == null) {
      // UC4.1 E1: no readings in the selected range.
      return const SizedBox(
        key: Key('trend-range-empty'),
        height: 120,
        child: Center(child: Text('No readings in this period. Try a longer range.')),
      );
    }
    final hrMissing = compareHeartRate && !hasHeartRate(points);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: BpTrendChart(
            points: points,
            range: range,
            now: now,
            showHeartRate: compareHeartRate,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          children: [
            const ChartLegend(color: BpTrendChart.systolicColor, label: 'Systolic'),
            const ChartLegend(color: BpTrendChart.diastolicColor, label: 'Diastolic'),
            if (compareHeartRate && !hrMissing)
              const ChartLegend(color: BpTrendChart.heartRateColor, label: 'Heart rate'),
          ],
        ),
        if (hrMissing)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            // UC4.3 E1: show the primary vital only and note the gap.
            child: Text(
              'No heart-rate readings in this period, so only blood pressure is shown.',
              key: Key('hr-missing'),
            ),
          ),
        if (range.dailyAverages)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Each point is a daily average.', style: TextStyle(fontSize: 12)),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Avg',
                value: '${stats.avgSystolic}/${stats.avgDiastolic}',
                key: const Key('stat-avg'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'Min',
                value: '${stats.min.systolic}/${stats.min.diastolic}',
                key: const Key('stat-min'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'Max',
                value: '${stats.max.systolic}/${stats.max.diastolic}',
                highlight:
                    BpClassifier.classify(stats.max.systolic, stats.max.diastolic).index >=
                    BpCategory.stage2.index,
                key: const Key('stat-max'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          key: const Key('stat-summary'),
          [
            '${stats.count} ${stats.count == 1 ? 'reading' : 'readings'}',
            if (stats.avgHeartRate != null) 'avg heart rate ${stats.avgHeartRate} bpm',
            // UC4.2 E1: trend statistics need at least two readings.
            if (stats.hasTrend)
              'systolic ${stats.systolicChange! > 0
                      ? 'up'
                      : stats.systolicChange! < 0
                      ? 'down'
                      : 'unchanged'}'
                  '${stats.systolicChange == 0 ? '' : ' ${stats.systolicChange!.abs()} mmHg'} '
                  'over this period',
          ].join(' · '),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({super.key, required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: highlight ? scheme.errorContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: highlight ? scheme.onErrorContainer : null),
          ),
        ],
      ),
    );
  }
}

/// Fig 4.3.4.2: fewer than three readings.
class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData({required this.readings, required this.own});

  final List<VitalReading> readings;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final hr = readings.map((r) => r.heartRate).whereType<int>();
    final avgHr = hr.isEmpty ? null : (hr.reduce((a, b) => a + b) / hr.length).round();
    final avgBp = readings.isEmpty
        ? null
        : '${(readings.map((r) => r.systolic).reduce((a, b) => a + b) / readings.length).round()}'
              '/${(readings.map((r) => r.diastolic).reduce((a, b) => a + b) / readings.length).round()}';
    return ListView(
      key: const Key('trends-not-enough'),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.insights, size: 48),
                const SizedBox(height: 12),
                Text('Not enough data yet', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Log ${minReadingsForRisk - readings.length} more '
                  '${minReadingsForRisk - readings.length == 1 ? 'reading' : 'readings'} to see '
                  'your health trends and personalised insights.',
                  textAlign: TextAlign.center,
                ),
                if (own) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('trends-log-now'),
                    onPressed: () => context.push('/vitals/log'),
                    icon: const Icon(Icons.add),
                    label: const Text('Log Vitals Now'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Overview', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Avg Heart Rate',
                value: avgHr == null ? '-- bpm' : '$avgHr bpm',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(label: 'Avg BP', value: avgBp ?? '--/--'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Overall Risk Score'),
            subtitle: Text('Pending Data'),
          ),
        ),
      ],
    );
  }
}
