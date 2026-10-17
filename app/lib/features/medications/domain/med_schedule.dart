import '../../../shared/models/health_models.dart';

/// Module 5 schedule rules shared with the backend (D-43; app/services/medications.py).
///
/// `schedule` is "08:00,20:00" (24-hour, Malaysia time) or "as_needed". Malaysia has
/// no daylight saving, so MYT is always UTC+8 whatever the phone's own time zone is.
const mytOffset = Duration(hours: 8);
const asNeeded = 'as_needed';

/// A dose may be confirmed up to an hour early (matches the API's EARLY_CONFIRM).
const earlyConfirm = Duration(hours: 1);

/// After this, an unconfirmed dose is missed (the API's MISSED_WINDOW); taking it later
/// counts as "taken late" (D-49).
const missedWindow = Duration(hours: 2);

/// D-49: confirmed after the missed window.
bool takenLate(DateTime scheduled, DateTime? confirmedAt) =>
    confirmedAt != null && confirmedAt.difference(scheduled) > missedWindow;

class DoseTime implements Comparable<DoseTime> {
  const DoseTime(this.hour, this.minute);

  final int hour;
  final int minute;

  String get hhmm => '${_two(hour)}:${_two(minute)}';

  /// "8:00 AM" for display.
  String get label {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${_two(minute)} ${hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  int compareTo(DoseTime other) => (hour * 60 + minute) - (other.hour * 60 + other.minute);

  @override
  bool operator ==(Object other) =>
      other is DoseTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => hour * 60 + minute;
}

String _two(int v) => v.toString().padLeft(2, '0');

final _time = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

/// Sorted unique dose times, or null for as-needed. Throws [FormatException].
List<DoseTime>? parseSchedule(String raw) {
  final text = raw.trim().toLowerCase();
  if (text == asNeeded) return null;
  final parts = text.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty);
  if (parts.isEmpty) throw const FormatException('Add at least one dose time.');
  final times = <DoseTime>{};
  for (final p in parts) {
    final m = _time.firstMatch(p);
    if (m == null) throw FormatException("'$p' is not a time like 08:00.");
    times.add(DoseTime(int.parse(m.group(1)!), int.parse(m.group(2)!)));
  }
  if (times.length > 8) throw const FormatException('At most 8 dose times per day.');
  return times.toList()..sort();
}

/// Never throws: an unreadable legacy schedule is treated as as-needed.
List<DoseTime>? tryParseSchedule(String raw) {
  try {
    return parseSchedule(raw);
  } on FormatException {
    return null;
  }
}

String formatSchedule(List<DoseTime>? times) =>
    times == null ? asNeeded : times.map((t) => t.hhmm).join(',');

/// "8:00 AM, 8:00 PM" or "As needed"; older free-text schedules are shown as written.
String describeSchedule(String raw) {
  if (raw.trim().toLowerCase() == asNeeded) return 'As needed';
  try {
    return parseSchedule(raw)!.map((t) => t.label).join(', ');
  } on FormatException {
    return raw;
  }
}

/// The Malaysian wall-clock time for an instant.
DateTime toMyt(DateTime instant) => instant.toUtc().add(mytOffset);

/// The UTC instant of dose time [t] on [now]'s Malaysian date.
DateTime doseMoment(DateTime now, DoseTime t) {
  final local = toMyt(now);
  return DateTime.utc(local.year, local.month, local.day, t.hour, t.minute).subtract(mytOffset);
}

/// Start of [now]'s Malaysian day, as a UTC instant.
DateTime startOfMytDay(DateTime now) => doseMoment(now, const DoseTime(0, 0));

/// Same id the API uses for a dose_log: medication + MYT "yyyyMMddHHmm".
String doseId(String medicationId, DateTime moment) {
  final l = toMyt(moment);
  return '${medicationId}_${l.year}${_two(l.month)}${_two(l.day)}${_two(l.hour)}${_two(l.minute)}';
}

enum DosePeriod {
  morning('Morning'),
  afternoon('Afternoon'),
  evening('Night'), // D-77: shown as Night
  asNeeded('As needed (PRN)');

  const DosePeriod(this.label);
  final String label;

  static DosePeriod of(DoseTime t) => t.hour < 12
      ? DosePeriod.morning
      : t.hour < 17
      ? DosePeriod.afternoon
      : DosePeriod.evening;
}

enum DoseState { taken, missed, due, upcoming }

/// One dose slot on today's schedule.
class ScheduledDose {
  const ScheduledDose({
    required this.medication,
    required this.time,
    required this.moment,
    required this.state,
    this.confirmedAt,
  });

  final Medication medication;
  final DoseTime time;
  final DateTime moment;
  final DoseState state;
  final DateTime? confirmedAt;

  DosePeriod get period => DosePeriod.of(time);

  bool get isLate => takenLate(moment, confirmedAt);
}

/// Today's scheduled doses (MYT), sorted by time, with their state from dose_logs.
List<ScheduledDose> todaysDoses(
  List<Medication> meds,
  Map<String, DoseLog> logsById,
  DateTime now,
) {
  final out = <ScheduledDose>[];
  for (final med in meds) {
    final times = tryParseSchedule(med.schedule);
    if (times == null) continue;
    for (final t in times) {
      final moment = doseMoment(now, t);
      final log = logsById[doseId(med.id, moment)];
      final state = switch (log?.status) {
        'taken' => DoseState.taken,
        'missed' => DoseState.missed,
        _ => now.isBefore(moment.subtract(earlyConfirm)) ? DoseState.upcoming : DoseState.due,
      };
      out.add(
        ScheduledDose(
          medication: med,
          time: t,
          moment: moment,
          state: state,
          confirmedAt: log?.confirmedAt,
        ),
      );
    }
  }
  out.sort((a, b) => a.moment.compareTo(b.moment));
  return out;
}

/// Remaining supply in days; null when stock isn't tracked or the medicine is as-needed.
double? daysOfSupply(Medication med) {
  final times = tryParseSchedule(med.schedule);
  final q = med.quantityOnHand;
  if (q == null || times == null || times.isEmpty) return null;
  return q / times.length;
}

/// UC5.2: below the refill threshold (D-05, default 7 days).
bool needsRefill(Medication med) {
  final days = daysOfSupply(med);
  return days != null && days < med.refillThresholdDays;
}
