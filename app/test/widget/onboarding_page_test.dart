import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/domain/onboarding_data.dart';
import 'package:hypertension/features/auth/presentation/onboarding/onboarding_complete_page.dart';
import 'package:hypertension/features/auth/presentation/onboarding/onboarding_page.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';

Widget app(FakeAuthRepository repo, FakeDraftStore drafts) {
  final router = GoRouter(
    initialLocation: '/onboard',
    routes: [
      GoRoute(path: '/onboard', builder: (_, _) => const OnboardingPage()),
      GoRoute(path: '/onboard/complete', builder: (_, _) => const Text('COMPLETE')),
    ],
  );
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      clientAppProvider.overrideWithValue(ClientApp.patient),
      onboardingDraftStoreProvider.overrideWithValue(drafts),
      authUidProvider.overrideWith((ref) => Stream.value('u1')),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// A draft with every required answer, so the test can jump to any step.
OnboardingData completeDraft() => OnboardingData()
  ..dateOfBirth = DateTime(1970, 1, 1)
  ..gender = Gender.male
  ..heightCm = 170
  ..weightKg = 80
  ..phone = '0123456789'
  ..smokingStatus = SmokingStatus.never
  ..alcohol = AlcoholUse.none
  ..exerciseDaysPerWeek = 2
  ..saltIntake = SaltIntake.low;

void main() {
  setUp(() {
    // Tall viewport so every step's fields are on screen.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> setTall(WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  testWidgets('UC1.4 E1 step 1 blocks Next and highlights missing fields', (t) async {
    await setTall(t);
    final repo = FakeAuthRepository();
    await t.pumpWidget(app(repo, FakeDraftStore()));
    await t.pumpAndSettle();
    expect(find.text('Step 1 of 3 · Personal information'), findsOneWidget);

    await t.tap(find.byKey(const Key('onboarding-next')));
    await t.pumpAndSettle();
    expect(find.text('Date of birth is required.'), findsOneWidget);
    expect(find.text('Gender is required.'), findsOneWidget);
    expect(find.text('Height is required.'), findsOneWidget);
    expect(find.text('Step 1 of 3 · Personal information'), findsOneWidget);
  });

  testWidgets('UC1.4 A1 restores a saved draft at the saved step', (t) async {
    await setTall(t);
    final drafts = FakeDraftStore()
      ..draft = completeDraft()
      ..step = 2;
    await t.pumpWidget(app(FakeAuthRepository(), drafts));
    await t.pumpAndSettle();
    expect(find.text('Step 3 of 3 · Lifestyle'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
  });

  testWidgets('UC1.4 A1 save & finish later stores the draft and signs out', (t) async {
    await setTall(t);
    final repo = FakeAuthRepository();
    final drafts = FakeDraftStore();
    await t.pumpWidget(app(repo, drafts));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('onboarding-phone')), '0123456789');
    await t.tap(find.byKey(const Key('onboarding-save-exit')));
    await t.pumpAndSettle();
    expect(drafts.draft?.phone, '0123456789');
    expect(repo.calls, contains('signOut'));
  });

  testWidgets('FR-1.4 complete flow submits D-25 payload and shows completion', (t) async {
    await setTall(t);
    final repo = FakeAuthRepository();
    final drafts = FakeDraftStore()..draft = completeDraft();
    await t.pumpWidget(app(repo, drafts));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('onboarding-next'))); // to medical history
    await t.pumpAndSettle();
    await t.tap(find.text('Diabetes').first);
    await t.tap(find.byKey(const Key('onboarding-next'))); // to lifestyle
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('onboarding-next'))); // submit
    await t.pumpAndSettle();

    expect(repo.calls, contains('onboarding'));
    expect((repo.lastOnboarding!['medicalHistory'] as Map)['conditions'], ['diabetes']);
    expect(drafts.cleared, isTrue);
    expect(find.text('COMPLETE'), findsOneWidget);
  });

  testWidgets('submit error keeps the draft and shows the message', (t) async {
    await setTall(t);
    final repo = FakeAuthRepository()..onboardingError = ApiException('NETWORK_ERROR', 'offline');
    final drafts = FakeDraftStore()
      ..draft = completeDraft()
      ..step = 2;
    await t.pumpWidget(app(repo, drafts));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('onboarding-next')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-error')), findsOneWidget);
    expect(drafts.cleared, isFalse);
    expect(drafts.draft, isNotNull);
  });

  testWidgets('Fig 4.3.1.2 OnboardingCompletePage renders', (t) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const OnboardingCompletePage(autoRedirect: null)),
        GoRoute(path: '/dashboard', builder: (_, _) => const Text('DASH')),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('Profile Complete'), findsOneWidget);
    await t.tap(find.text('Go to Dashboard'));
    await t.pumpAndSettle();
    expect(find.text('DASH'), findsOneWidget);
  });
}
