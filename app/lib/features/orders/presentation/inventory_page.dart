import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_models.dart';
import '../state/orders_providers.dart';
import 'pharmacy_shared.dart';

/// D-70 Inventory tab (pharmacist and admin): Stock and Catalogue as tables. Admins may
/// also delete stock items; catalogue medicines are deactivated, never deleted (old
/// prescriptions refer to them).
class InventoryPage extends ConsumerWidget {
  const InventoryPage({super.key, this.admin = false});
  final bool admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 2,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(
            children: [
              Expanded(child: Text('Inventory', style: Theme.of(context).textTheme.headlineSmall)),
              IconButton(
                key: const Key('inventory-refresh'),
                tooltip: 'Refresh',
                onPressed: () => ref
                  ..invalidate(stockProvider)
                  ..invalidate(catalogProvider),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(key: Key('inventory-tab-stock'), text: 'Stock'),
              Tab(key: Key('inventory-tab-catalogue'), text: 'Catalogue'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _StockTab(admin: admin),
              const _CatalogueTab(),
            ],
          ),
        ),
      ],
    ),
  );
}

// ---------------- stock ----------------

class _StockTab extends ConsumerWidget {
  const _StockTab({required this.admin});
  final bool admin;

  Future<void> _receive(BuildContext context, WidgetRef ref, StockItem s) async {
    final result = await showDialog<(String, int, String)>(
      context: context,
      builder: (_) => StockDialog(title: 'Receive ${s.name}', askName: false),
    );
    if (result == null || !context.mounted) return;
    final (_, units, expiry) = result;
    await runPharmacyAction(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).receiveStock(s.id, units, expiry),
      '$units units added.',
    );
  }

  Future<void> _lowAt(BuildContext context, WidgetRef ref, StockItem s) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => PromptDialog(
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
    await runPharmacyAction(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).setLowStockAt(s.id, v),
      'Warning level saved.',
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, StockItem s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${s.name}?'),
        content: const Text('The stock record is removed. Orders already filled are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('stock-delete-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runPharmacyAction(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).deleteStock(s.id),
      '${s.name} deleted.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockProvider);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Expanded(child: Text('Units on hand, warning levels and earliest expiry.')),
            FilledButton.tonalIcon(
              key: const Key('new-stock'),
              onPressed: () => addStockItem(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New stock item'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        stock.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(stockProvider),
            child: const Text('Could not load stock. Retry'),
          ),
          data: (items) => items.isEmpty
              ? const Text('No stock recorded yet.')
              : Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      key: const Key('stock-table'),
                      columns: const [
                        DataColumn(label: Text('Medicine')),
                        DataColumn(label: Text('Units'), numeric: true),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Earliest expiry')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: [
                        for (final s in items)
                          DataRow(
                            key: ValueKey('stock-${s.id}'),
                            cells: [
                              DataCell(Text(s.name)),
                              DataCell(Text('${s.units}')),
                              DataCell(
                                s.low
                                    ? Chip(
                                        label: Text('Low (< ${s.lowStockAt})'),
                                        backgroundColor: theme.colorScheme.errorContainer,
                                        visualDensity: VisualDensity.compact,
                                      )
                                    : Text('OK (warn < ${s.lowStockAt})'),
                              ),
                              DataCell(Text(s.expiryDate ?? '—')),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: Key('receive-${s.id}'),
                                      tooltip: 'Receive stock',
                                      onPressed: () => _receive(context, ref, s),
                                      icon: const Icon(Icons.add_box_outlined),
                                    ),
                                    IconButton(
                                      key: Key('low-at-${s.id}'),
                                      tooltip: 'Low-stock warning level',
                                      onPressed: () => _lowAt(context, ref, s),
                                      icon: const Icon(Icons.tune),
                                    ),
                                    if (admin)
                                      IconButton(
                                        key: Key('stock-delete-${s.id}'),
                                        tooltip: 'Delete',
                                        onPressed: () => _delete(context, ref, s),
                                        icon: const Icon(Icons.delete_outline),
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
        ),
      ],
    );
  }
}

// ---------------- catalogue ----------------

class _CatalogueTab extends ConsumerWidget {
  const _CatalogueTab();

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String, double)>(
      context: context,
      builder: (_) => const CatalogDialog(),
    );
    if (result == null || !context.mounted) return;
    final (name, strength, price) = result;
    await runPharmacyAction(
      context,
      ref,
      () => ref
          .read(ordersRepositoryProvider)
          .addCatalogItem(name: name, strength: strength, form: 'tablet', unitPrice: price),
      '$name $strength added to the catalogue.',
    );
    ref.invalidate(catalogProvider);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, CatalogItem c) async {
    final result = await showDialog<_CatalogEdit>(
      context: context,
      builder: (_) => _EditCatalogDialog(item: c),
    );
    if (result == null || !context.mounted) return;
    await runPharmacyAction(
      context,
      ref,
      () => ref
          .read(ordersRepositoryProvider)
          .editCatalogItem(
            c.id,
            name: result.name,
            strength: result.strength,
            drugClass: result.drugClass,
            unitPrice: result.price,
          ),
      '${result.name} ${result.strength} saved. New prescriptions use the new price.',
    );
    ref.invalidate(catalogProvider);
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, CatalogItem c, bool active) async {
    await runPharmacyAction(
      context,
      ref,
      () => ref.read(ordersRepositoryProvider).editCatalogItem(c.id, active: active),
      active ? '${c.label} offered to doctors again.' : '${c.label} hidden from doctors.',
    );
    ref.invalidate(catalogProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Medicines doctors can prescribe. Prices apply to new prescriptions only.',
              ),
            ),
            FilledButton.tonalIcon(
              key: const Key('catalog-add'),
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add medicine'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        catalog.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(catalogProvider),
            child: const Text('Could not load the catalogue. Retry'),
          ),
          data: (items) => Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('catalog-table'),
                columns: const [
                  DataColumn(label: Text('Medicine')),
                  DataColumn(label: Text('Class')),
                  DataColumn(label: Text('Form')),
                  DataColumn(label: Text('Unit price'), numeric: true),
                  DataColumn(label: Text('Offered')),
                  DataColumn(label: Text('Edit')),
                ],
                rows: [
                  for (final c in items)
                    DataRow(
                      key: ValueKey('catalog-${c.id}'),
                      cells: [
                        DataCell(Text(c.label)),
                        DataCell(Text(c.drugClass)),
                        DataCell(Text(c.form)),
                        DataCell(Text(rm(c.unitPrice))),
                        DataCell(
                          Switch(
                            key: Key('catalog-active-${c.id}'),
                            value: c.active,
                            onChanged: (v) => _toggle(context, ref, c, v),
                          ),
                        ),
                        DataCell(
                          IconButton(
                            key: Key('catalog-edit-${c.id}'),
                            tooltip: 'Edit',
                            onPressed: () => _edit(context, ref, c),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
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

typedef _CatalogEdit = ({String name, String strength, String drugClass, double price});

class _EditCatalogDialog extends StatefulWidget {
  const _EditCatalogDialog({required this.item});
  final CatalogItem item;

  @override
  State<_EditCatalogDialog> createState() => _EditCatalogDialogState();
}

class _EditCatalogDialogState extends State<_EditCatalogDialog> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _strength = TextEditingController(text: widget.item.strength);
  late final _class = TextEditingController(text: widget.item.drugClass);
  late final _price = TextEditingController(text: widget.item.unitPrice.toStringAsFixed(2));

  @override
  void dispose() {
    for (final c in [_name, _strength, _class, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().length >= 2 &&
      _strength.text.trim().isNotEmpty &&
      (double.tryParse(_price.text) ?? 0) >= 0.01;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${widget.item.label}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('catalog-edit-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const Key('catalog-edit-strength'),
          controller: _strength,
          decoration: const InputDecoration(labelText: 'Strength'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const Key('catalog-edit-class'),
          controller: _class,
          decoration: const InputDecoration(labelText: 'Drug class'),
        ),
        TextField(
          key: const Key('catalog-edit-price'),
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(
            labelText: 'Price per ${widget.item.form}',
            prefixText: 'RM ',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const Key('catalog-edit-save'),
        onPressed: _valid
            ? () => Navigator.pop<_CatalogEdit>(context, (
                name: _name.text.trim(),
                strength: _strength.text.trim(),
                drugClass: _class.text.trim(),
                price: double.parse(_price.text),
              ))
            : null,
        child: const Text('Save'),
      ),
    ],
  );
}
