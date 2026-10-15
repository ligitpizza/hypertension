import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/admin/state/admin_providers.dart';
import 'package:hypertension/features/appointments/data/appointments_repository.dart';
import 'package:hypertension/features/appointments/presentation/admin_appointments_page.dart';
import 'package:hypertension/features/appointments/presentation/admin_assignments_page.dart';
import 'package:hypertension/features/appointments/presentation/appointments_page.dart';
import 'package:hypertension/features/appointments/presentation/booking_confirmed_page.dart';
import 'package:hypertension/features/appointments/presentation/doctor_calendar_page.dart';
import 'package:hypertension/features/appointments/presentation/pre_visit_summary_page.dart';
import 'package:hypertension/features/appointments/presentation/reassignment_dialog.dart';
import 'package:hypertension/features/appointments/state/appointment_providers.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/provider_portal/domain/portal_models.dart';
import 'package:hypertension/features/provider_portal/state/portal_providers.dart';
import 'package:hypertension/shared/models/health_models.dart';

import '../helpers/fakes.dart';
import '../helpers/admin_fakes.dart';

// Module 7 screens (Figs 4.3.6.1, 4.3.6.2, 4.3.12.3; FR-7.1-7.4; UC7.1-UC7.5; D-53, D-54).

/// Wed 14 Oct 2026, 09:00 Malaysia time.
final now = DateTime.utc(2026, 10, 14, 1);
DateTime myt(int d, int h, [int m = 0]) => DateTime.utc(2026, 10, d, h - 8, m);

class FakeAppointmentsRepository implements AppointmentsRepository {
  List<Appointment> upcoming = const [];
  List<Appointment> history = const [];
  List<AssignmentRequest> requests = const [];
  List<AssignmentRequest> pending = const [];
  bool noDoctor = false;
  bool slotTaken = false;
  final booked = <(DateTime, AppointmentType)>[];
  List<Appointment> all = const [];
  List<Appointment> active = const [];
  bool activeOnBook = false;
  bool cancelNow = false;
  final rescheduled = <(String, DateTime, String, String?)>[];
  final cancelled = <(String, String, String?)>[];
  final calls = <String>[];

  @override
  Stream<List<Appointment>> patientAppointments(String patientId, DateTime from) =>
      Stream.value(upcoming);

  @override
  Stream<List<Appointment>> patientHistory(String patientId, DateTime before) =>
      Stream.value(history);

  @override
  Stream<List<Appointment>> doctorAppointments(String d, DateTime s, DateTime e) => Stream.value([
    for (final a in upcoming)
      if (!a.dateTime.isBefore(s) && a.dateTime.isBefore(e)) a,
  ]);

  bool customTimes = false;

  @override
  Future<DaySlots> slots(DateTime day) async {
    if (noDoctor) throw const NoDoctorException();
    final weekend = day.weekday > 5;
    return DaySlots(
      customTimes: customTimes,
      doctor: const DoctorInfo(id: 'd1', name: 'Dr John', specialty: 'Cardiology'),
      slots: weekend
          ? const []
          : [
              Slot(time: myt(day.day, 10), period: 'morning', available: true),
              Slot(time: myt(day.day, 10, 30), period: 'morning', available: false),
              Slot(time: myt(day.day, 18), period: 'evening', available: true),
            ],
      alternatives: weekend ? [myt(19, 9)] : const [],
    );
  }

  @override
  Future<String> book(DateTime time, AppointmentType type) async {
    if (slotTaken) throw SlotTakenException([myt(15, 11), myt(15, 11, 30)]);
    if (activeOnBook) {
      throw const ActiveAppointmentException('You already have an appointment on Fri 16 Oct.');
    }
    booked.add((time, type));
    return 'new1';
  }

  @override
  Future<void> requestReschedule(String id, DateTime time, String reason, {String? note}) async =>
      rescheduled.add((id, time, reason, note));

  @override
  Future<bool> requestCancel(String id, String reason, {String? note}) async {
    cancelled.add((id, reason, note));
    return cancelNow;
  }

  @override
  Future<void> withdrawRequest(String id) async => calls.add('withdraw:$id');

  @override
  Future<void> decide(String id, {required bool approve, String? note}) async =>
      calls.add('decide:$id:$approve:$note');

