import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../data/order_models.dart';
import '../state/orders_providers.dart';
import 'order_widgets.dart';

/// D-70 order tracking: every order with its status, filterable by stage. The pharmacist's
/// Tracking tab and the admin's Orders tab. Opening a row goes to the patient (pharmacist:
/// dispensing view; admin: user detail).
class OrderTrackingPage extends ConsumerStatefulWidget {
  const OrderTrackingPage({super.key, this.admin = false});
  final bool admin;

  @override
  ConsumerState<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends ConsumerState<OrderTrackingPage> {
  String _group = 'all';
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _courier(MedicationOrder o) {
    if (o.method != homeDelivery) return o.method == selfCollection ? 'Pick-up' : '—';
    final eta = o.etaAt;
    final ref = o.courierRef;
    return [
      ?ref,
      if (eta != null && o.status == Fulfilment.readyForDelivery) 'ETA ${timeLabel(eta)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final filter = (group: _group, query: _query);
    final data = ref.watch(ordersOverviewProvider(filter));
    final counts = data.value?.counts ?? const <String, int>{};
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.admin ? 'Orders' : 'Order tracking',
                style: theme.textTheme.headlineSmall,
              ),
            ),
            IconButton(
              key: const Key('tracking-refresh'),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(ordersOverviewProvider(filter)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text('Every medication order and where it is now.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in orderGroups.entries)
              ChoiceChip(
                key: Key('group-${g.key}'),
                label: Text(
                  g.key == 'all'
                      ? '${g.value} (${data.value?.total ?? 0})'
                      : '${g.value} (${counts[g.key] ?? 0})',
                ),
                selected: _group == g.key,
                onSelected: (_) => setState(() => _group = g.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('tracking-search'),
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search patient, medicine or order ref',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 12),
        data.when(
          skipLoadingOnRefresh: true,
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(ordersOverviewProvider(filter)),
            child: const Text('Could not load orders. Retry'),
          ),
          data: (d) => d.orders.isEmpty
              ? const Padding(
                  key: Key('tracking-empty'),
                  padding: EdgeInsets.all(16),
                  child: Text('No orders here.'),
                )
              : Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      key: const Key('tracking-table'),
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('Order')),
                        DataColumn(label: Text('Patient')),
                        DataColumn(label: Text('Medicines')),
                        DataColumn(label: Text('Total'), numeric: true),
                        DataColumn(label: Text('Payment')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Fulfilment')),
                        DataColumn(label: Text('Cycle')),
                      ],
                      rows: [
                        for (final o in d.orders)
                          DataRow(
                            key: ValueKey('tracking-${o.id}'),
                            // D-73: admins open the order itself; pharmacists the patient.
                            onSelectChanged: (_) => context.go(
                              widget.admin
                                  ? '/admin/orders/${o.id}'
                                  : '/pharmacy/patients/${o.patientId}',
                            ),
                            cells: [
                              DataCell(Text(o.ref)),
                              DataCell(Text(o.patientName ?? 'Patient')),
                              DataCell(
                                SizedBox(
                                  width: 260,
                                  child: Text(
                                    o.items.isEmpty
                                        ? o.medicationDetails
                                        : o.items
                                              .map((i) => '${i.label} ×${i.quantity}')
                                              .join(', '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text(o.total == null ? '—' : rm(o.total!))),
                              DataCell(Text(o.paymentStatus)),
                              DataCell(OrderStatusChip(status: o.status)),
                              DataCell(Text(_courier(o))),
                              DataCell(Text(o.cycleDate == null ? '—' : dateLabel(o.cycleDate!))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
