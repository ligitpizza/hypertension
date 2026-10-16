import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../../medications/domain/med_schedule.dart';
import '../../orders/data/order_models.dart';
import '../../orders/state/orders_providers.dart';
import '../domain/portal_models.dart';
import '../state/portal_providers.dart';
import 'portal_prescription_tile.dart';
import 'portal_widgets.dart';
import 'delivery_preference_card.dart';

/// Fig 4.3.12.7 Prescription Management (FR-8.3; UC8.4 and E1 interaction warning).
/// D-69: one prescription lists several catalogue medicines with dose, frequency and
/// quantity; it goes to the pharmacy as one order.
class PrescriptionPage extends ConsumerStatefulWidget {
  const PrescriptionPage({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<PrescriptionPage> createState() => _PrescriptionPageState();
}

class _PrescriptionPageState extends ConsumerState<PrescriptionPage> {
  /// D-69: the medicines of this consolidated prescription.
  final _lines = <_RxLine>[];
  bool _recurring = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _add(CatalogItem item) => setState(() => _lines.add(_RxLine(item)));

  Future<void> _submit({bool acknowledge = false}) async {
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one medicine.');
      return;
    }
    if (_lines.any((l) => l.quantity == null || l.dose.text.trim().isEmpty)) {
      setState(() => _error = 'Each medicine needs a dose and a quantity of at least 1.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(portalRepositoryProvider)
          .issueConsolidated(
            widget.patientId,
            items: [for (final l in _lines) l.toJson()],
            isRecurring: _recurring,
            acknowledgeInteractions: acknowledge,
          );
      if (!mounted) return;
      final total = result.total;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('rx-saved'),
          content: Text(
            'Prescription issued${total == null ? '' : ' (${rm(total)})'}. '
            'The order was sent to the pharmacy.',
          ),
        ),
      );
      setState(() {
        for (final l in _lines) {
          l.dispose();
        }
        _lines.clear();
        _recurring = false;
      });
    } on ApiException catch (e) {
      if (e.code == 'DRUG_INTERACTION') {
        setState(() => _saving = false);
        final proceed = await _confirmInteractions(InteractionWarning.fromDetails(e.details));
        if (proceed == true) return _submit(acknowledge: true);
        return;
      }
      setState(
        () => _error = e.code == 'NETWORK_ERROR' ? 'Could not reach the server.' : e.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// UC8.4 E1: warn before saving; critical interactions need an explicit tick.
  Future<bool?> _confirmInteractions(List<InteractionWarning> warnings) {
    final critical = warnings.any((w) => w.isCritical);
    var reviewed = !critical;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          key: const Key('interaction-dialog'),
          icon: Icon(
            Icons.warning_amber_rounded,
            color: critical ? Theme.of(context).colorScheme.error : null,
          ),
          title: Text(critical ? 'Critical drug interaction' : 'Drug interaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final w in warnings)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('With ${w.existingDrug} (${w.severity})'),
                    subtitle: Text(w.message),
                  ),
                if (critical)
                  CheckboxListTile(
                    key: const Key('interaction-reviewed'),
                    contentPadding: EdgeInsets.zero,
                    value: reviewed,
                    onChanged: (v) => setDialog(() => reviewed = v ?? false),
                    title: const Text(
                      'I have reviewed this interaction and still want to prescribe.',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              key: const Key('interaction-proceed'),
              onPressed: reviewed ? () => Navigator.pop(context, true) : null,
              child: const Text('Prescribe anyway'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.patientId;
    final patient = ref.watch(portalPatientProvider(id)).value;
    final meds = ref.watch(patientMedicationsProvider(id));
    final rx = ref.watch(patientPrescriptionsProvider(id));
    final notes = ref.watch(patientNotesProvider(id));
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final regimen = SectionCard(
      title: 'Current regimen',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeliveryPreferenceCard(patientId: widget.patientId), // D-72 (M8)
          AsyncSection(
            value: meds,
            isEmpty: (m) => m.isEmpty,
            emptyText: 'No medications on the patient\'s list.',
            builder: (m) => Column(
              children: [
                for (final x in m)
                  ListTile(
                    dense: true,
                    title: Text('${x.name} ${x.dosage}'),
                    subtitle: Text(describeSchedule(x.schedule)),
                  ),
              ],
            ),
          ),
          const Divider(),
          AsyncSection(
            value: rx,
            isEmpty: (p) => p.isEmpty,
            emptyText: 'No prescriptions issued yet.',
            builder: (p) => Column(
              children: [
                for (final x in p)
                  PortalPrescriptionTile(prescription: x, patientId: widget.patientId),
              ],
            ),
          ),
          const Divider(),
          Text('Latest clinical note', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            notes.value?.firstOrNull?.content ?? 'No clinical notes yet.',
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );

    final catalog = ref.watch(catalogProvider);
    final total = _lines.fold<double>(0, (sum, l) => sum + l.lineTotal);
    final form = SectionCard(
      title: 'New prescription',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // D-69: pick medicines from the catalogue; prices come from the pharmacy.
          catalog.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => TextButton(
              onPressed: () => ref.invalidate(catalogProvider),
              child: const Text('Could not load the medication catalogue. Retry'),
            ),
            data: (items) => _CatalogPicker(items: items, onPicked: _add),
          ),
          const SizedBox(height: 12),
          if (_lines.isEmpty)
            const Text('No medicines added yet.', key: Key('rx-empty'))
          else
            for (final (n, l) in _lines.indexed)
              _RxLineCard(
                key: Key('rx-line-$n'),
                line: l,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() => _lines.removeAt(n).dispose()),
              ),
          if (_lines.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total ${rm(total)}',
                key: const Key('rx-total'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const Key('rx-recurring'),
            contentPadding: EdgeInsets.zero,
            value: _recurring,
            onChanged: (v) => setState(() => _recurring = v),
            title: const Text('Recurring for chronic condition'),
            subtitle: const Text('The order goes to the pharmacy now and repeats every month.'),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => context.go('/doctor/patient/$id'),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('rx-submit'),
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.send),
                label: Text(_saving ? 'Saving...' : 'Authorize'),
              ),
            ],
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/doctor/patient/$id'),
            icon: const Icon(Icons.arrow_back),
            label: Text(patient?.name ?? 'Patient'),
          ),
        ),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: regimen),
              const SizedBox(width: 16),
              Expanded(child: form),
            ],
          )
        else ...[
          form,
          const SizedBox(height: 16),
          regimen,
        ],
      ],
    );
  }
}

