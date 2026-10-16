import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../appointments/domain/appointment_text.dart';
import '../../medications/domain/med_schedule.dart';
import '../data/order_models.dart';
import '../state/orders_providers.dart';

/// Module 13 display helpers (D-66). Times are Malaysia time.

const pharmacyName = 'Harvey pharmacy';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "October 2026" for an order's cycle.
String cycleLabel(DateTime? cycle) {
  if (cycle == null) return 'Monthly refill';
  final l = toMyt(cycle);
  return '${_months[l.month - 1]} ${l.year}';
}

/// Where the patient should land for an order: confirm, pay or track (Figs 4.3.10.1-3).
String orderRoute(MedicationOrder o) => switch (o.status) {
  Fulfilment.awaitingConfirmation || Fulfilment.skipped => '/orders/${o.id}/confirm',
  Fulfilment.awaitingPayment => '/orders/${o.id}/pay',
  _ => '/orders/${o.id}/track',
};

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});
  final Fulfilment status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      Fulfilment.outOfStock ||
      Fulfilment.failed ||
      Fulfilment.cancelled => (scheme.errorContainer, scheme.onErrorContainer),
      Fulfilment.readyForCollection ||
      Fulfilment.readyForDelivery ||
      Fulfilment.delivered ||
      Fulfilment.collected => (scheme.primaryContainer, scheme.onPrimaryContainer),
      Fulfilment.preparing => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}

/// One step of a vertical timeline (Fig 4.3.10.3).
class TimelineStep {
  const TimelineStep(this.title, {this.subtitle, this.icon = Icons.circle_outlined});
  final String title;
  final String? subtitle;
  final IconData icon;
}

class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.steps, required this.current});

  final List<TimelineStep> steps;

  /// Index of the step in progress; earlier steps are done.
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 36,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: i < current || (i == current && i == steps.length - 1)
                            ? scheme.primary
                            : i == current
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        child: Icon(
                          i < current || (i == current && i == steps.length - 1)
                              ? Icons.check
                              : steps[i].icon,
                          size: 16,
                          color: i < current || (i == current && i == steps.length - 1)
                              ? scheme.onPrimary
                              : i == current
                              ? scheme.primary
                              : scheme.outline,
                        ),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: i < current ? scheme.primary : scheme.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20, top: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].title,
                          key: Key('step-$i'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: i > current ? scheme.outline : null,
                            fontWeight: i == current ? FontWeight.bold : null,
                          ),
                        ),
                        if (steps[i].subtitle != null && i <= current)
                          Text(steps[i].subtitle!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Medications page entry point (UC13.2): the orders waiting for the patient, or a link to
/// the order list. Shows nothing for patients without recurring prescriptions.
class MonthlyOrdersBanner extends ConsumerWidget {
  const MonthlyOrdersBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider).value ?? const <MedicationOrder>[];
    if (orders.isEmpty) return const SizedBox.shrink();
    final waiting = orders.where((o) => o.needsPatient).toList();
    final theme = Theme.of(context);
    return Card(
      key: const Key('orders-banner'),
      color: waiting.isEmpty ? null : theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          waiting.isEmpty ? Icons.local_pharmacy_outlined : Icons.notifications_active_outlined,
        ),
        title: Text(
          waiting.isEmpty
              ? 'Monthly orders'
              : waiting.length == 1
              ? 'Your monthly order needs you'
              : '${waiting.length} monthly orders need you',
        ),
        subtitle: Text(
          waiting.isEmpty
              ? 'Track your recurring prescription refills'
              : '${waiting.first.medicationDetails}: ${waiting.first.status.label.toLowerCase()}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(waiting.length == 1 ? orderRoute(waiting.first) : '/orders'),
      ),
    );
  }
}

/// "Ready 2:30 PM, Thu 16 Oct".
String readyLabel(DateTime t) => '${timeLabel(t)}, ${dateLabel(t)}';
