import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../provider_portal/presentation/portal_widgets.dart' show formatDate;
import '../../settings/state/settings_providers.dart';
import '../data/records_repository.dart';
import '../state/records_providers.dart';

/// Opens a record (UC6.3): images in a zoomable dialog, PDFs through the system viewer
/// (share sheet on the phone, a download in the browser).
Future<void> openRecord(BuildContext context, WidgetRef ref, HealthRecord r) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await ref.read(recordsRepositoryProvider).fileBytes(r.id);
    if (r.isPdf) {
      await ref
          .read(fileSharerProvider)
          .share(bytes, fileName: r.fileName, mimeType: r.contentType);
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        key: const Key('record-image'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(r.fileName),
              subtitle: Text(r.category.label),
              trailing: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(c).pop(),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(bytes, fit: BoxFit.contain, semanticLabel: r.fileName),
              ),
            ),
          ],
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not open the document.')));
  }
}

/// UC6.1 step 3: the category is required. Null when the patient cancels.
Future<RecordCategory?> askRecordCategory(
  BuildContext context, {
  required String title,
  RecordCategory? initial,
  String confirm = 'Save',
}) => showDialog<RecordCategory>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _CategoryDialog(title: title, initial: initial, confirm: confirm),
);

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.title, this.initial, required this.confirm});

  final String title;
  final RecordCategory? initial;
  final String confirm;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late RecordCategory? _value = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('record-category-dialog'),
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: RadioGroup<RecordCategory>(
        groupValue: _value,
        onChanged: (v) => setState(() => _value = v),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in RecordCategory.values)
              RadioListTile<RecordCategory>(
                key: Key('category-${c.value}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: c,
                title: Text(c.label),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        key: const Key('category-confirm'),
        onPressed: _value == null ? null : () => Navigator.of(context).pop(_value),
        child: Text(widget.confirm),
      ),
    ],
  );
}

IconData recordIcon(HealthRecord r) => r.isPdf ? Icons.picture_as_pdf : Icons.image_outlined;

/// D-78: one colour and icon per category, so documents are easy to tell apart.
(IconData, Color) categoryStyle(RecordCategory c) => switch (c) {
  RecordCategory.labResult => (Icons.science_outlined, Colors.purple.shade400),
  RecordCategory.prescription => (Icons.medication_outlined, Colors.teal.shade600),
  RecordCategory.imaging => (Icons.monitor_heart_outlined, Colors.indigo.shade400),
  RecordCategory.dischargeSummary => (Icons.local_hospital_outlined, Colors.red.shade400),
  RecordCategory.referralLetter => (Icons.mail_outline, Colors.orange.shade700),
  RecordCategory.other => (Icons.description_outlined, Colors.blueGrey),
};

String recordSubtitle(HealthRecord r) =>
    '${r.category.label} · ${fileSizeLabel(r.sizeBytes)} · ${formatDate(r.uploadedAt)}';
