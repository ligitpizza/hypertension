import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/family/presentation/alert_page.dart';
import '../../features/family/presentation/family_dashboard_page.dart';
import '../../features/family/presentation/family_settings_page.dart';
import '../../features/family/presentation/family_shell.dart';
import '../../features/family/presentation/link_page.dart';
import '../../features/appointments/presentation/admin_appointments_page.dart';
import '../../features/appointments/presentation/admin_assignments_page.dart';
import '../../features/appointments/presentation/doctor_calendar_page.dart';

import '../../features/admin/presentation/admin_user_detail_page.dart';
import '../../features/admin/presentation/hospital_analytics_page.dart';
import '../../features/admin/presentation/system_analytics_page.dart';
import '../../features/admin/presentation/system_health_page.dart';
import '../../features/admin/presentation/audit_logs_page.dart';
import '../../features/admin/presentation/admin_users_page.dart';
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
import '../../features/messaging/presentation/conversation_pages.dart';
import '../../features/staff_shell/dashboards.dart';
import '../../features/staff_shell/staff_settings_page.dart';
import '../../features/messaging/presentation/inbox_pages.dart';
import '../../features/provider_portal/presentation/care_plan_page.dart';
import '../../features/provider_portal/presentation/clinical_note_page.dart';
import '../../features/provider_portal/presentation/doctor_dashboard_page.dart';
import '../../features/provider_portal/presentation/patient_detail_page.dart';
import '../../features/provider_portal/presentation/prescription_page.dart';
import '../../features/staff_shell/staff_shell.dart';
import '../constants/enums.dart';
import 'patient_routes.dart';
import '../../features/orders/presentation/admin_deliveries_page.dart';
import '../../features/orders/presentation/pharmacy_page.dart';
import '../../features/orders/presentation/pharmacy_chat_pages.dart';
import '../../features/orders/presentation/pharmacy_patient_page.dart';
import '../../features/orders/presentation/inventory_page.dart';
import '../../features/orders/presentation/pharmacy_patients_page.dart';
import '../../features/orders/presentation/tracking_page.dart';
import '../../features/orders/presentation/staff_order_page.dart';

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

/// FR-14.2 family screens (Figs 4.3.16.1-4.3.16.3; D-62). D-63: served by the Harvey
/// app to family-member accounts (and by the legacy Family build).
final List<RouteBase> familyRoutes = [
  ShellRoute(
    builder: (_, state, child) => FamilyShell(location: state.matchedLocation, child: child),
    routes: [
      GoRoute(path: '/family/home', builder: (_, _) => const FamilyDashboardPage()),
      GoRoute(path: '/family/link', builder: (_, _) => const LinkPage()),
      GoRoute(path: '/family/settings', builder: (_, _) => const FamilySettingsPage()),
    ],
  ),
  GoRoute(
    path: '/family/alert/:alertId',
    builder: (_, s) => AlertPage(alertId: s.pathParameters['alertId']!),
  ),
];

/// D-63: one Harvey app for patients and family members; each lands on its own home and
/// cannot open the other's screens.
String? patientAppGuard(String location, UserRole? role) {
  final family = role == UserRole.familyMember;
  if (location == '/start') return family ? '/family/home' : '/dashboard';
  if (role == null) return null;
  final inFamily = location.startsWith('/family/');
  if (family && !inFamily) return '/family/home';
  if (!family && inFamily) return '/dashboard';
  return null;
}

final patientRouterProvider = Provider<GoRouter>(
  (ref) => _guardedRouter(
    ref,
    app: ClientApp.patient,
    home: '/start',
    roleGuard: (location) => patientAppGuard(location, ref.read(currentUserProvider).value?.role),
    routes: [
      GoRoute(path: '/start', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (_, s) => RegisterPage(family: s.uri.queryParameters['role'] == 'family'),
      ),
      GoRoute(path: '/onboard', builder: (_, _) => const OnboardingPage()),
      GoRoute(path: '/onboard/complete', builder: (_, _) => const OnboardingCompletePage()),
      ...patientFeatureRoutes,
      ...familyRoutes,
    ],
  ),
);

