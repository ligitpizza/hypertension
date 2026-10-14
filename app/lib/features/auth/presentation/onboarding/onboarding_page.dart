import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/enums.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/services/api/api_client.dart';
import '../../domain/onboarding_data.dart';
import '../../state/auth_providers.dart';
import 'onboarding_labels.dart';
import '../../../../core/utils/ic_number.dart';

/// UC1.4 Complete Onboarding Health Profile (FR-1.4), three steps:
/// personal information, medical history, lifestyle (D-25).
/// Progress is kept on the device so the patient can resume later (A1);
/// each step blocks "Next" and highlights missing fields (E1).
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _forms = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];
  OnboardingData _data = OnboardingData();
  int _step = 0;
  bool _loading = true;
  bool _submitting = false;
  bool _showChoiceErrors = false;
  String? _error;

  String? get _uid => ref.read(authUidProvider).value;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    // Keep the provider listened while waiting so it is not paused.
    final sub = ref.listenManual(authUidProvider, (_, _) {});
    final String? uid;
    try {
      uid = await ref.read(authUidProvider.future);
    } finally {
      sub.close();
    }
    if (uid != null) {
      final store = ref.read(onboardingDraftStoreProvider);
      final draft = await store.load(uid);
      final step = await store.loadStep(uid);
      if (draft != null) {
        _data = draft;
        _step = step.clamp(0, 2);
      }
    }
    // D-51: date of birth and gender come from the IC number unless already entered.
    final ic = ref.read(currentUserProvider).value?.icNumber;
    if (ic != null) {
      try {
        final info = parseIc(ic);
        _data.dateOfBirth ??= info.dateOfBirth;
        _data.gender ??= info.gender;
      } on FormatException {
        // Leave the fields for the patient to fill in.
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveDraft() async {
    final uid = _uid;
    if (uid != null) await ref.read(onboardingDraftStoreProvider).save(uid, _data, _step);
  }

  bool _stepValid(int step) {
    final formOk = _forms[step].currentState?.validate() ?? false;
    final choicesOk = switch (step) {
      0 =>
        Validators.dateOfBirth(_data.dateOfBirth, DateTime.now()) == null && _data.gender != null,
      1 => true,
      _ =>
        _data.smokingStatus != null &&
            _data.alcohol != null &&
            _data.exerciseDaysPerWeek != null &&
            _data.saltIntake != null,
    };
    return formOk && choicesOk;
  }

  Future<void> _next() async {
    if (!_stepValid(_step)) {
      setState(() => _showChoiceErrors = true);
      return;
    }
    if (_step < 2) {
      setState(() {
        _step++;
        _showChoiceErrors = false;
      });
      await _saveDraft();
    } else {
      await _submit();
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final busy = ref.read(authBusyProvider.notifier)..set(true);
    try {
      await ref.read(authRepositoryProvider).completeOnboarding(_data.toApiJson());
      final uid = _uid;
      if (uid != null) await ref.read(onboardingDraftStoreProvider).clear(uid);
      if (mounted) context.go('/onboard/complete');
    } on ApiException catch (e) {
      await _saveDraft();
      if (mounted) {
        setState(
          () => _error = e.code == 'NETWORK_ERROR'
              ? 'Could not reach the server. Your answers are saved; please try again.'
              : e.message,
        );
      }
    } finally {
      busy.set(false);
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _saveAndExit() async {
    await _saveDraft();
    await ref.read(authRepositoryProvider).signOut(ref.read(clientAppProvider));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    const titles = ['Personal information', 'Medical history', 'Lifestyle'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your health profile'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            key: const Key('onboarding-save-exit'),
            onPressed: _submitting ? null : _saveAndExit,
            child: const Text('Save & finish later'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step ${_step + 1} of 3 · ${titles[_step]}',
                    key: const Key('onboarding-step-title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: (_step + 1) / 3),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: IndexedStack(
                      index: _step,
                      children: [_personal(), _medical(), _lifestyle()],
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error!,
                  key: const Key('onboarding-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _submitting ? null : () => setState(() => _step--),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('onboarding-next'),
                    onPressed: _submitting ? null : _next,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_step < 2 ? 'Next' : 'Submit'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- step 1: personal information ----------

  Widget _personal() {
    final dob = _data.dateOfBirth;
    return Form(
      key: _forms[0],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Label('Date of birth'),
          OutlinedButton.icon(
            key: const Key('onboarding-dob'),
            icon: const Icon(Icons.cake_outlined),
            label: Text(dob == null ? 'Select date' : _formatDate(dob)),
            onPressed: _pickDob,
          ),
          if (_showChoiceErrors && Validators.dateOfBirth(dob, DateTime.now()) != null)
            _ErrorText(Validators.dateOfBirth(dob, DateTime.now())!),
          const SizedBox(height: 16),
          _Label('Gender'),
          _Choices<Gender>(
            values: Gender.values,
            selected: _data.gender,
            label: OnboardingLabels.gender,
            onSelected: (g) => setState(() => _data.gender = g),
          ),
          if (_showChoiceErrors && _data.gender == null) _ErrorText('Gender is required.'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  key: const Key('onboarding-height'),
                  label: 'Height (cm)',
                  initial: _data.heightCm,
                  validator: (v) => Validators.numberInRange(v, 100, 250, label: 'Height'),
                  onChanged: (v) => _data.heightCm = double.tryParse(v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  key: const Key('onboarding-weight'),
                  label: 'Weight (kg)',
                  initial: _data.weightKg,
                  validator: (v) => Validators.numberInRange(v, 25, 300, label: 'Weight'),
                  onChanged: (v) => _data.weightKg = double.tryParse(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('onboarding-phone'),
            initialValue: _data.phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
            validator: Validators.phone,
            onChanged: (v) => _data.phone = v,
          ),
          const SizedBox(height: 20),
          _Label('Emergency contact (optional)'),
          TextFormField(
            initialValue: _data.emergencyName,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) => _data.hasEmergencyContact ? Validators.name(v) : null,
            onChanged: (v) => setState(() => _data.emergencyName = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _data.emergencyPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
            validator: (v) => _data.hasEmergencyContact ? Validators.phone(v) : null,
            onChanged: (v) => setState(() => _data.emergencyPhone = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _data.emergencyRelationship,
            decoration: const InputDecoration(labelText: 'Relationship (e.g. Spouse)'),
            validator: (v) => _data.hasEmergencyContact
                ? Validators.requiredText(v, label: 'Relationship')
                : null,
            onChanged: (v) => setState(() => _data.emergencyRelationship = v),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    // D-28: only dates at least 13 years ago can be picked.
    final last = Validators.latestAllowedDob(now);
    final current = _data.dateOfBirth;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isAfter(last) ? current : DateTime(now.year - 50),
      firstDate: DateTime(now.year - 120),
      lastDate: last,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _data.dateOfBirth = picked);
  }

  // ---------- step 2: medical history ----------

  Widget _medical() {
    return Form(
      key: _forms[1],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('onboarding-diagnosed-year'),
            initialValue: _data.hypertensionDiagnosedYear?.toString() ?? '',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Year diagnosed with high blood pressure (optional)',
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return null;
              return Validators.numberInRange(v, 1900, DateTime.now().year, label: 'Year');
            },
            onChanged: (v) => _data.hypertensionDiagnosedYear = int.tryParse(v),
          ),
          const SizedBox(height: 16),
          _Label('Do you have any of these conditions?'),
          _MultiChoices<MedicalCondition>(
            values: MedicalCondition.values,
            selected: _data.conditions,
            label: OnboardingLabels.condition,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 16),
          _Label('Has a close family member had any of these?'),
          _MultiChoices<FamilyHistoryCondition>(
            values: FamilyHistoryCondition.values,
            selected: _data.familyHistory,
            label: OnboardingLabels.family,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _data.allergies,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Allergies (optional)'),
            onChanged: (v) => _data.allergies = v,
          ),
          TextFormField(
            initialValue: _data.notes,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Anything else your doctor should know?'),
            onChanged: (v) => _data.notes = v,
          ),
        ],
      ),
    );
  }

  // ---------- step 3: lifestyle ----------

  Widget _lifestyle() {
    final days = _data.exerciseDaysPerWeek;
    return Form(
      key: _forms[2],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Label('Smoking'),
          _Choices<SmokingStatus>(
            values: SmokingStatus.values,
            selected: _data.smokingStatus,
            label: OnboardingLabels.smoking,
            onSelected: (v) => setState(() => _data.smokingStatus = v),
          ),
          if (_showChoiceErrors && _data.smokingStatus == null) _ErrorText('Please choose one.'),
          const SizedBox(height: 16),
          _Label('Alcohol'),
          _Choices<AlcoholUse>(
            values: AlcoholUse.values,
            selected: _data.alcohol,
            label: OnboardingLabels.alcohol,
            onSelected: (v) => setState(() => _data.alcohol = v),
          ),
          if (_showChoiceErrors && _data.alcohol == null) _ErrorText('Please choose one.'),
          const SizedBox(height: 16),
          _Label('Days per week with 30+ minutes of exercise: ${days ?? '-'}'),
          Slider(
            key: const Key('onboarding-exercise'),
            value: (days ?? 0).toDouble(),
            max: 7,
            divisions: 7,
            label: '${days ?? 0}',
            onChanged: (v) => setState(() => _data.exerciseDaysPerWeek = v.round()),
          ),
          if (_showChoiceErrors && days == null) _ErrorText('Move the slider to choose.'),
          const SizedBox(height: 16),
          _Label('How salty is your usual diet?'),
          _Choices<SaltIntake>(
            values: SaltIntake.values,
            selected: _data.saltIntake,
            label: OnboardingLabels.salt,
            onSelected: (v) => setState(() => _data.saltIntake = v),
          ),
          if (_showChoiceErrors && _data.saltIntake == null) _ErrorText('Please choose one.'),
        ],
      ),
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error)),
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.label,
    required this.initial,
    required this.validator,
    required this.onChanged,
  });

  final String label;
  final double? initial;
  final FormFieldValidator<String> validator;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initial == null
        ? ''
        : (initial! % 1 == 0 ? initial!.toInt().toString() : initial.toString()),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    decoration: InputDecoration(labelText: label),
    validator: validator,
    onChanged: onChanged,
  );
}

class _Choices<T> extends StatelessWidget {
  const _Choices({
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

class _MultiChoices<T> extends StatelessWidget {
  const _MultiChoices({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final Set<T> selected;
  final String Function(T) label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in values)
        FilterChip(
          label: Text(label(v)),
          selected: selected.contains(v),
          onSelected: (on) {
            on ? selected.add(v) : selected.remove(v);
            onChanged();
          },
        ),
    ],
  );
}
