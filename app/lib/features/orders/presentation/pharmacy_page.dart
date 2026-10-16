import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/order_models.dart';
import '../state/orders_providers.dart';
import 'order_widgets.dart';
import 'pharmacy_shared.dart';

/// Fig 4.3.13.1 Pharmacist view (UC13.6; FR-13.3; D-66): the paid-order queue, recurring
/// prescriptions waiting for a price, stock levels and a patient lookup.
class PharmacyPage extends ConsumerWidget {
  const PharmacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        const main = [
          _QueueCard(),
          SizedBox(height: 16),
          _IncomingCard(),
          SizedBox(height: 16),
          _PriceCard(),
        ];
        const side = [_QuickActions()];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(child: Text('Pharmacy operations', style: theme.textTheme.headlineSmall)),
                IconButton(
                  key: const Key('pharmacy-refresh'),
                  tooltip: 'Refresh',
                  onPressed: () => ref
                    ..invalidate(ordersOverviewProvider((group: 'awaiting_patient', query: '')))
                    ..invalidate(pharmacyQueueProvider)
                    ..invalidate(stockProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'Prepare paid orders and price older prescriptions. Stock and the catalogue are under Inventory.',
            ),
            const SizedBox(height: 16),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(flex: 2, child: Column(children: main)),
                  const SizedBox(width: 16),
                  const Expanded(child: Column(children: side)),
                ],
              )
            else
              const Column(children: [...main, SizedBox(height: 16), ...side]),
          ],
        );
      },
    );
  }
}

// ---------------- queue ----------------

class _QueueCard extends ConsumerWidget {
  const _QueueCard();

