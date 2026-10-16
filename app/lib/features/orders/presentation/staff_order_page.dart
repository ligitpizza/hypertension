import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../../family/state/family_providers.dart';
import '../data/order_models.dart';
import '../state/orders_providers.dart';
import 'order_widgets.dart';

/// D-73: one order in the staff portal (admin Orders / Deliveries rows): medicines and
/// prices, payment, collection or delivery details, courier and the status history.
class StaffOrderPage extends ConsumerWidget {
  const StaffOrderPage({super.key, required this.orderId, required this.backPath, this.backLabel});

  final String orderId;
  final String backPath;
  final String? backLabel;

  String _when(DateTime? t) => t == null ? '—' : '${dateLabel(t)}, ${timeLabel(t)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            TextButton.icon(
              key: const Key('order-back'),
              onPressed: () => context.go(backPath),
              icon: const Icon(Icons.arrow_back),
              label: Text(backLabel ?? 'Back'),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(orderProvider(orderId)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        order.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('This order could not be loaded.'),
          data: (o) {
            Widget row(String label, String value, {Key? key}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 170, child: Text(label, style: theme.textTheme.bodySmall)),
                  Expanded(child: SelectableText(value, key: key)),
                ],
              ),
            );
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
            final tracking = o.trackingUrl;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Order ${o.ref}', style: theme.textTheme.headlineSmall),
                    const SizedBox(width: 12),
                    OrderStatusChip(status: o.status),
                  ],
                ),
                Text('${o.patientName ?? 'Patient'} · ${cycleLabel(o.cycleDate)}'),
                const SizedBox(height: 12),
                section('Medicines', [
                  if (o.items.isEmpty)
                    row('Prescription', o.medicationDetails)
                  else
                    for (final i in o.items)
                      row(
                        i.label,
                        '${i.dose}, ${frequencyLabel(i.frequency).toLowerCase()} · '
                        '${i.quantity} × ${rm(i.unitPrice)} = ${rm(i.lineTotal)}',
                      ),
                  const Divider(),
                  row('Medicines', o.amount == null ? 'Not priced yet' : rm(o.amount!)),
                  if (o.deliveryFee > 0) row('Delivery fee', rm(o.deliveryFee)),
                  row(
                    'Total',
                    o.total == null ? '—' : rm(o.total!),
                    key: const Key('staff-order-total'),
                  ),
                ]),
                section('Payment', [
                  row('Status', o.paymentStatus),
                  row('Paid at', _when(o.paidAt)),
                ]),
                section(o.isDelivery ? 'Home delivery' : 'Collection', [
                  row('Method', switch (o.method) {
                    homeDelivery => 'Home delivery',
                    selfCollection => 'Self-collection at the pharmacy',
                    _ => 'Not chosen yet',
                  }),
                  if (o.isDelivery) ...[
                    row('Address', o.deliveryAddress ?? '—'),
                    row('Contact number', o.deliveryPhone ?? '—'),
                    row('Courier booking', o.courierRef ?? 'Not booked yet'),
                    row('Delivery status', o.deliveryStatus?.replaceAll('_', ' ') ?? '—'),
                    row('Estimated arrival', _when(o.etaAt)),
                    if (o.failureReason != null) row('Problem', o.failureReason!),
                    if (tracking != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('staff-courier-tracking'),
                          onPressed: () => ref.read(openUrlProvider)(Uri.parse(tracking)),
                          icon: const Icon(Icons.open_in_new),
                          label: Text('Open ${o.courierBrand} tracking page'),
                        ),
                      ),
                  ] else ...[
                    row('Estimated ready', _when(o.estimatedReadyAt)),
                    row('Ready since', _when(o.readyAt)),
                  ],
                ]),
                section('Status history', [
                  row('Order created', _when(o.cycleDate)),
                  row('Paid', _when(o.paidAt)),
                  row('Ready', _when(o.readyAt)),
                  row('Dispatched', _when(o.dispatchedAt)),
                  for (final e in o.events)
                    row(
                      'Courier: ${e.status.replaceAll('_', ' ')}',
                      [_when(e.timestamp), ?e.location].join(' · '),
                    ),
                ]),
              ],
            );
          },
        ),
      ],
    );
  }
}
