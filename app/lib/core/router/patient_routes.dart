import '../../features/family/presentation/family_requests_page.dart';
import '../../features/family/presentation/sos_page.dart';
import '../../features/records/presentation/records_page.dart';
import '../../features/medications/data/medications_repository.dart';
import '../../features/medications/presentation/medication_form_page.dart';
import '../../features/medications/presentation/medications_page.dart';
import '../../features/messaging/presentation/chat_thread_page.dart';
import '../../features/messaging/presentation/conversation_pages.dart';
import '../../features/prescriptions/presentation/reported_prescription_page.dart';
import '../../features/provider_portal/domain/portal_models.dart';
import '../../features/settings/presentation/data_privacy_page.dart';
import '../../features/settings/presentation/profile_pages.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../shared/models/health_models.dart';
import '../../features/messaging/presentation/inbox_pages.dart';
import '../../features/symptom_checker/data/symptom_repository.dart';
import '../../features/symptom_checker/presentation/symptom_checker_page.dart';
import '../../features/symptom_checker/presentation/triage_result_page.dart';
import '../../features/ai_agent/presentation/agent_page.dart';
import 'package:go_router/go_router.dart';

import '../../features/appointments/presentation/appointments_page.dart';
import '../../features/appointments/presentation/booking_confirmed_page.dart';
import '../../features/appointments/presentation/pre_visit_summary_page.dart';
import '../../features/charts/presentation/trends_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/dashboard/presentation/patient_shell.dart';
import '../../features/vitals/data/vitals_repository.dart';
import '../../features/vitals/presentation/log_vitals_page.dart';
import '../../features/vitals/presentation/reading_saved_page.dart';
import '../../features/vitals/presentation/vitals_page.dart';
import '../../features/orders/presentation/order_confirm_page.dart';
import '../../features/orders/presentation/order_pay_page.dart';
import '../../features/orders/presentation/order_track_page.dart';
import '../../features/orders/presentation/orders_page.dart';
import '../../features/orders/presentation/address_page.dart';
import '../../features/orders/presentation/pharmacy_chat_pages.dart';

/// Patient app feature routes (docs/05). Tabs live inside the bottom-navigation
/// shell; full-screen flows sit outside it. Placeholders are replaced module by module.
final List<RouteBase> patientFeatureRoutes = [
  ShellRoute(
    builder: (_, state, child) => PatientShell(location: state.matchedLocation, child: child),
    routes: [
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
      GoRoute(path: '/vitals', builder: (_, _) => const VitalsPage()),
      GoRoute(path: '/medications', builder: (_, _) => const MedicationsPage()),
      GoRoute(path: '/records', builder: (_, _) => const RecordsPage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    ],
  ),
  GoRoute(path: '/vitals/log', builder: (_, _) => const LogVitalsPage()),
  // FR-14.2 (D-62): family requests and the SOS screen (Fig 4.3.9.1).
  GoRoute(path: '/family-requests', builder: (_, _) => const FamilyRequestsPage()),
  GoRoute(path: '/sos', builder: (_, _) => const SosPage()),
  GoRoute(
    path: '/vitals/saved',
    redirect: (_, state) => state.extra is LoggedReading ? null : '/vitals',
    builder: (_, state) => ReadingSavedPage(reading: state.extra! as LoggedReading),
  ),
  GoRoute(path: '/more', redirect: (_, _) => '/settings'),
  // D-50: record or edit a prescription from another clinic.
  GoRoute(
    path: '/medications/prescription',
    builder: (_, state) => ReportedPrescriptionPage(
      existing: state.extra is Prescription ? state.extra! as Prescription : null,
    ),
  ),
  GoRoute(path: '/settings/personal', builder: (_, _) => const PersonalInfoPage()),
  GoRoute(path: '/settings/contact', builder: (_, _) => const ContactDetailsPage()),
  GoRoute(path: '/settings/health', builder: (_, _) => const HealthProfilePage()),
  GoRoute(path: '/settings/privacy', builder: (_, _) => const DataPrivacyPage()),
  GoRoute(
    path: '/medications/add',
    // Optional draft from a doctor's prescription (D-49 "Add to my reminders").
    builder: (_, state) => MedicationFormPage(
      prefill: state.extra is MedicationDraft ? state.extra! as MedicationDraft : null,
    ),
  ),
  GoRoute(
    path: '/medications/edit',
    redirect: (_, state) => state.extra is Medication ? null : '/medications',
    builder: (_, state) => MedicationFormPage(existing: state.extra! as Medication),
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
    builder: (_, _) => const PatientInboxPage(),
    routes: [
      // :threadId = the other participant's uid (the assigned doctor).
      GoRoute(
        path: ':threadId',
        builder: (_, s) => ChatThreadPage(
          otherId: s.pathParameters['threadId']!,
          draft: s.extra is String ? s.extra! as String : null,
        ),
      ),
    ],
  ),
  GoRoute(
    path: '/ai-agent',
    // Optional quick replies passed by the screen that opened the chat (triage, reading).
    builder: (_, state) =>
        AgentPage(quickReplies: state.extra is List<String> ? state.extra! as List<String> : null),
  ),
  // Module 13 (D-66; Figs 4.3.10.1-4.3.10.3).
  GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
  // D-69: the Harvey Pharmacy conversation and the delivery address.
  GoRoute(path: '/pharmacy-chat', builder: (_, _) => const PatientPharmacyChatPage()),
  // D-76: a chat an admin opened with the patient (or between them and a pharmacist).
  GoRoute(
    path: '/conversation/:id',
    builder: (_, s) => PatientConversationPage(conversationId: s.pathParameters['id']!),
  ),
  GoRoute(path: '/settings/address', builder: (_, _) => const AddressPage()),
  GoRoute(
    path: '/orders/:id/confirm',
    builder: (_, s) => OrderConfirmPage(orderId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/orders/:id/pay',
    builder: (_, s) => OrderPayPage(orderId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/orders/:id/track',
    builder: (_, s) => OrderTrackPage(orderId: s.pathParameters['id']!),
  ),
  // Module 7 (D-53).
  GoRoute(path: '/appointments', builder: (_, _) => const AppointmentsPage()),
  GoRoute(path: '/appointments/history', builder: (_, _) => const AppointmentHistoryPage()),
  GoRoute(
    path: '/appointments/reschedule',
    redirect: (_, state) => state.extra is Appointment ? null : '/appointments',
    builder: (_, state) => AppointmentsPage(rescheduling: state.extra! as Appointment),
  ),
  GoRoute(
    path: '/appointments/booked/:id',
    builder: (_, s) => BookingConfirmedPage(appointmentId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/appointments/:id/summary',
    builder: (_, s) => PreVisitSummaryPage(appointmentId: s.pathParameters['id']!),
  ),
];
