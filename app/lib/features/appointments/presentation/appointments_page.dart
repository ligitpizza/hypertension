import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';
import '../../../shared/services/api/api_client.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../medications/domain/med_schedule.dart';
import '../data/appointments_repository.dart';
import '../domain/appointment_text.dart';
import '../state/appointment_providers.dart';
import 'change_reason_dialog.dart';

/// Fig 4.3.6.1 Appointments (FR-7.1, FR-7.4; UC7.1, UC7.2, UC7.5; D-53, D-54).
/// With [rescheduling], the same screen picks a new time for that appointment.
class AppointmentsPage extends ConsumerStatefulWidget {
  const AppointmentsPage({super.key, this.rescheduling});

  final Appointment? rescheduling;

  @override
  ConsumerState<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends ConsumerState<AppointmentsPage> {
  late DateTime _day = _firstSelectableDay(ref.read(nowProvider)());
  String _period = 'morning';
  DateTime? _slot;
  late AppointmentType _type = widget.rescheduling?.type ?? AppointmentType.checkup;
  bool _busy = false;
  List<DateTime> _alternatives = const [];

  bool get _rescheduling => widget.rescheduling != null;

  /// Today (Malaysia), or the next weekday if today is a weekend.
  static DateTime _firstSelectableDay(DateTime now) {
    final l = toMyt(now);
    var d = DateTime(l.year, l.month, l.day);
    while (d.weekday > 5) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  void _pickDay(DateTime d) => setState(() {
    _day = d;
    _slot = null;
    _alternatives = const [];
  });

  void _useAlternative(DateTime t) {
    final l = toMyt(t);
    setState(() {
      _day = DateTime(l.year, l.month, l.day);
      _period = l.hour < 12 ? 'morning' : (l.hour < 17 ? 'afternoon' : 'evening');
      _slot = t;
      _alternatives = const [];
    });
  }

  /// D-57 testing aid: any Malaysia date and time, picked freely.
  Future<void> _pickAnyTime() async {
    final now = toMyt(ref.read(nowProvider)());
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today.subtract(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: now.hour, minute: now.minute),
    );
    if (time == null) return;
    setState(() {
      _slot = DateTime.utc(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).subtract(mytOffset);
      _alternatives = const [];
    });
  }

  Future<void> _submit() async {
    final slot = _slot;
    if (slot == null) return;
    final repo = ref.read(appointmentsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final old = widget.rescheduling;
    (String, String?)? reason;
    if (old != null) {
      if (isLateChange(old.dateTime, ref.read(nowProvider)()) &&
          !await _confirmLateChange(context, 'reschedule')) {
        return;
      }
      if (!mounted) return;
      reason = await askChangeReason(context, title: 'Why do you need to reschedule?');
      if (reason == null) return;
    }
    setState(() => _busy = true);
    try {
      if (old != null) {
        // D-55: a request; the doctor approves it (the new time is held meanwhile).
        await repo.requestReschedule(old.id, slot, reason!.$1, note: reason.$2);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Request sent: ${whenLabel(slot, ref.read(nowProvider)())}. '
              'Your doctor will confirm.',
            ),
          ),
        );
        context.pop();
      } else {
        final id = await repo.book(slot, _type);
        if (!mounted) return;
        context.go('/appointments/booked/$id');
      }
    } on ActiveAppointmentException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on SlotTakenException catch (e) {
      ref.invalidate(daySlotsProvider(_day));
      setState(() {
        _slot = null;
        _alternatives = e.alternatives;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('That time was just taken. Please choose another.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not book. Please check your connection.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider)();
    final theme = Theme.of(context);
    final slots = ref.watch(daySlotsProvider(_day));
    // D-56: one active appointment at a time; rescheduling it is still allowed.
    final current = _rescheduling ? null : ref.watch(myActiveAppointmentProvider).value;
    return Scaffold(
      appBar: AppBar(
        // Reached by go() after booking too, so there may be nothing to pop: then go home.
        leading: BackButton(
          key: const Key('appointments-back'),
          onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: Text(_rescheduling ? 'Choose a new time' : 'Appointments'),
        actions: [
          if (!_rescheduling)
            TextButton(
              key: const Key('appointments-history'),
              onPressed: () => context.push('/appointments/history'),
              child: const Text('History'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          if (_rescheduling)
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_repeat),
                title: const Text('Current time'),
                subtitle: Text(whenLabel(widget.rescheduling!.dateTime, now)),
              ),
            )
          else ...[
            Text('Next appointment', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const _NextAppointment(),
            const SizedBox(height: 24),
            Text('Book new appointment', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
          ],
          if (current != null)
            _OneAtATime(appointment: current, now: now)
          else
            slots.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => e is NoDoctorException
                  ? const _NoDoctorCard()
                  : _Problem(onRetry: () => ref.invalidate(daySlotsProvider(_day))),
              data: (day) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'With ${day.doctor.name}${day.doctor.specialty == null ? '' : ' · ${day.doctor.specialty}'}',
                    key: const Key('booking-doctor'),
                  ),
                  const SizedBox(height: 8),
                  _MonthCalendar(
                    selected: _day,
                    first: _firstSelectableDay(now),
                    last: toMyt(now).add(const Duration(days: 60)),
                    onSelect: _pickDay,
                  ),
                  if (!_rescheduling) ...[
                    const SizedBox(height: 16),
                    SegmentedButton<AppointmentType>(
                      key: const Key('appointment-type'),
                      segments: const [
                        ButtonSegment(value: AppointmentType.checkup, label: Text('Checkup')),
                        ButtonSegment(value: AppointmentType.followUp, label: Text('Follow-up')),
                      ],
                      selected: {
                        _type == AppointmentType.emergency ? AppointmentType.checkup : _type,
                      },
                      onSelectionChanged: (s) => setState(() => _type = s.first),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text('Available times', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final p in const ['morning', 'afternoon', 'evening'])
                        ChoiceChip(
                          key: Key('period-$p'),
                          label: Text(p[0].toUpperCase() + p.substring(1)),
                          selected: _period == p,
                          onSelected: (_) => setState(() => _period = p),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _SlotGrid(
                    slots: [
                      for (final s in day.slots)
                        if (s.period == _period) s,
                    ],
                    selected: _slot,
                    onSelect: (t) => setState(() => _slot = t),
                  ),
                  if (day.customTimes)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        key: const Key('pick-any-time'),
                        icon: const Icon(Icons.bug_report_outlined),
                        onPressed: _pickAnyTime,
                        label: const Text('Pick any time (testing)'),
                      ),
                    ),
                  if (day.slots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('The clinic is closed on this day.'),
                    ),
                  if (day.alternatives.isNotEmpty || _alternatives.isNotEmpty)
                    _Alternatives(
                      times: _alternatives.isNotEmpty ? _alternatives : day.alternatives,
                      now: now,
                      onPick: _useAlternative,
                    ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: slots.hasValue && current == null
          ? SafeArea(
              minimum: const EdgeInsets.all(16),
              child: FilledButton.icon(
                key: const Key('book-appointment'),
                onPressed: _slot == null || _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator())
                    : const Icon(Icons.event_available),
                label: Text(
                  _slot == null
                      ? 'Choose a time'
                      : '${_rescheduling ? 'Reschedule to' : 'Book'} ${whenLabel(_slot!, now)}',
                ),
              ),
            )
          : null,
    );
  }
}

/// UC7.2 E1: changes under 24 hours ahead need an extra confirmation.
Future<bool> _confirmLateChange(BuildContext context, String what) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('late-change-warning'),
        title: Text('$what within 24 hours?'.replaceFirst(what[0], what[0].toUpperCase())),
        content: const Text(
          'Your appointment is less than 24 hours away. Your doctor may already have prepared '
          'for it. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Keep it')),
          FilledButton(
            key: const Key('late-change-continue'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
    false;

/// UC7.2 / D-55: a cancellation request with a reason (after the < 24 h warning).
/// Returns true when a request was sent or the appointment was cancelled.
Future<bool> cancelAppointment(BuildContext context, WidgetRef ref, Appointment a) async {
  if (isLateChange(a.dateTime, ref.read(nowProvider)()) &&
      !await _confirmLateChange(context, 'cancel')) {
    return false;
  }
  if (!context.mounted) return false;
  final reason = await askChangeReason(context, title: 'Why do you need to cancel?');
  if (reason == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final cancelledNow = await ref
        .read(appointmentsRepositoryProvider)
        .requestCancel(a.id, reason.$1, note: reason.$2);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          cancelledNow
              ? 'Appointment cancelled.'
              : 'Cancellation request sent. Your doctor will confirm.',
        ),
      ),
    );
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not send. Please try again.')));
    return false;
  }
}

Future<void> _withdraw(BuildContext context, WidgetRef ref, Appointment a) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(appointmentsRepositoryProvider).withdrawRequest(a.id);
    messenger.showSnackBar(const SnackBar(content: Text('Request withdrawn.')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not withdraw. Please try again.')));
  }
}

class _NextAppointment extends ConsumerWidget {
  const _NextAppointment();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider)();
    final list = ref.watch(myUpcomingAppointmentsProvider).value ?? const <Appointment>[];
    final next = list.where((a) => a.isActive && a.dateTime.isAfter(now)).firstOrNull;
    if (next == null) {
      return const Card(
        key: Key('no-next-appointment'),
        child: ListTile(
          leading: Icon(Icons.event_available_outlined),
          title: Text('No upcoming appointment'),
          subtitle: Text('Book one below.'),
        ),
      );
    }
    return AppointmentCard(appointment: next, now: now);
  }
}

/// Next-appointment card (Fig 4.3.6.1 top / Fig 4.3.6.2 details).
class AppointmentCard extends ConsumerWidget {
  const AppointmentCard({super.key, required this.appointment, required this.now});

  final Appointment appointment;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = appointment;
    final scheme = Theme.of(context).colorScheme;
    final doctor = a.doctorId == null ? null : ref.watch(personProvider(a.doctorId!)).value;
    final color = appointmentColor(a.type);
    return Card(
      key: Key('appointment-${a.id}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${a.status == AppointmentStatus.rescheduled ? 'Rescheduled' : 'Upcoming'} · '
              '${whenLabel(a.dateTime, now)}',
              style: TextStyle(color: scheme.primary),
            ),
            const SizedBox(height: 4),
            Text(doctor?.name ?? 'Your doctor', style: Theme.of(context).textTheme.titleLarge),
            Text('${a.type.label} · $clinicName'),
            const SizedBox(height: 12),
            ListTile(
              key: Key('summary-${a.id}'),
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.assignment_outlined)),
              title: const Text('Pre-visit summary'),
              subtitle: const Text('Review your recent vitals before the visit.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/appointments/${a.id}/summary'),
            ),
            if (a.pendingChange != null)
              _PendingBanner(appointment: a, now: now)
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('reschedule-${a.id}'),
                      onPressed: () => context.push('/appointments/reschedule', extra: a),
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: const Text('Reschedule'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('cancel-${a.id}'),
                      style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                      onPressed: () => cancelAppointment(context, ref, a),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// D-56: booking is closed while an appointment is active.
class _OneAtATime extends StatelessWidget {
  const _OneAtATime({required this.appointment, required this.now});

  final Appointment appointment;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final past = !now.isBefore(appointment.dateTime);
    return Card(
      key: const Key('one-at-a-time'),
      child: ListTile(
        leading: const Icon(Icons.event_busy_outlined),
        title: Text('You already have an appointment: ${whenLabel(appointment.dateTime, now)}'),
        subtitle: Text(
          past
              ? 'You can book a new one once your doctor has closed this visit.'
              : 'You can book a new one after this visit. To change the time, use '
                    'Reschedule above.',
        ),
      ),
    );
  }
}

/// D-55: what the patient asked for, waiting for the doctor; can be withdrawn.
class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({required this.appointment, required this.now});

  final Appointment appointment;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = appointment.pendingChange!;
    final text = p.isCancel
        ? 'Cancellation requested'
        : 'Move to ${whenLabel(p.dateTime!, now)} requested';
    return Card(
      key: Key('pending-${appointment.id}'),
      color: Colors.amber.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$text · waiting for your doctor'),
            Text('Reason: ${p.reasonText}', style: Theme.of(context).textTheme.bodySmall),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key('withdraw-${appointment.id}'),
                onPressed: () => _withdraw(context, ref, appointment),
                child: const Text('Withdraw request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// D-54: no doctor yet -> request one; show when a request is waiting.
class _NoDoctorCard extends ConsumerStatefulWidget {
  const _NoDoctorCard();

  @override
  ConsumerState<_NoDoctorCard> createState() => _NoDoctorCardState();
}

class _NoDoctorCardState extends ConsumerState<_NoDoctorCard> {
  bool _sending = false;

  Future<void> _request() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appointmentsRepositoryProvider).requestDoctor();
      messenger.showSnackBar(
        const SnackBar(content: Text('Request sent. The clinic will assign your doctor.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(myAssignmentRequestsProvider).value ?? const [];
    final pending = requests.any((r) => r.status == AssignmentRequestStatus.pending);
    return Card(
      key: const Key('no-doctor'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("You don't have a doctor yet"),
            const SizedBox(height: 4),
            Text(
              pending
                  ? 'Your request has been sent. The clinic will assign a doctor and let you know.'
                  : 'Ask the clinic to assign you a doctor. You can book once they have.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (pending)
              const Chip(key: Key('doctor-request-pending'), label: Text('Waiting for the clinic'))
            else
              FilledButton(
                key: const Key('request-doctor'),
                onPressed: _sending ? null : _request,
                child: const Text('Request a doctor'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.cloud_off),
      title: const Text('Could not load available times.'),
      trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
    ),
  );
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.slots, required this.selected, required this.onSelect});

  final List<Slot> slots;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) return const SizedBox.shrink();
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.6,
      children: [
        for (final s in slots)
          ChoiceChip(
            key: Key('slot-${timeLabel(s.time)}'),
            label: SizedBox(
              width: double.infinity,
              child: Text(timeLabel(s.time), textAlign: TextAlign.center),
            ),
            selected: s.time == selected,
            onSelected: s.available ? (_) => onSelect(s.time) : null,
          ),
      ],
    );
  }
}

class _Alternatives extends StatelessWidget {
  const _Alternatives({required this.times, required this.now, required this.onPick});

  final List<DateTime> times;
  final DateTime now;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('alternatives'),
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nearest available times'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final t in times)
              ActionChip(label: Text(whenLabel(t, now)), onPressed: () => onPick(t)),
          ],
        ),
      ],
    ),
  );
}

