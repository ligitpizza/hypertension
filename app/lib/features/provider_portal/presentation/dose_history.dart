import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/health_models.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../medications/domain/med_schedule.dart';
import '../../medications/state/medication_providers.dart';

const historyWindow = Duration(days: 14);

/// D-49: one medicine's dose_logs for the last 14 days (assigned doctor reads them; rules).
final patientDoseLogsProvider = StreamProvider.autoDispose.family<List<DoseLog>, String>((
  ref,
  medicationId,
) {
  final since = ref.watch(nowProvider)().subtract(historyWindow);
  return ref.watch(medicationsRepositoryProvider).doseLogs(medicationId, since);
}, retry: (_, _) => null);

/// Counts for the summary line.
typedef DoseCounts = ({int taken, int late, int missed});

DoseCounts countDoses(List<DoseLog> logs) {
  var taken = 0, late = 0, missed = 0;
  for (final l in logs) {
    if (l.status == 'missed') {
      missed++;
    } else if (l.status == 'taken') {
      taken++;
      if (takenLate(l.scheduledTime, l.confirmedAt)) late++;
    }
  }
  return (taken: taken, late: late, missed: missed);
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

String _when(DateTime instant) {
  final l = toMyt(instant);
  return '${_days[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}, '
      '${DoseTime(l.hour, l.minute).label}';
}

String _lateBy(DoseLog l) {
  final d = l.confirmedAt!.difference(l.scheduledTime);
  return d.inHours >= 1 ? '${d.inHours} h late' : '${d.inMinutes} min late';
}

class DoseHistory extends ConsumerWidget {
  const DoseHistory({super.key, required this.medication});

  final Medication medication;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(patientDoseLogsProvider(medication.id));
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      key: Key('history-${medication.id}'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: logs.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => Text('Dose history unavailable.', style: small),
        data: (all) {
          final oldestFirst = [...all]..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
          if (tryParseSchedule(medication.schedule) == null) {
            final weekAgo = ref.watch(nowProvider)().subtract(const Duration(days: 7));
            final week = oldestFirst.where((l) => l.scheduledTime.isAfter(weekAgo)).toList();
            return Text(
              week.isEmpty
                  ? 'As needed: not taken in the last 7 days.'
                  : 'As needed: taken ${week.length}× in the last 7 days, '
                        'last ${_when(week.last.confirmedAt ?? week.last.scheduledTime)}.',
              style: small,
            );
          }
          if (oldestFirst.isEmpty) return Text('No doses recorded yet.', style: small);
          final c = countDoses(oldestFirst);
          final notable = [
            for (final l in oldestFirst.reversed)
              if (l.status == 'missed' || takenLate(l.scheduledTime, l.confirmedAt)) l,
          ].take(5);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last 14 days: ${c.taken} taken'
                '${c.late > 0 ? ' (${c.late} late)' : ''} · ${c.missed} missed',
                key: Key('history-summary-${medication.id}'),
                style: small,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [for (final l in oldestFirst) _Dot(log: l)],
              ),
              for (final l in notable)
                Text(
                  '${_when(l.scheduledTime)}: '
                  '${l.status == 'missed' ? 'missed' : 'taken ${_lateBy(l)}'}',
                  style: small,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.log});

  final DoseLog log;

  @override
  Widget build(BuildContext context) {
    final late = takenLate(log.scheduledTime, log.confirmedAt);
    final (color, label) = log.status == 'missed'
        ? (Theme.of(context).colorScheme.error, 'missed')
        : late
        ? (Colors.amber.shade700, 'taken late')
        : (Colors.green.shade600, 'taken');
    return Tooltip(
      message: '${_when(log.scheduledTime)}: $label',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
