import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../domain/portal_logic.dart';
import '../state/portal_providers.dart';
import 'patient_detail_page.dart' show NotesList;
import 'portal_widgets.dart';

/// Fig 4.3.12.5 Consultation Notes / 4.3.12.6 Note Saved (FR-8.3; UC8.4).
///
/// Notes are final once saved (Ch4 `clinical_notes` has no draft state); the text
/// being written stays in this page until it is saved.
class ClinicalNotePage extends ConsumerStatefulWidget {
  const ClinicalNotePage({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<ClinicalNotePage> createState() => _ClinicalNotePageState();
}

class _ClinicalNotePageState extends ConsumerState<ClinicalNotePage> {
  final _text = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _applyTemplate(String body) {
    final current = _text.text.trimRight();
    _text.text = current.isEmpty ? body : '$current\n\n$body';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  Future<void> _save() async {
    final content = _text.text.trim();
    if (content.isEmpty) {
      setState(() => _error = 'Write the note before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(portalRepositoryProvider).addNote(widget.patientId, content);
      if (!mounted) return;
      _text.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(key: Key('note-saved'), content: Text('Clinical note saved.')));
    } on ApiException catch (e) {
      setState(
        () => _error = e.code == 'NETWORK_ERROR' ? 'Could not reach the server.' : e.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = ref.watch(portalPatientProvider(widget.patientId)).value;
    final notes = ref.watch(patientNotesProvider(widget.patientId));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/doctor/patient/${widget.patientId}'),
            icon: const Icon(Icons.arrow_back),
            label: Text(patient?.name ?? 'Patient'),
          ),
        ),
        SectionCard(
          title: 'Clinical note',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Smart templates:'),
                  for (final t in noteTemplates.entries)
                    ActionChip(
                      key: Key('template-${t.key}'),
                      label: Text(t.key),
                      onPressed: () => _applyTemplate(t.value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('note-text'),
                controller: _text,
                minLines: 10,
                maxLines: 20,
                maxLength: 10000,
                decoration: const InputDecoration(
                  hintText: 'Begin typing the clinical note here...',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('note-save'),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(_saving ? 'Saving...' : 'Save note'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Previous notes',
          child: NotesList(notes: notes, shrinkWrap: true),
        ),
      ],
    );
  }
}
