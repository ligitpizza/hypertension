import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/auth/domain/onboarding_data.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/medications/state/medication_providers.dart';
import 'package:hypertension/features/settings/data/settings_repository.dart';
import 'package:hypertension/features/settings/presentation/data_privacy_page.dart';
import 'package:hypertension/features/settings/presentation/profile_pages.dart';
import 'package:hypertension/features/settings/presentation/settings_page.dart';
import 'package:hypertension/features/settings/state/settings_providers.dart';
import 'package:hypertension/shared/models/health_models.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';

// Module 12 Settings (Fig 4.3.11.1; FR-12.1, FR-12.2; UC12.1-UC12.4; D-45-D-47).

class FakeSettingsRepository implements SettingsRepository {
  OnboardingData? stored;
  final calls = <String>[];
  final prefsSaved = <NotificationPrefs>[];
  OnboardingData? contactSaved;
  OnboardingData? healthSaved;
  bool rescored = false;
  Object? saveError;
  Object? exportError;
  List<String> recurring = const [];
  final deletes = <bool>[];

  @override
  Stream<OnboardingData?> profile(AppUser user) => Stream.value(stored);

  @override
  Future<bool> updatePersonal({
    required String name,
    required DateTime dateOfBirth,
    required Gender gender,
    String? icNumber,
  }) async {
    if (saveError != null) throw saveError!;
    calls.add(
      'personal:$name:${gender.value}:${dateOfBirth.year}${icNumber == null ? '' : ':$icNumber'}',
    );
    return rescored;
  }

  @override
  Future<void> updateContact(OnboardingData data) async {
    if (saveError != null) throw saveError!;
    contactSaved = data;
  }

  @override
  Future<bool> updateHealth(OnboardingData data) async {
    healthSaved = data;
    return rescored;
  }

  @override
  Future<void> updateNotifications(NotificationPrefs prefs) async => prefsSaved.add(prefs);

  @override
  Future<Uint8List> export(String format) async {
    if (exportError != null) throw exportError!;
    calls.add('export:$format');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> deleteAccount({bool acknowledgeRecurring = false}) async {
    deletes.add(acknowledgeRecurring);
    if (recurring.isNotEmpty && !acknowledgeRecurring) {
      throw RecurringPrescriptionWarning(recurring);
    }
  }
}

class FakeSharer implements FileSharer {
  final shared = <String>[];

