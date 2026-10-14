import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Small form pieces for the Module 12 edit screens (same look as onboarding).

final phonePattern = RegExp(r'^\+?[0-9][0-9\s-]{6,18}[0-9]$'); // matches the API (_PHONE_RE)

String? validatePhone(String? v, {bool required = true}) {
  final text = (v ?? '').trim();
  if (text.isEmpty) return required ? 'Enter a phone number.' : null;
  return phonePattern.hasMatch(text) ? null : 'Enter a valid phone number.';
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    required this.min,
    required this.max,
    this.decimals = false,
    this.required = true,
  });

  final String label;
  final num? initial;
  final ValueChanged<num?> onChanged;
  final num min;
  final num max;
  final bool decimals;
  final bool required;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initial == null
        ? ''
        : (decimals ? initial.toString() : initial!.round().toString()),
    decoration: InputDecoration(labelText: label),
    keyboardType: TextInputType.numberWithOptions(decimal: decimals),
    inputFormatters: [
      FilteringTextInputFormatter.allow(decimals ? RegExp(r'[0-9.]') : RegExp(r'[0-9]')),
    ],
    onChanged: (v) => onChanged(num.tryParse(v)),
    validator: (v) {
      final n = num.tryParse((v ?? '').trim());
      if (n == null) return required ? 'Required.' : null;
      if (n < min || n > max) return 'Enter $min to $max.';
      return null;
    },
  );
}

class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in values)
        ChoiceChip(
          label: Text(label(v)),
          selected: v == selected,
          onSelected: (_) => onSelected(v),
        ),
    ],
  );
}

class MultiChips<T> extends StatelessWidget {
  const MultiChips({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final Set<T> selected;
  final String Function(T) label;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in values)
        FilterChip(
          label: Text(label(v)),
          selected: selected.contains(v),
          onSelected: (on) => onChanged(on ? ({...selected, v}) : ({...selected}..remove(v))),
        ),
    ],
  );
}

/// Save button with a spinner and an inline error (UC12.1 E1).
class SaveBar extends StatelessWidget {
  const SaveBar({super.key, required this.saving, required this.onSave, this.error});

  final bool saving;
  final VoidCallback onSave;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            error!,
            key: const Key('settings-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('settings-save'),
        onPressed: saving ? null : onSave,
        child: saving
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
            : const Text('Save'),
      ),
    ],
  );
}
