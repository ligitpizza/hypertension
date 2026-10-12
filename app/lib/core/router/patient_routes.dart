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
          note: 'Your readings and trends arrive with Modules 3 and 4.',
        ),
      ),
      GoRoute(
        path: '/medications',
        builder: (_, _) => const ComingSoonPage(
          title: 'Medications',
          note: 'Medication tracking arrives with Module 5 (Increment 3).',
        ),
      ),
      GoRoute(
        path: '/records',
        builder: (_, _) => const ComingSoonPage(
          title: 'Health records',
          note: 'Document upload and sharing arrive with Module 6 (Increment 3).',
        ),
      ),
      GoRoute(path: '/more', builder: (_, _) => const MorePage()),
    ],
  ),
  GoRoute(
    path: '/vitals/log',
    builder: (_, _) => const ComingSoonPage(
      title: 'Log vitals',
      note: 'Blood pressure logging arrives with Module 3.',
    ),
  ),
  GoRoute(
    path: '/symptom',
    builder: (_, _) => const ComingSoonPage(
      title: 'Symptom checker',
      note: 'The symptom checker arrives in Increment 2.',
    ),
  ),
  GoRoute(
    path: '/chat',
    builder: (_, _) => const ComingSoonPage(
      title: 'Messages',
      note: 'Secure messaging with your doctor arrives in Increment 3.',
    ),
  ),
  GoRoute(
    path: '/ai-agent',
    builder: (_, _) => const ComingSoonPage(
      title: 'AI Health Agent',
      note: 'The AI Health Agent arrives in Increment 2.',
    ),
  ),
  GoRoute(
    path: '/appointments',
    builder: (_, _) => const ComingSoonPage(
      title: 'Appointments',
      note: 'Appointment booking arrives with Module 7 (Increment 3).',
    ),
  ),
];
