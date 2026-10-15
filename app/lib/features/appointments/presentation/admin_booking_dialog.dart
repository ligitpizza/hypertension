import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';
import '../../../shared/services/api/api_client.dart';
import '../../admin/data/admin_repository.dart';
import '../../admin/state/admin_providers.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../medications/domain/med_schedule.dart';
import '../domain/appointment_text.dart';
import '../state/appointment_providers.dart';

/// "Admin assigned" label (D-60), shown to patient, doctor and admin.
class AdminAssignedBadge extends StatelessWidget {
  const AdminAssignedBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('admin-assigned'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.deepPurple.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      'Admin assigned',
      style: TextStyle(
        color: Colors.deepPurple.shade700,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// D-60: the admin books for a patient ([editing] null) or changes an appointment.
/// Returns true when something was saved.
Future<bool> showAdminBooking(BuildContext context, {Appointment? editing, DateTime? day}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _AdminBookingDialog(editing: editing, day: day),
    ) ??
    false;

class _AdminBookingDialog extends ConsumerStatefulWidget {
  const _AdminBookingDialog({this.editing, this.day});

  final Appointment? editing;

  /// Malaysian date to start from (calendar).
  final DateTime? day;

  @override
  ConsumerState<_AdminBookingDialog> createState() => _AdminBookingDialogState();
}

class _AdminBookingDialogState extends ConsumerState<_AdminBookingDialog> {
  String? _patient;
  String? _doctor;
  late AppointmentType _type;
  late DateTime _date; // Malaysian calendar date
  late TimeOfDay _time;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final now = toMyt(ref.read(nowProvider)());
    if (e != null) {
      final l = toMyt(e.dateTime);
      _patient = e.patientId;
      _doctor = e.doctorId;
      _type = e.type;
      _date = DateTime(l.year, l.month, l.day);
      _time = TimeOfDay(hour: l.hour, minute: l.minute);
    } else {
      final d = widget.day ?? now;
      _type = AppointmentType.checkup;
      _date = DateTime(d.year, d.month, d.day);
      _time = TimeOfDay(hour: (now.hour + 1).clamp(0, 23), minute: 0);
    }
  }

  /// The chosen Malaysian date and time as a UTC instant.
  DateTime get _instant => DateTime.utc(
    _date.year,
    _date.month,
    _date.day,
    _time.hour,
    _time.minute,
  ).subtract(mytOffset);

  Future<void> _save() async {
    if (_patient == null || _doctor == null) {
      setState(() => _error = 'Choose a patient and a doctor.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(appointmentsRepositoryProvider);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final e = widget.editing;
    try {
      if (e == null) {
        await repo.adminBook(patientId: _patient!, doctorId: _doctor!, time: _instant, type: _type);
      } else {
        await repo.adminEdit(
          e.id,
          time: _instant == e.dateTime ? null : _instant,
          doctorId: _doctor == e.doctorId ? null : _doctor,
          type: _type == e.type ? null : _type,
        );
      }
      nav.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${e == null ? 'Booked' : 'Updated'}: ${whenLabel(_instant, ref.read(nowProvider)())}.',
          ),
        ),
      );
    } on ApiException catch (err) {
      setState(() => _error = err.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    final patients = [
      for (final u
          in ref.watch(adminUsersProvider((UserRole.patient, ''))).value ?? const <AdminUser>[])
        if (u.isActive) u,
    ];
    final doctors = [
      for (final u
          in ref.watch(adminUsersProvider((UserRole.doctor, ''))).value ?? const <AdminUser>[])
        if (u.isActive) u,
    ];
    final patientName = patients.where((p) => p.uid == _patient).firstOrNull?.name;
    return AlertDialog(
      key: const Key('admin-booking'),
      title: Text(editing == null ? 'Book for a patient' : 'Edit appointment'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (editing == null)
                DropdownMenu<String>(
                  key: const Key('admin-book-patient'),
                  label: const Text('Patient'),
                  enableFilter: true,
                  requestFocusOnTap: true,
                  expandedInsets: EdgeInsets.zero,
                  onSelected: (v) => setState(() => _patient = v),
                  dropdownMenuEntries: [
                    for (final p in patients)
                      DropdownMenuEntry(value: p.uid, label: p.name.isEmpty ? p.email : p.name),
                  ],
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Patient'),
                  subtitle: Text(patientName ?? 'Patient'),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('admin-book-doctor'),
                initialValue: doctors.any((d) => d.uid == _doctor) ? _doctor : null,
                decoration: const InputDecoration(labelText: 'Doctor'),
                items: [
                  for (final d in doctors)
                    DropdownMenuItem(
                      value: d.uid,
                      child: Text('${d.name}${d.specialty == null ? '' : ' · ${d.specialty}'}'),
                    ),
                ],
                onChanged: (v) => setState(() => _doctor = v),
              ),
              const SizedBox(height: 12),
              SegmentedButton<AppointmentType>(
                key: const Key('admin-book-type'),
                segments: [
                  for (final t in AppointmentType.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('admin-book-date'),
                      icon: const Icon(Icons.event),
                      label: Text(dateLabel(_instant)),
                      onPressed: () async {
                        final today = toMyt(ref.read(nowProvider)());
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(today.year, today.month, today.day - 1),
                          lastDate: DateTime(today.year + 1, today.month, today.day),
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('admin-book-time'),
                      icon: const Icon(Icons.schedule),
                      label: Text(timeLabel(_instant)),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _time);
                        if (picked != null) setState(() => _time = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Malaysia time. Any time is allowed; the doctor must be free within 30 minutes. '
                'The patient sees this as "Admin assigned".',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('admin-book-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('admin-book-save'),
          onPressed: _busy ? null : _save,
          child: Text(editing == null ? 'Book' : 'Save'),
        ),
      ],
    );
  }
}
