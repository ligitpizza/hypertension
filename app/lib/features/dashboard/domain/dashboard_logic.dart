import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../shared/models/health_models.dart';

/// Pure helpers behind the dashboard cards, kept separate for unit tests.

/// "Good Morning/Afternoon/Evening/Night" (Fig 4.3.2.1; D-77 adds night).
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return 'Good Morning';
  if (h >= 12 && h < 18) return 'Good Afternoon';
  if (h >= 18 && h < 22) return 'Good Evening';
  return 'Good Night';
}

/// D-77: the line under the greeting follows the time of day too.
String snapshotLineFor(DateTime now) => switch (greetingFor(now)) {
  'Good Morning' => "Here's your morning health snapshot. A good time to check your BP.",
  'Good Afternoon' => "Here's your afternoon check-in. Keep your plan on track.",
  'Good Evening' => "Here's your evening health snapshot. Remember tonight's medicines.",
  _ => "Here's today's summary. Rest well and log your BP in the morning.",
};

/// D-77: the morning "log your BP" nudge shows until noon if nothing is logged today.
bool showMorningBpNudge({
  required DateTime now,
  required DateTime? latestReading,
  required bool dismissedToday,
}) {
  if (dismissedToday || now.hour >= 12) return false;
  if (latestReading == null) return true;
  final l = latestReading.toLocal();
  return !(l.year == now.year && l.month == now.month && l.day == now.day);
}

/// Systolic change of the latest reading versus the most recent reading taken on
/// an earlier calendar day ("-4 from yesterday"). Null when there is nothing to compare.
int? systolicChangeFromPreviousDay(List<VitalReading> newestFirst) {
  if (newestFirst.isEmpty) return null;
  final latest = newestFirst.first;
  final latestDay = DateTime(latest.timestamp.year, latest.timestamp.month, latest.timestamp.day);
  for (final r in newestFirst.skip(1)) {
    if (r.timestamp.isBefore(latestDay)) return latest.systolic - r.systolic;
  }
  return null;
}

/// "2 hours ago" style label for the latest reading.
String timeAgo(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}

/// "Tomorrow, 10:30 AM" style label for an appointment.
String appointmentLabel(DateTime when, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final diff = day.difference(today).inDays;
  final hour12 = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final time = '$hour12:${when.minute.toString().padLeft(2, '0')} ${when.hour < 12 ? 'AM' : 'PM'}';
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
  final dayLabel = switch (diff) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => '${when.day} ${months[when.month - 1]}',
  };
  return '$dayLabel, $time';
}

/// Risk assessment is shown only after at least three readings (Figs 4.3.3.1 / 4.3.4.2).
const minReadingsForRisk = 3;

/// D-37: how long after a crisis reading or an emergency triage result the dashboard keeps
/// the one-tap Call 999 card.
const emergencyWindow = Duration(hours: 6);

/// D-37: an emergency is active when the latest reading is in the crisis range or the
/// latest symptom check said "seek emergency care", within [emergencyWindow].
bool activeEmergency({
  required VitalReading? latestReading,
  required TriageOutcome? latestTriage,
  required DateTime? latestTriageAt,
  required DateTime now,
}) {
  bool recent(DateTime t) => now.difference(t) <= emergencyWindow;
  final crisisReading =
      latestReading != null &&
      recent(latestReading.timestamp) &&
      BpClassifier.classify(latestReading.systolic, latestReading.diastolic) == BpCategory.crisis;
  final emergencyTriage =
      latestTriage == TriageOutcome.seekEmergencyCare &&
      latestTriageAt != null &&
      recent(latestTriageAt);
  return crisisReading || emergencyTriage;
}
