import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';
import '../../auth/state/auth_providers.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../medications/domain/med_schedule.dart';
import '../../provider_portal/domain/portal_models.dart';
import '../../provider_portal/state/portal_providers.dart';
import '../domain/appointment_text.dart';
import '../state/appointment_providers.dart';
import 'pre_visit_summary_page.dart';

enum CalendarView { month, week, day }

/// Fig 4.3.12.3 Doctor schedule (FR-7.1, FR-7.4): monthly / weekly / daily, coloured by
/// type (D-53). Cancelled appointments are hidden.
class DoctorCalendarPage extends ConsumerStatefulWidget {
  const DoctorCalendarPage({super.key});

  @override
  ConsumerState<DoctorCalendarPage> createState() => _DoctorCalendarPageState();
}

class _DoctorCalendarPageState extends ConsumerState<DoctorCalendarPage> {
  CalendarView _view = CalendarView.month;
  late DateTime _anchor = _today();

  DateTime _today() {
    final l = toMyt(ref.read(nowProvider)());
    return DateTime(l.year, l.month, l.day);
  }

  /// [start, end) of the visible range, as Malaysian calendar dates.
  (DateTime, DateTime) get _range => switch (_view) {
    CalendarView.month => (
      DateTime(_anchor.year, _anchor.month),
      DateTime(_anchor.year, _anchor.month + 1),
    ),
    CalendarView.week => (
      _anchor.subtract(Duration(days: _anchor.weekday % 7)),
      _anchor.subtract(Duration(days: _anchor.weekday % 7)).add(const Duration(days: 7)),
    ),
    CalendarView.day => (_anchor, _anchor.add(const Duration(days: 1))),
  };

  /// Malaysian midnight as a UTC instant.
  static DateTime _utc(DateTime mytDate) =>
      DateTime.utc(mytDate.year, mytDate.month, mytDate.day).subtract(mytOffset);

  void _move(int step) => setState(() {
    _anchor = switch (_view) {
      CalendarView.month => DateTime(_anchor.year, _anchor.month + step),
      CalendarView.week => _anchor.add(Duration(days: 7 * step)),
      CalendarView.day => _anchor.add(Duration(days: step)),
    };
  });

