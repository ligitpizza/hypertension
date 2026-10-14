import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/medications/data/dose_reminders.dart';
import 'package:hypertension/features/medications/data/medications_repository.dart';
import 'package:hypertension/features/medications/presentation/medication_form_page.dart';
import 'package:hypertension/features/medications/presentation/medications_page.dart';
import 'package:hypertension/features/medications/state/medication_providers.dart';
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

  @override
  Stream<List<DoseLog>> doseLogs(String medicationId, DateTime since) =>
      Stream.value(logs[medicationId] ?? const []);

  @override
  Future<void> confirmDose(String medicationId, {DateTime? scheduledTime}) async {
    if (confirmError != null) throw confirmError!;
    confirmed.add((medicationId, scheduledTime));
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
  Future<void> sync(List<Medication> meds) async => synced.add(meds.length);
}

Widget app(
  FakeMedicationsRepository repo,
  List<Medication> meds, {
  String initial = '/medications',
  Object? extra,
  String? doctorId = 'd1',
  FakeReminders? reminders,
}) {
  final router = GoRouter(
    initialLocation: initial,
    initialExtra: extra,
    routes: [
      GoRoute(path: '/medications', builder: (_, _) => const MedicationsPage()),
      GoRoute(path: '/medications/add', builder: (_, _) => const MedicationFormPage()),
      GoRoute(
        path: '/medications/edit',
        builder: (_, s) => MedicationFormPage(existing: s.extra! as Medication),
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
      medicationsProvider.overrideWith((ref) => Stream.value(meds)),
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
    expect(find.text('EVENING'), findsOneWidget);
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
      app(
        FakeMedicationsRepository(),
        [med('m3', 'Ibuprofen', 'as_needed')],
        reminders: FakeReminders(exact: false),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('exact-reminders-banner')), findsNothing);
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
  });
}
