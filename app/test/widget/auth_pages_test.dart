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
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/staff_shell/staff_shell.dart';
import 'package:hypertension/shared/widgets/home_placeholder.dart';
import 'package:hypertension/shared/providers/api_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

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
      expect(find.text('Forgot Password?'), findsOneWidget);
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
      expect(find.text('Harvey Family'), findsOneWidget);
      await fill(t, 'login-email', 'f@x.my');
      await fill(t, 'login-password', 'secret123');
      await t.tap(find.byKey(const Key('login-submit')));
      await t.pumpAndSettle();
      expect(repo.lastSelectedRole, UserRole.familyMember);
    });

    tallTest('D-63 Family mode looks different and signs in as family', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const LoginPage(), repo: repo));
      expect(find.byKey(const Key('login-icon-patient')), findsOneWidget);
      expect(find.byKey(const Key('login-family-note')), findsNothing);
      await t.tap(find.text('Family'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('login-icon-family')), findsOneWidget);
      expect(find.text('Harvey Family'), findsOneWidget);
      expect(find.text('Welcome, family member'), findsOneWidget);
      expect(find.byKey(const Key('login-family-note')), findsOneWidget);
      expect(find.text('Sign In as Family'), findsOneWidget);
      expect(find.text('Create a family account'), findsOneWidget);
      final primary = Theme.of(
        t.element(find.byKey(const Key('login-submit'))),
      ).colorScheme.primary;
      expect(primary, isNot(Theme.of(t.element(find.byType(LoginPage))).colorScheme.primary));
      await fill(t, 'login-email', 'f@x.my');
      await fill(t, 'login-password', 'secret123');
      await t.tap(find.byKey(const Key('login-submit')));
      await t.pumpAndSettle();
      expect(repo.lastSelectedRole, UserRole.familyMember);
    });

    tallTest('D-63 registration can start as a family member', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const RegisterPage(family: true), repo: repo));
      await t.pumpAndSettle();
      expect(find.textContaining('Register as a family member'), findsOneWidget);
      expect(find.byKey(const Key('register-ic')), findsNothing);
      await t.tap(find.text('Patient'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('register-ic')), findsOneWidget);
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
      await fill(t, 'register-ic', '900101145677');
      await fill(t, 'register-email', 'ali@x.my');
      await fill(t, 'register-password', 'goodpass1');
      await fill(t, 'register-confirm', 'goodpass1');
      await t.tap(find.byKey(const Key('register-submit')));
      await t.pumpAndSettle();
      expect(repo.lastRegisterRole, UserRole.patient);
      expect(repo.lastRegisterIc, '900101-14-5677'); // D-51, formatted
    });

    tallTest('D-51 a patient must give a valid IC; it previews date of birth', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(harness(const RegisterPage(), repo: repo));
      await fill(t, 'register-name', 'Ali Bin Abu');
      await fill(t, 'register-ic', '901301145677'); // month 13
      await fill(t, 'register-email', 'ali@x.my');
      await fill(t, 'register-password', 'goodpass1');
      await fill(t, 'register-confirm', 'goodpass1');
      await t.tap(find.byKey(const Key('register-submit')));
      await t.pump();
      expect(find.textContaining('real date of birth'), findsOneWidget);
      expect(repo.calls, isEmpty);
      await fill(t, 'register-ic', '900101145677');
      await t.pump();
      expect(find.text('Born 1 Jan 1990 · Male'), findsOneWidget);
      expect(find.text('900101-14-5677'), findsOneWidget); // dashes added while typing
    });

    tallTest('D-51 family members are not asked for an IC', (t) async {
      await t.pumpWidget(
        harness(const RegisterPage(), repo: FakeAuthRepository(), app: ClientApp.family),
      );
      expect(find.byKey(const Key('register-ic')), findsNothing);
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
      await fill(t, 'register-ic', '900101145677');
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
      expect(find.textContaining('The link works for 1 hour'), findsOneWidget);
    });

    tallTest('D-65 an unknown email still gets the neutral confirmation', (t) async {
      final repo = FakeAuthRepository()..resetError = ApiException('NETWORK_ERROR', 'x');
      await t.pumpWidget(harness(const ForgotPasswordPage(), repo: repo));
      await fill(t, 'reset-email', 'p@x.my');
      await t.tap(find.byKey(const Key('reset-submit')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reset-sent')), findsOneWidget);
    });

    tallTest('D-65 too many requests asks to wait', (t) async {
      final repo = FakeAuthRepository()..resetError = ApiException('RATE_LIMITED', 'Too many');
      await t.pumpWidget(harness(const ForgotPasswordPage(), repo: repo));
      await fill(t, 'reset-email', 'p@x.my');
      await t.tap(find.byKey(const Key('reset-submit')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reset-error')), findsOneWidget);
      expect(find.byKey(const Key('reset-sent')), findsNothing);
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

  group('NFR-3.2 role-specific shells', () {
    Widget withUser(Widget child, AppUser user, ClientApp app) => ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        clientAppProvider.overrideWithValue(app),
        currentUserProvider.overrideWith((ref) => Stream.value(user)),
      ],
      child: MaterialApp(home: child),
    );

    AppUser u(UserRole role) =>
        AppUser(uid: 'u', email: 'e@x.my', name: 'Nur', role: role, isActive: true);

    tallTest('D-26 wrong-app page tells staff to use the portal', (t) async {
      await t.pumpWidget(withUser(const WrongAppPage(), u(UserRole.doctor), ClientApp.patient));
      await t.pumpAndSettle();
      expect(find.text(AuthMessages.useStaffPortal), findsOneWidget);
    });

    tallTest('staff shell shows the signed-in role and a sign-out action', (t) async {
      await t.pumpWidget(
        withUser(
          const StaffShell(location: '/admin/users', child: Text('BODY')),
          u(UserRole.admin),
          ClientApp.staff,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Nur · Admin'), findsOneWidget);
      expect(find.text('BODY'), findsOneWidget);
      expect(find.byKey(const Key('staff-sign-out')), findsOneWidget);
    });

    test('FR-1.3 each staff role has its own home and menu', () {
      expect(staffHome(UserRole.doctor), '/doctor');
      expect(staffHome(UserRole.pharmacist), '/pharmacy');
      expect(staffHome(UserRole.admin), '/admin/users');
      expect(staffDestinations(UserRole.admin).map((d) => d.path), [
        '/admin/users',
        '/admin/calendar', // D-60
        '/admin/appointments', // D-55
        '/admin/assignments', // D-54
        '/admin/messages', // D-76
        '/admin/audit-logs', // UC11.3
        '/admin/orders', // D-70 order tracking
        '/admin/deliveries', // UC11.4 (Module 13)
        '/admin/inventory', // D-70 drug inventory
        '/admin/analytics/hospital', // FR-11.4
        '/admin/analytics/system', // FR-11.3
        '/admin/system-health', // FR-11.3
      ]);
      expect(staffDestinations(UserRole.pharmacist).map((d) => d.path), [
        '/pharmacy',
        '/pharmacy/tracking', // D-70
        '/pharmacy/inventory', // D-70
        '/pharmacy/patients', // D-70
        '/pharmacy/messages', // D-69
      ]);
      expect(staffDestinations(UserRole.patient), isEmpty);
    });
  });

  group('UC1.3 sign-out confirmation', () {
    Widget home(FakeAuthRepository repo) => ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        clientAppProvider.overrideWithValue(ClientApp.patient),
        currentUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
              uid: 'u',
              email: 'e@x.my',
              name: 'Woo',
              role: UserRole.patient,
              isActive: true,
            ),
          ),
        ),
      ],
      child: const MaterialApp(home: HomePlaceholder()),
    );

    tallTest('cancel keeps the user signed in', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(home(repo));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('home-sign-out')));
      await t.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      await t.tap(find.byKey(const Key('sign-out-cancel')));
      await t.pumpAndSettle();
      expect(repo.calls, isEmpty);
    });

    tallTest('confirm signs out', (t) async {
      final repo = FakeAuthRepository();
      await t.pumpWidget(home(repo));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('home-sign-out')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('sign-out-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, ['signOut']);
    });
  });
}