  String get _title => switch (_view) {
    CalendarView.month => monthLabel(_anchor.year, _anchor.month),
    CalendarView.week => 'Week of ${dateLabel(_utc(_range.$1).add(const Duration(hours: 12)))}',
    CalendarView.day => dateLabel(_utc(_anchor).add(const Duration(hours: 12))),
  };

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authUidProvider).value;
    if (uid == null) return const Center(child: CircularProgressIndicator());
    final (start, end) = _range;
    final appts = ref.watch(doctorAppointmentsProvider((uid, _utc(start), _utc(end))));
    final names = <String, String>{
      for (final p in ref.watch(assignedPatientsProvider).value ?? const <PortalPatient>[])
        p.uid: p.name,
    };
    final list = [
      for (final a in appts.value ?? const <Appointment>[])
        if (a.status != AppointmentStatus.cancelled) a,
    ];
    final emergencies = list.where((a) => a.type == AppointmentType.emergency).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  key: const Key('calendar-title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${list.length} scheduled appointments · $emergencies '
                  '${emergencies == 1 ? 'emergency' : 'emergencies'}',
                  key: const Key('calendar-counts'),
                ),
              ],
            ),
            SegmentedButton<CalendarView>(
              key: const Key('calendar-view'),
              segments: const [
                ButtonSegment(value: CalendarView.month, label: Text('Monthly')),
                ButtonSegment(value: CalendarView.week, label: Text('Weekly')),
                ButtonSegment(value: CalendarView.day, label: Text('Daily')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('calendar-prev'),
                  onPressed: () => _move(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton(
                  onPressed: () => setState(() => _anchor = _today()),
                  child: const Text('Today'),
                ),
                IconButton(
                  key: const Key('calendar-forward'),
                  onPressed: () => _move(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          children: [
            for (final t in AppointmentType.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 10, color: appointmentColor(t)),
                  const SizedBox(width: 4),
                  Text(t.label),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (appts.hasError) const Text('Could not load appointments.'),
        switch (_view) {
          CalendarView.month => _MonthGrid(
            month: _anchor,
            appointments: list,
            names: names,
            onDay: (d) => setState(() {
              _anchor = d;
              _view = CalendarView.day;
            }),
          ),
          _ => _AgendaList(appointments: list, names: names),
        },
      ],
    );
  }
}

DateTime _mytDay(DateTime instant) {
  final l = toMyt(instant);
  return DateTime(l.year, l.month, l.day);
}

String _short(String? name) {
  if (name == null || name.trim().isEmpty) return 'Patient';
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.length == 1 ? parts.first : '${parts.first[0]}. ${parts.last}';
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.appointments,
    required this.names,
    required this.onDay,
  });

  final DateTime month;
  final List<Appointment> appointments;
  final Map<String, String> names;
  final ValueChanged<DateTime> onDay;

  @override
  Widget build(BuildContext context) {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final lead = DateTime(month.year, month.month).weekday % 7;
    final byDay = <DateTime, List<Appointment>>{};
    for (final a in appointments) {
      byDay.putIfAbsent(_mytDay(a.dateTime), () => []).add(a);
    }
    return Column(
      children: [
        Row(
          children: [
            for (final d in const ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'])
              Expanded(
                child: Center(child: Text(d, style: Theme.of(context).textTheme.labelSmall)),
              ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.9,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var day = 1; day <= days; day++)
              Builder(
                builder: (context) {
                  final d = DateTime(month.year, month.month, day);
                  final items = byDay[d] ?? const [];
                  return InkWell(
                    key: Key('cal-day-$day'),
                    onTap: () => onDay(d),
                    child: Card(
                      margin: const EdgeInsets.all(2),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$day'),
                            for (final a in items.take(3))
                              _Chip(
                                appointment: a,
                                text: '${timeLabel(a.dateTime)} ${_short(names[a.patientId])}',
                              ),
                            if (items.length > 3)
                              Text(
                                '+${items.length - 3} more',
                                style: const TextStyle(fontSize: 10),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.appointment, required this.text});

  final Appointment appointment;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = appointmentColor(appointment.type);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10),
      ),
    );
  }
}

class _AgendaList extends StatelessWidget {
  const _AgendaList({required this.appointments, required this.names});

  final List<Appointment> appointments;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No appointments in this period.')),
      );
    }
    // Group by Malaysian date, keeping time order.
    final days = <DateTime, List<Appointment>>{};
    for (final a in appointments) {
      days.putIfAbsent(_mytDay(a.dateTime), () => []).add(a);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final MapEntry(key: day, value: items) in days.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              dateLabel(items.first.dateTime),
              key: Key('agenda-day-${day.day}'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final a in items)
            Card(
              key: Key('agenda-${a.id}'),
              child: ListTile(
                leading: Container(width: 6, height: 40, color: appointmentColor(a.type)),
                title: Text('${timeLabel(a.dateTime)} · ${names[a.patientId] ?? 'Patient'}'),
                subtitle: Text(
                  '${a.type.label}${a.status == AppointmentStatus.completed ? ' · completed' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAppointmentDetails(context, a, names[a.patientId]),
              ),
            ),
        ],
      ],
    );
  }
}

/// Doctor taps an appointment: pre-visit summary (UC7.5) + open the patient.
void showAppointmentDetails(BuildContext context, Appointment a, String? patientName) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      key: const Key('appointment-details'),
      title: Text('${patientName ?? 'Patient'} · ${a.type.label}'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${dateLabel(a.dateTime)}, ${timeLabel(a.dateTime)} · ${a.status.value}'),
            const Divider(),
            Expanded(child: PreVisitSummaryView(appointmentId: a.id)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: () {
            Navigator.of(c).pop();
            context.go('/doctor/patient/${a.patientId}');
          },
          child: const Text('Open patient'),
        ),
      ],
    ),
  );
}
