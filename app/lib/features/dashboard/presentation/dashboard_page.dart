import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../shared/models/health_models.dart';
import '../../auth/state/auth_providers.dart';
import '../domain/dashboard_logic.dart';
import '../state/dashboard_providers.dart';

/// Fig 4.3.2.1 Home Dashboard (FR-2.1, FR-2.2; UC2.1-UC2.5; sequence Fig 4.1.1.2).
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final now = ref.watch(nowProvider)();
    final firstName = (user?.name ?? '').split(' ').first;
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(recentReadingsProvider)
            ..invalidate(latestRiskProvider)
            ..invalidate(medicationsProvider)
            ..invalidate(upcomingAppointmentsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              '${greetingFor(now)}, $firstName',
              key: const Key('dashboard-greeting'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text('Here is your daily health snapshot.'),
            const SizedBox(height: 16),
            const _TodaysPlanCard(),
            const SizedBox(height: 16),
            const _LatestBpCard(),
            const SizedBox(height: 16),
            const _RiskCard(),
            const SizedBox(height: 24),
            Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const _QuickActions(),
          ],
        ),
      ),
    );
  }
}

/// Renders one AsyncValue section with its own loading / error / data states,
/// so one failing source never blanks the whole dashboard (UC2.1 E1).
class _Section<T> extends StatelessWidget {
  const _Section({required this.value, required this.onRetry, required this.builder, this.label});

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text('Could not load ${label ?? 'this section'}.')),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({super.key, required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: accent == null ? null : Border(left: BorderSide(color: accent!, width: 4)),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

// ---------- Today's Plan: medications (UC2.2) + next appointment (UC2.3) ----------

class _TodaysPlanCard extends ConsumerWidget {
  const _TodaysPlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meds = ref.watch(medicationsProvider);
    final appts = ref.watch(upcomingAppointmentsProvider);
    final now = ref.watch(nowProvider)();
    return _CardShell(
      key: const Key('card-todays-plan'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text("Today's Plan", style: Theme.of(context).textTheme.titleMedium)),
              const Icon(Icons.calendar_today_outlined, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          _Section<List<Medication>>(
            value: meds,
            label: 'medications',
            onRetry: () => ref.invalidate(medicationsProvider),
            builder: (list) => list.isEmpty
                ? _EmptyRow(
                    key: const Key('empty-medications'),
                    icon: Icons.medication_outlined,
                    text: 'No medications yet.',
                    action: 'Add one',
                    onTap: () => context.go('/medications'),
                  )
                : Column(
                    children: [
                      for (final m in list.take(3))
                        _PlanTile(
                          icon: Icons.medication,
                          title: '${m.name} ${m.dosage}'.trim(),
                          subtitle: m.schedule,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          _Section<List<Appointment>>(
            value: appts,
            label: 'appointments',
            onRetry: () => ref.invalidate(upcomingAppointmentsProvider),
            builder: (list) => list.isEmpty
                ? _EmptyRow(
                    key: const Key('empty-appointments'),
                    icon: Icons.event_available_outlined,
                    text: 'No upcoming appointments.',
                    action: 'Book one',
                    onTap: () => context.push('/appointments'),
                  )
                : _PlanTile(
                    key: const Key('next-appointment'),
                    icon: Icons.medical_services_outlined,
                    title: 'Appointment',
                    subtitle: appointmentLabel(list.first.dateTime, now),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({super.key, required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title),
      subtitle: Text(subtitle),
    ),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({
    super.key,
    required this.icon,
    required this.text,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
      TextButton(onPressed: onTap, child: Text(action)),
    ],
  );
}

// ---------- Latest BP reading ----------

class _LatestBpCard extends ConsumerWidget {
  const _LatestBpCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(recentReadingsProvider);
    final now = ref.watch(nowProvider)();
    final scheme = Theme.of(context).colorScheme;
    return _CardShell(
      key: const Key('card-latest-bp'),
      accent: scheme.primary,
      child: _Section<List<VitalReading>>(
        value: readings,
        label: 'your latest reading',
        onRetry: () => ref.invalidate(recentReadingsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return _EmptyRow(
              key: const Key('empty-bp'),
              icon: Icons.monitor_heart_outlined,
              text: 'No blood pressure readings yet.',
              action: 'Log one',
              onTap: () => context.push('/vitals/log'),
            );
          }
          final latest = list.first;
          final change = systolicChangeFromPreviousDay(list);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('LATEST BP READING', style: Theme.of(context).textTheme.labelLarge),
                  ),
                  Text(timeAgo(latest.timestamp, now)),
                ],
              ),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final c = BpClassifier.classify(latest.systolic, latest.diastolic);
                  return Chip(
                    key: const Key('latest-bp-category'),
                    avatar: CircleAvatar(backgroundColor: BpClassifier.color(c), radius: 5),
                    label: Text(BpClassifier.label(c)),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text.rich(
                key: const Key('latest-bp-value'),
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${latest.systolic} / ${latest.diastolic}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const TextSpan(text: '  mmHg'),
                  ],
                ),
              ),
              if (latest.heartRate != null) Text('Heart rate ${latest.heartRate} bpm (estimate)'),
              if (change != null) ...[
                const SizedBox(height: 8),
                Chip(
                  key: const Key('latest-bp-change'),
                  avatar: Icon(change <= 0 ? Icons.trending_down : Icons.trending_up, size: 18),
                  label: Text('${change > 0 ? '+' : ''}$change from yesterday'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------- AI risk assessment (UC2.4) ----------

Color riskColor(RiskLevel level) => switch (level) {
  RiskLevel.low => BpColors.normal,
  RiskLevel.moderate => BpColors.elevated,
  RiskLevel.high => BpColors.stage2,
  RiskLevel.critical => BpColors.crisis,
};

String riskLabel(RiskLevel level) => switch (level) {
  RiskLevel.low => 'Low Risk',
  RiskLevel.moderate => 'Moderate Risk',
  RiskLevel.high => 'High Risk',
  RiskLevel.critical => 'Critical Risk',
};

class _RiskCard extends ConsumerWidget {
  const _RiskCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final risk = ref.watch(latestRiskProvider);
    final readingCount = ref.watch(recentReadingsProvider).value?.length ?? 0;
    final level = risk.value?.overallLevel;
    return _CardShell(
      key: const Key('card-risk'),
      accent: level == null ? Theme.of(context).colorScheme.outline : riskColor(level),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('AI RISK ASSESSMENT', style: Theme.of(context).textTheme.labelLarge),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section<RiskScore?>(
            value: risk,
            label: 'your risk assessment',
            onRetry: () => ref.invalidate(latestRiskProvider),
            builder: (score) {
              if (score == null) {
                final remaining = (minReadingsForRisk - readingCount).clamp(0, minReadingsForRisk);
                return Text(
                  key: const Key('empty-risk'),
                  remaining > 0
                      ? 'Log $remaining more blood pressure '
                            '${remaining == 1 ? 'reading' : 'readings'} to unlock your risk '
                            'assessment.'
                      : 'Your risk assessment will appear here after your next reading.',
                );
              }
              final lvl = score.overallLevel;
              return Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: riskColor(lvl).withValues(alpha: 0.15),
                    child: Icon(Icons.favorite, color: riskColor(lvl)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          riskLabel(lvl),
                          key: const Key('risk-level'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Text(
                          'Highest of your five complication risks. '
                          'Ask the AI Health Agent what it means.',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------- Quick actions (FR-2.2, UC2.5) ----------

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    const actions = [
      ('Log Vitals', Icons.favorite_border, '/vitals/log', Key('qa-vitals')),
      ('Symptoms', Icons.sick_outlined, '/symptom', Key('qa-symptoms')),
      ('Messages', Icons.chat_bubble_outline, '/chat', Key('qa-messages')),
      ('AI Agent', Icons.smart_toy_outlined, '/ai-agent', Key('qa-agent')),
    ];
    return Row(
      children: [
        for (final (label, icon, path, key) in actions)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Card(
                key: key,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push(path),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        CircleAvatar(child: Icon(icon)),
                        const SizedBox(height: 8),
                        Text(label, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
