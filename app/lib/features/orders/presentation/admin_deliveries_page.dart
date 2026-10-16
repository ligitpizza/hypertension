import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api/api_client.dart';
import '../../appointments/domain/appointment_text.dart' show timeLabel;
import '../data/order_models.dart';
import '../state/orders_providers.dart';

/// Fig 4.3.14.4 Delivery oversight (FR-11.4, FR-13.4; D-66): every paid home delivery with
/// courier, status and ETA, out-of-stock flags from the pharmacy, and manual dispatch.
class AdminDeliveriesPage extends ConsumerStatefulWidget {
  const AdminDeliveriesPage({super.key});

  @override
  ConsumerState<AdminDeliveriesPage> createState() => _AdminDeliveriesPageState();
}

class _AdminDeliveriesPageState extends ConsumerState<AdminDeliveriesPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => ref.invalidate(deliveriesProvider));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(deliveriesProvider);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _delivery(MedicationOrder o) => switch (o.status) {
    Fulfilment.outOfStock => 'Waiting for stock',
    Fulfilment.preparing => 'Preparing',
    Fulfilment.failed => 'Failed',
    Fulfilment.delivered => 'Delivered',
    Fulfilment.collected || Fulfilment.readyForCollection => 'Switched to collection',
    Fulfilment.readyForDelivery => switch (o.deliveryStatus) {
      'in_transit' => 'In transit',
      'dispatched' => 'Dispatched',
      _ => 'Not dispatched',
    },
    _ => o.status.label,
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(deliveriesProvider);
    final theme = Theme.of(context);
    final repo = ref.read(ordersRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Delivery oversight', style: theme.textTheme.headlineSmall)),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(deliveriesProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const _CourierCard(),
        const SizedBox(height: 12),
        data.when(
          skipLoadingOnRefresh: true,
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(deliveriesProvider),
            child: const Text('Could not load deliveries. Retry'),
          ),
          data: (d) {
            final flagged = d.orders.where((o) => o.status == Fulfilment.outOfStock).toList();
            final active = d.orders
                .where(
                  (o) => o.status == Fulfilment.readyForDelivery || o.status == Fulfilment.failed,
                )
                .length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${d.courier}${d.simulated ? ' · simulated courier for the prototype (D-11)' : ''}'
                  ' · $active active',
                ),
                const SizedBox(height: 12),
                if (flagged.isNotEmpty)
                  Card(
                    key: const Key('oos-flags'),
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Out of stock (flagged by the pharmacy)',
                            style: theme.textTheme.titleMedium,
                          ),
                          for (final o in flagged)
                            Text(
                              '• ${o.patientName ?? 'Patient'}: ${o.medicationDetails}'
                              '${o.failureReason == null ? '' : ' ("${o.failureReason}")'}',
                            ),
                        ],
                      ),
                    ),
                  ),
                if (d.orders.isEmpty)
                  const Padding(
                    key: Key('deliveries-empty'),
                    padding: EdgeInsets.all(16),
                    child: Text('No home deliveries yet.'),
                  )
                else
                  Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Order')),
                          DataColumn(label: Text('Patient')),
                          DataColumn(label: Text('Medication')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Courier')),
                          DataColumn(label: Text('ETA')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: [
                          for (final o in d.orders)
                            DataRow(
                              key: ValueKey('delivery-${o.id}'),
                              cells: [
                                DataCell(Text(o.ref)),
                                DataCell(Text(o.patientName ?? 'Patient')),
                                DataCell(Text(o.medicationDetails)),
                                DataCell(Text(_delivery(o))),
                                DataCell(Text(o.courierRef ?? '—')),
                                DataCell(
                                  Text(
                                    o.etaAt != null && o.status == Fulfilment.readyForDelivery
                                        ? timeLabel(o.etaAt!)
                                        : '—',
                                  ),
                                ),
                                DataCell(
                                  Wrap(
                                    spacing: 4,
                                    children: [
                                      if (o.status == Fulfilment.failed ||
                                          (o.status == Fulfilment.readyForDelivery &&
                                              o.dispatchedAt == null))
                                        FilledButton.tonal(
                                          key: Key('dispatch-${o.id}'),
                                          onPressed: () =>
                                              _run(() => repo.dispatch(o.id), 'Courier booked.'),
                                          child: const Text('Dispatch'),
                                        ),
                                      if (d.simulated &&
                                          o.status == Fulfilment.readyForDelivery &&
                                          o.dispatchedAt != null)
                                        TextButton(
                                          key: Key('simulate-fail-${o.id}'),
                                          onPressed: () => _run(
                                            () => repo.simulateFailure(o.id),
                                            'Failure simulated. The patient was asked to choose.',
                                          ),
                                          child: const Text('Simulate failure'),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Self-collection orders are handled at the pharmacy counter.',
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

/// D-72 (M11 delivery partner settings): read-only; keys stay in Secret Manager and are
/// changed with the deploy scripts, never from the browser.
class _CourierCard extends ConsumerWidget {
  const _CourierCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(courierSettingsProvider).value;
    if (c == null) return const SizedBox.shrink();
    final simulated = c['simulated'] == true;
    Widget row(String label, Object? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label)),
          Expanded(child: SelectableText('${value ?? '—'}')),
        ],
      ),
    );
    return Card(
      key: const Key('courier-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handshake_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Delivery partner: ${c['provider']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(simulated ? 'Simulated' : 'Sandbox connected')),
              ],
            ),
            row('Mode', c['name']),
            row('Pickup address', c['pickupAddress']),
            row('Pickup phone', c['pickupPhone']),
            row('Webhook URL', c['webhookUrl']),
            const SizedBox(height: 4),
            Text(
              'Keys are kept in Secret Manager on the server and changed with the deploy '
              'scripts, not from the browser.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
