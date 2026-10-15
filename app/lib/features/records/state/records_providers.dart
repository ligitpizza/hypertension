import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/api_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../data/record_picker.dart';
import '../data/records_repository.dart';

Duration? _noRetry(int _, Object _) => null;

final recordsRepositoryProvider = Provider<RecordsRepository>(
  (ref) => FirebaseRecordsRepository(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
    ref.watch(apiClientProvider),
  ),
);

final recordPickerProvider = Provider<RecordPicker>((ref) => DeviceRecordPicker());

/// The signed-in patient's records (UC6.1).
final myRecordsProvider = StreamProvider.autoDispose<List<HealthRecord>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(recordsRepositoryProvider).myRecords(uid);
}, retry: _noRetry);

/// UC6.3: a patient's shared records, for their doctor.
final sharedRecordsProvider = StreamProvider.autoDispose.family<List<HealthRecord>, String>(
  (ref, patientId) => ref.watch(recordsRepositoryProvider).sharedRecords(patientId),
  retry: _noRetry,
);