  @override
  Future<void> staffCancel(String id, String reason) async => calls.add('staffCancel:$id:$reason');

  @override
  Future<void> recordOutcome(String id, {required bool completed}) async =>
      calls.add('outcome:$id:${completed ? 'completed' : 'no_show'}');

  @override
  Stream<List<Appointment>> activeAppointments(String patientId) => Stream.value(active);

  @override
  Stream<List<Appointment>> allAppointments(DateTime start, DateTime end) => Stream.value([
    for (final a in all)
      if (!a.dateTime.isBefore(start) && a.dateTime.isBefore(end)) a,
  ]);

  @override
  Future<Map<String, dynamic>> preVisitSummary(String appointmentId) async => {
    'dateTime': myt(16, 10).toIso8601String(),
    'vitals': {
      'count': 5,
      'averageSystolic': 146,
      'averageDiastolic': 92,
      'highest': '158/98',
      'latest': '140/90',
      'averageHeartRate': 78,
    },
    'risk': null,
    'medications': [
      {'name': 'Losartan 50mg', 'adherenceRate': 62.0},
    ],
    'openItems': ['Low adherence: Losartan 50mg'],
    'dataGaps': ['No risk assessment yet (needs three readings).'],
    'carePlan': 'Walk daily',
  };

  @override
  Stream<List<AssignmentRequest>> myRequests(String patientId) => Stream.value(requests);

  @override
  Future<void> requestDoctor() async => calls.add('requestDoctor');

  @override
  Future<void> requestReassignment(
    String patientId, {
    String? proposedDoctorId,
    String? reason,
  }) async => calls.add('reassign:$patientId:$proposedDoctorId:$reason');

  @override
  Stream<List<AssignmentRequest>> pendingRequests() => Stream.value(pending);

  @override
  Future<void> approve(String requestId, String doctorId) async =>
      calls.add('approve:$requestId:$doctorId');

  @override
  Future<void> decline(String requestId, {String? reason}) async =>
      calls.add('decline:$requestId:$reason');

  @override
  Stream<List<PersonName>> doctors() => Stream.value(const [
    PersonName('d1', 'Dr John', role: 'doctor'),
    PersonName('d2', 'Dr Aminah', role: 'doctor'),
  ]);

  @override
  Future<PersonName?> person(String uid) async => switch (uid) {
    'd1' => const PersonName('d1', 'Dr John'),
    'p1' => const PersonName('p1', 'Siti Aminah'),
    _ => null,
  };
}

Appointment appt(
  String id,
  DateTime at, {
  AppointmentType type = AppointmentType.checkup,
  AppointmentStatus status = AppointmentStatus.booked,
  String doctorId = 'd1',
  PendingChange? pending,
  String? changeReason,
  String? cancelledBy,
}) => Appointment(
  id: id,
  patientId: 'p1',
  doctorId: doctorId,
  dateTime: at,
  status: status,
  type: type,
  pendingChange: pending,
  changeReason: changeReason,
  cancelledBy: cancelledBy,
);

Future<void> pickReason(WidgetTester t, String code, {String? note}) async {
  expect(find.byKey(const Key('change-reason-dialog')), findsOneWidget);
  await t.tap(find.byKey(Key('reason-$code')));
  await t.pump();
  if (note != null) await t.enterText(find.byKey(const Key('reason-note')), note);
  await t.pump();
  await t.tap(find.byKey(const Key('reason-send')));
  await t.pumpAndSettle();
}

