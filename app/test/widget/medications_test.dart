import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/medications/data/background_access.dart';
import 'package:hypertension/features/medications/data/dose_reminders.dart';
import 'package:hypertension/features/medications/data/medications_repository.dart';
import 'package:hypertension/features/medications/presentation/medication_form_page.dart';
import 'package:hypertension/features/medications/presentation/medications_page.dart';
import 'package:hypertension/features/medications/state/medication_providers.dart';
import 'package:hypertension/features/prescriptions/presentation/reported_prescription_page.dart';
import 'package:hypertension/features/provider_portal/domain/portal_models.dart';
import 'package:hypertension/shared/models/health_models.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

// Module 5 screens: Fig 4.3.5.1 (FR-5.1-5.4; UC5.1-UC5.3, UC5.5, UC5.6; D-43).

final now = DateTime.utc(2026, 10, 14, 4); // 12:00 MYT

class FakeMedicationsRepository implements MedicationsRepository {
  final logs = <String, List<DoseLog>>{};
  final confirmed = <(String, DateTime?)>[];
  final saved = <(MedicationDraft, String?, bool)>[];
  final deleted = <String>[];
  Object? confirmError;
  MedicationWarnings? warnings;
  bool late = false;
  List<Prescription> rx = const [];

  @override
  Stream<List<Prescription>> prescriptions(String patientId) => Stream.value(rx);

  final reported = <(String, String?)>[];
  final deletedRx = <String>[];

  @override
  Future<void> saveReportedPrescription(ReportedPrescription rx, {String? id}) async =>
      reported.add(('${rx.toJson()}', id));

  @override
  Future<void> deleteReportedPrescription(String id) async => deletedRx.add(id);

  @override
  Stream<List<DoseLog>> doseLogs(String medicationId, DateTime since) =>
      Stream.value(logs[medicationId] ?? const []);

  @override
  Future<bool> confirmDose(String medicationId, {DateTime? scheduledTime}) async {
    if (confirmError != null) throw confirmError!;
    confirmed.add((medicationId, scheduledTime));
    return late;
  }

