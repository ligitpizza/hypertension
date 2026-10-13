import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../core/utils/risk_style.dart';
import '../../charts/presentation/risk_trend_card.dart' show complicationNames;
import '../data/vitals_repository.dart';

/// Fig 4.3.3.3 Reading Saved: confirms the entry with its BP category and heart rate.
class ReadingSavedPage extends StatelessWidget {
  const ReadingSavedPage({super.key, required this.reading});

  final LoggedReading reading;

  @override
  Widget build(BuildContext context) {
    final color = BpClassifier.color(reading.category);
    final t = reading.loggedAt;
    final time =
        '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} '
        '${t.hour < 12 ? 'AM' : 'PM'}';
    return Scaffold(
      appBar: AppBar(title: const Text('Reading Saved')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (reading.category == BpCategory.crisis) const _CrisisBanner(),
          Container(
            key: const Key('saved-card'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.history, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('Last Reading')),
                    Chip(
                      key: const Key('saved-category'),
                      avatar: CircleAvatar(backgroundColor: color, radius: 5),
                      label: Text(BpClassifier.label(reading.category)),
                    ),
                  ],
                ),
                Text('Today, $time'),
                const SizedBox(height: 12),
                Text(
                  '${reading.systolic}/${reading.diastolic} mmHg',
                  key: const Key('saved-value'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('saved-view-trends'),
                    onPressed: () => context.pushReplacement('/trends'),
                    icon: const Icon(Icons.trending_up),
                    label: const Text('View Trends'),
                  ),
                ),
              ],
            ),
          ),
          if (reading.heartRate != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.favorite_border),
                title: Text('${reading.heartRate} BPM', key: const Key('saved-hr')),
                subtitle: const Text('Heart rate (camera estimate)'),
              ),
            ),
          ],
          if (reading.bookAppointmentPrompt) ...[
            const SizedBox(height: 16),
            const _BookAppointmentCard(),
          ],
          const SizedBox(height: 16),
          if (reading.risk != null)
            _RiskCard(risk: reading.risk!)
          else if (reading.readingsUntilRisk > 0)
            Card(
              key: const Key('saved-risk-progress'),
              child: ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: const Text('Risk assessment'),
                subtitle: Text(
                  'Log ${reading.readingsUntilRisk} more '
                  'reading${reading.readingsUntilRisk == 1 ? '' : 's'} '
                  'to get your risk assessment.',
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (reading.recommendations.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.lightbulb_outline),
                title: Text('Great job logging!'),
                subtitle: Text(
                  'Consistent tracking helps you and your doctor understand your heart health '
                  'better. Keep it up!',
                ),
              ),
            )
          else
            _RecommendationsCard(tips: reading.recommendations),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

/// Health-safety message for a crisis-range reading (CLAUDE.md: emergency number 999).
/// Doctor/family escalation is delivered by Module 9 (Increment 2).
class _CrisisBanner extends StatelessWidget {
  const _CrisisBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('crisis-banner'),
      color: BpClassifier.color(BpCategory.crisis),
      margin: const EdgeInsets.only(bottom: 16),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'This reading is very high. Sit quietly for 5 minutes and measure again. '
          'If you have chest pain, shortness of breath, weakness, confusion or blurred vision, '
          'call 999 now.',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

/// UC9.2 / UC9.3: high reading or risk. Booking itself is FR-7.5 (appointments module).
class _BookAppointmentCard extends StatelessWidget {
  const _BookAppointmentCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('saved-book-prompt'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        leading: const Icon(Icons.event_available),
        title: const Text('Please see your doctor soon'),
        subtitle: const Text(
          'Your doctor has been notified. We recommend booking an appointment to review '
          'your treatment.',
        ),
      ),
    );
  }
}

/// UC9.1 result: overall level and each complication (FR-9.2, FR-9.3).
class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.risk});

  final ReadingRisk risk;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return Card(
      key: const Key('saved-risk'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Risk assessment')),
                Chip(
                  key: const Key('saved-risk-overall'),
                  avatar: CircleAvatar(backgroundColor: riskColor(risk.overall), radius: 5),
                  label: Text(riskLabel(risk.overall)),
                ),
              ],
            ),
            for (final c in Complication.values)
              if (risk.scores[c] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(complicationNames[c]!)),
                      if (risk.diagnosed.contains(c))
                        Text(
                          'Already diagnosed',
                          key: Key('saved-diagnosed-${c.value}'),
                          style: muted,
                        )
                      else ...[
                        Text(riskPercent(risk.scores[c]!.value)),
                        const SizedBox(width: 8),
                        CircleAvatar(backgroundColor: riskColor(risk.scores[c]!.level), radius: 5),
                      ],
                    ],
                  ),
                ),
            if (risk.lowConfidence) ...[
              const SizedBox(height: 8),
              Text(
                'Some health details are missing, so this estimate is less certain. '
                'Complete your health profile to improve it.',
                key: const Key('saved-risk-low-confidence'),
                style: muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// FR-9.4 personalised tips; the server always ends with the not-a-doctor disclaimer.
class _RecommendationsCard extends StatelessWidget {
  const _RecommendationsCard({required this.tips});

  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    final body = tips.length > 1 ? tips.sublist(0, tips.length - 1) : tips;
    return Card(
      key: const Key('saved-recommendations'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb_outline),
                SizedBox(width: 8),
                Text('Recommendations'),
              ],
            ),
            const SizedBox(height: 8),
            for (final tip in body)
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('• $tip')),
            if (tips.length > 1) ...[
              const SizedBox(height: 8),
              Text(tips.last, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
