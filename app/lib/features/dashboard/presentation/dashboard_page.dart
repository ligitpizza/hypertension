import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../medications/domain/med_schedule.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../core/utils/risk_style.dart';
import '../../../shared/models/health_models.dart';
import '../../../core/constants/enums.dart';
import '../../../shared/widgets/care_plan_history.dart';
import '../../auth/state/auth_providers.dart';
import '../../symptom_checker/state/symptom_providers.dart';
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
            ..invalidate(upcomingAppointmentsProvider)
            ..invalidate(latestTriageProvider)
            ..invalidate(carePlanProvider);
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
            const _EmergencyCallCard(),
            const _TodaysPlanCard(),
            const SizedBox(height: 16),
            const _LatestBpCard(),
            const SizedBox(height: 16),
            const _RiskCard(),
            const SizedBox(height: 16),
            const _CarePlanCard(),
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
                          subtitle: describeSchedule(m.schedule),
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

  /// Shortcuts, four per row; more rows appear as actions are added.
  static const actions = [
    ('Log Vitals', Icons.favorite_border, '/vitals/log', Key('qa-vitals')),
    ('Symptoms', Icons.sick_outlined, '/symptom', Key('qa-symptoms')),
    ('Messages', Icons.chat_bubble_outline, '/chat', Key('qa-messages')),
    ('AI Agent', Icons.smart_toy_outlined, '/ai-agent', Key('qa-agent')),
    ('Appointments', Icons.event_outlined, '/appointments', Key('qa-appointments')),
  ];

  @override
  Widget build(BuildContext context) => GridView.count(
    key: const Key('quick-actions'),
    crossAxisCount: 4,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 4,
    crossAxisSpacing: 4,
    childAspectRatio: 0.82,
    children: [
      for (final (label, icon, path, key) in actions)
        Card(
          key: key,
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push(path),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(child: Icon(icon)),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

/// D-37 / Fig 4.3.8.2: one-tap emergency call on the dashboard while an emergency is
/// active (crisis reading or emergency symptom check in the last 6 hours).
class _EmergencyCallCard extends ConsumerWidget {
  const _EmergencyCallCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(recentReadingsProvider).value ?? const <VitalReading>[];
    final triage = ref.watch(latestTriageProvider).value;
    final active = activeEmergency(
      latestReading: readings.firstOrNull,
      latestTriage: triage?.outcome,
      latestTriageAt: triage?.generatedAt,
      now: ref.watch(nowProvider)(),
    );
    if (!active) return const SizedBox.shrink();
    final color = BpClassifier.color(BpCategory.crisis);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: const Key('dashboard-emergency'),
        color: color,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Emergency: if you feel unwell, call 999 now. Stay calm and do not drive '
                'yourself. Your doctor has been notified.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('dashboard-call-999'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: color,
                ),
                onPressed: () => ref.read(dialerProvider)('999'),
                icon: const Icon(Icons.call),
                label: const Text('Call 999 Now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Module 2 "active care plan": the doctor's plan (written in Module 8), read-only here.
class _CarePlanCard extends ConsumerStatefulWidget {
  const _CarePlanCard();

  @override
  ConsumerState<_CarePlanCard> createState() => _CarePlanCardState();
}

class _CarePlanCardState extends ConsumerState<_CarePlanCard> {
  bool _expanded = false;

  /// D-41: every version the doctor saved, newest first.
  void _showHistory(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => Consumer(
        builder: (context, ref, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: controller,
            children: [
              Text('Care plan history', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ref
                  .watch(carePlanHistoryProvider)
                  .when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const Text('Could not load the history. Try again later.'),
                    data: (v) => CarePlanHistoryList(versions: v, shrinkWrap: true),
                  ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(carePlanProvider);
    return Card(
      key: const Key('card-care-plan'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('My care plan', style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            plan.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Could not load your care plan. Pull down to retry.'),
              data: (p) {
                if (p == null || p.content.trim().isEmpty) {
                  return const Text(
                    'Your doctor has not written a care plan yet.',
                    key: Key('care-plan-empty'),
                  );
                }
                final long = p.content.length > 220 || '\n'.allMatches(p.content).length > 4;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.content,
                      key: const Key('care-plan-text'),
                      maxLines: _expanded ? null : 4,
                      overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    ),
                    if (long)
                      TextButton(
                        key: const Key('care-plan-more'),
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Show less' : 'Read more'),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'From your doctor · updated '
                            '${timeAgo(p.updatedAt, ref.watch(nowProvider)())}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          key: const Key('care-plan-history-button'),
                          onPressed: () => _showHistory(context),
                          child: const Text('View history'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