  @override
  Future<void> save(MedicationDraft draft, {String? id, bool acknowledge = false}) async {
    saved.add((draft, id, acknowledge));
    if (warnings != null && !acknowledge) throw warnings!;
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

Medication med(String id, String name, String schedule, {double? qty, double? rate}) => Medication(
  id: id,
  patientId: 'p1',
  name: name,
  dosage: '5mg',
  schedule: schedule,
  quantityOnHand: qty,
  adherenceRate: rate,
);

final pushed = <(String, Object?)>[];

class FakeBackground implements BackgroundAccess {
  FakeBackground({this.free = true});

  bool free;
  bool hidden = false;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<bool> unrestricted() async => free;

  @override
  Future<void> request() async {
    requests++;
    free = true;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<bool> dismissed() async => hidden;

  @override
  Future<void> dismiss() async => hidden = true;
}

class FakeReminders implements DoseReminders {
  FakeReminders({this.exact = true});

  bool exact;
  int requests = 0;
  final synced = <int>[];

  @override
  Future<bool> exactAllowed() async => exact;

  @override
  Future<void> requestExact() async {
    requests++;
    exact = true; // the patient switched it on
  }

  @override
  Future<ReminderStatus> sync(List<Medication> meds) async {
    synced.add(meds.length);
    return const ReminderStatus();
  }
}

Widget app(
  FakeMedicationsRepository repo,
  List<Medication> meds, {
  String initial = '/medications',
  Object? extra,
  String? doctorId = 'd1',
  FakeReminders? reminders,
  FakeBackground? background,
}) {
  final router = GoRouter(
    initialLocation: initial,
    initialExtra: extra,
    routes: [
      GoRoute(path: '/medications', builder: (_, _) => const MedicationsPage()),
      GoRoute(
        path: '/medications/add',
        builder: (_, s) => MedicationFormPage(
          prefill: s.extra is MedicationDraft ? s.extra! as MedicationDraft : null,
        ),
      ),
      GoRoute(
        path: '/medications/edit',
        builder: (_, s) => MedicationFormPage(existing: s.extra! as Medication),
      ),
      GoRoute(
        path: '/medications/prescription',
        builder: (_, s) => ReportedPrescriptionPage(
          existing: s.extra is Prescription ? s.extra! as Prescription : null,
        ),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (_, s) {
          pushed.add(('/chat/${s.pathParameters['id']}', s.extra));
          return const Text('CHAT');
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      medicationsRepositoryProvider.overrideWithValue(repo),
      doseRemindersProvider.overrideWithValue(reminders ?? FakeReminders()),
      backgroundAccessProvider.overrideWithValue(background ?? FakeBackground()),
      medicationsProvider.overrideWith((ref) => Stream.value(meds)),
      authUidProvider.overrideWith((ref) => Stream.value('p1')),
      nowProvider.overrideWithValue(() => now),
      currentUserProvider.overrideWith(
        (ref) => Stream.value(
          AppUser(
            uid: 'p1',
            email: 's@x.my',
            name: 'Sarah Lim',
            role: UserRole.patient,
            isActive: true,
            onboardingComplete: true,
            assignedDoctorId: doctorId,
          ),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

DoseLog taken(String medId, DateTime at) => DoseLog(
  id: '${medId}_202610140800',
  medicationId: medId,
  scheduledTime: at,
  status: 'taken',
  confirmedAt: at.add(const Duration(minutes: 15)),
);

void main() {
  setUp(pushed.clear);

  testWidgets('empty list invites the patient to add a medicine (FR-5.1)', (t) async {
    await t.pumpWidget(app(FakeMedicationsRepository(), const []));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('meds-empty')), findsOneWidget);
    await t.tap(find.byKey(const Key('add-medication')));
    await t.pumpAndSettle();
    expect(find.text('Add medication'), findsOneWidget);
  });

  testWidgets("UC5.3 today's schedule grouped by time with progress", (t) async {
    final repo = FakeMedicationsRepository()
      ..logs['m1'] = [taken('m1', DateTime.utc(2026, 10, 14, 0))];
    await t.pumpWidget(
      app(repo, [med('m1', 'Lisinopril', '08:00'), med('m2', 'Atorvastatin', '12:30,20:00')]),
    );
    await t.pumpAndSettle();
    expect(find.text('Wed, Oct 14'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('MORNING'), findsOneWidget);
    expect(find.text('AFTERNOON'), findsOneWidget);
    expect(find.text('NIGHT'), findsOneWidget);
    expect(find.text('Taken at 8:15 AM'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget); // 20:00

    await t.tap(find.byKey(const Key('take-m2-12:30')));
    await t.pumpAndSettle();
    expect(repo.confirmed, [('m2', DateTime.utc(2026, 10, 14, 4, 30))]);
    expect(find.text('Atorvastatin dose recorded.'), findsOneWidget);
  });

  testWidgets('a dose already recorded elsewhere shows a friendly message', (t) async {
    final repo = FakeMedicationsRepository()
      ..confirmError = ApiException('DOSE_ALREADY_LOGGED', 'x', statusCode: 409);
    await t.pumpWidget(app(repo, [med('m1', 'Lisinopril', '12:00')]));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('take-m1-12:00')));
    await t.pumpAndSettle();
    expect(find.text('That dose is already recorded.'), findsOneWidget);
  });

  testWidgets('as-needed medicines log a dose now (UC5.3)', (t) async {
    final repo = FakeMedicationsRepository();
    await t.pumpWidget(app(repo, [med('m3', 'Ibuprofen', 'as_needed')]));
    await t.pumpAndSettle();
    expect(find.text('AS NEEDED (PRN)'), findsOneWidget);
    expect(find.byKey(const Key('meds-progress')), findsNothing);
    await t.tap(find.byKey(const Key('log-m3')));
    await t.pumpAndSettle();
    expect(repo.confirmed, [('m3', null)]);
  });

  testWidgets('UC5.5 adherence per medicine, none without history', (t) async {
    await t.pumpWidget(
      app(FakeMedicationsRepository(), [
        med('m1', 'Lisinopril', '08:00', rate: 75),
        med('m2', 'Amlodipine', '20:00'),
      ]),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('medicine-m2')), 200);
    expect(find.textContaining('Adherence (30 days): 75%'), findsOneWidget);
    expect(find.textContaining('Adherence: no history yet'), findsOneWidget);
  });

  testWidgets('UC5.2 refill alert opens a pre-filled request to the doctor', (t) async {
    await t.pumpWidget(
      app(FakeMedicationsRepository(), [med('m1', 'Lisinopril', '20:00', qty: 3)]),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('request-refill-m1')), 200);
    expect(find.text('3 days left'), findsOneWidget);
    await t.tap(find.byKey(const Key('request-refill-m1')));
    await t.pumpAndSettle();
    expect(pushed.single.$1, '/chat/d1');
    expect(pushed.single.$2, contains('running low on Lisinopril 5mg'));
  });

  testWidgets('refill request without an assigned doctor explains why', (t) async {
    await t.pumpWidget(
      app(FakeMedicationsRepository(), [med('m1', 'Lisinopril', '20:00', qty: 3)], doctorId: null),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('request-refill-m1')), 200);
    await t.tap(find.byKey(const Key('request-refill-m1')));
    await t.pumpAndSettle();
    expect(pushed, isEmpty);
    expect(find.textContaining('No doctor is assigned'), findsOneWidget);
  });

  testWidgets('D-43 asks for exact reminders only when they are not allowed', (t) async {
    final reminders = FakeReminders(exact: false);
    await t.pumpWidget(
      app(FakeMedicationsRepository(), [med('m1', 'Lisinopril', '20:00')], reminders: reminders),
    );
    await t.pumpAndSettle();
    expect(find.text('Reminders may arrive late'), findsOneWidget);
    await t.tap(find.byKey(const Key('allow-exact-reminders')));
    await t.pumpAndSettle();
    expect(reminders.requests, 1);
    expect(reminders.synced, isNotEmpty); // re-scheduled with the new precision
    expect(find.byKey(const Key('exact-reminders-banner')), findsNothing);
  });

  testWidgets('no banner when exact reminders are allowed', (t) async {
    await t.pumpWidget(app(FakeMedicationsRepository(), [med('m1', 'Lisinopril', '20:00')]));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('exact-reminders-banner')), findsNothing);
  });

  testWidgets('no banner when nothing has a dose time', (t) async {
    await t.pumpWidget(
      app(FakeMedicationsRepository(), [
        med('m3', 'Ibuprofen', 'as_needed'),
      ], reminders: FakeReminders(exact: false)),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('exact-reminders-banner')), findsNothing);
  });

  group('D-49 late doses', () {
    testWidgets('a missed dose offers "Took it late" and records it', (t) async {
      final at = DateTime.utc(2026, 10, 14, 0); // 08:00 MYT, missed by noon
      final repo = FakeMedicationsRepository()
        ..late = true
        ..logs['m1'] = [
          DoseLog(id: 'm1_202610140800', medicationId: 'm1', scheduledTime: at, status: 'missed'),
        ];
      await t.pumpWidget(app(repo, [med('m1', 'Lisinopril', '08:00')]));
      await t.pumpAndSettle();
      expect(find.textContaining('Missed'), findsOneWidget);
      await t.tap(find.byKey(const Key('late-m1-08:00')));
      await t.pumpAndSettle();
      expect(repo.confirmed, [('m1', at)]);
      expect(find.text('Lisinopril recorded as taken late.'), findsOneWidget);
    });

    testWidgets('a dose taken late says so', (t) async {
      final at = DateTime.utc(2026, 10, 14, 0);
      final repo = FakeMedicationsRepository()
        ..logs['m1'] = [
          DoseLog(
            id: 'm1_202610140800',
            medicationId: 'm1',
            scheduledTime: at,
            status: 'taken',
            confirmedAt: at.add(const Duration(hours: 3)),
          ),
        ];
      await t.pumpWidget(app(repo, [med('m1', 'Lisinopril', '08:00')]));
      await t.pumpAndSettle();
      expect(find.text('Taken late at 11:00 AM'), findsOneWidget);
    });
  });

  group('D-49 From your doctor', () {
    final losartan = Prescription(
      id: 'rx1',
      medicationDetails: 'Losartan 50mg, Twice daily, for 3 months',
      isRecurring: true,
      issuedAt: DateTime.utc(2026, 10, 13, 15),
    );

    testWidgets('shown even before the patient adds any medicine', (t) async {
      final repo = FakeMedicationsRepository()..rx = [losartan];
      await t.pumpWidget(app(repo, const []));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('meds-empty')), findsNothing);
      expect(find.text('Losartan 50mg, Twice daily, for 3 months'), findsOneWidget);
      expect(find.textContaining('repeats monthly'), findsOneWidget);
    });

    testWidgets('Add to my reminders pre-fills the form', (t) async {
      final repo = FakeMedicationsRepository()..rx = [losartan];
      await t.pumpWidget(app(repo, const []));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rx-add-rx1')));
      await t.pumpAndSettle();
      expect(find.text('Add medication'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Losartan'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '50mg'), findsOneWidget);
      expect(find.byKey(const Key('time-08:00')), findsOneWidget);
      expect(find.byKey(const Key('time-20:00')), findsOneWidget);
      await t.tap(find.byKey(const Key('save-medication')));
      await t.pumpAndSettle();
      expect(repo.saved.single.$1.schedule, '08:00,20:00');
    });

    testWidgets('a prescription already on the list is marked', (t) async {
      final repo = FakeMedicationsRepository()..rx = [losartan];
      await t.pumpWidget(app(repo, [med('m1', 'Losartan', '08:00')]));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('rx-rx1')), 200);
      expect(find.text('On your list'), findsOneWidget);
      expect(find.byKey(const Key('rx-add-rx1')), findsNothing);
    });
  });