  @override
  Future<void> share(Uint8List bytes, {required String fileName, required String mimeType}) async =>
      shared.add('$fileName|$mimeType');
}

const user = AppUser(
  uid: 'abc123xyz',
  email: 'siti@x.my',
  name: 'Siti Aminah',
  role: UserRole.patient,
  isActive: true,
  onboardingComplete: true,
  linkCode: 'K7Q2PX',
  gender: Gender.female,
);

OnboardingData stored() => OnboardingData.fromStored(
  personalInfo: {'heightCm': 160, 'weightKg': 62.5, 'phone': '+60 12-345 6789'},
  medicalHistory: {
    'hypertensionDiagnosedYear': 2019,
    'conditions': ['diabetes'],
    'familyHistory': ['stroke'],
    'allergies': 'Penicillin',
    'notes': '',
  },
  lifestyleFactors: {
    'smokingStatus': 'former',
    'alcohol': 'none',
    'exerciseDaysPerWeek': 2,
    'saltIntake': 'high',
  },
  dateOfBirth: DateTime(1965, 4, 2),
  gender: Gender.female,
);

Widget app(
  FakeSettingsRepository repo,
  FakeAuthRepository auth, {
  String initial = '/settings',
  FakeSharer? sharer,
  AppUser me = user,
}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/settings/personal', builder: (_, _) => const PersonalInfoPage()),
      GoRoute(path: '/settings/contact', builder: (_, _) => const ContactDetailsPage()),
      GoRoute(path: '/settings/health', builder: (_, _) => const HealthProfilePage()),
      GoRoute(path: '/settings/privacy', builder: (_, _) => const DataPrivacyPage()),
    ],
  );
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repo),
      fileSharerProvider.overrideWithValue(sharer ?? FakeSharer()),
      authRepositoryProvider.overrideWithValue(auth),
      clientAppProvider.overrideWithValue(ClientApp.patient),
      currentUserProvider.overrideWith((ref) => Stream.value(me)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late FakeSettingsRepository repo;
  late FakeAuthRepository auth;

  setUp(() {
    repo = FakeSettingsRepository()..stored = stored();
    auth = FakeAuthRepository();
  });

  group('D-25 profile round trip', () {
    test('stored JSON becomes editable data and API bodies', () {
      final d = stored();
      expect((d.heightCm, d.weightKg, d.phone), (160.0, 62.5, '+60 12-345 6789'));
      expect(d.conditions, {MedicalCondition.diabetes});
      expect(d.smokingStatus, SmokingStatus.former);
      expect(d.toContactJson(), {'phone': '+60 12-345 6789', 'emergencyContact': null});
      final h = d.toHealthJson();
      expect(h['heightCm'], 160.0);
      expect((h['lifestyleFactors'] as Map)['saltIntake'], 'high');
      expect((h['medicalHistory'] as Map)['allergies'], 'Penicillin');
      expect(h.containsKey('phone'), isFalse);
    });

    test('D-45 prefs default to on', () {
      final p = NotificationPrefs.fromMap(null);
      expect((p.medicationReminders, p.healthUpdates), (true, true));
      expect(NotificationPrefs.fromMap({'healthUpdates': false}).healthUpdates, isFalse);
    });
  });

  group('Fig 4.3.11.1 Settings', () {
    testWidgets('shows the profile header, sections and link code', (t) async {
      await t.pumpWidget(app(repo, auth));
      await t.pumpAndSettle();
      expect(find.text('Siti Aminah'), findsOneWidget);
      expect(find.text('Patient ID: #ABC123'), findsOneWidget);
      for (final k in ['settings-personal', 'settings-contact', 'settings-health']) {
        expect(find.byKey(Key(k)), findsOneWidget);
      }
      await t.scrollUntilVisible(find.byKey(const Key('settings-link-code')), 200);
      expect(find.textContaining('K7Q2PX'), findsOneWidget);
      expect(find.textContaining('Urgent alerts'), findsOneWidget);
    });

    testWidgets('D-45 toggles save the preferences', (t) async {
      await t.pumpWidget(app(repo, auth));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('pref-medication')), 200);
      await t.tap(find.byKey(const Key('pref-medication')));
      await t.pumpAndSettle();
      expect(repo.prefsSaved.single.medicationReminders, isFalse);
      expect(repo.prefsSaved.single.healthUpdates, isTrue);
    });

    testWidgets('UC1.3 sign out asks first', (t) async {
      await t.pumpWidget(app(repo, auth));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('settings-sign-out')), 200);
      await t.tap(find.byKey(const Key('settings-sign-out')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('sign-out-confirm')));
      await t.pumpAndSettle();
      expect(auth.calls.where((c) => c == 'signOut'), hasLength(1));
    });
  });

  group('UC12.1 personal and contact', () {
    testWidgets('personal info saves and reports a re-score', (t) async {
      repo.rescored = true;
      await t.pumpWidget(app(repo, auth, me: user.copyForTest(dateOfBirth: DateTime(1965, 4, 2))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings-edit-profile')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('settings-name')), 'Siti A.');
      await t.tap(find.text('Male'));
      await t.tap(find.byKey(const Key('settings-save')));
      await t.pumpAndSettle();
      expect(repo.calls, ['personal:Siti A.:male:1965']);
      expect(find.text('Saved. Your risk assessment was updated.'), findsOneWidget);
      expect(find.text('Settings'), findsWidgets); // popped back
    });

    testWidgets('D-51 an existing patient adds their IC; DOB and gender follow it', (t) async {
      await t.pumpWidget(
        app(
          repo,
          auth,
          initial: '/settings/personal',
          me: user.copyForTest(dateOfBirth: DateTime(1965)),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('settings-ic')), '800505105679');
      await t.pump();
      expect(find.text('5/5/1980'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings-save')));
      await t.pumpAndSettle();
      expect(repo.calls, ['personal:Siti Aminah:male:1980:800505-10-5679']);
    });

    testWidgets('E1 server rejection is shown on the form', (t) async {
      repo.saveError = ApiException('VALIDATION_ERROR', 'Enter a valid date of birth.');
      await t.pumpWidget(
        app(
          repo,
          auth,
          initial: '/settings/personal',
          me: user.copyForTest(dateOfBirth: DateTime(1965)),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings-save')));
      await t.pumpAndSettle();
      expect(find.text('Enter a valid date of birth.'), findsOneWidget);
    });

    testWidgets('E1 invalid phone is highlighted and not sent', (t) async {
      await t.pumpWidget(app(repo, auth, initial: '/settings/contact'));
      await t.pumpAndSettle();
      expect(find.text('siti@x.my'), findsOneWidget);
      await t.enterText(find.byKey(const Key('settings-phone')), 'abc');
      await t.tap(find.byKey(const Key('settings-save')));
      await t.pumpAndSettle();
      expect(find.text('Enter a valid phone number.'), findsOneWidget);
      expect(repo.contactSaved, isNull);
    });

    testWidgets('emergency contact is all-or-nothing', (t) async {
      await t.pumpWidget(app(repo, auth, initial: '/settings/contact'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('settings-emergency-name')), 'Ali');
      await t.tap(find.byKey(const Key('settings-save')));
      await t.pumpAndSettle();
      expect(repo.contactSaved, isNull);
      await t.enterText(find.byKey(const Key('settings-emergency-phone')), '0123456789');
      await t.enterText(find.byKey(const Key('settings-emergency-relationship')), 'Son');
      await t.tap(find.byKey(const Key('settings-save')));
      await t.pumpAndSettle();
      expect(repo.contactSaved!.toContactJson()['emergencyContact'], {
        'name': 'Ali',
        'phone': '0123456789',
        'relationship': 'Son',
      });
    });
  });

  testWidgets('UC12.2 health profile edits are sent', (t) async {
    await t.pumpWidget(app(repo, auth, initial: '/settings/health'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Heart failure'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Heart failure'));
    await t.scrollUntilVisible(
      find.text('Smoke now'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Smoke now'));
    await t.scrollUntilVisible(
      find.byKey(const Key('settings-save')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('settings-save')));
    await t.pumpAndSettle();
    final saved = repo.healthSaved!;
    expect(saved.smokingStatus, SmokingStatus.current);
    expect(saved.conditions, {MedicalCondition.diabetes, MedicalCondition.heartFailure});
    expect(saved.allergies, 'Penicillin');
  });

  group('UC12.3 export', () {
    testWidgets('PDF goes to the share sheet', (t) async {
      final sharer = FakeSharer();
      await t.pumpWidget(app(repo, auth, initial: '/settings/privacy', sharer: sharer));
      await t.pumpAndSettle();
      expect(find.textContaining('not included'), findsOneWidget);
      await t.tap(find.byKey(const Key('export-pdf')));
      await t.pumpAndSettle();
      expect(
        sharer.shared.single,
        matches(RegExp(r'^careflow-export-\d{8}\.pdf\|application/pdf$')),
      );
    });

    testWidgets('E1 failure offers retry', (t) async {
      repo.exportError = ApiException('EXPORT_FAILED', 'x');
      await t.pumpWidget(app(repo, auth, initial: '/settings/privacy'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('export-json')));
      await t.pumpAndSettle();
      expect(find.text('We could not create your export.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('UC12.4 delete', () {
    Future<void> openDelete(WidgetTester t, {FakeSharer? sharer}) async {
      await t.pumpWidget(app(repo, auth, initial: '/settings/privacy', sharer: sharer));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('privacy-delete')));
      await t.pumpAndSettle();
    }

    testWidgets('A1 skip export, confirm, deactivate and sign out', (t) async {
      await openDelete(t);
      expect(find.byKey(const Key('delete-offer-export')), findsOneWidget);
      await t.tap(find.byKey(const Key('delete-skip-export')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('delete-confirm-button')));
      await t.pumpAndSettle();
      expect(repo.deletes, [false]);
      expect(auth.calls.where((c) => c == 'signOut'), hasLength(1));
    });

    testWidgets('step 2 exports first', (t) async {
      final sharer = FakeSharer();
      await openDelete(t, sharer: sharer);
      await t.tap(find.byKey(const Key('delete-export-first')));
      await t.pumpAndSettle();
      expect(sharer.shared, hasLength(1));
      expect(find.byKey(const Key('delete-confirm')), findsOneWidget);
    });

    testWidgets('E1 recurring prescription warning, then delete', (t) async {
      repo.recurring = ['Amlodipine 5mg daily'];
      await openDelete(t);
      await t.tap(find.byKey(const Key('delete-skip-export')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('delete-confirm-button')));
      await t.pumpAndSettle();
      expect(find.textContaining('Amlodipine 5mg daily'), findsOneWidget);
      await t.tap(find.byKey(const Key('delete-recurring-confirm')));
      await t.pumpAndSettle();
      expect(repo.deletes, [false, true]);
      expect(auth.calls.where((c) => c == 'signOut'), hasLength(1));
    });

    testWidgets('cancel keeps the account', (t) async {
      await openDelete(t);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(repo.deletes, isEmpty);
    });
  });

  test('D-45 reminders follow the medication switch', () async {
    const med = Medication(id: 'm1', patientId: 'p', name: 'A', dosage: '1', schedule: '08:00');
    ProviderContainer make(NotificationPrefs prefs) => ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => Stream.value(user.copyForTest(notificationPrefs: prefs)),
        ),
        medicationsProvider.overrideWith((ref) => Stream.value(const [med])),
      ],
    );
    for (final (prefs, expected) in [
      (const NotificationPrefs(), 1),
      (const NotificationPrefs(medicationReminders: false), 0),
    ]) {
      final c = make(prefs);
      addTearDown(c.dispose);
      c.listen(reminderMedicationsProvider, (_, _) {});
      await c.read(currentUserProvider.future);
      await c.read(medicationsProvider.future);
      expect(c.read(reminderMedicationsProvider), hasLength(expected));
    }
  });
}

extension on AppUser {
  AppUser copyForTest({DateTime? dateOfBirth, NotificationPrefs? notificationPrefs}) => AppUser(
    uid: uid,
    email: email,
    name: name,
    role: role,
    isActive: isActive,
    onboardingComplete: onboardingComplete,
    linkCode: linkCode,
    gender: gender,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    notificationPrefs: notificationPrefs ?? this.notificationPrefs,
  );
}
