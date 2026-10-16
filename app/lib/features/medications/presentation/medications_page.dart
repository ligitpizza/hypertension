import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/health_models.dart';
import '../../../shared/services/api/api_client.dart';
import '../../auth/state/auth_providers.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../provider_portal/domain/portal_models.dart';
import '../domain/med_schedule.dart';
import '../../../shared/widgets/prescription_style.dart';
import '../domain/prescription_import.dart';
import '../state/medication_providers.dart';
import '../../orders/presentation/order_widgets.dart';

/// Fig 4.3.5.1 Medications (FR-5.1, FR-5.2, FR-5.3, FR-5.4; UC5.2, UC5.3, UC5.5).
class MedicationsPage extends ConsumerStatefulWidget {
  const MedicationsPage({super.key});

  @override
  ConsumerState<MedicationsPage> createState() => _MedicationsPageState();
}

class _MedicationsPageState extends ConsumerState<MedicationsPage> {
  Timer? _tick;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    // Upcoming doses become "Take" an hour before their time.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => ref.invalidate(todaysDosesProvider));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _confirm(Medication med, {DateTime? scheduledTime}) async {
    final key = '${med.id}@$scheduledTime';
    setState(() => _busy.add(key));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final late = await ref
          .read(medicationsRepositoryProvider)
          .confirmDose(med.id, scheduledTime: scheduledTime);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            late ? '${med.name} recorded as taken late.' : '${med.name} dose recorded.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'DOSE_ALREADY_LOGGED' ? 'That dose is already recorded.' : e.message,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not record the dose. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final meds = ref.watch(medicationsProvider);
    final doses = ref.watch(todaysDosesProvider);
    final now = ref.watch(nowProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Meds')),
      floatingActionButton: FloatingActionButton(
        key: const Key('add-medication'),
        tooltip: 'Add medication',
        onPressed: () => context.push('/medications/add'),
        child: const Icon(Icons.add),
      ),
      body: meds.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Message(
          icon: Icons.cloud_off,
          text: 'Could not load your medications.',
          action: TextButton(
            onPressed: () => ref.invalidate(medicationsProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (list) {
          final prescriptions = ref.watch(myPrescriptionsProvider).value ?? const <Prescription>[];
          if (list.isEmpty && prescriptions.isEmpty) {
            return _Message(
              key: const Key('meds-empty'),
              icon: Icons.medication_outlined,
              text: 'No medications yet. Tap + to add your first one and get reminders.',
              action: TextButton(
                key: const Key('record-prescription'),
                onPressed: () => context.push('/medications/prescription'),
                child: const Text('Record a prescription from another clinic'),
              ),
            );
          }
          final scheduled = doses.value ?? const <ScheduledDose>[];
          final prn = [
            for (final m in list)
              if (tryParseSchedule(m.schedule) == null) m,
          ];
          final refills = [
            for (final m in list)
              if (needsRefill(m)) m,
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _ScheduleHeader(now: now),
              const MonthlyOrdersBanner(), // UC13.2 (D-66)
              if (scheduled.isNotEmpty) const _ReminderStatusLine(),
              if (scheduled.isNotEmpty) const _ExactRemindersBanner(),
              if (scheduled.isNotEmpty) const _BackgroundBanner(),
              if (scheduled.isNotEmpty) _ProgressCard(doses: scheduled),
              for (final period in DosePeriod.values.where((p) => p != DosePeriod.asNeeded))
                if (scheduled.any((d) => d.period == period)) ...[
                  _PeriodHeader(period: period),
                  for (final d in scheduled.where((d) => d.period == period))
                    _DoseTile(
                      dose: d,
                      busy: _busy.contains('${d.medication.id}@${d.moment}'),
                      onTake: () => _confirm(d.medication, scheduledTime: d.moment),
                    ),
                ],
              if (prn.isNotEmpty) ...[
                const _PeriodHeader(period: DosePeriod.asNeeded),
                for (final m in prn)
                  _AsNeededTile(
                    med: m,
                    busy: _busy.contains('${m.id}@null'),
                    onLog: () => _confirm(m),
                  ),
              ],
              if (refills.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Action needed', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final m in refills) _RefillCard(med: m),
              ],
              const SizedBox(height: 16),
              if (list.isNotEmpty) ...[
                Text('Your medicines', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final m in list) _MedicineTile(med: m),
              ] else
                const Text('No medicines on your reminder list yet.'),
              const SizedBox(height: 16),
              Text('Prescriptions', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final p in prescriptions)
                _PrescriptionTile(
                  prescription: p,
                  tracked: alreadyTracked(p.medicationDetails, list.map((m) => m.name)),
                ),
              // D-50: prescriptions from other clinics, shown in green.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('record-prescription'),
                  onPressed: () => context.push('/medications/prescription'),
                  icon: const Icon(Icons.add),
                  label: const Text('Record a prescription from another clinic'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// What the phone actually scheduled, or why it couldn't (never fail silently).
class _ReminderStatusLine extends ConsumerWidget {
  const _ReminderStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(reminderStatusProvider);
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    Widget problem(String key, String text) => Row(
      key: Key(key),
      children: [
        Expanded(
          child: Text(text, style: small?.copyWith(color: scheme.error)),
        ),
        TextButton(
          key: const Key('reminders-retry'),
          onPressed: () {
            final meds = ref.read(reminderMedicationsProvider);
            if (meds != null) syncReminders(ref, meds);
          },
          child: const Text('Try again'),
        ),
      ],
    );
    return switch (status) {
      AsyncError(:final error) => problem(
        'reminders-failed',
        'Phone reminders could not be set: $error',
      ),
      AsyncData(:final value) when value.errors.isNotEmpty => problem(
        'reminders-partial',
        'Some reminders could not be set:\n${value.errors.join('\n')}',
      ),
      AsyncData(:final value) => Padding(
        key: const Key('reminders-ok'),
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(Icons.alarm_on, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value.scheduled.isEmpty
                    ? 'No phone reminders set.'
                    : 'Phone reminders set${value.exact ? '' : ' (may be a few minutes late)'}: '
                          '${value.scheduled.join(', ')}',
                style: small,
              ),
            ),
          ],
        ),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// D-43: without Android's "Alarms & reminders" permission, reminders may arrive late.
class _ExactRemindersBanner extends ConsumerWidget {
  const _ExactRemindersBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(exactRemindersAllowedProvider).value != false) return const SizedBox.shrink();
    return Card(
      key: const Key('exact-reminders-banner'),
      child: ListTile(
        leading: const Icon(Icons.alarm_off_outlined),
        title: const Text('Reminders may arrive late'),
        subtitle: const Text('Allow "Alarms & reminders" so CareFlow reminds you on time.'),
        trailing: TextButton(
          key: const Key('allow-exact-reminders'),
          onPressed: () async {
            final reminders = ref.read(doseRemindersProvider);
            await reminders.requestExact();
            ref.invalidate(exactRemindersAllowedProvider);
            // Re-schedule so existing reminders use the new precision.
            final meds = ref.read(reminderMedicationsProvider);
            if (meds != null) await syncReminders(ref, meds);
          },
          child: const Text('Allow'),
        ),
      ),
    );
  }
}

/// Phones that save battery aggressively (Honor, Xiaomi) can hold reminders back.
class _BackgroundBanner extends ConsumerWidget {
  const _BackgroundBanner();

  Future<void> _phoneSteps(BuildContext context, WidgetRef ref) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('background-steps'),
        title: const Text('Keep reminders on time'),
        content: const Text(
          'In the settings page that opens:\n\n'
          'Honor / Huawei: Battery → App launch → CareFlow → turn off "Manage '
          'automatically", then turn on Auto-launch, Secondary launch and Run in background.\n\n'
          'Xiaomi / Redmi: turn on Autostart and set Battery saver to "No restrictions".\n\n'
          'Other phones: set Battery to "Unrestricted".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('open-phone-settings'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (open == true) await ref.read(backgroundAccessProvider).openSettings();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(backgroundPromptProvider).value != true) return const SizedBox.shrink();
    final access = ref.read(backgroundAccessProvider);
    return Card(
      key: const Key('background-banner'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.battery_alert_outlined),
                SizedBox(width: 12),
                Expanded(child: Text('Let CareFlow run in the background')),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Battery saving on some phones stops medicine reminders.'),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  key: const Key('background-not-now'),
                  onPressed: () async {
                    await access.dismiss();
                    ref.invalidate(backgroundPromptProvider);
                  },
                  child: const Text('Not now'),
                ),
                TextButton(
                  key: const Key('background-phone-settings'),
                  onPressed: () => _phoneSteps(context, ref),
                  child: const Text('Phone settings'),
                ),
                FilledButton.tonal(
                  key: const Key('background-allow'),
                  onPressed: () async {
                    await access.request();
                    ref.invalidate(backgroundPromptProvider);
                  },
                  child: const Text('Allow'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// D-49/D-50: a prescription (doctor-issued blue, patient-reported green) that the
/// patient can copy into their reminders; their own ones open for editing.
class _PrescriptionTile extends StatelessWidget {
  const _PrescriptionTile({required this.prescription, required this.tracked});

  final Prescription prescription;
  final bool tracked;

  @override
  Widget build(BuildContext context) {
    final p = prescription;
    final issued = toMyt(p.issuedAt);
    final color = prescriptionColor(p);
    final theme = Theme.of(context);
    // Text gets the full width; the action sits on its own row so long names never wrap
    // letter by letter.
    return Card(
      key: Key('rx-${p.id}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: p.byPatient ? () => context.push('/medications/prescription', extra: p) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(
                      p.byPatient ? Icons.edit_note : Icons.receipt_long_outlined,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.medicationDetails, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '${p.byPatient ? 'Recorded' : 'Prescribed'} ${issued.day} '
                          '${_months[issued.month - 1]} ${issued.year}'
                          '${p.isRecurring ? ' • repeats monthly' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Chip left, action right; on narrow phones the action wraps below.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    PrescriptionSourceChip(prescription: p, forDoctor: false),
                    if (tracked)
                      const Chip(label: Text('On your list'))
                    else
                      TextButton.icon(
                        key: Key('rx-add-${p.id}'),
                        onPressed: () => context.push(
                          '/medications/add',
                          extra: draftFromPrescription(p.medicationDetails),
                        ),
                        icon: const Icon(Icons.alarm_add_outlined, size: 18),
                        label: const Text('Add to my reminders'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

String _clock(DateTime instant) {
  final l = toMyt(instant);
  return DoseTime(l.hour, l.minute).label;
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = toMyt(now);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text("Today's Schedule", style: theme.textTheme.titleMedium)),
          Text(
            '${_weekdays[l.weekday - 1]}, ${_months[l.month - 1]} ${l.day}',
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.doses});

  final List<ScheduledDose> doses;

  @override
  Widget build(BuildContext context) {
    final taken = doses.where((d) => d.state == DoseState.taken).length;
    final left = doses.length - taken;
    final scheme = Theme.of(context).colorScheme;
    final text = left == 0
        ? 'All done for today. Well done!'
        : taken == 0
        ? '$left ${left == 1 ? 'dose' : 'doses'} to take today.'
        : 'Great progress! $left ${left == 1 ? 'dose' : 'doses'} left for today.';
    return Card(
      key: const Key('meds-progress'),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.surface,
              child: Text('$taken/${doses.length}', style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(text, style: TextStyle(color: scheme.onPrimaryContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.period});

  final DosePeriod period;

  @override
  Widget build(BuildContext context) {
    final icon = switch (period) {
      DosePeriod.morning => Icons.wb_sunny_outlined,
      DosePeriod.afternoon => Icons.wb_cloudy_outlined,
      DosePeriod.evening => Icons.nightlight_outlined,
      DosePeriod.asNeeded => Icons.water_drop_outlined,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(period.label.toUpperCase(), style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({required this.dose, required this.busy, required this.onTake});

  final ScheduledDose dose;
  final bool busy;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final med = dose.medication;
    final scheme = Theme.of(context).colorScheme;
    final taken = dose.state == DoseState.taken;
    final Widget? trailing = switch (dose.state) {
      // The taken time sits under the dose (below) so the name keeps its full width.
      DoseState.taken => null,
      // D-49: a missed dose can still be recorded as taken late until midnight.
      DoseState.missed =>
        busy
            ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator())
            : OutlinedButton(
                key: Key('late-${med.id}-${dose.time.hhmm}'),
                style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                onPressed: onTake,
                child: const Text('Took it late'),
              ),
      DoseState.upcoming => const Text('Upcoming'),
      DoseState.due =>
        busy
            ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator())
            : FilledButton(
                key: Key('take-${med.id}-${dose.time.hhmm}'),
                onPressed: onTake,
                child: const Text('Take'),
              ),
    };
    return Card(
      key: Key('dose-${med.id}-${dose.time.hhmm}'),
      child: ListTile(
        leading: CircleAvatar(child: Icon(taken ? Icons.check_circle : Icons.medication_outlined)),
        title: Text(
          med.name,
          style: taken ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${med.dosage} • ${dose.time.label}'
              '${dose.state == DoseState.missed ? ' • Missed' : ''}',
            ),
            if (med.fromDoctor) // D-69: set by the doctor (locked)
              Text(
                'From ${med.prescribedBy ?? 'your doctor'}',
                key: Key('from-doctor-${med.id}'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (taken)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  dose.confirmedAt == null
                      ? 'Taken'
                      : '${dose.isLate ? 'Taken late' : 'Taken'} at ${_clock(dose.confirmedAt!)}',
                  key: Key('taken-${med.id}-${dose.time.hhmm}'),
                  style: TextStyle(
                    color: dose.isLate ? Colors.orange.shade800 : scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        trailing: trailing,
      ),
    );
  }
}

class _AsNeededTile extends ConsumerWidget {
  const _AsNeededTile({required this.med, required this.busy, required this.onLog});

  final Medication med;
  final bool busy;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(todaysDoseLogsProvider(med.id)).value ?? const <DoseLog>[];
    final last = logs.isEmpty ? null : logs.first.confirmedAt ?? logs.first.scheduledTime;
    return Card(
      key: Key('prn-${med.id}'),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.healing_outlined)),
        title: Text(med.name),
        subtitle: Text(
          last == null
              ? med.dosage
              : '${med.dosage} • taken ${logs.length}× today, last at ${_clock(last)}',
        ),
        trailing: busy
            ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator())
            : FilledButton.tonal(
                key: Key('log-${med.id}'),
                onPressed: onLog,
                child: const Text('Log dose'),
              ),
      ),
    );
  }
}

class _RefillCard extends ConsumerWidget {
  const _RefillCard({required this.med});

  final Medication med;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final days = daysOfSupply(med)!.floor();
    final doctorId = ref.watch(currentUserProvider).value?.assignedDoctorId;
    return Card(
      key: Key('refill-${med.id}'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Refill required\n${med.name} (${med.dosage})',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
                Chip(label: Text(days == 1 ? '1 day left' : '$days days left')),
              ],
            ),
            const SizedBox(height: 12),
            // Until Module 13 (pharmacy orders), a refill request goes to the doctor (D-43).
            FilledButton(
              key: Key('request-refill-${med.id}'),
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: doctorId == null || doctorId.trim().isEmpty
                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No doctor is assigned to you yet, so a refill '
                          'cannot be requested in the app.',
                        ),
                      ),
                    )
                  : () => context.push(
                      '/chat/${doctorId.trim()}',
                      extra:
                          'Hello doctor, I am running low on ${med.name} ${med.dosage} '
                          '(about $days days left). Could you please renew my prescription?',
                    ),
              child: const Text('Request refill from doctor'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicineTile extends StatelessWidget {
  const _MedicineTile({required this.med});

  final Medication med;

  @override
  Widget build(BuildContext context) {
    final scheduled = tryParseSchedule(med.schedule) != null;
    final rate = med.adherenceRate;
    // UC5.5 E1: no doses logged yet -> no rate.
    final adherence = !scheduled
        ? 'As needed'
        : rate == null
        ? 'Adherence: no history yet'
        : 'Adherence (30 days): ${rate.toStringAsFixed(0)}%';
    final stock = med.quantityOnHand == null
        ? ''
        : ' • ${med.quantityOnHand!.toStringAsFixed(0)} left';
    return Card(
      key: Key('medicine-${med.id}'),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.medication)),
        title: Text('${med.name} ${med.dosage}'.trim()),
        subtitle: Text('${describeSchedule(med.schedule)}\n$adherence$stock'),
        isThreeLine: true,
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => context.push('/medications/edit', extra: med),
      ),
    );
  }
}