/// A simple month grid (Fig 4.3.6.1); weekends and out-of-range days are disabled.
class _MonthCalendar extends StatefulWidget {
  const _MonthCalendar({
    required this.selected,
    required this.first,
    required this.last,
    required this.onSelect,
  });

  final DateTime selected;
  final DateTime first;
  final DateTime last;
  final ValueChanged<DateTime> onSelect;

  @override
  State<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<_MonthCalendar> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);

  bool _enabled(DateTime d) =>
      d.weekday <= 5 &&
      !d.isBefore(DateTime(widget.first.year, widget.first.month, widget.first.day)) &&
      !d.isAfter(DateTime(widget.last.year, widget.last.month, widget.last.day));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final lead = DateTime(_month.year, _month.month).weekday % 7; // Sunday first
    final canBack = DateTime(
      _month.year,
      _month.month,
    ).isAfter(DateTime(widget.first.year, widget.first.month));
    final canForward = DateTime(
      _month.year,
      _month.month + 1,
    ).isBefore(DateTime(widget.last.year, widget.last.month + 1));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    monthLabel(_month.year, _month.month),
                    key: const Key('calendar-month'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: canBack
                      ? () => setState(() => _month = DateTime(_month.year, _month.month - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  key: const Key('calendar-next'),
                  tooltip: 'Next month',
                  onPressed: canForward
                      ? () => setState(() => _month = DateTime(_month.year, _month.month + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final d in const ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'])
                  Expanded(
                    child: Center(child: Text(d, style: Theme.of(context).textTheme.labelSmall)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                for (var day = 1; day <= days; day++)
                  Builder(
                    builder: (context) {
                      final d = DateTime(_month.year, _month.month, day);
                      final selected = DateUtils.isSameDay(d, widget.selected);
                      final enabled = _enabled(d);
                      return InkWell(
                        key: Key('day-${d.year}-${d.month}-${d.day}'),
                        customBorder: const CircleBorder(),
                        onTap: enabled ? () => widget.onSelect(d) : null,
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          alignment: Alignment.center,
                          decoration: selected
                              ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                              : null,
                          child: Text(
                            '$day',
                            style: TextStyle(
                              color: selected
                                  ? scheme.onPrimary
                                  : enabled
                                  ? null
                                  : scheme.onSurface.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// UC7.1 "History": past and cancelled appointments.
class AppointmentHistoryPage extends ConsumerWidget {
  const AppointmentHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final past = ref.watch(myAppointmentHistoryProvider).value ?? const <Appointment>[];
    final upcoming = ref.watch(myUpcomingAppointmentsProvider).value ?? const <Appointment>[];
    final cancelled = [
      for (final a in upcoming)
        if (a.status == AppointmentStatus.cancelled) a,
    ];
    final all = [...cancelled, ...past];
    final now = ref.watch(nowProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Appointment history')),
      body: all.isEmpty
          ? const Center(child: Text('No past appointments yet.'))
          : ListView(
              children: [
                for (final a in all)
                  ListTile(
                    key: Key('history-${a.id}'),
                    leading: Icon(Icons.circle, size: 12, color: appointmentColor(a.type)),
                    title: Text(whenLabel(a.dateTime, now)),
                    subtitle: Text(
                      '${a.type.label} · ${a.status.label}'
                      '${a.changeReason == null ? '' : ' · ${a.changeReason}'}',
                    ),
                    onTap: a.status == AppointmentStatus.cancelled
                        ? null
                        : () => context.push('/appointments/${a.id}/summary'),
                  ),
              ],
            ),
    );
  }
}
