import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../data/order_models.dart';
import '../state/orders_providers.dart';
import 'order_widgets.dart';

/// The patient's monthly recurring orders (UC13.2), newest first.
class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  Future<void> _nextCycle(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref.read(ordersRepositoryProvider).devNextCycle();
      ref.invalidate(myOrdersProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(n == 0 ? 'No recurring prescriptions.' : "Next month's order created."),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'NOT_FOUND' ? 'This testing tool is turned off on the server.' : e.message,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly orders'),
        actions: [
          PopupMenuButton<String>(
            key: const Key('orders-menu'),
            onSelected: (_) => _nextCycle(context, ref),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'next', child: Text("Start next month's order (testing)")),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myOrdersProvider.future),
        child: orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: [
              const SizedBox(height: 120),
              const Icon(Icons.cloud_off, size: 48),
              const Text('Could not load your orders.', textAlign: TextAlign.center),
              TextButton(
                onPressed: () => ref.invalidate(myOrdersProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? ListView(
                  key: const Key('orders-empty'),
                  padding: const EdgeInsets.all(32),
                  children: const [
                    SizedBox(height: 80),
                    Icon(Icons.local_pharmacy_outlined, size: 48),
                    SizedBox(height: 12),
                    Text(
                      'No monthly orders yet. When your doctor makes a prescription recurring, '
                      "you'll confirm each month's refill here.",
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [for (final o in list) _OrderCard(order: o)],
                ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final MedicationOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = order.total;
    return Card(
      key: Key('order-${order.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(orderRoute(order)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(cycleLabel(order.cycleDate), style: theme.textTheme.labelLarge),
                  ),
                  OrderStatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(order.medicationDetails, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                [
                  'Order ${order.ref}',
                  if (total != null) rm(total) else 'Awaiting price from the pharmacy',
                  if (order.method == homeDelivery) 'Home delivery',
                  if (order.method == selfCollection) 'Self-collection',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
