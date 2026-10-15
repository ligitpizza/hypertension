import 'package:flutter/material.dart';

import '../../../shared/models/health_models.dart';

/// D-55: why the patient wants to cancel or reschedule. Returns (reason code, note) or null.
Future<(String, String?)?> askChangeReason(BuildContext context, {required String title}) =>
    showDialog<(String, String?)>(
      context: context,
      builder: (_) => _ReasonDialog(title: title),
    );

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _valid => _reason != null && (_reason != 'other' || _note.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('change-reason-dialog'),
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your doctor will review this request.'),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(
              children: [
                for (final MapEntry(key: code, value: label) in changeReasons.entries)
                  RadioListTile<String>(
                    key: Key('reason-$code'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: code,
                    title: Text(label),
                  ),
              ],
            ),
          ),
          TextField(
            key: const Key('reason-note'),
            controller: _note,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _reason == 'other' ? 'Please explain' : 'Note (optional)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
      FilledButton(
        key: const Key('reason-send'),
        onPressed: _valid
            ? () => Navigator.of(
                context,
              ).pop((_reason!, _note.text.trim().isEmpty ? null : _note.text.trim()))
            : null,
        child: const Text('Send request'),
      ),
    ],
  );
}