  Future<void> _ready(BuildContext context, WidgetRef ref, MedicationOrder o) async {
    if (o.items.isNotEmpty) {
      // D-69: each medicine is taken from its catalogue-linked stock.
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(o.isDelivery ? 'Ready for delivery' : 'Ready for collection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('These quantities are taken from stock:'),
              const SizedBox(height: 8),
              for (final i in o.items) Text('• ${i.label} × ${i.quantity}'),
              if (o.isDelivery)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('A courier is booked as soon as you confirm.'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              key: const Key('ready-confirm'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      await runPharmacyAction(
        context,
        ref,
        () => ref.read(ordersRepositoryProvider).markReady(o.id),
        o.isDelivery ? 'Ready for delivery. Courier booked.' : 'Ready for collection.',
      );
      return;
    }
    final stock = await ref.read(stockProvider.future).catchError((_) => <StockItem>[]);
    if (!context.mounted) return;
    if (stock.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add the medicine to stock first (New stock).')));
      return;
    }
    final words = o.medicationDetails.toLowerCase().split(RegExp(r'[\s,]+'));
    final guess = stock
        .where((s) => words.isNotEmpty && s.name.toLowerCase().contains(words.first))
        .firstOrNull;
    final picked = await showDialog<(String, int)>(
      context: context,
      builder: (_) => _ReadyDialog(order: o, stock: stock, initial: guess ?? stock.first),
    );
    if (picked == null || !context.mounted) return;
    await runPharmacyAction(
      context,
      ref,
      () => ref
          .read(ordersRepositoryProvider)
          .markReady(o.id, stockItemId: picked.$1, units: picked.$2),
      o.isDelivery ? 'Ready for delivery. Courier booked.' : 'Ready for collection.',
    );
  }

  Future<void> _outOfStock(BuildContext context, WidgetRef ref, MedicationOrder o) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => PromptDialog(
        title: 'Mark out of stock?',
        message:
            'The admin is alerted and ${o.patientName ?? 'the patient'} is told about the delay.',
        fieldKey: const Key('oos-note'),
        label: 'Note for the admin (optional)',
        confirmKey: const Key('oos-confirm'),
        confirmText: 'Mark out of stock',
        maxLength: 300,
      ),
    );
    if (note == null || !context.mounted) return;
    final text = note.trim();
    await runPharmacyAction(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).outOfStock(o.id, note: text.isEmpty ? null : text),
      'Marked out of stock. Admin alerted.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(pharmacyQueueProvider);
    return PharmacySection(
      icon: Icons.receipt_long_outlined,
      title: 'Active prescription queue',
      child: queue.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(pharmacyQueueProvider),
          child: const Text('Could not load the queue. Retry'),
        ),
        data: (q) => q.orders.isEmpty
            ? const Padding(
                key: Key('queue-empty'),
                padding: EdgeInsets.all(8),
                child: Text('No paid orders waiting. New ones appear here after payment.'),
              )
            : Column(
                children: [
                  for (final o in q.orders)
                    ListTile(
                      key: Key('queue-${o.id}'),
                      contentPadding: EdgeInsets.zero,
                      // D-69: the patient's dispensing details.
                      onTap: () => context.go('/pharmacy/patients/${o.patientId}'),
                      leading: CircleAvatar(
                        child: Text(
                          (o.patientName ?? '?')
                              .trim()
                              .split(' ')
                              .map((w) => w.isEmpty ? '' : w[0])
                              .take(2)
                              .join(),
                        ),
                      ),
                      title: Text(
                        o.items.isEmpty
                            ? '${o.patientName ?? 'Patient'} · ${o.medicationDetails}'
                            : '${o.patientName ?? 'Patient'} · '
                                  '${o.items.map((i) => '${i.label} ×${i.quantity}').join(', ')}',
                      ),
                      subtitle: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OrderStatusChip(status: o.status),
                          Text(
                            [
                              o.ref,
                              if (o.isDelivery) 'Delivery' else 'Pick-up',
                              ?o.courierRef,
                              if (o.status == Fulfilment.failed && o.failureReason != null)
                                o.failureReason!,
                            ].join(' · '),
                          ),
                        ],
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          if (o.status == Fulfilment.preparing || o.status == Fulfilment.outOfStock)
                            FilledButton(
                              key: Key('ready-${o.id}'),
                              onPressed: () => _ready(context, ref, o),
                              child: const Text('Mark ready'),
                            ),
                          if (o.status == Fulfilment.preparing)
                            OutlinedButton(
                              key: Key('oos-${o.id}'),
                              onPressed: () => _outOfStock(context, ref, o),
                              child: const Text('Out of stock'),
                            ),
                          if (o.status == Fulfilment.readyForCollection)
                            FilledButton.tonal(
                              key: Key('collected-${o.id}'),
                              onPressed: () => runPharmacyAction(
                                context,
                                ref,
                                () => ref.read(ordersRepositoryProvider).collected(o.id),
                                'Marked as collected.',
                              ),
                              child: const Text('Collected'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ReadyDialog extends StatefulWidget {
  const _ReadyDialog({required this.order, required this.stock, required this.initial});
  final MedicationOrder order;
  final List<StockItem> stock;
  final StockItem initial;

  @override
  State<_ReadyDialog> createState() => _ReadyDialogState();
}

class _ReadyDialogState extends State<_ReadyDialog> {
  late String _stockId = widget.initial.id;
  final _units = TextEditingController(text: '30');

  @override
  void dispose() {
    _units.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = int.tryParse(_units.text) ?? 0;
    return AlertDialog(
      title: Text(widget.order.isDelivery ? 'Ready for delivery' : 'Ready for collection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.order.medicationDetails),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('ready-stock'),
            initialValue: _stockId,
            decoration: const InputDecoration(labelText: 'Take from stock'),
            items: [
              for (final s in widget.stock)
                DropdownMenuItem(value: s.id, child: Text('${s.name} (${s.units} units)')),
            ],
            onChanged: (v) => setState(() => _stockId = v ?? _stockId),
          ),
          TextField(
            key: const Key('ready-units'),
            controller: _units,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Units dispensed'),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.order.isDelivery)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('A courier is booked as soon as you confirm.'),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('ready-confirm'),
          onPressed: units < 1 ? null : () => Navigator.pop(context, (_stockId, units)),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

// ---------------- pricing ----------------

class _PriceCard extends ConsumerWidget {
  const _PriceCard();

  Future<void> _price(BuildContext context, WidgetRef ref, UnpricedPrescription rx) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => PromptDialog(
        title: 'Monthly price',
        message: '${rx.patientName ?? 'Patient'} · ${rx.medicationDetails}',
        fieldKey: const Key('price-input'),
        label: '30-day supply (min RM2.00)',
        prefixText: 'RM ',
        confirmKey: const Key('price-save'),
        confirmText: 'Save',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        allowed: RegExp(r'[0-9.]'),
        isValid: (v) => (double.tryParse(v) ?? 0) >= 2,
      ),
    );
    final price = double.tryParse(text ?? '');
    if (price == null || !context.mounted) return;
    await runPharmacyAction(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).setPrice(rx.id, price),
      'Price saved. The patient can now confirm.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pharmacyQueueProvider).value?.needsPrice ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return PharmacySection(
      icon: Icons.sell_outlined,
      title: 'Recurring prescriptions to price',
      child: Column(
        children: [
          for (final rx in list)
            ListTile(
              key: Key('needs-price-${rx.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(rx.medicationDetails),
              subtitle: Text(rx.patientName ?? 'Patient'),
              trailing: FilledButton.tonal(
                key: Key('price-${rx.id}'),
                onPressed: () => _price(context, ref, rx),
                child: const Text('Set price'),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------- lookup + quick actions ----------------

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = (ref.watch(pharmacyQueueProvider).value?.orders ?? const [])
        .where((o) => o.status == Fulfilment.preparing)
        .length;
    Widget link(String key, IconData icon, String label, String path) => OutlinedButton.icon(
      key: Key(key),
      onPressed: () => context.go(path),
      icon: Icon(icon),
      label: Text(label),
    );
    return PharmacySection(
      icon: Icons.bolt_outlined,
      title: 'Quick actions',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(
            avatar: const Icon(Icons.pending_actions_outlined, size: 18),
            label: Text('$ready order${ready == 1 ? '' : 's'} to prepare'),
          ),
          OutlinedButton.icon(
            key: const Key('quick-new-stock'),
            onPressed: () => addStockItem(context, ref),
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('New stock'),
          ),
          link(
            'quick-tracking',
            Icons.local_shipping_outlined,
            'Track orders',
            '/pharmacy/tracking',
          ),
          link('quick-inventory', Icons.inventory_2_outlined, 'Inventory', '/pharmacy/inventory'),
          link('quick-patients', Icons.people_outline, 'Patients', '/pharmacy/patients'),
          link('quick-messages', Icons.chat_bubble_outline, 'Messages', '/pharmacy/messages'),
        ],
      ),
    );
  }
}

/// D-73: prescriptions the doctor has issued that are waiting for the patient to confirm
/// and pay; they move to the queue above once paid.
class _IncomingCard extends ConsumerWidget {
  const _IncomingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(ordersOverviewProvider((group: 'awaiting_patient', query: '')));
    return PharmacySection(
      icon: Icons.move_to_inbox_outlined,
      title: 'New prescriptions',
      child: waiting.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () =>
              ref.invalidate(ordersOverviewProvider((group: 'awaiting_patient', query: ''))),
          child: const Text('Could not load. Retry'),
        ),
        data: (d) => d.orders.isEmpty
            ? const Text('No prescriptions waiting for patients.', key: Key('incoming-empty'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Issued by doctors; the patient still has to confirm and pay. '
                    'They move to the queue above once paid.',
                  ),
                  for (final o in d.orders)
                    ListTile(
                      key: Key('incoming-${o.id}'),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.go('/pharmacy/patients/${o.patientId}'),
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        '${o.patientName ?? 'Patient'} · '
                        '${o.items.isEmpty ? o.medicationDetails : o.items.map((i) => '${i.label} ×${i.quantity}').join(', ')}',
                      ),
                      subtitle: Text(
                        [
                          o.ref,
                          o.status.label,
                          if (o.total != null) rm(o.total!) else 'awaiting price',
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
