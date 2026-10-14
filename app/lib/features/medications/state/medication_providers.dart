import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/health_models.dart';
import '../../../shared/providers/api_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../provider_portal/domain/portal_models.dart';
import '../data/background_access.dart';
import '../data/dose_reminders.dart';
import '../data/medications_repository.dart';
import '../domain/med_schedule.dart';

final medicationsRepositoryProvider = Provider<MedicationsRepository>(
  (ref) => ApiMedicationsRepository(FirebaseFirestore.instance, ref.watch(apiClientProvider)),
);

final doseRemindersProvider = Provider<DoseReminders>(
  (ref) => kIsWeb ? const NoopDoseReminders() : LocalDoseReminders(),
);

/// Today's (MYT) dose_logs for one medication.
final todaysDoseLogsProvider = StreamProvider.family<List<DoseLog>, String>((ref, medId) {
  final since = startOfMytDay(ref.watch(nowProvider)());
  return ref.watch(medicationsRepositoryProvider).doseLogs(medId, since);
}, retry: (_, _) => null);

/// Today's schedule across all scheduled medications (UC5.3), with taken / missed state.
final todaysDosesProvider = Provider<AsyncValue<List<ScheduledDose>>>((ref) {
  final meds = ref.watch(medicationsProvider);
  return meds.whenData((list) {
    final logs = <String, DoseLog>{};
    for (final m in list) {
      if (tryParseSchedule(m.schedule) == null) continue;
      for (final l in ref.watch(todaysDoseLogsProvider(m.id)).value ?? const <DoseLog>[]) {
        logs[l.id] = l;
      }
    }
    return todaysDoses(list, logs, ref.watch(nowProvider)());
  });
});

/// What the phone should remind about (D-43, D-45): the medication list, or nothing when the
/// patient turned medication reminders off. Null while loading.
final reminderMedicationsProvider = Provider<List<Medication>?>((ref) {
  final prefs = ref.watch(currentUserProvider).value?.notificationPrefs;
  final meds = ref.watch(medicationsProvider).value;
  if (prefs != null && !prefs.medicationReminders) return const [];
  return meds;
});

/// Whether dose reminders can fire on the minute (Android "Alarms & reminders").
final exactRemindersAllowedProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(doseRemindersProvider).exactAllowed(),
  retry: (_, _) => null,
);

final backgroundAccessProvider = Provider<BackgroundAccess>(
  (ref) => kIsWeb ? const NoopBackgroundAccess() : const AndroidBackgroundAccess(),
);

/// Show the "let CareFlow run in the background" card: restricted and not dismissed.
final backgroundPromptProvider = FutureProvider.autoDispose<bool>((ref) async {
  final access = ref.watch(backgroundAccessProvider);
  return !await access.unrestricted() && !await access.dismissed();
}, retry: (_, _) => null);

/// D-49 "From your doctor": the signed-in patient's prescriptions.
final myPrescriptionsProvider = StreamProvider<List<Prescription>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(medicationsRepositoryProvider).prescriptions(uid);
}, retry: (_, _) => null);

/// The result of the latest reminder sync (null until the first one finishes).
class ReminderStatusNotifier extends Notifier<AsyncValue<ReminderStatus>?> {
  @override
  AsyncValue<ReminderStatus>? build() => null;

  void set(AsyncValue<ReminderStatus> value) => state = value;
}

final reminderStatusProvider =
    NotifierProvider<ReminderStatusNotifier, AsyncValue<ReminderStatus>?>(
      ReminderStatusNotifier.new,
    );

/// Sync the phone's reminders and record the outcome for the Meds tab.
Future<void> syncReminders(WidgetRef ref, List<Medication> meds) async {
  final status = await AsyncValue.guard(() => ref.read(doseRemindersProvider).sync(meds));
  if (status case AsyncError(:final error)) {
    debugPrint('CareFlow: reminder sync failed: $error');
  }
  ref.read(reminderStatusProvider.notifier).set(status);
}
