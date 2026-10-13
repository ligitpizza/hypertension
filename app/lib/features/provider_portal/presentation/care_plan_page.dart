import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../state/portal_providers.dart';
import 'portal_widgets.dart';

/// UC8.5 Update Care Plan (FR-8.3): one living plan per patient, shared with the
/// patient's view (UC10.2, Increment 3).
class CarePlanPage extends ConsumerStatefulWidget {
  const CarePlanPage({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<CarePlanPage> createState() => _CarePlanPageState();
}

class _CarePlanPageState extends ConsumerState<CarePlanPage> {
  final _text = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _text.text.trim();
    if (content.isEmpty) {
      setState(() => _error = 'The care plan cannot be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(portalRepositoryProvider).saveCarePlan(widget.patientId, content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(key: Key('care-plan-saved'), content: Text('Care plan saved.')),
      );
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
    final id = widget.patientId;
    final patient = ref.watch(portalPatientProvider(id)).value;
    final plan = ref.watch(patientCarePlanProvider(id));
    // Fill the editor once with the stored plan; later saves don't overwrite typing.
    if (!_loaded && plan.hasValue) {
      _loaded = true;
      _text.text = plan.value?.content ?? '';
    }
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
        SectionCard(
          title: 'Care plan',
          trailing: plan.value == null
              ? null
              : Text(
                  'Updated ${formatDate(plan.value!.updatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          child: plan.isLoading && !_loaded
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('care-plan-text'),
                      controller: _text,
                      minLines: 10,
                      maxLines: 24,
                      maxLength: 10000,
                      decoration: const InputDecoration(
                        hintText:
                            'Targets (e.g. home BP below 130/80), medicines, lifestyle goals, '
                            'monitoring and review dates...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null)
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: const Key('care-plan-save'),
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Saving...' : 'Save care plan'),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
