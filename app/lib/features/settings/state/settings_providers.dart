import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/api_providers.dart';
import '../../auth/domain/onboarding_data.dart';
import '../../auth/state/auth_providers.dart';
import '../data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => ApiSettingsRepository(FirebaseFirestore.instance, ref.watch(apiClientProvider)),
);

final fileSharerProvider = Provider<FileSharer>((ref) => const ShareSheetFileSharer());

/// The signed-in patient's health profile for the Settings forms (UC12.1, UC12.2).
final healthProfileProvider = StreamProvider<OnboardingData?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(settingsRepositoryProvider).profile(user);
}, retry: (_, _) => null);
