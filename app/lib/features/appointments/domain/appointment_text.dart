import 'package:flutter/material.dart';

import '../../../core/constants/enums.dart';
import '../../medications/domain/med_schedule.dart';

/// Module 7 display helpers (D-53). All times are Malaysia time.

/// Shown on the confirmation screen (Fig 4.3.6.2 location line); one clinic for the PoC.
const clinicName = 'Harvey Hypertension Clinic';

/// UC7.2 E1: changing within this window shows a warning first.
const lateChangeWindow = Duration(hours: 24);

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

String timeLabel(DateTime instant) {
  final l = toMyt(instant);
  return DoseTime(l.hour, l.minute).label;
}

String dateLabel(DateTime instant) {
  final l = toMyt(instant);
  return '${_weekdays[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}';
}

/// "Today, 10:00 AM" / "Tomorrow, 10:00 AM" / "Thu 16 Oct, 10:00 AM".
String whenLabel(DateTime instant, DateTime now) {
  final day = toMyt(instant);
  final today = toMyt(now);
  final days = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  final d = days == 0
      ? 'Today'
      : days == 1
      ? 'Tomorrow'
      : dateLabel(instant);
  return '$d, ${timeLabel(instant)}';
}

String monthLabel(int year, int month) =>
    '${const [
      'January', 'February', 'March', 'April', 'May', 'June', //
      'July', 'August', 'September', 'October', 'November', 'December',
    ][month - 1]} $year';

/// Fig 4.3.12.3 legend colours.
Color appointmentColor(AppointmentType type) => switch (type) {
  AppointmentType.checkup => Colors.blue.shade600,
  AppointmentType.emergency => Colors.red.shade600,
  AppointmentType.followUp => Colors.brown.shade400,
};

/// UC7.2 E1.
bool isLateChange(DateTime appointment, DateTime now) =>
    appointment.difference(now) < lateChangeWindow;
