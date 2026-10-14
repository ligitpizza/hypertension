import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/health_models.dart';
import '../../../shared/providers/api_providers.dart';
import '../../dashboard/state/dashboard_providers.dart';
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
