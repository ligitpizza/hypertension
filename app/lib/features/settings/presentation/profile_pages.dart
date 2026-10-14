import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';
import '../../auth/domain/onboarding_data.dart';
import '../../auth/presentation/onboarding/onboarding_labels.dart';
import '../../auth/state/auth_providers.dart';
import '../state/settings_providers.dart';
import 'settings_widgets.dart';

/// Shared save handling: validate, call the API, show the result (UC12.1 E1 inline).
mixin _SaveFlow<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;

  /// [action] returns true when the risk score was re-generated.
  Future<void> save(Future<bool> Function() action) async {
    setState(() => error = null);
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final rescored = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rescored ? 'Saved. Your risk assessment was updated.' : 'Saved.')),
      );
      context.pop();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'Could not save. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

Widget _loading(AsyncValue<OnboardingData?> value, Widget Function(OnboardingData) form) =>
    value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load your profile.')),
      data: (d) => d == null
          ? const Center(child: Text('Finish onboarding to set up your profile.'))
          : form(d),
    );

// ---------------- UC12.1 personal information ----------------

class PersonalInfoPage extends ConsumerWidget {
  const PersonalInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Personal information')),
      // Wait for the user document so the form starts with the saved values.
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : _PersonalForm(name: user.name, dateOfBirth: user.dateOfBirth, gender: user.gender),
    );
  }
}

class _PersonalForm extends ConsumerStatefulWidget {
  const _PersonalForm({required this.name, this.dateOfBirth, this.gender});

  final String name;
  final DateTime? dateOfBirth;
  final Gender? gender;

