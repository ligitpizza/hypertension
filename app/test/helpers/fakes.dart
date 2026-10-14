import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/data/auth_repository.dart';
import 'package:hypertension/features/auth/data/onboarding_draft_store.dart';
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/auth/domain/onboarding_data.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/shared/providers/api_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

class FakeAuthRepository implements AuthRepository {
  Object? signInError;
  Object? registerError;
  Object? onboardingError;
  final calls = <String>[];
  Map<String, dynamic>? lastOnboarding;
  UserRole? lastSelectedRole;
  String? lastRegisterIc;
  UserRole? lastRegisterRole;
  final _signInGate = Completer<void>();
  bool holdSignIn = false;

  void releaseSignIn() => _signInGate.complete();

  @override
  Stream<String?> uidChanges() => Stream.value('u1');

  @override
  Stream<AppUser?> watchProfile(String uid) => Stream.value(null);

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole selectedRole,
    required ClientApp app,
  }) async {
    calls.add('signIn');
    lastSelectedRole = selectedRole;
    if (holdSignIn) await _signInGate.future;
    if (signInError != null) throw signInError!;
    return AppUser(uid: 'u1', email: email, name: 'N', role: selectedRole, isActive: true);
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? icNumber,
  }) async {
    calls.add('register');
    lastRegisterRole = role;
    lastRegisterIc = icNumber;
    if (registerError != null) throw registerError!;
  }

  @override
  Future<void> sendPasswordReset(String email) async => calls.add('reset');

  @override
  Future<void> completeOnboarding(Map<String, dynamic> body) async {
    calls.add('onboarding');
    lastOnboarding = body;
    if (onboardingError != null) throw onboardingError!;
  }

  @override
  Future<void> signOut(ClientApp app) async => calls.add('signOut');
}

class FakeDraftStore implements OnboardingDraftStore {
  OnboardingData? draft;
  int step = 0;
  bool cleared = false;

  @override
  Future<OnboardingData?> load(String uid) async => draft;

  @override
  Future<int> loadStep(String uid) async => step;

  @override
  Future<void> save(String uid, OnboardingData data, int step) async {
    draft = OnboardingData.fromDraftJson(data.toDraftJson());
    this.step = step;
  }

  @override
  Future<void> clear(String uid) async {
    draft = null;
    cleared = true;
  }
}

class FakeApiClient extends ApiClient {
  FakeApiClient() : super(Dio());

  Map<String, dynamic> createStaffResult = {'uid': 's1', 'role': 'doctor', 'emailSent': true};
  Object? createStaffError;
  Map<String, dynamic>? lastCreateStaff;
  Object? healthError;

  @override
  Future<Map<String, dynamic>> health() async {
    if (healthError != null) throw healthError!;
    return {'status': 'ok'};
  }

  @override
  Future<Map<String, dynamic>> createStaff({
    required String name,
    required String email,
    required String role,
    String? specialty,
  }) async {
    lastCreateStaff = {'name': name, 'email': email, 'role': role, 'specialty': specialty};
    if (createStaffError != null) throw createStaffError!;
    return createStaffResult;
  }
}

/// Wraps [child] in a ProviderScope with fakes and a MaterialApp.
Widget harness(
  Widget child, {
  required FakeAuthRepository repo,
  ClientApp app = ClientApp.patient,
  FakeDraftStore? drafts,
  FakeApiClient? api,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      clientAppProvider.overrideWithValue(app),
      onboardingDraftStoreProvider.overrideWithValue(drafts ?? FakeDraftStore()),
      apiClientProvider.overrideWithValue(api ?? FakeApiClient()),
    ],
    child: MaterialApp(home: child),
  );
}

/// testWidgets with a tall viewport so full-height forms are on screen.
void tallTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (t) async {
    t.view.physicalSize = const Size(1200, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await body(t);
  });
}
