import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../family/state/family_providers.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/providers/api_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../data/symptom_repository.dart';

final symptomRepositoryProvider = Provider<SymptomRepository>(
  (ref) => ApiSymptomRepository(
    FirebaseFirestore.instance,
    ref.watch(apiClientProvider),
    ref.watch(locationSourceProvider),
  ),
);

final symptomCatalogProvider = StreamProvider<List<SymptomOption>>(
  (ref) => ref.watch(symptomRepositoryProvider).catalog(),
  retry: (_, _) => null,
);

/// The signed-in patient's latest triage outcome (dashboard emergency card, D-37).
final latestTriageProvider = StreamProvider<TriageRecord?>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(null);
  return ref
      .watch(symptomRepositoryProvider)
      .outcomes(uid, limit: 1)
      .map((list) => list.firstOrNull);
}, retry: (_, _) => null);

/// One patient's triage history for the doctor portal (D-37).
final patientTriageProvider = StreamProvider.family<List<TriageRecord>, String>(
  (ref, patientId) => ref.watch(symptomRepositoryProvider).outcomes(patientId),
  retry: (_, _) => null,
);

/// Opens the phone dialer with [number] filled in; the patient still presses Call.
/// A seam so widget tests don't launch the real dialer.
final dialerProvider = Provider<Future<bool> Function(String number)>(
  (ref) =>
      (number) => launchUrl(Uri(scheme: 'tel', path: number)),
);
