import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api/api_client.dart';
import '../../appointments/domain/appointment_text.dart' show dateLabel;
import '../data/order_models.dart';
import '../state/orders_providers.dart';

/// Shared pharmacy and admin portal pieces (D-66, D-69, D-70): the action runner, card
/// section, prompt, stock and catalogue dialogs.

Future<void> runPharmacyAction(
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

String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class PharmacySection extends StatelessWidget {
  const PharmacySection({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.action,
  });
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

/// "New Stock" quick action (Fig 4.3.13.1).
Future<void> addStockItem(BuildContext context, WidgetRef ref) async {
  final catalog = await ref.read(catalogProvider.future).catchError((_) => <CatalogItem>[]);
  if (!context.mounted) return;
  final result = await showDialog<(String, int, String)>(
    context: context,
    builder: (_) => StockDialog(title: 'New stock item', askName: true, catalog: catalog),
  );
  if (result == null || !context.mounted) return;
  final (name, units, expiry) = result;
  // D-69: a stock item named like a catalogue medicine is linked to it.
  final linked = catalog.where((c) => c.label.toLowerCase() == name.toLowerCase()).firstOrNull;
  await runPharmacyAction(
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

class StockDialog extends StatefulWidget {
  const StockDialog({
    super.key,
    required this.title,
    required this.askName,
    this.catalog = const [],
  });
  final String title;
  final bool askName;

  /// D-69: picking a catalogue medicine fills the name and links the stock to it.
  final List<CatalogItem> catalog;

  @override
  State<StockDialog> createState() => StockDialogState();
}

class StockDialogState extends State<StockDialog> {
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
                isoDate(_expiry!),
              ))
            : null,
        child: const Text('Save'),
      ),
    ],
  );
}

class PromptDialog extends StatefulWidget {
  const PromptDialog({
    super.key,
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
  State<PromptDialog> createState() => PromptDialogState();
}

class PromptDialogState extends State<PromptDialog> {
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

class CatalogDialog extends StatefulWidget {
  const CatalogDialog({super.key});

  @override
  State<CatalogDialog> createState() => CatalogDialogState();
}

class CatalogDialogState extends State<CatalogDialog> {
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
