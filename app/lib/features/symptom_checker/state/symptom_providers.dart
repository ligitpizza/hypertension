import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/providers/api_providers.dart';
import '../data/symptom_repository.dart';

final symptomRepositoryProvider = Provider<SymptomRepository>(
  (ref) => ApiSymptomRepository(FirebaseFirestore.instance, ref.watch(apiClientProvider)),
);

final symptomCatalogProvider = StreamProvider<List<SymptomOption>>(
  (ref) => ref.watch(symptomRepositoryProvider).catalog(),
  retry: (_, _) => null,
);

/// Opens the phone dialer with [number] filled in; the patient still presses Call.
/// A seam so widget tests don't launch the real dialer.
final dialerProvider = Provider<Future<bool> Function(String number)>(
  (ref) =>
      (number) => launchUrl(Uri(scheme: 'tel', path: number)),
);