Widget app(FakeAppointmentsRepository repo, {String initial = '/appointments', String uid = 'p1'}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/appointments', builder: (_, _) => const AppointmentsPage()),
      GoRoute(
        path: '/appointments/reschedule',
        builder: (_, s) => AppointmentsPage(rescheduling: s.extra! as Appointment),
      ),
      GoRoute(
        path: '/appointments/booked/:id',
        builder: (_, s) => BookingConfirmedPage(appointmentId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/appointments/:id/summary',
        builder: (_, s) => PreVisitSummaryPage(appointmentId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/calendar',
        builder: (_, _) => const Scaffold(body: DoctorCalendarPage()),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, _) => const Scaffold(body: AdminAssignmentsPage()),
      ),
      GoRoute(
        path: '/admin/appointments',
        builder: (_, _) => const Scaffold(body: AdminAppointmentsPage()),
      ),
      GoRoute(
        path: '/reassign',
        builder: (_, _) => Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => requestReassignment(c, 'p1', 'Siti'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/dashboard', builder: (_, _) => const Text('HOME')),
      GoRoute(
        path: '/doctor/patient/:id',
        builder: (_, s) => Text('PATIENT ${s.pathParameters['id']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appointmentsRepositoryProvider.overrideWithValue(repo),
      adminRepositoryProvider.overrideWithValue(admin),
      nowProvider.overrideWithValue(() => now),
      authUidProvider.overrideWith((ref) => Stream.value(uid)),
      assignedPatientsProvider.overrideWith(
        (ref) => Stream.value(const [PortalPatient(uid: 'p1', name: 'Siti Aminah')]),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

final admin = FakeAdminRepository()
  ..all = [
    user('d1', 'Dr John', UserRole.doctor, caseload: 12),
    user('d2', 'Dr Aminah', UserRole.doctor, caseload: 30),
  ];

void main() {
  late FakeAppointmentsRepository repo;
  setUp(() => repo = FakeAppointmentsRepository());

  group('Fig 4.3.6.1 booking (UC7.1)', () {
    tallTest('pick a time, choose follow-up and book with the assigned doctor', (t) async {
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('booking-doctor')), findsOneWidget);
      expect(find.textContaining('Dr John'), findsWidgets);
      expect(find.text('Choose a time'), findsOneWidget);
      await t.tap(find.text('Follow-up'));
      await t.tap(find.byKey(const Key('slot-10:00 AM')));
      await t.pump();
      expect(find.textContaining('Book Today, 10:00 AM'), findsOneWidget);
      await t.tap(find.byKey(const Key('book-appointment')));
      await t.pumpAndSettle();
      expect(repo.booked, [(myt(14, 10), AppointmentType.followUp)]);
      expect(find.byKey(const Key('booking-confirmed')), findsOneWidget);
    });

    tallTest('taken slots are disabled; evening tab shows evening slots', (t) async {
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      final taken = t.widget<ChoiceChip>(find.byKey(const Key('slot-10:30 AM')));
      expect(taken.onSelected, isNull);
      await t.tap(find.byKey(const Key('period-evening')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('slot-6:00 PM')), findsOneWidget);
      expect(find.byKey(const Key('slot-10:00 AM')), findsNothing);
    });

    tallTest('E1 a slot taken meanwhile offers the nearest alternatives', (t) async {
      repo.slotTaken = true;
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('slot-10:00 AM')));
      await t.pump();
      await t.tap(find.byKey(const Key('book-appointment')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('alternatives')), findsOneWidget);
      await t.tap(find.text('Tomorrow, 11:00 AM'));
      await t.pumpAndSettle();
      expect(find.textContaining('Book Tomorrow, 11:00 AM'), findsOneWidget);
    });

    tallTest('weekends cannot be chosen', (t) async {
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      final saturday = t.widget<InkWell>(find.byKey(const Key('day-2026-10-17')));
      expect(saturday.onTap, isNull);
    });
  });

  tallTest('the back button returns home when there is nothing to go back to', (t) async {
    await t.pumpWidget(app(repo));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('appointments-back')));
    await t.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  group('D-54 no doctor yet', () {
    tallTest('the patient requests a doctor; then sees it is waiting', (t) async {
      repo.noDoctor = true;
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('no-doctor')), findsOneWidget);
      await t.tap(find.byKey(const Key('request-doctor')));
      await t.pumpAndSettle();
      expect(repo.calls, ['requestDoctor']);
    });

    tallTest('a pending request shows instead of the button', (t) async {
      repo
        ..noDoctor = true
        ..requests = [
          AssignmentRequest(
            id: 'r1',
            patientId: 'p1',
            requestedBy: 'p1',
            kind: AssignmentRequestKind.newPatient,
            status: AssignmentRequestStatus.pending,
            createdAt: now,
          ),
        ];
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('doctor-request-pending')), findsOneWidget);
      expect(find.byKey(const Key('request-doctor')), findsNothing);
    });
  });

  group('UC7.2 next appointment', () {
    tallTest('shows the doctor, time and summary link; cancel within 24 h warns', (t) async {
      repo.upcoming = [appt('a1', myt(14, 18))];
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.textContaining('Upcoming · Today, 6:00 PM'), findsOneWidget);
      expect(find.text('Dr John'), findsOneWidget);
      await t.tap(find.byKey(const Key('cancel-a1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('late-change-warning')), findsOneWidget);
      await t.tap(find.byKey(const Key('late-change-continue')));
      await t.pumpAndSettle();
      await pickReason(t, 'transport');
      expect(repo.cancelled, [('a1', 'transport', null)]);
    });

    tallTest('D-55 cancelling sends a request with a reason; "Other" needs a note', (t) async {
      repo.upcoming = [appt('a1', myt(20, 10))];
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cancel-a1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('late-change-warning')), findsNothing);
      await t.tap(find.byKey(const Key('reason-other')));
      await t.pump();
      expect(t.widget<FilledButton>(find.byKey(const Key('reason-send'))).onPressed, isNull);
      await pickReason(t, 'other', note: 'Travelling');
      expect(repo.cancelled, [('a1', 'other', 'Travelling')]);
      expect(find.text('Cancellation request sent. Your doctor will confirm.'), findsOneWidget);
    });

    tallTest('D-55 a pending request shows a banner that can be withdrawn', (t) async {
      repo.upcoming = [
        appt(
          'a1',
          myt(20, 10),
          pending: const PendingChange(kind: 'cancel', reason: 'cost'),
        ),
      ];
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pending-a1')), findsOneWidget);
      expect(
        find.textContaining('Cancellation requested · waiting for your doctor'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('cancel-a1')), findsNothing);
      await t.tap(find.byKey(const Key('withdraw-a1')));
      await t.pumpAndSettle();
      expect(repo.calls, ['withdraw:a1']);
    });

    tallTest('reschedule picks a new time for the same appointment', (t) async {
      repo.upcoming = [appt('a1', myt(20, 10))];
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('reschedule-a1')));
      await t.pumpAndSettle();
      expect(find.text('Choose a new time'), findsOneWidget);
      await t.tap(find.byKey(const Key('slot-10:00 AM')));
      await t.pump();
      await t.tap(find.byKey(const Key('book-appointment')));
      await t.pumpAndSettle();
      await pickReason(t, 'schedule_conflict', note: 'Work meeting');
      expect(repo.rescheduled, [('a1', myt(14, 10), 'schedule_conflict', 'Work meeting')]);
      expect(repo.booked, isEmpty);
    });
  });

  tallTest('UC7.5 pre-visit summary with E1 data gaps', (t) async {
    await t.pumpWidget(app(repo, initial: '/appointments/a1/summary'));
    await t.pumpAndSettle();
    expect(find.text('Average 146/92 mmHg (5 readings)'), findsOneWidget);
    expect(find.textContaining('(estimate)'), findsOneWidget);
    expect(find.byKey(const Key('summary-gaps')), findsOneWidget);
    expect(find.text('Low adherence: Losartan 50mg'), findsOneWidget);
  });

  group('Fig 4.3.12.3 doctor calendar', () {
    tallTest('month view counts and colours; daily agenda opens the summary', (t) async {
      repo.upcoming = [
        appt('a1', myt(16, 10)),
        appt('a2', myt(16, 15), type: AppointmentType.emergency),
        appt('a3', myt(20, 9), type: AppointmentType.followUp),
      ];
      await t.pumpWidget(app(repo, initial: '/calendar', uid: 'd1'));
      await t.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('3 scheduled appointments · 1 emergency'), findsOneWidget);
      expect(find.text('10:00 AM S. Aminah'), findsOneWidget);
      await t.tap(find.byKey(const Key('cal-day-16')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agenda-a1')), findsOneWidget);
      expect(find.byKey(const Key('agenda-a3')), findsNothing);
      await t.tap(find.byKey(const Key('agenda-a2')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('appointment-details')), findsOneWidget);
      expect(find.byKey(const Key('pre-visit-summary')), findsOneWidget);
    });
  });

  tallTest('a cancelled appointment stays on the calendar, struck through and labelled', (t) async {
    repo.upcoming = [
      appt('a1', myt(16, 10)),
      Appointment(
        id: 'a2',
        patientId: 'p1',
        doctorId: 'd1',
        dateTime: myt(16, 15),
        status: AppointmentStatus.cancelled,
        updatedAt: myt(15, 9),
      ),
    ];
    await t.pumpWidget(app(repo, initial: '/calendar', uid: 'd1'));
    await t.pumpAndSettle();
    expect(find.text('1 scheduled appointments · 0 emergencies · 1 cancelled'), findsOneWidget);
    final chip = t.widget<Text>(
      find.descendant(of: find.byKey(const Key('chip-a2')), matching: find.byType(Text)),
    );
    expect(chip.style?.decoration, TextDecoration.lineThrough);
    await t.tap(find.byKey(const Key('cal-day-16')));
    await t.pumpAndSettle();
    expect(find.text('Cancelled Thu 15 Oct, 9:00 AM'), findsOneWidget);
  });

  group('D-54 admin and doctor', () {
    final req = AssignmentRequest(
      id: 'r1',
      patientId: 'p1',
      requestedBy: 'd1',
      kind: AssignmentRequestKind.reassign,
      status: AssignmentRequestStatus.pending,
      createdAt: now,
      proposedDoctorId: 'd2',
      reason: 'Moving to Penang',
    );

    tallTest('admin approves with the suggested doctor preselected', (t) async {
      repo.pending = [req];
      await t.pumpWidget(app(repo, initial: '/admin', uid: 'admin'));
      await t.pumpAndSettle();
      expect(find.text('Reassignment requested'), findsOneWidget);
      expect(find.text('Reason: Moving to Penang'), findsOneWidget);
      await t.tap(find.byKey(const Key('approve-r1')));
      await t.pumpAndSettle();
      // The requesting doctor is not offered; the suggested one is preselected.
      await t.tap(find.byKey(const Key('choose-doctor-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, ['approve:r1:d2']);
    });

    tallTest('admin declines with a message', (t) async {
      repo.pending = [req];
      await t.pumpWidget(app(repo, initial: '/admin', uid: 'admin'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('decline-r1')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('decline-reason')), 'Please visit the clinic.');
      await t.tap(find.byKey(const Key('decline-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, ['decline:r1:Please visit the clinic.']);
    });

    tallTest('D-59 caseloads beside the requests; a full doctor is flagged', (t) async {
      repo.pending = [req];
      await t.pumpWidget(app(repo, initial: '/admin', uid: 'admin'));
      await t.pumpAndSettle();
      expect(find.text('12 / 30 patients'), findsOneWidget);
      expect(find.text('30 / 30 patients'), findsOneWidget);
      expect(find.text('Full'), findsWidgets);
      await t.tap(find.byKey(const Key('approve-r1')));
      await t.pumpAndSettle();
      // Dr Aminah (d2) is suggested and full.
      expect(find.byKey(const Key('doctor-full')), findsOneWidget);
      expect(find.text('Assign anyway'), findsOneWidget);
    });

    tallTest('no pending requests', (t) async {
      await t.pumpWidget(app(repo, initial: '/admin', uid: 'admin'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('no-requests')), findsOneWidget);
    });

    tallTest('doctor asks for a reassignment, suggesting a colleague', (t) async {
      await t.pumpWidget(app(repo, initial: '/reassign', uid: 'd1'));
      await t.pumpAndSettle();
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('reassign-doctor')));
      await t.pumpAndSettle();
      expect(find.text('Dr John'), findsNothing); // not themselves
      await t.tap(find.text('Dr Aminah').last);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('reassign-reason')), 'Specialist care');
      await t.tap(find.byKey(const Key('reassign-send')));
      await t.pumpAndSettle();
      expect(repo.calls, ['reassign:p1:d2:Specialist care']);
    });
  });

  group('D-55 doctor decides', () {
    tallTest('the calendar flags a request; the doctor approves it', (t) async {
      repo.upcoming = [
        appt(
          'a1',
          myt(16, 10),
          pending: PendingChange(kind: 'reschedule', reason: 'transport', dateTime: myt(19, 11)),
        ),
      ];
      await t.pumpWidget(app(repo, initial: '/calendar', uid: 'd1'));
      await t.pumpAndSettle();
      expect(find.textContaining('1 waiting for you'), findsOneWidget);
      await t.tap(find.byKey(const Key('cal-day-16')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('request-a1')), findsOneWidget);
      await t.tap(find.byKey(const Key('agenda-a1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('details-pending')), findsOneWidget);
      expect(find.text('Patient asks to move to Mon 19 Oct, 11:00 AM'), findsOneWidget);
      expect(find.text('Reason: Transport problem'), findsOneWidget);
      await t.tap(find.byKey(const Key('details-approve')));
      await t.pumpAndSettle();
      expect(repo.calls, ['decide:a1:true:null']);
    });

    tallTest('the doctor declines with a message', (t) async {
      repo.upcoming = [
        appt(
          'a1',
          myt(16, 10),
          pending: const PendingChange(kind: 'cancel', reason: 'cost'),
        ),
      ];
      await t.pumpWidget(app(repo, initial: '/calendar', uid: 'd1'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cal-day-16')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('agenda-a1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('details-decline')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('staff-note')), 'Please keep it; BP is high.');
      await t.tap(find.byKey(const Key('staff-note-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, ['decide:a1:false:Please keep it; BP is high.']);
    });

    tallTest('the doctor cancels with a required reason', (t) async {
      repo.upcoming = [appt('a1', myt(16, 10))];
      await t.pumpWidget(app(repo, initial: '/calendar', uid: 'd1'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cal-day-16')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('agenda-a1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('details-cancel')));
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(find.byKey(const Key('staff-note-confirm'))).onPressed, isNull);
      await t.enterText(find.byKey(const Key('staff-note')), 'Doctor on leave');
      await t.pump();
      await t.tap(find.byKey(const Key('staff-note-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, ['staffCancel:a1:Doctor on leave']);
    });
  });

  group('D-55 admin appointments overview', () {
    setUp(
      () => repo.all = [
        appt('a1', myt(16, 10)),
        appt('a2', myt(16, 11), doctorId: 'd2', status: AppointmentStatus.rescheduled),
        appt(
          'a3',
          myt(19, 9),
          status: AppointmentStatus.cancelled,
          cancelledBy: 'patient',
          changeReason: 'Cost',
        ),
        appt(
          'a4',
          myt(20, 9),
          pending: const PendingChange(kind: 'cancel', reason: 'cost'),
        ),
        appt('a5', myt(20, 9).add(const Duration(days: 30))), // next month
      ],
    );

    tallTest('lists the month across doctors with status counts and filters', (t) async {
      await t.pumpWidget(app(repo, initial: '/admin/appointments', uid: 'admin'));
      await t.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('All (4)'), findsOneWidget);
      expect(find.text('Change requested (1)'), findsOneWidget);
      expect(find.text('Cancelled (1)'), findsOneWidget);
      expect(find.byKey(const Key('admin-appt-a5')), findsNothing);
      expect(find.textContaining('Cancelled by patient: Cost'), findsOneWidget);
      await t.tap(find.byKey(const Key('filter-cancelled')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin-appt-a3')), findsOneWidget);
      expect(find.byKey(const Key('admin-appt-a1')), findsNothing);
      await t.tap(find.byKey(const Key('filter-rescheduled')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin-appt-a2')), findsOneWidget);
      expect(find.byKey(const Key('admin-appt-a3')), findsNothing);
    });

    tallTest('filters by doctor and moves between months', (t) async {
      await t.pumpWidget(app(repo, initial: '/admin/appointments', uid: 'admin'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('admin-doctor-filter')));
      await t.pumpAndSettle();
      await t.tap(find.text('Dr Aminah').last);
      await t.pumpAndSettle();
      expect(find.text('All (1)'), findsOneWidget);
      expect(find.byKey(const Key('admin-appt-a2')), findsOneWidget);
      await t.tap(find.byKey(const Key('admin-doctor-filter')));
      await t.pumpAndSettle();
      await t.tap(find.text('All doctors').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('admin-next-month')));
      await t.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.byKey(const Key('admin-appt-a5')), findsOneWidget);
    });

    tallTest('the admin decides a pending request', (t) async {
      await t.pumpWidget(app(repo, initial: '/admin/appointments', uid: 'admin'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('filter-requested')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('admin-appt-a4')));
      await t.pumpAndSettle();
      expect(find.text('Patient asks to cancel'), findsOneWidget);
      expect(find.text('Open patient'), findsNothing);
      await t.tap(find.byKey(const Key('details-approve')));
      await t.pumpAndSettle();
      expect(repo.calls, ['decide:a4:true:null']);
    });
  });

  group('D-56 one booking at a time; the doctor records the outcome', () {
    tallTest('an active appointment closes booking but keeps the next-appointment card', (t) async {
      repo
        ..upcoming = [appt('a1', myt(20, 10))]
        ..active = [appt('a1', myt(20, 10))];
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('one-at-a-time')), findsOneWidget);
      expect(find.textContaining('You already have an appointment: Tue 20 Oct'), findsOneWidget);
      expect(find.byKey(const Key('book-appointment')), findsNothing);
      expect(find.byKey(const Key('reschedule-a1')), findsOneWidget);
    });

    tallTest('a past visit the doctor has not closed also blocks booking', (t) async {
      repo.active = [appt('old', myt(12, 10))];
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.textContaining('once your doctor has closed this visit'), findsOneWidget);
    });

    tallTest('the server refusal is shown if booking races another device', (t) async {
      repo.activeOnBook = true;
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('slot-10:00 AM')));
      await t.pump();
      await t.tap(find.byKey(const Key('book-appointment')));
      await t.pumpAndSettle();
      expect(find.text('You already have an appointment on Fri 16 Oct.'), findsOneWidget);
      expect(repo.booked, isEmpty);
    });

    tallTest('an unclosed past visit is flagged; the doctor completes it', (t) async {
      repo.upcoming = [appt('a1', myt(13, 10)), appt('a2', myt(16, 10))];
      await t.pumpWidget(app(repo, initial: '/calendar', uid: 'd1'));
      await t.pumpAndSettle();
      expect(find.textContaining('1 to complete'), findsOneWidget);
      await t.tap(find.byKey(const Key('cal-day-13')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('overdue-a1')), findsOneWidget);
      await t.tap(find.byKey(const Key('agenda-a1')));
      await t.pumpAndSettle();
      expect(find.text('Not completed yet: record how the visit went.'), findsOneWidget);
      await t.tap(find.byKey(const Key('details-complete')));
      await t.pumpAndSettle();
      expect(repo.calls, ['outcome:a1:completed']);
    });

    tallTest('no outcome buttons before the appointment starts', (t) async {
      repo.upcoming = [appt('a1', myt(16, 10))];
      await t.pumpWidget(app(repo, initial: '/calendar', uid: 'd1'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cal-day-16')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('agenda-a1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('details-outcome')), findsNothing);
    });

    tallTest('once started the doctor can mark a no-show', (t) async {
      repo.upcoming = [appt('a2', myt(14, 8, 45))];
      await t.pumpWidget(app(repo, initial: '/calendar', uid: 'd1'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cal-day-14')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('agenda-a2')));
      await t.pumpAndSettle();
      expect(find.text('The appointment has started.'), findsOneWidget);
      await t.tap(find.byKey(const Key('details-no-show')));
      await t.pumpAndSettle();
      expect(repo.calls, ['outcome:a2:no_show']);
    });

    tallTest('the admin filters for visits not completed and no-shows', (t) async {
      repo.all = [
        appt('a1', myt(12, 10)),
        appt('a2', myt(12, 11), status: AppointmentStatus.noShow),
        appt('a3', myt(16, 10)),
      ];
      await t.pumpWidget(app(repo, initial: '/admin/appointments', uid: 'admin'));
      await t.pumpAndSettle();
      expect(find.text('Not completed (1)'), findsOneWidget);
      await t.tap(find.byKey(const Key('filter-notCompleted')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin-appt-a1')), findsOneWidget);
      expect(find.byKey(const Key('admin-appt-a3')), findsNothing);
      await t.tap(find.byKey(const Key('filter-noShow')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin-appt-a2')), findsOneWidget);
      expect(find.textContaining('no-show'), findsOneWidget);
    });
  });

  group('D-57 testing aid', () {
    tallTest('hidden unless the backend allows any time', (t) async {
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pick-any-time')), findsNothing);
    });

    tallTest('pick any date and time, then book it', (t) async {
      repo.customTimes = true;
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pick-any-time')));
      await t.pumpAndSettle();
      await t.tap(find.text('OK')); // today
      await t.pumpAndSettle();
      await t.tap(find.text('OK')); // the time now
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('book-appointment')));
      await t.pumpAndSettle();
      expect(repo.booked.single.$1, myt(14, 9));
    });
  });
}
