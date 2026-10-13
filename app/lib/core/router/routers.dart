import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/create_staff_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/onboarding/onboarding_complete_page.dart';
import '../../features/auth/presentation/onboarding/onboarding_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/auth/presentation/staff_login_page.dart';
import '../../features/auth/presentation/status_pages.dart';
import '../../features/auth/state/auth_providers.dart';
import '../../features/auth/state/auth_redirect.dart';
import '../../features/messaging/presentation/chat_thread_page.dart';
import '../../features/messaging/presentation/inbox_pages.dart';
import '../../features/provider_portal/presentation/care_plan_page.dart';
import '../../features/provider_portal/presentation/clinical_note_page.dart';
import '../../features/provider_portal/presentation/doctor_dashboard_page.dart';
import '../../features/provider_portal/presentation/patient_detail_page.dart';
import '../../features/provider_portal/presentation/prescription_page.dart';
import '../../features/staff_shell/staff_shell.dart';
import '../../shared/widgets/home_placeholder.dart';
import '../constants/enums.dart';
import 'patient_routes.dart';

// One router per entrypoint; each registers only its own roles' routes
// (docs/05 "Routes per entrypoint", NFR-3.2). Feature routes are added per module.

/// Rebuilds go_router's redirect whenever auth state changes.
GoRouter _guardedRouter(
  Ref ref, {
  required ClientApp app,
  required String home,
  required List<RouteBase> routes,
  String? Function(String location)? roleGuard,
}) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(authUidProvider, (_, _) => refresh.value++)
    ..listen(currentUserProvider, (_, _) => refresh.value++)
    ..listen(authBusyProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final uid = ref.read(authUidProvider);
      final profile = ref.read(currentUserProvider);
      final location = state.matchedLocation;
      final target = authRedirect(
        location: location,
        app: app,
        authLoading: uid.isLoading && !uid.hasValue,
        uid: uid.value,
        profileLoading: profile.isLoading && !profile.hasValue,
        profile: profile.value,
        busy: ref.read(authBusyProvider),
        home: home,
      );
      return target ?? roleGuard?.call(location);
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordPage()),
      GoRoute(path: '/finish-registration', builder: (_, _) => const FinishRegistrationPage()),
      GoRoute(path: '/deactivated', builder: (_, _) => const DeactivatedPage()),
      GoRoute(path: '/wrong-app', builder: (_, _) => const WrongAppPage()),
      ...routes,
    ],
  );
}

final patientRouterProvider = Provider<GoRouter>(
  (ref) => _guardedRouter(
    ref,
    app: ClientApp.patient,
    home: '/dashboard',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(path: '/onboard', builder: (_, _) => const OnboardingPage()),
      GoRoute(path: '/onboard/complete', builder: (_, _) => const OnboardingCompletePage()),
      ...patientFeatureRoutes,
    ],
  ),
);

final familyRouterProvider = Provider<GoRouter>(
  (ref) => _guardedRouter(
    ref,
    app: ClientApp.family,
    home: '/home',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(path: '/home', builder: (_, _) => const HomePlaceholder()),
    ],
  ),
);

/// Staff sections are limited to their role (FR-1.3, NFR-3.2).
String? staffRoleGuard(String location, UserRole? role) {
  final allowed = switch (role) {
    UserRole.doctor => '/doctor',
    UserRole.pharmacist => '/pharmacy',
    UserRole.admin => '/admin',
    _ => null,
  };
  const sections = ['/doctor', '/pharmacy', '/admin'];
  final inSection = sections.where(location.startsWith).firstOrNull;
  if (inSection == null || allowed == null || inSection == allowed) return null;
  return staffHome(role);
}

final staffRouterProvider = Provider<GoRouter>((ref) {
  String home() => staffHome(ref.read(currentUserProvider).value?.role);
  Widget shell(GoRouterState s, Widget child) =>
      StaffShell(location: s.matchedLocation, child: child);
  return _guardedRouter(
    ref,
    app: ClientApp.staff,
    home: '/staff-home',
    roleGuard: (location) => location == '/staff-home'
        ? home()
        : staffRoleGuard(location, ref.read(currentUserProvider).value?.role),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const StaffLoginPage()),
      GoRoute(path: '/staff-home', redirect: (_, _) => home()),
      ShellRoute(
        builder: (_, state, child) => shell(state, child),
        routes: [
          // Module 8 doctor portal (docs/05 routes; Figs 4.3.12.1-4.3.12.7).
          GoRoute(
            path: '/doctor',
            builder: (_, _) => const DoctorDashboardPage(),
            routes: [
              // Module 10 (Fig 4.3.15.1 / 4.3.15.2 in the portal).
              GoRoute(
                path: 'messages',
                builder: (_, _) => const DoctorMessagesPage(),
                routes: [
                  GoRoute(
                    path: ':patientId',
                    builder: (_, s) => ChatThreadPage(
                      otherId: s.pathParameters['patientId']!,
                      backPath: '/doctor/messages',
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'patient/:id',
                builder: (_, s) => PatientDetailPage(patientId: s.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'notes',
                    builder: (_, s) => ClinicalNotePage(patientId: s.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'prescriptions',
                    builder: (_, s) => PrescriptionPage(patientId: s.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'care-plan',
                    builder: (_, s) => CarePlanPage(patientId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/pharmacy',
            builder: (_, _) => const ComingSoon(
              title: 'Prescription queue',
              note: 'The prescription and order queue is coming soon.',
            ),
          ),
          GoRoute(path: '/admin/users', builder: (_, _) => const CreateStaffPage()),
        ],
      ),
    ],
  );
});