/// Search the catalogue and add a medicine (D-69).
class _CatalogPicker extends StatefulWidget {
  const _CatalogPicker({required this.items, required this.onPicked});
  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onPicked;

  @override
  State<_CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<_CatalogPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final matches = q.isEmpty
        ? const <CatalogItem>[]
        : widget.items
              .where(
                (c) =>
                    c.active &&
                    (c.label.toLowerCase().contains(q) || c.drugClass.toLowerCase().contains(q)),
              )
              .take(8)
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('rx-search'),
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Add a medicine',
            hintText: 'Search name or class, e.g. amlodipine',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        for (final c in matches)
          ListTile(
            key: Key('rx-option-${c.id}'),
            dense: true,
            leading: const Icon(Icons.add_circle_outline),
            title: Text(c.label),
            subtitle: Text('${c.drugClass} · ${rm(c.unitPrice)} per ${c.form}'),
            onTap: () {
              widget.onPicked(c);
              setState(_search.clear);
            },
          ),
        if (q.isNotEmpty && matches.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No catalogue medicine matches. Ask the pharmacy to add it.'),
          ),
      ],
    );
  }
}

/// One medicine of the prescription being built (D-69).
class _RxLine {
  _RxLine(this.item);

  final CatalogItem item;
  final dose = TextEditingController(text: '1 tablet');
  final qty = TextEditingController(text: '30');
  String frequency = 'once_daily';

  int? get quantity {
    final n = int.tryParse(qty.text.trim());
    return n != null && n >= 1 && n <= 1000 ? n : null;
  }

  double get lineTotal => (quantity ?? 0) * item.unitPrice;

  /// A month's supply for the chosen frequency (one unit per dose).
  void suggestQuantity() {
    final perDay = prescriptionFrequencies[frequency]?.$2 ?? 1;
    qty.text = '${perDay == 0 ? 10 : perDay * 30}';
  }

  Map<String, dynamic> toJson() => {
    'catalogId': item.id,
    'dose': dose.text.trim(),
    'frequency': frequency,
    'quantity': quantity,
  };

  void dispose() {
    dose.dispose();
    qty.dispose();
  }
}

class _RxLineCard extends StatelessWidget {
  const _RxLineCard({
    super.key,
    required this.line,
    required this.onChanged,
    required this.onRemove,
  });

  final _RxLine line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final item = line.item;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(item.label, style: Theme.of(context).textTheme.titleSmall)),
                Text('${rm(item.unitPrice)} / ${item.form}'),
                IconButton(
                  key: const Key('rx-remove'),
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: 130,
                  child: TextField(
                    key: const Key('rx-dose'),
                    controller: line.dose,
                    decoration: const InputDecoration(labelText: 'Dose'),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    key: const Key('rx-frequency'),
                    isExpanded: true,
                    initialValue: line.frequency,
                    decoration: const InputDecoration(labelText: 'Frequency'),
                    items: [
                      for (final f in prescriptionFrequencies.entries)
                        DropdownMenuItem(value: f.key, child: Text(f.value.$1)),
                    ],
                    onChanged: (v) {
                      line.frequency = v ?? line.frequency;
                      line.suggestQuantity();
                      onChanged();
                    },
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    key: const Key('rx-quantity'),
                    controller: line.qty,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                Text(rm(line.lineTotal), style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
