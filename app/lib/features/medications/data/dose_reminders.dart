import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../shared/models/health_models.dart';
import '../domain/med_schedule.dart';

/// UC5.3 dose reminders on the phone (D-43): one daily local notification per dose time,
/// in Malaysia time, so reminders arrive on time even offline. The backend's 15-minute
/// job sends a backup push for doses still not taken.
/// What the last sync did, shown on the Meds tab so a failure is never silent.
class ReminderStatus {
  const ReminderStatus({this.scheduled = const [], this.exact = false, this.errors = const []});

  /// "Amlodipine 8:00 PM" for each reminder set on the phone.
  final List<String> scheduled;
  final bool exact;

  /// One line per reminder that could not be set.
  final List<String> errors;
}

abstract interface class DoseReminders {
  /// Make the scheduled reminders match [meds] exactly (empty list = cancel all).
  Future<ReminderStatus> sync(List<Medication> meds);

  /// Whether reminders can fire at the exact minute (Android "Alarms & reminders").
  Future<bool> exactAllowed();

  /// Opens the system screen where the patient allows exact reminders.
  Future<void> requestExact();
}

class NoopDoseReminders implements DoseReminders {
  const NoopDoseReminders();

  @override
  Future<ReminderStatus> sync(List<Medication> meds) async => const ReminderStatus();

  @override
  Future<bool> exactAllowed() async => true;

  @override
  Future<void> requestExact() async {}
}

const remindersChannel = AndroidNotificationChannel(
  'careflow_reminders',
  'Medication reminders',
  description: 'Reminders to take your medicines',
  importance: Importance.high,
);

const _payloadPrefix = 'dose:';

/// Stable notification id per medication and dose time (FNV-1a, so ids survive app
/// updates; String.hashCode isn't guaranteed stable).
int reminderId(String medicationId, DoseTime t) {
  var h = 0x811c9dc5;
  for (final c in '$medicationId@${t.hhmm}'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h & 0x3fffffff;
}

/// The reminders that [meds] should have: id -> (medication, time).
Map<int, (Medication, DoseTime)> plannedReminders(List<Medication> meds) => {
  for (final m in meds)
    for (final t in tryParseSchedule(m.schedule) ?? const <DoseTime>[]) reminderId(m.id, t): (m, t),
};

/// Malaysia's zone for scheduling. Needs the *full* tz database: since tzdata 2023
/// "Asia/Kuala_Lumpur" is an alias of Asia/Singapore, and the slim `latest.dart` set leaves
/// aliases out (live bug: "Location with the name Asia/Kuala_Lumpur doesn't exist").
tz.Location malaysiaTimeZone() {
  tzdata.initializeTimeZones();
  return tz.getLocation('Asia/Kuala_Lumpur');
}

class LocalDoseReminders implements DoseReminders {
  LocalDoseReminders({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  tz.Location? _myt;

  Future<tz.Location> _start() async {
    if (_myt != null) return _myt!;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(remindersChannel);
    return _myt = malaysiaTimeZone();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> exactAllowed() async {
    await _start();
    return await _android?.canScheduleExactNotifications() ?? true;
  }

  @override
  Future<void> requestExact() async {
    await _start();
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<ReminderStatus> sync(List<Medication> meds) async {
    final myt = await _start();
    // Exact when the patient allowed it; otherwise inexact (may be a few minutes late),
    // with the server's 15-minute backup push as the safety net (D-43 as revised).
    final exact = await exactAllowed();
    final planned = plannedReminders(meds);
    // Cancel ours that are no longer wanted (deleted medicine, changed time, signed out).
    for (final p in await _plugin.pendingNotificationRequests()) {
      if ((p.payload ?? '').startsWith(_payloadPrefix) && !planned.containsKey(p.id)) {
        await _plugin.cancel(id: p.id);
      }
    }
    final now = tz.TZDateTime.now(myt);
    final scheduled = <String>[];
    final errors = <String>[];
    for (final MapEntry(key: id, value: (med, t)) in planned.entries) {
      var at = tz.TZDateTime(myt, now.year, now.month, now.day, t.hour, t.minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
        id: id,
        title: 'Time to take ${med.name}',
        body: '${med.dosage} at ${t.label}. Open CareFlow to confirm.',
        scheduledDate: at,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            remindersChannel.id,
            remindersChannel.name,
            channelDescription: remindersChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: mode,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: '$_payloadPrefix${med.id}',
      );
      final label = '${med.name} ${t.label}';
      try {
        // One failing reminder must not stop the others; a refused exact alarm falls
        // back to an inexact one rather than no reminder at all.
        try {
          await schedule(
            exact
                ? AndroidScheduleMode.exactAllowWhileIdle
                : AndroidScheduleMode.inexactAllowWhileIdle,
          );
        } on PlatformException catch (e) {
          if (!exact) rethrow;
          debugPrint('CareFlow: exact reminder refused (${e.code}); using inexact');
          await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
        }
        scheduled.add(label);
      } catch (e) {
        debugPrint('CareFlow: reminder for $label failed: $e');
        errors.add('$label: $e');
      }
    }
    return ReminderStatus(scheduled: scheduled, exact: exact, errors: errors);
  }
}