  group('D-50 patient-reported prescriptions', () {
    final doctorRx = Prescription(
      id: 'rx1',
      medicationDetails: 'Losartan 50mg, Once daily',
      isRecurring: false,
      issuedAt: DateTime.utc(2026, 10, 13),
      doctorId: 'd1',
    );
    final mineRx = Prescription(
      id: 'rx2',
      medicationDetails: 'Metformin 500mg, Twice daily, from Klinik Setapak',
      isRecurring: false,
      issuedAt: DateTime.utc(2026, 10, 14),
      source: PrescriptionSource.patient,
    );

    testWidgets('doctor and patient prescriptions are labelled apart', (t) async {
      await t.pumpWidget(app(FakeMedicationsRepository()..rx = [doctorRx, mineRx], const []));
      await t.pumpAndSettle();
      expect(find.text('From your doctor'), findsOneWidget);
      expect(find.text('Added by you'), findsOneWidget);
      final doctorCard = t.widget<Card>(find.byKey(const Key('rx-rx1')));
      final mineCard = t.widget<Card>(find.byKey(const Key('rx-rx2')));
      Color side(Card c) => (c.shape! as RoundedRectangleBorder).side.color;
      expect(side(doctorCard), isNot(side(mineCard)));
    });

    testWidgets('record a prescription from another clinic', (t) async {
      final repo = FakeMedicationsRepository();
      await t.pumpWidget(app(repo, const []));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('record-prescription')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('reported-name')), 'Metformin');
      await t.enterText(find.byKey(const Key('reported-dosage')), '500mg');
      await t.tap(find.byKey(const Key('reported-frequency')));
      await t.pumpAndSettle();
      await t.tap(find.text('Twice daily').last);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('reported-clinic')), 'Klinik Setapak');
      await t.tap(find.byKey(const Key('reported-save')));
      await t.pumpAndSettle();
      final (body, id) = repo.reported.single;
      expect(id, isNull);
      expect(body, contains('medicationName: Metformin'));
      expect(body, contains('clinic: Klinik Setapak'));
    });

    testWidgets('their own prescription opens pre-filled and can be deleted', (t) async {
      final repo = FakeMedicationsRepository()..rx = [mineRx];
      await t.pumpWidget(app(repo, const []));
      await t.pumpAndSettle();
      await t.tap(find.text('Metformin 500mg, Twice daily, from Klinik Setapak'));
      await t.pumpAndSettle();
      expect(find.text('Edit prescription'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Klinik Setapak'), findsOneWidget);
      await t.tap(find.byKey(const Key('reported-delete')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('reported-delete-confirm')));
      await t.pumpAndSettle();
      expect(repo.deletedRx, ['rx2']);
    });

    testWidgets('on a phone-width screen the name uses most of the card', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final long = Prescription(
        id: 'rx3',
        medicationDetails: 'Losartan 50mg, Once daily, morning',
        isRecurring: true,
        issuedAt: DateTime.utc(2026, 10, 13),
        doctorId: 'd1',
      );
      await t.pumpWidget(app(FakeMedicationsRepository()..rx = [long], const []));
      await t.pumpAndSettle();
      final card = t.getSize(find.byKey(const Key('rx-rx3')));
      final name = t.getSize(find.text('Losartan 50mg, Once daily, morning'));
      expect(name.width, greaterThan(card.width * 0.6));
      expect(t.takeException(), isNull); // no overflow
    });

    testWidgets('a doctor prescription does not open for editing', (t) async {
      await t.pumpWidget(app(FakeMedicationsRepository()..rx = [doctorRx], const []));
      await t.pumpAndSettle();
      await t.tap(find.text('Losartan 50mg, Once daily'));
      await t.pumpAndSettle();
      expect(find.text('Edit prescription'), findsNothing);
    });
  });

  group('reminder status line (never fail silently)', () {
    Future<void> show(WidgetTester t, AsyncValue<ReminderStatus> status) async {
      await t.pumpWidget(app(FakeMedicationsRepository(), [med('m1', 'Lisinopril', '22:48')]));
      await t.pumpAndSettle();
      ProviderScope.containerOf(
        t.element(find.byType(MedicationsPage)),
      ).read(reminderStatusProvider.notifier).set(status);
      await t.pumpAndSettle();
    }

    testWidgets('lists what the phone scheduled', (t) async {
      await show(
        t,
        const AsyncData(ReminderStatus(scheduled: ['Lisinopril 10:48 PM'], exact: true)),
      );
      expect(find.text('Phone reminders set: Lisinopril 10:48 PM'), findsOneWidget);
    });

    testWidgets('says when reminders may be late', (t) async {
      await show(t, const AsyncData(ReminderStatus(scheduled: ['Lisinopril 10:48 PM'])));
      expect(find.textContaining('may be a few minutes late'), findsOneWidget);
    });

    testWidgets('shows the real error with a retry', (t) async {
      await show(t, AsyncError(StateError('exact_alarms_not_permitted'), StackTrace.empty));
      expect(
        find.textContaining('could not be set: Bad state: exact_alarms_not_permitted'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reminders-retry')), findsOneWidget);
    });

    testWidgets('shows reminders that failed individually', (t) async {
      await show(
        t,
        const AsyncData(ReminderStatus(errors: ['Lisinopril 10:48 PM: PlatformException(x)'])),
      );
      expect(find.byKey(const Key('reminders-partial')), findsOneWidget);
    });
  });

  group('battery saving prompt', () {
    Future<FakeBackground> open(WidgetTester t, {String schedule = '20:00'}) async {
      final bg = FakeBackground(free: false);
      await t.pumpWidget(
        app(FakeMedicationsRepository(), [med('m1', 'Lisinopril', schedule)], background: bg),
      );
      await t.pumpAndSettle();
      return bg;
    }

    testWidgets('Allow shows the system dialog and hides the card', (t) async {
      final bg = await open(t);
      expect(find.byKey(const Key('background-banner')), findsOneWidget);
      await t.tap(find.byKey(const Key('background-allow')));
      await t.pumpAndSettle();
      expect(bg.requests, 1);
      expect(find.byKey(const Key('background-banner')), findsNothing);
    });

    testWidgets('Phone settings explains the brand steps, then opens settings', (t) async {
      final bg = await open(t);
      await t.tap(find.byKey(const Key('background-phone-settings')));
      await t.pumpAndSettle();
      expect(find.textContaining('Manage automatically'), findsOneWidget);
      await t.tap(find.byKey(const Key('open-phone-settings')));
      await t.pumpAndSettle();
      expect(bg.settingsOpened, 1);
    });

    testWidgets('Not now hides it on this phone', (t) async {
      final bg = await open(t);
      await t.tap(find.byKey(const Key('background-not-now')));
      await t.pumpAndSettle();
      expect(bg.hidden, isTrue);
      expect(find.byKey(const Key('background-banner')), findsNothing);
    });

    testWidgets('not shown without timed doses', (t) async {
      await open(t, schedule: 'as_needed');
      expect(find.byKey(const Key('background-banner')), findsNothing);
    });
  });

  group('UC5.1 add / edit form', () {
    testWidgets('a scheduled medicine needs at least one time', (t) async {
      final repo = FakeMedicationsRepository();
      await t.pumpWidget(app(repo, const [], initial: '/medications/add'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('med-name')), 'Amlodipine');
      await t.enterText(find.byKey(const Key('med-dosage')), '5mg');
      await t.tap(find.byKey(const Key('save-medication')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('med-error')), findsOneWidget);
      expect(repo.saved, isEmpty);
    });

    testWidgets('as-needed medicine saves with the D-43 schedule value', (t) async {
      final repo = FakeMedicationsRepository();
      await t.pumpWidget(app(repo, const [], initial: '/medications/add'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('med-name')), 'Paracetamol');
      await t.enterText(find.byKey(const Key('med-dosage')), '500mg');
      await t.tap(find.text('As needed'));
      await t.enterText(find.byKey(const Key('med-quantity')), '20');
      await t.tap(find.byKey(const Key('save-medication')));
      await t.pumpAndSettle();
      final (draft, id, ack) = repo.saved.single;
      expect(
        (draft.schedule, draft.quantityOnHand, draft.refillThresholdDays),
        ('as_needed', 20.0, 7),
      );
      expect((id, ack), (null, false));
    });

    testWidgets('UC5.1 E1 / UC5.6 warnings must be acknowledged before saving', (t) async {
      final repo = FakeMedicationsRepository()
        ..warnings = const MedicationWarnings(
          duplicates: ['Lisinopril 10mg'],
          interactions: [
            InteractionWarning(
              existingDrug: 'Spironolactone 25mg',
              severity: 'major',
              message: 'Risk of high potassium.',
            ),
          ],
        );
      await t.pumpWidget(
        app(
          repo,
          const [],
          initial: '/medications/edit',
          extra: med('m1', 'Lisinopril', '08:00,20:00'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('time-08:00')), findsOneWidget);
      await t.tap(find.byKey(const Key('save-medication')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('med-warnings')), findsOneWidget);
      expect(find.text('You already have Lisinopril 10mg on your list.'), findsOneWidget);
      expect(find.textContaining('Risk of high potassium.'), findsOneWidget);
      expect(find.textContaining('not a substitute for a doctor'), findsOneWidget);
      await t.tap(find.byKey(const Key('save-anyway')));
      await t.pumpAndSettle();
      expect(repo.saved.map((s) => (s.$1.schedule, s.$2, s.$3)), [
        ('08:00,20:00', 'm1', false),
        ('08:00,20:00', 'm1', true),
      ]);
    });

    testWidgets('going back from the warnings does not save', (t) async {
      final repo = FakeMedicationsRepository()
        ..warnings = const MedicationWarnings(duplicates: ['Lisinopril 5mg'], interactions: []);
      await t.pumpWidget(
        app(repo, const [], initial: '/medications/edit', extra: med('m1', 'Lisinopril', '08:00')),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('save-medication')));
      await t.pumpAndSettle();
      await t.tap(find.text('Go back'));
      await t.pumpAndSettle();
      expect(repo.saved, hasLength(1));
      expect(find.text('Edit medication'), findsOneWidget);
    });

    testWidgets('delete asks first', (t) async {
      final repo = FakeMedicationsRepository();
      await t.pumpWidget(
        app(repo, const [], initial: '/medications/edit', extra: med('m1', 'Lisinopril', '08:00')),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('delete-medication')));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(repo.deleted, ['m1']);
    });

    testWidgets('D-69 a doctor-set medicine only lets the patient change reminder times', (
      t,
    ) async {
      final repo = FakeMedicationsRepository();
      const fromDoctor = Medication(
        id: 'm9',
        patientId: 'p1',
        name: 'Amlodipine 5mg',
        dosage: '1 tablet',
        schedule: '08:00',
        quantityOnHand: 30,
        source: 'doctor',
        prescribedBy: 'Dr Tan',
      );
      await t.pumpWidget(app(repo, const [], initial: '/medications/edit', extra: fromDoctor));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('med-locked')), findsOneWidget);
      expect(find.text('Prescribed by Dr Tan'), findsOneWidget);
      expect(find.byKey(const Key('delete-medication')), findsNothing);
      for (final k in ['med-name', 'med-dosage', 'med-quantity']) {
        final field = t.widget<TextField>(
          find.descendant(of: find.byKey(Key(k)), matching: find.byType(TextField)),
        );
        expect(field.readOnly, isTrue, reason: k);
      }
    });

    testWidgets('D-69 the Meds tab says who prescribed a medicine', (t) async {
      final repo = FakeMedicationsRepository();
      const fromDoctor = Medication(
        id: 'm9',
        patientId: 'p1',
        name: 'Amlodipine 5mg',
        dosage: '1 tablet',
        schedule: '08:00',
        source: 'doctor',
        prescribedBy: 'Dr Tan',
      );
      await t.pumpWidget(app(repo, const [fromDoctor]));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('from-doctor-m9')), findsWidgets);
      expect(find.text('From Dr Tan'), findsWidgets);
    });
  });
}
