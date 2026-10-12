import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/dashboard/presentation/patient_shell.dart';

/// Patient app feature routes (docs/05). Tabs live inside the bottom-navigation
/// shell; full-screen flows sit outside it. Placeholders are replaced module by module.
final List<RouteBase> patientFeatureRoutes = [
  ShellRoute(
    builder: (_, state, child) => PatientShell(location: state.matchedLocation, child: child),
    routes: [
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
      GoRoute(
        path: '/vitals',
        builder: (_, _) => const ComingSoonPage(
          title: 'Vitals',
          note: 'Your blood pressure readings and trends are coming soon.',
        ),
      ),
      GoRoute(
        path: '/medications',
        builder: (_, _) => const ComingSoonPage(
          title: 'Medications',
          note: 'Medication reminders and tracking are coming soon.',
        ),
      ),
      GoRoute(
        path: '/records',
        builder: (_, _) => const ComingSoonPage(
          title: 'Health records',
          note: 'Uploading and sharing your medical documents is coming soon.',
        ),
      ),
      GoRoute(path: '/more', builder: (_, _) => const MorePage()),
    ],
  ),
  GoRoute(
    path: '/vitals/log',
    builder: (_, _) =>
        const ComingSoonPage(title: 'Log vitals', note: 'Blood pressure logging is coming soon.'),
  ),
  GoRoute(
    path: '/symptom',
    builder: (_, _) =>
        const ComingSoonPage(title: 'Symptom checker', note: 'The symptom checker is coming soon.'),
  ),
  GoRoute(
    path: '/chat',
    builder: (_, _) => const ComingSoonPage(
      title: 'Messages',
      note: 'Secure messaging with your doctor is coming soon.',
    ),
  ),
  GoRoute(
    path: '/ai-agent',
    builder: (_, _) =>
        const ComingSoonPage(title: 'AI Health Agent', note: 'The AI Health Agent is coming soon.'),
  ),
  GoRoute(
    path: '/appointments',
    builder: (_, _) =>
        const ComingSoonPage(title: 'Appointments', note: 'Appointment booking is coming soon.'),
  ),
];