  @override
  ConsumerState<_PersonalForm> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends ConsumerState<_PersonalForm> with _SaveFlow<_PersonalForm> {
  late final _name = TextEditingController(text: widget.name);
  late DateTime? _dob = widget.dateOfBirth;
  late Gender? _gender = widget.gender;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 50),
      firstDate: DateTime(now.year - 120),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dob = _dob;
    return Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            key: const Key('settings-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your full name.' : null,
          ),
          const SectionLabel('Date of birth'),
          OutlinedButton.icon(
            key: const Key('settings-dob'),
            onPressed: _pickDob,
            icon: const Icon(Icons.cake_outlined),
            label: Text(dob == null ? 'Choose date' : '${dob.day}/${dob.month}/${dob.year}'),
          ),
          const SectionLabel('Gender'),
          ChoiceChips<Gender>(
            values: Gender.values,
            selected: _gender,
            label: OnboardingLabels.gender,
            onSelected: (g) => setState(() => _gender = g),
          ),
          SaveBar(
            saving: saving,
            error: error,
            onSave: () {
              if (_dob == null || _gender == null) {
                setState(() => error = 'Choose your date of birth and gender.');
                return;
              }
              save(
                () => ref
                    .read(settingsRepositoryProvider)
                    .updatePersonal(name: _name.text, dateOfBirth: _dob!, gender: _gender!),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------- UC12.1 contact details ----------------

class ContactDetailsPage extends ConsumerWidget {
  const ContactDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Contact details')),
    body: _loading(ref.watch(healthProfileProvider), (d) => _ContactForm(data: d)),
  );
}

class _ContactForm extends ConsumerStatefulWidget {
  const _ContactForm({required this.data});

  final OnboardingData data;

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> with _SaveFlow<_ContactForm> {
  late final OnboardingData _d = widget.data;

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(currentUserProvider).value?.email ?? '';
    return Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.email_outlined),
            title: Text(email),
            subtitle: const Text('Sign-in email (cannot be changed here)'),
          ),
          TextFormField(
            key: const Key('settings-phone'),
            initialValue: _d.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
            keyboardType: TextInputType.phone,
            onChanged: (v) => _d.phone = v,
            validator: validatePhone,
          ),
          const SectionLabel('Emergency contact (optional)'),
          TextFormField(
            key: const Key('settings-emergency-name'),
            initialValue: _d.emergencyName,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (v) => _d.emergencyName = v,
            validator: (v) =>
                _d.hasEmergencyContact && (v ?? '').trim().length < 2 ? 'Enter their name.' : null,
          ),
          TextFormField(
            key: const Key('settings-emergency-phone'),
            initialValue: _d.emergencyPhone,
            decoration: const InputDecoration(labelText: 'Phone'),
            keyboardType: TextInputType.phone,
            onChanged: (v) => _d.emergencyPhone = v,
            validator: (v) => validatePhone(v, required: _d.hasEmergencyContact),
          ),
          TextFormField(
            key: const Key('settings-emergency-relationship'),
            initialValue: _d.emergencyRelationship,
            decoration: const InputDecoration(labelText: 'Relationship'),
            onChanged: (v) => _d.emergencyRelationship = v,
            validator: (v) => _d.hasEmergencyContact && (v ?? '').trim().length < 2
                ? 'Enter the relationship.'
                : null,
          ),
          SaveBar(
            saving: saving,
            error: error,
            onSave: () => save(() async {
              await ref.read(settingsRepositoryProvider).updateContact(_d);
              return false;
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------- UC12.2 health profile ----------------

class HealthProfilePage extends ConsumerWidget {
  const HealthProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Health profile')),
    body: _loading(ref.watch(healthProfileProvider), (d) => _HealthForm(data: d)),
  );
}

class _HealthForm extends ConsumerStatefulWidget {
  const _HealthForm({required this.data});

  final OnboardingData data;

  @override
  ConsumerState<_HealthForm> createState() => _HealthFormState();
}

class _HealthFormState extends ConsumerState<_HealthForm> with _SaveFlow<_HealthForm> {
  late final OnboardingData _d = widget.data;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Changes to these answers update your risk assessment.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Row(
            children: [
              Expanded(
                child: NumberField(
                  key: const Key('settings-height'),
                  label: 'Height (cm)',
                  initial: _d.heightCm,
                  min: 100,
                  max: 250,
                  decimals: true,
                  onChanged: (v) => _d.heightCm = v?.toDouble(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NumberField(
                  key: const Key('settings-weight'),
                  label: 'Weight (kg)',
                  initial: _d.weightKg,
                  min: 25,
                  max: 300,
                  decimals: true,
                  onChanged: (v) => _d.weightKg = v?.toDouble(),
                ),
              ),
            ],
          ),
          NumberField(
            label: 'Year diagnosed with high blood pressure (optional)',
            initial: _d.hypertensionDiagnosedYear,
            min: 1900,
            max: year,
            required: false,
            onChanged: (v) => _d.hypertensionDiagnosedYear = v?.toInt(),
          ),
          const SectionLabel('Conditions you have'),
          MultiChips<MedicalCondition>(
            values: MedicalCondition.values,
            selected: _d.conditions,
            label: OnboardingLabels.condition,
            onChanged: (s) => setState(() => _d.conditions = s),
          ),
          const SectionLabel('Family history'),
          MultiChips<FamilyHistoryCondition>(
            values: FamilyHistoryCondition.values,
            selected: _d.familyHistory,
            label: OnboardingLabels.family,
            onChanged: (s) => setState(() => _d.familyHistory = s),
          ),
          TextFormField(
            key: const Key('settings-allergies'),
            initialValue: _d.allergies,
            decoration: const InputDecoration(labelText: 'Allergies'),
            maxLength: 500,
            onChanged: (v) => _d.allergies = v,
          ),
          const SectionLabel('Smoking'),
          ChoiceChips<SmokingStatus>(
            key: const Key('settings-smoking'),
            values: SmokingStatus.values,
            selected: _d.smokingStatus,
            label: OnboardingLabels.smoking,
            onSelected: (v) => setState(() => _d.smokingStatus = v),
          ),
          const SectionLabel('Alcohol'),
          ChoiceChips<AlcoholUse>(
            values: AlcoholUse.values,
            selected: _d.alcohol,
            label: OnboardingLabels.alcohol,
            onSelected: (v) => setState(() => _d.alcohol = v),
          ),
          const SectionLabel('Salt in your diet'),
          ChoiceChips<SaltIntake>(
            values: SaltIntake.values,
            selected: _d.saltIntake,
            label: OnboardingLabels.salt,
            onSelected: (v) => setState(() => _d.saltIntake = v),
          ),
          const SizedBox(height: 8),
          NumberField(
            label: 'Days of exercise per week',
            initial: _d.exerciseDaysPerWeek,
            min: 0,
            max: 7,
            onChanged: (v) => _d.exerciseDaysPerWeek = v?.toInt(),
          ),
          SaveBar(
            saving: saving,
            error: error,
            onSave: () {
              if (_d.smokingStatus == null || _d.alcohol == null || _d.saltIntake == null) {
                setState(() => error = 'Answer the smoking, alcohol and salt questions.');
                return;
              }
              save(() => ref.read(settingsRepositoryProvider).updateHealth(_d));
            },
          ),
        ],
      ),
    );
  }
}
