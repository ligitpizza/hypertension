import '../../features/symptom_checker/data/symptom_repository.dart';
import '../../features/symptom_checker/presentation/symptom_checker_page.dart';
import '../../features/symptom_checker/presentation/triage_result_page.dart';
import '../../features/ai_agent/presentation/agent_page.dart';
import 'package:go_router/go_router.dart';

import '../../features/charts/presentation/trends_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/dashboard/presentation/patient_shell.dart';
import '../../features/vitals/data/vitals_repository.dart';
import '../../features/vitals/presentation/log_vitals_page.dart';
import '../../features/vitals/presentation/reading_saved_page.dart';
import '../../features/vitals/presentation/vitals_page.dart';

/// Patient app feature routes (docs/05). Tabs live inside the bottom-navigation
/// shell; full-screen flows sit outside it. Placeholders are replaced module by module.
final List<RouteBase> patientFeatureRoutes = [
  ShellRoute(
    builder: (_, state, child) => PatientShell(location: state.matchedLocation, child: child),
    routes: [
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
      GoRoute(path: '/vitals', builder: (_, _) => const VitalsPage()),
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
  GoRoute(path: '/vitals/log', builder: (_, _) => const LogVitalsPage()),
  GoRoute(
    path: '/vitals/saved',
    redirect: (_, state) => state.extra is LoggedReading ? null : '/vitals',
    builder: (_, state) => ReadingSavedPage(reading: state.extra! as LoggedReading),
  ),
  GoRoute(path: '/trends', builder: (_, _) => const TrendsPage()),
  GoRoute(path: '/symptom', builder: (_, _) => const SymptomCheckerPage()),
  GoRoute(
    path: '/symptom/result/:id',
    // The result comes from the submission; a stale link goes back to the checker.
    redirect: (_, state) => state.extra is TriageResult ? null : '/symptom',
    builder: (_, state) => TriageResultPage(result: state.extra! as TriageResult),
  ),
  GoRoute(
    path: '/chat',
    builder: (_, _) => const ComingSoonPage(
      title: 'Messages',
      note: 'Secure messaging with your doctor is coming soon.',
    ),
  ),
  GoRoute(path: '/ai-agent', builder: (_, _) => const AgentPage()),
  GoRoute(
    path: '/appointments',
    builder: (_, _) =>
        const ComingSoonPage(title: 'Appointments', note: 'Appointment booking is coming soon.'),
  ),
];
