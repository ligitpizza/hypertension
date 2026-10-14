import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/risk_style.dart';
import '../domain/appointment_text.dart';
import '../state/appointment_providers.dart';

/// UC7.5 pre-visit summary, shared by the patient app and the doctor portal (FR-7.4).
class PreVisitSummaryPage extends ConsumerWidget {
  const PreVisitSummaryPage({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Pre-visit summary')),
    body: PreVisitSummaryView(appointmentId: appointmentId),
  );
}

class PreVisitSummaryView extends ConsumerWidget {
  const PreVisitSummaryView({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(preVisitSummaryProvider(appointmentId));
    return summary.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(preVisitSummaryProvider(appointmentId)),
          child: const Text('Could not load the summary. Retry'),
        ),
      ),
      data: (s) => _Body(s: s),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.s});

  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vitals = s['vitals'] as Map<String, dynamic>?;
    final risk = s['risk'] as Map<String, dynamic>?;
    final meds = (s['medications'] as List? ?? const []).cast<Map<dynamic, dynamic>>();
    final gaps = (s['dataGaps'] as List? ?? const []).cast<String>();
    final open = (s['openItems'] as List? ?? const []).cast<String>();
    final when = DateTime.tryParse('${s['dateTime']}');
    Widget section(String title, List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
    return ListView(
      key: const Key('pre-visit-summary'),
      padding: const EdgeInsets.all(16),
      children: [
        if (when != null) Text('For ${dateLabel(when)}, ${timeLabel(when)}'),
        if (gaps.isNotEmpty)
          Card(
            key: const Key('summary-gaps'),
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Missing information'),
                  for (final g in gaps) Text('• $g', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        section('Blood pressure (last 14 days)', [
          if (vitals == null)
            const Text('No readings.')
          else ...[
            Text(
              'Average ${vitals['averageSystolic']}/${vitals['averageDiastolic']} mmHg '
              '(${vitals['count']} readings)',
            ),
            Text('Highest ${vitals['highest']} · Latest ${vitals['latest']}'),
            if (vitals['averageHeartRate'] != null)
              Text('Average heart rate ${vitals['averageHeartRate']} bpm (estimate)'),
          ],
        ]),
        section('Risk assessment', [
          if (risk == null)
            const Text('Not available yet.')
          else ...[
            Text('Overall: ${'${risk['overallLevel']}'.toUpperCase()}'),
            for (final e in ((risk['scores'] as Map?) ?? const {}).entries)
              if (e.value is Map)
                Text(
                  '${factorLabel('${e.key}')}: '
                  '${((((e.value as Map)['value'] as num?) ?? 0) * 100).toStringAsFixed(1)}%',
                ),
          ],
        ]),
        section('Medicines', [
          if (meds.isEmpty) const Text('None recorded.'),
          for (final m in meds)
            Text(
              '${m['name']}'
              '${m['adherenceRate'] == null ? '' : ' · adherence ${(m['adherenceRate'] as num).round()}%'}',
            ),
          for (final o in open) Text(o, style: TextStyle(color: theme.colorScheme.error)),
        ]),
        if (s['carePlan'] != null) section('Care plan', [Text('${s['carePlan']}')]),
        const SizedBox(height: 8),
        Text(
          'A summary of your records to discuss with your doctor; not a diagnosis.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
