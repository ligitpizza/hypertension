import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/risk_style.dart';
import '../../../shared/models/health_models.dart';
import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../../dashboard/state/dashboard_providers.dart';
import '../../medications/domain/med_schedule.dart' show toMyt;
import '../data/family_repository.dart';
import '../state/family_providers.dart';

final _readingsProvider = StreamProvider.autoDispose.family<List<VitalReading>, String>(
  (ref, id) => ref.watch(dashboardRepositoryProvider).recentReadings(id, limit: 60),
);
final _riskProvider = StreamProvider.autoDispose.family<RiskScore?, String>(
  (ref, id) => ref.watch(dashboardRepositoryProvider).latestRiskScore(id),
);

/// An unacknowledged alert from the last day is shown as a banner (UC15.3).
EmergencyAlert? activeAlert(List<EmergencyAlert> alerts, DateTime now) => alerts
    .where((a) => !a.isAcknowledged && now.difference(a.sentAt) < const Duration(hours: 24))
    .firstOrNull;

/// Family Dashboard (Fig 4.3.16.2; FR-14.2, UC15.1): read-only.
class FamilyDashboardPage extends ConsumerWidget {
  const FamilyDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked = ref.watch(linkedPatientIdProvider);
    final pending = ref.watch(myPendingLinkProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Family Dashboard')),
      body: linked.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load. Check your connection.')),
        data: (patientId) => patientId == null
            ? _NotLinked(pending: pending != null)
            : _Linked(patientId: patientId),
      ),
    );
  }
}

class _NotLinked extends StatelessWidget {
  const _NotLinked({required this.pending});

  final bool pending;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Icon(pending ? Icons.hourglass_top : Icons.link, size: 56),
      const SizedBox(height: 12),
      Text(
        pending ? 'Waiting for approval' : 'Not linked yet',
        key: const Key('family-not-linked'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        pending
            ? 'Your request was sent. You will see their health here once they approve it.'
            : 'Ask your family member for the link code in their Harvey app (Settings → '
                  'Family), then enter it here.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      if (!pending)
        FilledButton.icon(
          key: const Key('family-go-link'),
          onPressed: () => context.go('/family/link'),
          icon: const Icon(Icons.key),
          label: const Text('Enter link code'),
        ),
    ],
  );
}

class _Linked extends ConsumerWidget {
  const _Linked({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(nowProvider)();
    final person = ref.watch(linkedPersonProvider(patientId)).value;
    final readings = ref.watch(_readingsProvider(patientId)).value ?? const <VitalReading>[];
    final risk = ref.watch(_riskProvider(patientId)).value;
    final alert = activeAlert(ref.watch(myEmergencyAlertsProvider).value ?? const [], now);
    final today = toMyt(now);
    bool sameDay(DateTime t, DateTime d) {
      final l = toMyt(t);
      return l.year == d.year && l.month == d.month && l.day == d.day;
    }

    final latest = readings.firstOrNull;
    final latestToday = latest != null && sameDay(latest.timestamp, today) ? latest : null;
    final yesterday = today.subtract(const Duration(days: 1));
    final prev = readings.where((r) => sameDay(r.timestamp, yesterday)).firstOrNull;
    final hr = readings.where((r) => r.heartRate != null).firstOrNull;
    final level = risk?.overallLevel;
    final week = readings
        .where((r) => now.difference(r.timestamp).inDays < 7)
        .toList()
        .reversed
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            CircleAvatar(child: Text((person?.name ?? '?').characters.first.toUpperCase())),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monitoring patient', style: theme.textTheme.bodySmall),
                Text(person?.name ?? '…', style: theme.textTheme.titleMedium),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (alert != null)
          Card(
            key: const Key('family-alert-banner'),
            color: Colors.red.shade700,
            child: ListTile(
              leading: const Icon(Icons.warning_amber, color: Colors.white),
              title: Text(
                'Emergency: ${alert.title}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${dateLabel(alert.sentAt)}, ${timeLabel(alert.sentAt)} · tap to see where they are',
                style: const TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () => context.go('/family/alert/${alert.id}'),
            ),
          ),
        Card(
          key: const Key('family-status'),
          color: level == null ? null : riskColor(level).withValues(alpha: 0.12),
          child: ListTile(
            title: Text('CURRENT STATUS', style: theme.textTheme.labelLarge),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: level == null ? Colors.grey : riskColor(level),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      level == null ? 'Not assessed yet' : riskLabel(level),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                Text(switch (level) {
                  null => 'A risk assessment appears after three readings.',
                  RiskLevel.low => 'Readings look steady.',
                  RiskLevel.moderate => 'Elevated blood pressure detected recently.',
                  RiskLevel.high => 'High risk. They may need to see their doctor soon.',
                  RiskLevel.critical => 'Critical risk. Please check on them now.',
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text("Today's vitals", style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Card(
          key: const Key('family-bp'),
          child: ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('BLOOD PRESSURE'),
            subtitle: Text(
              latestToday == null
                  ? 'No reading today${latest == null ? '' : ' (last: ${latest.systolic}/${latest.diastolic}, ${dateLabel(latest.timestamp)})'}'
                  : '${latestToday.systolic}/${latestToday.diastolic} mmHg'
                        '${prev == null ? '' : ' · ${latestToday.systolic - prev.systolic >= 0 ? '+' : ''}${latestToday.systolic - prev.systolic} from yesterday'}',
            ),
            trailing: latestToday == null ? null : Text(timeLabel(latestToday.timestamp)),
          ),
        ),
        Card(
          key: const Key('family-hr'),
          child: ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('HEART RATE'),
            subtitle: Text(
              hr == null ? 'No heart rate recorded' : '${hr.heartRate} BPM (camera estimate)',
            ),
            trailing: hr == null ? null : Text(timeLabel(hr.timestamp)),
          ),
        ),
        const SizedBox(height: 12),
        Text('7-day trend', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Card(
          key: const Key('family-trend'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: week.length < 2
                ? const Text('Not enough readings this week to show a trend.')
                : SizedBox(
                    height: 160,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(drawVerticalLine: false),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(
                          topTitles: AxisTitles(),
                          rightTitles: AxisTitles(),
                          bottomTitles: AxisTitles(),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (final (i, r) in week.indexed)
                                FlSpot(i.toDouble(), r.systolic.toDouble()),
                            ],
                            color: theme.colorScheme.primary,
                            isCurved: true,
                          ),
                          LineChartBarData(
                            spots: [
                              for (final (i, r) in week.indexed)
                                FlSpot(i.toDouble(), r.diastolic.toDouble()),
                            ],
                            color: Colors.teal,
                            isCurved: true,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Read-only view. Only your family member and their doctor can change their records.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
