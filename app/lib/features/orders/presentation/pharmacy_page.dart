import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../../appointments/domain/appointment_text.dart' show dateLabel;
import '../data/order_models.dart';
import '../state/orders_providers.dart';
import 'order_widgets.dart';

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
          _PriceCard(),
          SizedBox(height: 16),
          _StockCard(),
          SizedBox(height: 16),
          _CatalogCard(),
        ];
        const side = [_LookupCard(), SizedBox(height: 16), _QuickActions()];
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
                    ..invalidate(pharmacyQueueProvider)
                    ..invalidate(stockProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'Prepare paid monthly orders, price recurring prescriptions and keep stock.',
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

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
  String done,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    ref
      ..invalidate(pharmacyQueueProvider)
      ..invalidate(stockProvider);
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Something went wrong. Try again.')));
  }
}

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child, this.action});
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
              ?action,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
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
      await _run(
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
    await _run(
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
      builder: (_) => _PromptDialog(
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
    await _run(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).outOfStock(o.id, note: text.isEmpty ? null : text),
      'Marked out of stock. Admin alerted.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(pharmacyQueueProvider);
    return _Section(
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
                              onPressed: () => _run(
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
      builder: (_) => _PromptDialog(
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
    await _run(
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
    return _Section(
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

// ---------------- stock ----------------

class _StockCard extends ConsumerWidget {
  const _StockCard();

  Future<void> _receive(BuildContext context, WidgetRef ref, StockItem s) async {
    final result = await showDialog<(String, int, String)>(
      context: context,
      builder: (_) => _StockDialog(title: 'Receive ${s.name}', askName: false),
    );
    if (result == null || !context.mounted) return;
    final (_, units, expiry) = result;
    await _run(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).receiveStock(s.id, units, expiry),
      '$units units added.',
    );
  }

  Future<void> _lowAt(BuildContext context, WidgetRef ref, StockItem s) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: 'Low-stock warning for ${s.name}',
        initial: '${s.lowStockAt}',
        fieldKey: const Key('low-at-input'),
        label: 'Warn below (units)',
        confirmText: 'Save',
        keyboardType: TextInputType.number,
        allowed: RegExp(r'[0-9]'),
        isValid: (v) => int.tryParse(v) != null,
      ),
    );
    final v = int.tryParse(text ?? '');
    if (v == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).setLowStockAt(s.id, v),
      'Warning level saved.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockProvider);
    final theme = Theme.of(context);
    return _Section(
      icon: Icons.inventory_2_outlined,
      title: 'Medication inventory',
      action: TextButton.icon(
        key: const Key('new-stock'),
        onPressed: () => addStockItem(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New stock item'),
      ),
      child: stock.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(stockProvider),
          child: const Text('Could not load stock. Retry'),
        ),
        data: (items) => items.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No stock recorded yet. Add each medicine you dispense.'),
              )
            : Column(
                children: [
                  for (final s in items)
                    ListTile(
                      key: Key('stock-${s.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: s.lowStockAt <= 0
                                ? 1
                                : (s.units / (s.lowStockAt * 4)).clamp(0.02, 1).toDouble(),
                            color: s.low ? theme.colorScheme.error : theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${s.units} units'
                            '${s.low ? ' · LOW (below ${s.lowStockAt})' : ''}'
                            '${s.expiryDate == null ? '' : ' · earliest expiry ${s.expiryDate}'}',
                            style: s.low ? TextStyle(color: theme.colorScheme.error) : null,
                          ),
                        ],
                      ),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            key: Key('low-at-${s.id}'),
                            tooltip: 'Low-stock warning level',
                            onPressed: () => _lowAt(context, ref, s),
                            icon: const Icon(Icons.tune),
                          ),
                          IconButton(
                            key: Key('receive-${s.id}'),
                            tooltip: 'Receive stock',
                            onPressed: () => _receive(context, ref, s),
                            icon: const Icon(Icons.add_box_outlined),
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

/// "New Stock" quick action (Fig 4.3.13.1).
Future<void> addStockItem(BuildContext context, WidgetRef ref) async {
  final catalog = await ref.read(catalogProvider.future).catchError((_) => <CatalogItem>[]);
  if (!context.mounted) return;
  final result = await showDialog<(String, int, String)>(
    context: context,
    builder: (_) => _StockDialog(title: 'New stock item', askName: true, catalog: catalog),
  );
  if (result == null || !context.mounted) return;
  final (name, units, expiry) = result;
  // D-69: a stock item named like a catalogue medicine is linked to it.
  final linked = catalog.where((c) => c.label.toLowerCase() == name.toLowerCase()).firstOrNull;
  await _run(
    context,
    ref,
    () => ref
        .read(ordersRepositoryProvider)
        .addStock(
          name: name,
          units: units,
          expiryDate: expiry,
          lowStockAt: 50,
          catalogId: linked?.id,
        ),
    '$name added to stock.',
  );
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.title, required this.askName, this.catalog = const []});
  final String title;
  final bool askName;

  /// D-69: picking a catalogue medicine fills the name and links the stock to it.
  final List<CatalogItem> catalog;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  final _name = TextEditingController();
  final _units = TextEditingController();
  DateTime? _expiry;

  @override
  void dispose() {
    _name.dispose();
    _units.dispose();
    super.dispose();
  }

  bool get _valid =>
      (int.tryParse(_units.text) ?? 0) > 0 &&
      _expiry != null &&
      (!widget.askName || _name.text.trim().length >= 2);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.askName && widget.catalog.isNotEmpty)
          DropdownButtonFormField<String>(
            key: const Key('stock-catalog'),
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Catalogue medicine (optional)'),
            items: [
              for (final c in widget.catalog)
                DropdownMenuItem(value: c.label, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _name.text = v ?? _name.text),
          ),
        if (widget.askName)
          TextField(
            key: const Key('stock-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Medicine and strength'),
            onChanged: (_) => setState(() {}),
          ),
        TextField(
          key: const Key('stock-units'),
          controller: _units,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Units received'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('stock-expiry'),
          onPressed: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              firstDate: now,
              lastDate: DateTime(now.year + 10),
              initialDate: DateTime(now.year + 1, now.month, now.day),
            );
            if (d != null) setState(() => _expiry = d);
          },
          icon: const Icon(Icons.event),
          label: Text(
            _expiry == null ? 'Expiry date' : 'Expires ${dateLabel(_expiry!)} ${_expiry!.year}',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const Key('stock-save'),
        onPressed: _valid
            ? () => Navigator.pop(context, (
                _name.text.trim(),
                int.parse(_units.text),
                _isoDate(_expiry!),
              ))
            : null,
        child: const Text('Save'),
      ),
    ],
  );
}

// ---------------- lookup + quick actions ----------------

class _LookupCard extends ConsumerStatefulWidget {
  const _LookupCard();

  @override
  ConsumerState<_LookupCard> createState() => _LookupCardState();
}

class _LookupCardState extends ConsumerState<_LookupCard> {
  String? _query;

  @override
  Widget build(BuildContext context) {
    final q = _query;
    final results = q == null ? null : ref.watch(pharmacyLookupProvider(q));
    return _Section(
      icon: Icons.person_search_outlined,
      title: 'Patient lookup',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('lookup-input'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Name, email or patient ID',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 8),
          if (results != null)
            results.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Lookup failed.'),
              data: (list) => list.isEmpty
                  ? const Text('No pharmacy patient matches.')
                  : Column(
                      children: [
                        for (final p in list)
                          Card(
                            key: Key('lookup-${p.id}'),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => context.go('/pharmacy/patients/${p.id}'),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                                    Text(
                                      ['ID: ${p.id}', ?p.email, ?p.phone].join(' · '),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('Current regimen'),
                                    for (final r in p.regimen)
                                      Text(
                                        '• ${r.medicationDetails}'
                                        '${r.monthlyPrice == null ? ' (no price yet)' : ' · ${rm(r.monthlyPrice!)}/month'}',
                                      ),
                                    if (p.recentOrders.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      const Text('Recent orders'),
                                      for (final o in p.recentOrders)
                                        Text('• ${cycleLabel(o.cycleDate)}: ${o.status.label}'),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = (ref.watch(pharmacyQueueProvider).value?.orders ?? const [])
        .where((o) => o.status == Fulfilment.preparing)
        .length;
    return _Section(
      icon: Icons.bolt_outlined,
      title: 'Quick actions',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('quick-new-stock'),
            onPressed: () => addStockItem(context, ref),
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('New stock'),
          ),
          Chip(
            avatar: const Icon(Icons.pending_actions_outlined, size: 18),
            label: Text('$ready order${ready == 1 ? '' : 's'} to prepare'),
          ),
        ],
      ),
    );
  }
}

/// A one-field dialog that owns its controller, so the field outlives the closing animation.
/// Returns the text on confirm, null on cancel.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.fieldKey,
    required this.label,
    required this.confirmText,
    this.message,
    this.initial = '',
    this.confirmKey,
    this.prefixText,
    this.keyboardType,
    this.allowed,
    this.maxLength,
    this.isValid,
  });

  final String title;
  final String? message;
  final String initial;
  final Key fieldKey;
  final String label;
  final Key? confirmKey;
  final String confirmText;
  final String? prefixText;
  final TextInputType? keyboardType;
  final RegExp? allowed;
  final int? maxLength;
  final bool Function(String)? isValid;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = widget.isValid?.call(_ctl.text.trim()) ?? true;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) Text(widget.message!),
          TextField(
            key: widget.fieldKey,
            controller: _ctl,
            autofocus: true,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboardType,
            inputFormatters: [
              if (widget.allowed != null) FilteringTextInputFormatter.allow(widget.allowed!),
            ],
            decoration: InputDecoration(labelText: widget.label, prefixText: widget.prefixText),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: widget.confirmKey,
          onPressed: ok ? () => Navigator.pop(context, _ctl.text.trim()) : null,
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

// ---------------- D-69: medication catalogue ----------------

/// The medicines doctors prescribe and their unit prices. A price change applies to new
/// prescriptions only; issued ones keep the price they were written with.
class _CatalogCard extends ConsumerWidget {
  const _CatalogCard();

  Future<void> _price(BuildContext context, WidgetRef ref, CatalogItem c) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: 'Price of ${c.label}',
        message: 'Per ${c.form}. Applies to new prescriptions.',
        initial: c.unitPrice.toStringAsFixed(2),
        fieldKey: const Key('catalog-price-input'),
        label: 'Unit price',
        prefixText: 'RM ',
        confirmKey: const Key('catalog-price-save'),
        confirmText: 'Save',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        allowed: RegExp(r'[0-9.]'),
        isValid: (v) => (double.tryParse(v) ?? 0) >= 0.01,
      ),
    );
    final price = double.tryParse(text ?? '');
    if (price == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).setCatalogPrice(c.id, price),
      '${c.label} now ${rm(price)} per ${c.form}.',
    );
    ref.invalidate(catalogProvider);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String, double)>(
      context: context,
      builder: (_) => const _CatalogDialog(),
    );
    if (result == null || !context.mounted) return;
    final (name, strength, price) = result;
    await _run(
      context,
      ref,
      () => ref
          .read(ordersRepositoryProvider)
          .addCatalogItem(name: name, strength: strength, form: 'tablet', unitPrice: price),
      '$name $strength added to the catalogue.',
    );
    ref.invalidate(catalogProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return _Section(
      icon: Icons.menu_book_outlined,
      title: 'Medication catalogue',
      action: TextButton.icon(
        key: const Key('catalog-add'),
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      child: catalog.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(catalogProvider),
          child: const Text('Could not load the catalogue. Retry'),
        ),
        data: (items) => ExpansionTile(
          key: const Key('catalog-list'),
          tilePadding: EdgeInsets.zero,
          title: Text('${items.length} medicines · prices used for prescriptions'),
          children: [
            for (final c in items)
              ListTile(
                key: Key('catalog-${c.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(c.label),
                subtitle: Text(c.drugClass),
                trailing: TextButton(
                  key: Key('catalog-price-${c.id}'),
                  onPressed: () => _price(context, ref, c),
                  child: Text('${rm(c.unitPrice)} / ${c.form}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogDialog extends StatefulWidget {
  const _CatalogDialog();

  @override
  State<_CatalogDialog> createState() => _CatalogDialogState();
}

class _CatalogDialogState extends State<_CatalogDialog> {
  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _price = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _price.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().length >= 2 &&
      _strength.text.trim().isNotEmpty &&
      (double.tryParse(_price.text) ?? 0) >= 0.01;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a medicine'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('catalog-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name, e.g. Olmesartan'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const Key('catalog-strength'),
          controller: _strength,
          decoration: const InputDecoration(labelText: 'Strength, e.g. 20mg'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const Key('catalog-price'),
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: const InputDecoration(labelText: 'Price per tablet', prefixText: 'RM '),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const Key('catalog-save'),
        onPressed: _valid
            ? () => Navigator.pop(context, (
                _name.text.trim(),
                _strength.text.trim(),
                double.parse(_price.text),
              ))
            : null,
        child: const Text('Add'),
      ),
    ],
  );
}
