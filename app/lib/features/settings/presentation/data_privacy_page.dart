import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../data/settings_repository.dart';
import '../state/settings_providers.dart';

/// UC12.3 export and UC12.4 delete (D-46, D-47). Not mocked in Ch4; built in the
/// Settings style (docs/07).
class DataPrivacyPage extends ConsumerStatefulWidget {
  const DataPrivacyPage({super.key});

  @override
  ConsumerState<DataPrivacyPage> createState() => _DataPrivacyPageState();
}

class _DataPrivacyPageState extends ConsumerState<DataPrivacyPage> {
  String? _busy; // 'pdf' | 'json'

  Future<void> _export(String format) async {
    setState(() => _busy = format);
    await exportAndShare(context, ref, format);
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget exportButton(String format, String label) => OutlinedButton.icon(
      key: Key('export-$format'),
      onPressed: _busy == null ? () => _export(format) : null,
      icon: _busy == format
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator())
          : const Icon(Icons.download_outlined),
      label: Text(label),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Data & privacy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Export your health data', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'A copy of your profile, health profile, blood pressure readings, risk scores, '
            'medicines and dose history, symptom checks, care plan, prescriptions and '
            'clinical notes. Messages are end-to-end encrypted and are not included.',
          ),
          const SizedBox(height: 12),
          exportButton('pdf', 'Export as PDF'),
          const SizedBox(height: 8),
          exportButton('json', 'Export as JSON (for other apps)'),
          const Divider(height: 40),
          Text('Delete your account', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Your account is switched off straight away and your data is permanently '
            'deleted after 7 days. Notes and prescriptions written by your doctor stay in '
            'their clinical records.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('privacy-delete'),
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            onPressed: () => startAccountDeletion(context, ref),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
  }
}

/// UC12.3: download the export and open the share sheet. E1: failure offers Retry.
Future<bool> exportAndShare(BuildContext context, WidgetRef ref, String format) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await ref.read(settingsRepositoryProvider).export(format);
    final day = DateTime.now();
    final stamp =
        '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}';
    await ref
        .read(fileSharerProvider)
        .share(
          bytes,
          fileName: 'careflow-export-$stamp.$format',
          mimeType: format == 'pdf' ? 'application/pdf' : 'application/json',
        );
    return true;
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(
        content: const Text('We could not create your export.'),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () {
            if (context.mounted) exportAndShare(context, ref, format);
          },
        ),
      ),
    );
    return false;
  }
}

/// UC12.4: offer export (step 2, A1 skip), confirm, warn about recurring prescriptions
/// (E1), deactivate, then sign out.
Future<void> startAccountDeletion(BuildContext context, WidgetRef ref) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      key: const Key('delete-offer-export'),
      title: const Text('Before you go'),
      content: const Text(
        'Would you like a copy of your health data first? After deletion it cannot be '
        'recovered.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Cancel')),
        TextButton(
          key: const Key('delete-skip-export'),
          onPressed: () => Navigator.of(c).pop('skip'),
          child: const Text('No, continue'),
        ),
        FilledButton(
          key: const Key('delete-export-first'),
          onPressed: () => Navigator.of(c).pop('export'),
          child: const Text('Export first'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'export' && !await exportAndShare(context, ref, 'pdf')) return;
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      key: const Key('delete-confirm'),
      title: const Text('Delete your account?'),
      content: const Text(
        'You will be signed out now. Your account and health data will be permanently '
        'deleted after 7 days.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('delete-confirm-button'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text('Delete account'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final repo = ref.read(settingsRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    try {
      await repo.deleteAccount();
    } on RecurringPrescriptionWarning catch (w) {
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          key: const Key('delete-recurring'),
          title: const Text('Recurring prescription'),
          content: Text(
            'Deleting your account will cancel your recurring prescription:\n'
            '${w.prescriptions.join('\n')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Keep account'),
            ),
            FilledButton(
              key: const Key('delete-recurring-confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Cancel it and delete'),
            ),
          ],
        ),
      );
      if (go != true) return;
      await repo.deleteAccount(acknowledgeRecurring: true);
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not delete your account. Please try again.')),
    );
    return;
  }
  messenger.showSnackBar(
    const SnackBar(content: Text('Your account has been deactivated and will be deleted.')),
  );
  await ref.read(authRepositoryProvider).signOut(ref.read(clientAppProvider));
}