final familyRouterProvider = Provider<GoRouter>(
  (ref) => _guardedRouter(
    ref,
    app: ClientApp.family,
    home: '/family/home',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (_, s) => RegisterPage(family: s.uri.queryParameters['role'] == 'family'),
      ),
      ...familyRoutes,
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
              // D-77: the doctor's home dashboard and Settings.
              GoRoute(path: 'dashboard', builder: (_, _) => const DoctorHomeDashboard()),
              GoRoute(path: 'settings', builder: (_, _) => const StaffSettingsPage()),
              GoRoute(path: 'calendar', builder: (_, _) => const DoctorCalendarPage()),
              // Module 10 (Fig 4.3.15.1 / 4.3.15.2 in the portal).
              GoRoute(
                path: 'messages',
                builder: (_, _) => const DoctorMessagesPage(),
                routes: [
                  // D-76 team and admin chats (before :patientId, which would match "team").
                  GoRoute(
                    path: 'team/:id',
                    builder: (_, s) => StaffConversationPage(
                      conversationId: s.pathParameters['id']!,
                      backPath: '/doctor/messages',
                    ),
                  ),
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
          // Module 13 pharmacist view (Fig 4.3.13.1; D-66).
          GoRoute(
            path: '/pharmacy',
            builder: (_, _) => const PharmacyPage(),
            routes: [
              GoRoute(path: 'dashboard', builder: (_, _) => const PharmacyDashboardPage()),
              GoRoute(path: 'settings', builder: (_, _) => const StaffSettingsPage()),
              // D-69/D-70: patients, dispensing details, tracking, inventory, chat.
              GoRoute(
                path: 'patients',
                builder: (_, _) => const PharmacyPatientsPage(),
                routes: [
                  GoRoute(
                    path: ':uid',
                    builder: (_, s) => PharmacyPatientPage(patientId: s.pathParameters['uid']!),
                  ),
                ],
              ),
              GoRoute(path: 'tracking', builder: (_, _) => const OrderTrackingPage()),
              GoRoute(path: 'inventory', builder: (_, _) => const InventoryPage()),
              GoRoute(
                path: 'messages',
                builder: (_, _) => const PharmacyMessagesPage(),
                routes: [
                  GoRoute(
                    path: 'team/:id',
                    builder: (_, s) => StaffConversationPage(
                      conversationId: s.pathParameters['id']!,
                      backPath: '/pharmacy/messages',
                    ),
                  ),
                  GoRoute(
                    path: ':uid',
                    builder: (_, s) => PharmacyThreadPage(patientId: s.pathParameters['uid']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/admin/users',
            builder: (_, _) => const AdminUsersPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (c, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: TextButton.icon(
                        key: const Key('back-to-users'),
                        onPressed: () => c.go('/admin/users'),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('User management'),
                      ),
                    ),
                    const Expanded(child: CreateStaffPage()),
                  ],
                ),
              ),
              GoRoute(
                path: ':uid',
                builder: (_, st) => AdminUserDetailPage(uid: st.pathParameters['uid']!),
              ),
            ],
          ),
          GoRoute(path: '/admin/appointments', builder: (_, _) => const AdminAppointmentsPage()),
          GoRoute(path: '/admin/dashboard', builder: (_, _) => const AdminDashboardPage()),
          GoRoute(path: '/admin/settings', builder: (_, _) => const StaffSettingsPage()),
          // D-76: admin chats with anyone and opens chats between two people.
          GoRoute(
            path: '/admin/messages',
            builder: (_, _) => const AdminMessagesPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => StaffConversationPage(
                  conversationId: s.pathParameters['id']!,
                  backPath: '/admin/messages',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/admin/calendar',
            builder: (_, _) => const DoctorCalendarPage(admin: true),
          ),
          GoRoute(path: '/admin/audit-logs', builder: (_, _) => const AuditLogsPage()),
          GoRoute(path: '/admin/system-health', builder: (_, _) => const SystemHealthPage()),
          GoRoute(
            path: '/admin/analytics/hospital',
            builder: (_, _) => const HospitalAnalyticsPage(),
          ),
          GoRoute(path: '/admin/analytics/system', builder: (_, _) => const SystemAnalyticsPage()),
          GoRoute(
            path: '/admin/deliveries',
            builder: (_, _) => const AdminDeliveriesPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => StaffOrderPage(
                  orderId: s.pathParameters['id']!,
                  backPath: '/admin/deliveries',
                  backLabel: 'Deliveries',
                ),
              ),
            ],
          ),
          // D-70: order tracking and drug inventory for admins.
          GoRoute(
            path: '/admin/orders',
            builder: (_, _) => const OrderTrackingPage(admin: true),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => StaffOrderPage(
                  orderId: s.pathParameters['id']!,
                  backPath: '/admin/orders',
                  backLabel: 'Orders',
                ),
              ),
            ],
          ),
          GoRoute(path: '/admin/inventory', builder: (_, _) => const InventoryPage(admin: true)),
          GoRoute(path: '/admin/assignments', builder: (_, _) => const AdminAssignmentsPage()),
        ],
      ),
    ],
  );
});
