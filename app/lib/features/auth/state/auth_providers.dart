import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap.dart';
import '../../../core/constants/enums.dart';
import '../../../core/di/locator.dart';
import '../../../shared/providers/api_providers.dart';
import '../data/auth_repository.dart';
import '../data/onboarding_draft_store.dart';
import '../domain/app_user.dart';

/// Which client surface is running; overridden per entrypoint and in tests.
final clientAppProvider = Provider<ClientApp>((ref) {
  return switch (locator<AppFlavor>()) {
    AppFlavor.patient => ClientApp.patient,
    AppFlavor.family => ClientApp.family,
    AppFlavor.staff => ClientApp.staff,
  };
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
    api: ref.watch(apiClientProvider),
  );
});

final onboardingDraftStoreProvider = Provider<OnboardingDraftStore>(
  (ref) => SharedPrefsOnboardingDraftStore(),
);

/// Firebase auth state: uid or null.
final authUidProvider = StreamProvider<String?>((ref) {
  return ref.watch(authRepositoryProvider).uidChanges();
});

/// The signed-in user's profile document, or null (signed out / not registered yet).
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(null);
  return ref.watch(authRepositoryProvider).watchProfile(uid);
});

/// True while sign-in / registration is running, so the router does not react
/// to the intermediate Firebase auth state (e.g. before the role check signs out).
class AuthBusy extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final authBusyProvider = NotifierProvider<AuthBusy, bool>(AuthBusy.new);
