import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/core/utils/validators.dart';
import 'package:hypertension/features/auth/data/auth_repository.dart';
import 'package:hypertension/features/auth/presentation/forgot_password_page.dart';
import 'package:hypertension/features/auth/presentation/login_page.dart';
import 'package:hypertension/features/auth/presentation/register_page.dart';
import 'package:hypertension/features/auth/presentation/staff_login_page.dart';
import 'package:hypertension/features/auth/presentation/status_pages.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/shared/providers/api_providers.dart';

import '../helpers/fakes.dart';

Future<void> fill(WidgetTester t, String key, String text) =>
    t.enterText(find.byKey(Key(key)), text);

void main() {
  group('UC1.2 LoginPage (Fig 4.3.1.1)', () {
    tallTest('renders mockup elements with role toggle defaulting to the app role', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const LoginPage(), repo: repo));
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('SELECT YOUR ROLE'), findsOneWidget);
      expect(find.text('Patient'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);
      expect(find.text('Forgot?'), findsOneWidget);
    });

    tallTest('blocks submit with empty fields', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const LoginPage(), repo: repo));
      await t.tap(find.byKey(const Key('login-submit')));
      await t.pump();
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    tallTest('D-26 sends the selected role; family app defaults to Family', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const LoginPage(), repo: repo, app: ClientApp.family));
      expect(find.text('CareFlow Family'), findsOneWidget);
      await fill(t, 'login-email', 'f@x.my');
      await fill(t, 'login-password', 'secret123');
      await t.tap(find.byKey(const Key('login-submit')));
      await t.pumpAndSettle();
      expect(repo.lastSelectedRole, UserRole.familyMember);
    });

    tallTest('UC1.2 E1 shows the generic credentials error', (t) async {
      final repo = FakeAuthRepository()
        ..signInError = const AuthFailure(
          LoginFailureReason.invalidCredentials,
          AuthMessages.invalidCredentials,
        );
      await t.pumpWidget(harness(const LoginPage(), repo: repo));
      await fill(t, 'login-email', 'p@x.my');
      await fill(t, 'login-password', 'wrong');
      await t.tap(find.byKey(const Key('login-submit')));
      await t.pumpAndSettle();
      expect(find.text(AuthMessages.invalidCredentials), findsOneWidget);
    });

    tallTest('shows a progress state while signing in', (t) async {
      final repo = FakeAuthRepository()..holdSignIn = true;
      await t.pumpWidget(harness(const LoginPage(), repo: repo));
      await fill(t, 'login-email', 'p@x.my');
      await fill(t, 'login-password', 'pw');
      await t.tap(find.byKey(const Key('login-submit')));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.releaseSignIn();
      await t.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('UC1.1 RegisterPage', () {
    tallTest('UC1.1 E2 rejects weak passwords and mismatches', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const RegisterPage(), repo: repo));
      await fill(t, 'register-name', 'Ali Bin Abu');
      await fill(t, 'register-email', 'ali@x.my');
      await fill(t, 'register-password', 'short');
      await fill(t, 'register-confirm', 'other');
      await t.tap(find.byKey(const Key('register-submit')));
      await t.pump();
      expect(find.text(Validators.passwordRule), findsNWidgets(2)); // helper + error
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    tallTest('FR-1.1 patient app registers a patient', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const RegisterPage(), repo: repo));
      await fill(t, 'register-name', 'Ali Bin Abu');
      await fill(t, 'register-email', 'ali@x.my');
      await fill(t, 'register-password', 'goodpass1');
      await fill(t, 'register-confirm', 'goodpass1');
      await t.tap(find.byKey(const Key('register-submit')));
      await t.pumpAndSettle();
      expect(repo.lastRegisterRole, UserRole.patient);
    });

    tallTest('FR-1.1 family app registers a family member', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const RegisterPage(), repo: repo, app: ClientApp.family));
      await fill(t, 'register-name', 'Siti');
      await fill(t, 'register-email', 's@x.my');
      await fill(t, 'register-password', 'goodpass1');
      await fill(t, 'register-confirm', 'goodpass1');
      await t.tap(find.byKey(const Key('register-submit')));
      await t.pumpAndSettle();
      expect(repo.lastRegisterRole, UserRole.familyMember);
    });

    tallTest('UC1.1 E1 email already registered prompts sign in', (t) async {
      final repo = FakeAuthRepository()
        ..registerError = const AuthFailure(LoginFailureReason.other, AuthMessages.emailInUse);
      await t.pumpWidget(harness(const RegisterPage(), repo: repo));
      await fill(t, 'register-name', 'Ali');
      await fill(t, 'register-email', 'ali@x.my');
      await fill(t, 'register-password', 'goodpass1');
      await fill(t, 'register-confirm', 'goodpass1');
      await t.tap(find.byKey(const Key('register-submit')));
      await t.pumpAndSettle();
      expect(find.text(AuthMessages.emailInUse), findsOneWidget);
      expect(find.text('Go to sign in'), findsOneWidget);
    });
  });

  group('UC1.2 A1 ForgotPasswordPage', () {
    tallTest('sends reset and shows a neutral confirmation', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const ForgotPasswordPage(), repo: repo));
      await fill(t, 'reset-email', 'p@x.my');
      await t.tap(find.byKey(const Key('reset-submit')));
      await t.pumpAndSettle();
      expect(repo.calls, ['reset']);
      expect(find.byKey(const Key('reset-sent')), findsOneWidget);
    });
  });

  group('UC1.2 StaffLoginPage (Fig 4.3.14.8)', () {
    tallTest('shows Doctor/Admin/Pharmacist toggle, no SSO, live status', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const StaffLoginPage(), repo: repo, app: ClientApp.staff));
      await t.pumpAndSettle();
      for (final label in ['Doctor', 'Admin', 'Pharmacist']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('SSO'), findsNothing);
      expect(find.text('System Status: All Operational'), findsOneWidget);
    });

    tallTest('API down shows unreachable status', (t) async {
      final api = FakeApiClient()..healthError = Exception('down');
      await t.pumpWidget(harness(const StaffLoginPage(), repo: FakeAuthRepository(), api: api));
      await t.pumpAndSettle();
      expect(find.text('System Status: API unreachable'), findsOneWidget);
    });

    tallTest('D-26 role mismatch error is shown', (t) async {
      final repo = FakeAuthRepository()
        ..signInError = const AuthFailure(
          LoginFailureReason.roleMismatch,
          AuthMessages.roleMismatch,
        );
      await t.pumpWidget(harness(const StaffLoginPage(), repo: repo, app: ClientApp.staff));
      await t.tap(find.text('Admin'));
      await fill(t, 'staff-email', 'd@h.my');
      await fill(t, 'staff-password', 'pw');
      await t.tap(find.byKey(const Key('staff-login-submit')));
      await t.pumpAndSettle();
      expect(repo.lastSelectedRole, UserRole.admin);
      expect(find.text(AuthMessages.roleMismatch), findsOneWidget);
    });
  });

  group('status pages', () {
    tallTest('UC1.2 E2 deactivated page offers sign out', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const DeactivatedPage(), repo: repo));
      expect(find.text(AuthMessages.deactivated), findsOneWidget);
      await t.tap(find.text('Sign out'));
      await t.pump();
      expect(repo.calls, ['signOut']);
    });

    tallTest('FR-1.6 staff portal never self-repairs a missing profile', (t) async {
      await t.pumpWidget(
        harness(const FinishRegistrationPage(), repo: FakeAuthRepository(), app: ClientApp.staff),
      );
      expect(find.text('Try again'), findsNothing);
      expect(find.textContaining('contact your administrator'), findsOneWidget);
    });

    tallTest('patient app offers to finish registration', (t) async {
      await t.pumpWidget(harness(const FinishRegistrationPage(), repo: FakeAuthRepository()));
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  tallTest('router splash route renders a loader', (t) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SplashPage())],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          apiClientProvider.overrideWithValue(FakeApiClient()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
