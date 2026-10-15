import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';
import '../../auth/state/auth_providers.dart';
import '../data/record_picker.dart';
import '../data/records_repository.dart';
import '../state/records_providers.dart';
import 'record_widgets.dart';

/// Patient Records tab (FR-6.1, FR-6.2; UC6.1, UC6.2; D-58). Not mocked in Ch4, so it
/// follows the Meds tab layout.
class RecordsPage extends ConsumerStatefulWidget {
  const RecordsPage({super.key});

  @override
  ConsumerState<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends ConsumerState<RecordsPage> {
  RecordCategory? _filter;

  /// Name and progress (0-1) of the file being uploaded, if any.
  (String, double)? _uploading;

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _chooseSource() async {
    final source = await showModalBottomSheet<RecordSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Add a document'),
              subtitle: Text('Supported: $supportedRecordText'),
            ),
            ListTile(
              key: const Key('source-files'),
              leading: const Icon(Icons.folder_open),
              title: const Text('Choose a file'),
              onTap: () => Navigator.of(c).pop(RecordSource.files),
            ),
            ListTile(
              key: const Key('source-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo from gallery'),
              onTap: () => Navigator.of(c).pop(RecordSource.gallery),
            ),
            ListTile(
              key: const Key('source-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(c).pop(RecordSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _upload(source);
  }

  /// UC6.1: pick -> upload -> category (required) -> save; then offer to share (Fig 3.44).
  Future<void> _upload(RecordSource source) async {
    final uid = ref.read(authUidProvider).value;
    if (uid == null) return;
    final repo = ref.read(recordsRepositoryProvider);
    PickedRecordFile? file;
    try {
      file = await ref.read(recordPickerProvider).pick(source);
    } on UnsupportedRecordFile catch (e) {
      _say(e.message); // E1
      return;
    } catch (_) {
      _say('Could not open that file.');
      return;
    }
    if (file == null || !mounted) return;
    final id = repo.newRecordId();
    setState(() => _uploading = (file!.name, 0));
    try {
      await repo.uploadFile(
        uid,
        id,
        file,
        onProgress: (p) {
          if (mounted) setState(() => _uploading = (file!.name, p));
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _uploading = null);
        _say('Upload failed after several tries. Check your connection and try again.'); // E2
      }
      return;
    }
    if (!mounted) return;
    setState(() => _uploading = null);
    final category = await askRecordCategory(context, title: 'What is this document?');
    if (category == null) {
      await repo.discardUpload(uid, id);
      if (mounted) _say('Upload cancelled.');
      return;
    }
    try {
      await repo.save(id, category, file.name);
    } on ApiException catch (e) {
      await repo.discardUpload(uid, id);
      _say(e.message);
      return;
    } catch (_) {
      await repo.discardUpload(uid, id);
      _say('Could not save the document. Please try again.');
      return;
    }
    if (!mounted) return;
    final share = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('share-now'),
        title: const Text('Saved to your records'),
        content: const Text('Share this document with your doctor now? You can also do it later.'),
        actions: [
          TextButton(
            key: const Key('share-later'),
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const Key('share-confirm'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (share == true) await _share(id);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      _say(done);
    } on ApiException catch (e) {
      _say(e.message);
    } catch (_) {
      _say('Something went wrong. Please try again.');
    }
  }

  Future<void> _share(String id) =>
      _run(() => ref.read(recordsRepositoryProvider).share(id), 'Shared with your doctor.');

  Future<void> _onAction(HealthRecord r, String action) async {
    final repo = ref.read(recordsRepositoryProvider);
    switch (action) {
      case 'share':
        await _share(r.id);
      case 'unshare':
        await _run(() => repo.unshare(r.id), 'Your doctor can no longer see this document.');
      case 'category':
        final c = await askRecordCategory(context, title: 'Change category', initial: r.category);
        if (c != null && c != r.category) {
          await _run(() => repo.setCategory(r.id, c), 'Category changed to ${c.label}.');
        }
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Delete this document?'),
            content: Text(
              '${r.fileName} will be removed${r.sharedWithDoctor ? ', and your doctor will no '
                        'longer see it' : ''}. This cannot be undone.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Keep')),
              FilledButton(
                key: const Key('delete-confirm'),
                style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok == true) await _run(() => repo.delete(r.id), 'Document deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(myRecordsProvider);
    final uploading = _uploading;
    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('upload-record'),
        onPressed: uploading == null ? _chooseSource : null,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const Text(
            'Keep lab results, scans and letters in one place. '
            'Your doctor sees a document only after you share it.',
          ),
          const SizedBox(height: 12),
          if (uploading != null)
            Card(
              key: const Key('upload-progress'),
              child: ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text('Uploading ${uploading.$1}'),
                subtitle: LinearProgressIndicator(value: uploading.$2 == 0 ? null : uploading.$2),
              ),
            ),
          records.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => ListTile(
              leading: const Icon(Icons.cloud_off),
              title: const Text('Could not load your records.'),
              trailing: TextButton(
                onPressed: () => ref.invalidate(myRecordsProvider),
                child: const Text('Retry'),
              ),
            ),
            data: (all) {
              if (all.isEmpty) {
                return const Card(
                  key: Key('records-empty'),
                  child: ListTile(
                    leading: Icon(Icons.folder_open),
                    title: Text('No documents yet'),
                    subtitle: Text('Tap Upload to add your first one.'),
                  ),
                );
              }
              final present = {for (final r in all) r.category};
              final shown = [
                for (final r in all)
                  if (_filter == null || r.category == _filter) r,
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        key: const Key('filter-all'),
                        label: Text('All (${all.length})'),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      for (final c in RecordCategory.values)
                        if (present.contains(c))
                          ChoiceChip(
                            key: Key('filter-${c.value}'),
                            label: Text(c.label),
                            selected: _filter == c,
                            onSelected: (_) => setState(() => _filter = c),
                          ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final r in shown) _RecordCard(record: r, onAction: _onAction),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends ConsumerWidget {
  const _RecordCard({required this.record, required this.onAction});

  final HealthRecord record;
  final Future<void> Function(HealthRecord, String) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = record;
    return Card(
      key: Key('record-${r.id}'),
      child: ListTile(
        leading: CircleAvatar(child: Icon(recordIcon(r))),
        title: Text(r.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(recordSubtitle(r)),
            if (r.sharedWithDoctor)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Shared with your doctor',
                  key: Key('shared-${r.id}'),
                  style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        onTap: () => openRecord(context, ref, r),
        trailing: PopupMenuButton<String>(
          key: Key('record-menu-${r.id}'),
          onSelected: (a) => onAction(r, a),
          itemBuilder: (_) => [
            r.sharedWithDoctor
                ? const PopupMenuItem(value: 'unshare', child: Text('Stop sharing'))
                : const PopupMenuItem(value: 'share', child: Text('Share with doctor')),
            const PopupMenuItem(value: 'category', child: Text('Change category')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
