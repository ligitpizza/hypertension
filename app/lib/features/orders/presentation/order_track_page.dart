import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api/api_client.dart';
import '../../appointments/domain/appointment_text.dart';
import '../data/order_models.dart';
import '../../family/state/family_providers.dart';
import '../state/orders_providers.dart';
import 'order_widgets.dart';

/// Fig 4.3.10.3 Delivery tracking (UC13.4, UC13.5; FR-13.4, FR-13.5), the self-collection
/// slip (docs/06 §J step 6) and the reschedule / switch choice after a failed delivery.
class OrderTrackPage extends ConsumerStatefulWidget {
  const OrderTrackPage({super.key, required this.orderId});
  final String orderId;

  /// How often an order in progress is refreshed while the screen is open.
  static const refreshEvery = Duration(seconds: 10);

  @override
  ConsumerState<OrderTrackPage> createState() => _OrderTrackPageState();
}

class _OrderTrackPageState extends ConsumerState<OrderTrackPage> {
  Timer? _poll;
  bool _busy = false;

  static const _live = {
    Fulfilment.preparing,
    Fulfilment.outOfStock,
    Fulfilment.readyForDelivery,
    Fulfilment.readyForCollection,
  };

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(OrderTrackPage.refreshEvery, (_) {
      final o = ref.read(orderProvider(widget.orderId)).value;
      if (o == null || _live.contains(o.status)) ref.invalidate(orderProvider(widget.orderId));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref
        ..invalidate(orderProvider(widget.orderId))
        ..invalidate(myOrdersProvider);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Order tracking')),
      body: order.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(orderProvider(widget.orderId)),
            child: const Text('Could not load the order. Retry'),
          ),
        ),
        data: (o) => RefreshIndicator(
          onRefresh: () => ref.refresh(orderProvider(widget.orderId).future),
          child: _body(context, o),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, MedicationOrder o) {
    final theme = Theme.of(context);
    final repo = ref.read(ordersRepositoryProvider);
    final (icon, title, subtitle) = switch (o.status) {
      Fulfilment.preparing => (
        Icons.inventory_2_outlined,
        'Preparing your order',
        "We're carefully putting everything together.",
      ),
      Fulfilment.outOfStock => (
        Icons.hourglass_bottom,
        'Your order is delayed',
        "The pharmacy is waiting for stock of your medicine. We'll let you know when it's ready.",
      ),
      Fulfilment.readyForDelivery => (
        Icons.local_shipping_outlined,
        o.deliveryStatus == 'in_transit' ? 'Out for delivery' : 'Courier booked',
        o.courierRef == null
            ? 'Your medication is on its way.'
            : '${o.courierBrand} booking ${o.courierRef}',
      ),
      Fulfilment.readyForCollection => (
        Icons.storefront_outlined,
        'Ready for collection',
        'Show your collection slip at $pharmacyName.',
      ),
      Fulfilment.delivered => (Icons.home_outlined, 'Delivered', 'Your medication has arrived.'),
      Fulfilment.collected => (Icons.check_circle_outline, 'Collected', 'Enjoy your month.'),
      Fulfilment.cancelled => (
        Icons.cancel_outlined,
        'Order cancelled',
        o.cancelReason ?? 'This order was cancelled.',
      ),
      Fulfilment.failed => (
        Icons.report_problem_outlined,
        'Delivery problem',
        o.failureReason ?? "We couldn't deliver your medication.",
      ),
      _ => (Icons.receipt_long_outlined, o.status.label, ''),
    };
    final delivery = o.isDelivery;
    final steps = delivery
        ? [
            TimelineStep(
              'Order confirmed',
              subtitle: o.paidAt == null ? null : timeLabel(o.paidAt!),
              icon: Icons.receipt_long_outlined,
            ),
            const TimelineStep(
              'Preparing',
              subtitle: 'Your items are being packed securely.',
              icon: Icons.inventory_2_outlined,
            ),
            TimelineStep(
              'Out for delivery',
              subtitle: o.courierRef == null ? null : '${o.courierBrand} ${o.courierRef}',
              icon: Icons.local_shipping_outlined,
            ),
            const TimelineStep('Delivered', icon: Icons.home_outlined),
          ]
        : [
            TimelineStep(
              'Order confirmed',
              subtitle: o.paidAt == null ? null : timeLabel(o.paidAt!),
              icon: Icons.receipt_long_outlined,
            ),
            TimelineStep(
              'Preparing',
              subtitle: o.estimatedReadyAt == null || o.readyAt != null
                  ? 'The pharmacist is preparing your medicine.'
                  : 'Estimated ready by ${readyLabel(o.estimatedReadyAt!)}',
              icon: Icons.inventory_2_outlined,
            ),
            TimelineStep(
              'Ready for collection',
              subtitle: o.readyAt == null ? null : readyLabel(o.readyAt!),
              icon: Icons.storefront_outlined,
            ),
            const TimelineStep('Collected', icon: Icons.check),
          ];
    final current = delivery
        ? o.deliveryStage
        : switch (o.status) {
            Fulfilment.collected => 3,
            Fulfilment.readyForCollection => 2,
            _ => o.isPaid ? 1 : 0,
          };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: o.status == Fulfilment.failed || o.status == Fulfilment.outOfStock
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.primaryContainer,
            child: Icon(icon, size: 36, color: theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          key: const Key('track-title'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        if (subtitle.isNotEmpty)
          Text(subtitle, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        if (o.status == Fulfilment.failed) ...[
          // FR-13.5: reschedule or switch to self-collection.
          FilledButton.icon(
            key: const Key('reschedule-delivery'),
            onPressed: _busy
                ? null
                : () => _act(() => repo.reschedule(o.id), 'A new courier has been booked.'),
            icon: const Icon(Icons.refresh),
            label: const Text('Reschedule delivery'),
          ),
          OutlinedButton.icon(
            key: const Key('switch-collection'),
            onPressed: _busy
                ? null
                : () => _act(
                    () => repo.switchToCollection(o.id),
                    'Switched to self-collection. Your order is ready at the pharmacy.',
                  ),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Switch to self-collection'),
          ),
          const SizedBox(height: 16),
        ],
        if (o.status == Fulfilment.readyForCollection) _CollectionSlip(order: o),
        // D-68: the courier's own tracking page (Lalamove share link).
        if (o.trackingUrl != null && o.status == Fulfilment.readyForDelivery)
          TextButton.icon(
            key: const Key('courier-tracking'),
            onPressed: () => ref.read(openUrlProvider)(Uri.parse(o.trackingUrl!)),
            icon: const Icon(Icons.open_in_new),
            label: Text('Open ${o.courierBrand} tracking page'),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (delivery && o.etaAt != null && o.status == Fulfilment.readyForDelivery) ...[
                  Text('ESTIMATED ARRIVAL', style: theme.textTheme.labelSmall),
                  Text(
                    timeLabel(o.etaAt!),
                    key: const Key('eta'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                OrderTimeline(steps: steps, current: current),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.medication_outlined),
            title: const Text('Prescription order'),
            subtitle: Text(
              '${o.items.isEmpty ? o.medicationDetails : o.items.map((i) => '${i.label} ×${i.quantity}').join('\n')}'
              '\nOrder ${o.ref}'
              '${o.total == null ? '' : ' · ${rm(o.total!)}${o.isPaid ? ' paid' : ''}'}',
            ),
            isThreeLine: true,
          ),
        ),
        if (o.isPaid)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Your receipt is saved in Health records.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// docs/06 §J step 6: prescription ID and ready time, shown at the pharmacy counter.
class _CollectionSlip extends StatelessWidget {
  const _CollectionSlip({required this.order});
  final MedicationOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('collection-slip'),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Collection slip', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              order.ref,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text('Prescription ID: ${order.prescriptionId}'),
            if (order.readyAt != null) Text('Ready since ${readyLabel(order.readyAt!)}'),
            Text(order.medicationDetails),
            const SizedBox(height: 8),
            Text('Show this at the $pharmacyName counter.', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
