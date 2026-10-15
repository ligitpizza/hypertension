import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../appointments/domain/appointment_text.dart' show timeLabel;
import '../data/admin_repository.dart';
import '../state/admin_providers.dart';

(String, Color) statusStyle(String status) => switch (status) {
  'operational' => ('Operational', Colors.teal.shade600),
  'degraded' => ('Degraded', Colors.orange.shade700),
  'simulated' => ('Simulated', Colors.blueGrey),
  'not_configured' => ('Not configured', Colors.blueGrey),
  _ => ('Down', Colors.red.shade700),
};

IconData _icon(String key) => switch (key) {
  'api' => Icons.hub_outlined,
  'firestore' => Icons.storage_outlined,
  'ml' => Icons.psychology_outlined,
  'push' => Icons.notifications_outlined,
  'email' => Icons.email_outlined,
  'ai' => Icons.smart_toy_outlined,
  'stripe' => Icons.payments_outlined,
  'grab' => Icons.local_shipping_outlined,
  _ => Icons.settings_outlined,
};

String _percent(double? v) => v == null ? '—' : '${v.toStringAsFixed(2)}%';

String _ms(double? v) => v == null ? '—' : '${v.round()}ms';

/// System Health (Fig 4.3.14.7; FR-11.3; D-59).
class SystemHealthPage extends ConsumerWidget {
  const SystemHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(systemHealthProvider);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('System Health', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        health.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListTile(
            leading: const Icon(Icons.cloud_off),
            title: const Text('Could not check the system.'),
            trailing: TextButton(
              onPressed: () => ref.invalidate(systemHealthProvider),
              child: const Text('Retry'),
            ),
          ),
          data: (h) {
            final (label, color) = statusStyle(h.overall);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  key: const Key('health-overview'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.circle, size: 12, color: color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('System overview', style: theme.textTheme.titleLarge),
                            ),
                            Chip(
                              key: const Key('health-overall'),
                              label: Text(
                                h.overall == 'operational'
                                    ? 'All systems operational'
                                    : 'Attention: $label',
                              ),
                              labelStyle: TextStyle(color: color),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 48,
                          runSpacing: 12,
                          children: [
                            _Big('API uptime (30 days)', _percent(h.uptime)),
                            _Big('Average latency', _ms(h.averageLatencyMs)),
                            _Big(
                              'Services',
                              '${h.services.where((s) => s.status == 'operational').length}'
                                  '/${h.services.length} live',
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                h.checkedAt == null
                                    ? 'Last checked: just now'
                                    : 'Last checked: ${timeLabel(h.checkedAt!)} MYT',
                              ),
                            ),
                            TextButton.icon(
                              key: const Key('health-refresh'),
                              onPressed: () => ref.invalidate(systemHealthProvider),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Service status', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [for (final s in h.services) _ServiceCard(service: s)],
                ),
                const SizedBox(height: 12),
                Text(
                  'Uptime counts the 15-minute scheduled sweep: runs received ÷ runs expected '
                  'over 30 days. Simulated services use test adapters.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelMedium),
      Text(value, style: Theme.of(context).textTheme.headlineMedium),
    ],
  );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});

  final ServiceHealth service;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final (label, color) = statusStyle(s.status);
    final theme = Theme.of(context);
    return SizedBox(
      width: 300,
      child: Card(
        key: Key('service-${s.key}'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon(s.key)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.name, style: theme.textTheme.titleMedium)),
                  Text('● $label', style: TextStyle(color: color)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _Big('Uptime', _percent(s.uptime))),
                  _Big('Latency', _ms(s.latencyMs)),
                ],
              ),
              if (s.note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(s.note, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 8),
              LinearProgressIndicator(value: 1, color: color, minHeight: 4),
            ],
          ),
        ),
      ),
    );
  }
}
