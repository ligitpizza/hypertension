import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
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
                    onPressed: () => context.go('/trends'),
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
          const SizedBox(height: 16),
          const Card(
            child: ListTile(
              leading: Icon(Icons.lightbulb_outline),
              title: Text('Great job logging!'),
              subtitle: Text(
                'Consistent tracking helps you and your doctor understand your heart health '
                'better. Keep it up!',
              ),
            ),
          ),
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
