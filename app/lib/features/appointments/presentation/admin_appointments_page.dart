import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../medications/domain/med_schedule.dart';
import '../domain/appointment_text.dart';
import '../state/appointment_providers.dart';
import 'appointment_details_dialog.dart';

/// Status filter for the admin overview (D-55). [requested] = a change awaiting a decision.
enum AppointmentFilter {
  all('All'),
  requested('Change requested'),
  booked('Booked'),
  rescheduled('Rescheduled'),
  cancelled('Cancelled'),
  completed('Completed');

  const AppointmentFilter(this.label);
  final String label;

  bool matches(Appointment a) => switch (this) {
    all => true,
    requested => a.pendingChange != null && !a.isCancelled,
    booked => a.status == AppointmentStatus.booked,
    rescheduled => a.status == AppointmentStatus.rescheduled,
    cancelled => a.isCancelled,
    completed => a.status == AppointmentStatus.completed,
  };
}

/// Admin: every doctor's appointments for one month, with filters; open one to decide a
/// pending request or cancel it with a reason (D-55).
class AdminAppointmentsPage extends ConsumerStatefulWidget {
  const AdminAppointmentsPage({super.key});

  @override
  ConsumerState<AdminAppointmentsPage> createState() => _AdminAppointmentsPageState();
}

class _AdminAppointmentsPageState extends ConsumerState<AdminAppointmentsPage> {
  late DateTime _month; // first day of the month, Malaysia date
  AppointmentFilter _filter = AppointmentFilter.all;
  String? _doctor;

  @override
  void initState() {
    super.initState();
    final today = toMyt(ref.read(nowProvider)());
    _month = DateTime.utc(today.year, today.month);
  }

  /// Malaysia midnight of the 1st -> UTC instant.
  DateTime _start(DateTime m) => DateTime.utc(m.year, m.month).subtract(mytOffset);

  @override
  Widget build(BuildContext context) {
    final next = DateTime.utc(_month.year, _month.month + 1);
    final appts = ref.watch(allAppointmentsProvider((_start(_month), _start(next))));
    final doctors = ref.watch(doctorsProvider).value ?? const [];
    final doctorNames = {for (final d in doctors) d.uid: d.name};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Appointments', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('All doctors. Open an appointment to decide a request or cancel it.'),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              key: const Key('admin-prev-month'),
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _month = DateTime.utc(_month.year, _month.month - 1)),
            ),
            Text(monthLabel(_month.year, _month.month), key: const Key('admin-month')),
            IconButton(
              key: const Key('admin-next-month'),
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _month = next),
            ),
            const SizedBox(width: 16),
            DropdownButton<String?>(
              key: const Key('admin-doctor-filter'),
              value: _doctor,
              hint: const Text('All doctors'),
              items: [
                const DropdownMenuItem(child: Text('All doctors')),
                for (final d in doctors) DropdownMenuItem(value: d.uid, child: Text(d.name)),
              ],
              onChanged: (v) => setState(() => _doctor = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        appts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('Could not load appointments.'),
          data: (all) {
            final ofDoctor = [
              for (final a in all)
                if (_doctor == null || a.doctorId == _doctor) a,
            ];
            final shown = [
              for (final a in ofDoctor)
                if (_filter.matches(a)) a,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in AppointmentFilter.values)
                      ChoiceChip(
                        key: Key('filter-${f.name}'),
                        label: Text('${f.label} (${ofDoctor.where(f.matches).length})'),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  const Card(
                    key: Key('no-appointments'),
                    child: ListTile(
                      leading: Icon(Icons.event_busy_outlined),
                      title: Text('No appointments match.'),
                    ),
                  )
                else
                  for (final a in shown) _Row(appointment: a, doctorName: doctorNames[a.doctorId]),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.appointment, this.doctorName});

  final Appointment appointment;
  final String? doctorName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = appointment;
    final patient = ref.watch(personProvider(a.patientId)).value?.name;
    final p = a.isCancelled ? null : a.pendingChange;
    final now = ref.watch(nowProvider)();
    final detail = a.isCancelled
        ? 'Cancelled${a.cancelledBy == null ? '' : ' by ${a.cancelledBy}'}'
              '${a.changeReason == null ? '' : ': ${a.changeReason}'}'
        : p != null
        ? '${p.isCancel ? 'Cancellation requested' : 'Move to ${whenLabel(p.dateTime!, now)} requested'}'
              ': ${p.reasonText}'
        : a.changeReason == null
        ? a.status.value
        : '${a.status.value} · ${a.changeReason}';
    return Card(
      key: Key('admin-appt-${a.id}'),
      color: p != null ? Colors.amber.withValues(alpha: 0.15) : null,
      child: ListTile(
        leading: Icon(Icons.circle, size: 12, color: appointmentColor(a.type)),
        title: Text(
          '${dateLabel(a.dateTime)}, ${timeLabel(a.dateTime)} · ${patient ?? '…'}',
          style: a.isCancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Text('${doctorName ?? 'Doctor'} · ${a.type.label}\n$detail'),
        isThreeLine: true,
        trailing: p != null ? const Chip(label: Text('Decide')) : null,
        onTap: () => showAppointmentDetails(
          context,
          a,
          patientName: patient,
          doctorName: doctorName,
          forAdmin: true,
        ),
      ),
    );
  }
}
