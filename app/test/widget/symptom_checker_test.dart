import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/symptom_checker/data/symptom_repository.dart';
import 'package:hypertension/features/symptom_checker/presentation/symptom_checker_page.dart';
import 'package:hypertension/features/symptom_checker/presentation/triage_result_page.dart';
import 'package:hypertension/features/symptom_checker/state/symptom_providers.dart';
import 'package:hypertension/features/vitals/state/vitals_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';
import 'vitals_pages_test.dart' show FakePpgCapture, FakeVitalsRepository;

// FR-14.3 Symptom checker (UC14.1, UC14.2 E1, UC14.3; Figs 4.3.8.1/4.3.8.2; D-36).

const testCatalog = [
  SymptomOption(id: 'headache', name: 'Headache', category: 'common'),
  SymptomOption(id: 'chest_pain', name: 'Chest Pain', category: 'common', isRedFlag: true),
  SymptomOption(id: 'vision_loss', name: 'Vision Loss', category: 'warning_signs', isRedFlag: true),
  SymptomOption(id: 'fatigue', name: 'Fatigue', category: 'other'),
];

class FakeSymptomRepository implements SymptomRepository {
  final calls = <Map<String, Object?>>[];
  Object? error;
  TriageOutcome outcome = TriageOutcome.monitorAtHome;

  @override
  Stream<List<SymptomOption>> catalog() => Stream.value(catalogList);

  List<SymptomOption> catalogList = testCatalog;
  List<TriageRecord> records = const [];

  @override
  Stream<List<TriageRecord>> outcomes(String patientId, {int limit = 20}) =>
      Stream.value(records.take(limit).toList());

  @override
  Future<TriageResult> submit({
    required List<String> symptomIds,
    required TriageSeverity severity,
    int? heartRate,
    String? vitalReadingId,
  }) async {
    calls.add({
      'symptoms': symptomIds,
      'severity': severity,
      'heartRate': heartRate,
      'vitalReadingId': vitalReadingId,
    });
    if (error != null) throw error!;
    return TriageResult(
      id: 't1',
      outcome: outcome,
      reason: 'Because.',
      symptoms: [
        for (final s in testCatalog)
          if (symptomIds.contains(s.id)) s,
      ],
      heartRate: heartRate,
      doctorNotified: outcome != TriageOutcome.monitorAtHome,
    );
  }
}

Widget checkerApp(FakeSymptomRepository repo, FakeVitalsRepository vitals, {List<String>? dialed}) {
  final router = GoRouter(
    initialLocation: '/symptom',
    routes: [
      GoRoute(path: '/symptom', builder: (_, _) => const SymptomCheckerPage()),
      GoRoute(
        path: '/symptom/result/:id',
        builder: (_, s) => TriageResultPage(result: s.extra! as TriageResult),
      ),
      for (final p in ['/dashboard', '/ai-agent'])
        GoRoute(path: p, builder: (_, _) => Text('ROUTE $p')),
    ],
  );
  return ProviderScope(
    overrides: [
      symptomRepositoryProvider.overrideWithValue(repo),
      vitalsRepositoryProvider.overrideWithValue(vitals),
      ppgCaptureProvider.overrideWithValue(FakePpgCapture()),
      dialerProvider.overrideWithValue((n) async {
        dialed?.add(n);
        return true;
      }),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget resultApp(TriageResult r, {List<String>? dialed}) => ProviderScope(
  overrides: [
    dialerProvider.overrideWithValue((n) async {
      dialed?.add(n);
      return true;
    }),
  ],
  child: MaterialApp(home: TriageResultPage(result: r)),
);

void main() {
  late FakeSymptomRepository repo;
  late FakeVitalsRepository vitals;
  setUp(() {
    repo = FakeSymptomRepository();
    vitals = FakeVitalsRepository();
  });

  final dialed = <String>[];

  /// D-38: type the pulse (the camera path is covered by the Module 3 card tests) and a BP.
  Future<void> fillVitals(
    WidgetTester t, {
    String hr = '72',
    String sys = '118',
    String dia = '76',
  }) async {
    await t.tap(find.byKey(const Key('ppg-manual')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('hr-manual-input')), hr);
    await t.enterText(find.byKey(const Key('sc-sys')), sys);
    await t.enterText(find.byKey(const Key('sc-dia')), dia);
    await t.pump();
  }

  Future<void> toSymptoms(WidgetTester t) async {
    await t.tap(find.byKey(const Key('sc-next')));
    await t.pumpAndSettle();
  }

  Future<void> pickAndSubmit(WidgetTester t, String symptom) async {
    await t.ensureVisible(find.byKey(Key('sym-$symptom')));
    await t.tap(find.byKey(Key('sym-$symptom')));
    await t.pump();
    await t.tap(find.byKey(const Key('sc-submit')));
    await t.pumpAndSettle();
  }

  bool continueEnabled(WidgetTester t) =>
      t.widget<FilledButton>(find.byKey(const Key('sc-next'))).onPressed != null;

  group('Fig 4.3.8.1 symptom checker', () {
    tallTest('D-38 Continue stays locked until heart rate AND blood pressure are given', (t) async {
      await t.pumpWidget(checkerApp(repo, vitals));
      await t.pumpAndSettle();
      expect(find.text('Heart rate (required)'), findsOneWidget);
      expect(find.text('Blood pressure (required)'), findsOneWidget);
      expect(continueEnabled(t), isFalse);
      await t.tap(find.byKey(const Key('ppg-manual')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('hr-manual-input')), '72');
      await t.pump();
      expect(continueEnabled(t), isFalse); // heart rate only
      await t.enterText(find.byKey(const Key('sc-sys')), '118');
      await t.pump();
      expect(continueEnabled(t), isFalse); // diastolic missing
      await t.enterText(find.byKey(const Key('sc-dia')), '76');
      await t.pump();
      expect(continueEnabled(t), isTrue);
      await toSymptoms(t);
      expect(find.text('What are you feeling today?'), findsOneWidget);
    });

    tallTest('D-38 the heart-rate card has no Skip in the checker', (t) async {
      await t.pumpWidget(checkerApp(repo, vitals));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ppg-skip')), findsNothing);
    });

    tallTest('D-38 implausible BP keeps Continue locked', (t) async {
      await t.pumpWidget(checkerApp(repo, vitals));
      await t.pumpAndSettle();
      await fillVitals(t, sys: '80', dia: '95');
      expect(continueEnabled(t), isFalse);
    });

    tallTest('D-38 Call 999 is always available on the vitals step', (t) async {
      await t.pumpWidget(checkerApp(repo, vitals, dialed: dialed));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('sc-call-999')));
      await t.pump();
      expect(dialed, ['999']);
      dialed.clear();
    });

    tallTest('symptoms are grouped by category; Continue needs a symptom', (t) async {
      await t.pumpWidget(checkerApp(repo, vitals));
      await t.pumpAndSettle();
      await fillVitals(t);
      await toSymptoms(t);
      expect(find.text('COMMON SYMPTOMS'), findsOneWidget);
      expect(find.text('WARNING SIGNS'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('sc-submit'))).onPressed, isNull);
      await t.tap(find.byKey(const Key('sym-headache')));
      await t.pump();
      expect(t.widget<FilledButton>(find.byKey(const Key('sc-submit'))).onPressed, isNotNull);
    });

    tallTest('severity has a plain-language hint that follows the choice', (t) async {
      await t.pumpWidget(checkerApp(repo, vitals));
      await t.pumpAndSettle();
      await fillVitals(t);
      await toSymptoms(t);
      expect(find.textContaining('Mild: noticeable'), findsOneWidget);
      await t.tap(find.text('Severe'));
      await t.pump();
      expect(find.textContaining('Severe: very strong'), findsOneWidget);
    });

    tallTest('an empty symptom list explains itself instead of a blank screen', (t) async {
      repo.catalogList = const [];
      await t.pumpWidget(checkerApp(repo, vitals));
      await t.pumpAndSettle();
      await fillVitals(t);
      await toSymptoms(t);
      expect(find.byKey(const Key('sc-empty')), findsOneWidget);
      expect(find.textContaining('call 999'), findsOneWidget);
    });

    tallTest('UC14.3 the BP is saved to Vitals and linked with the heart rate', (t) async {
      await t.pumpWidget(checkerApp(repo, vitals));
      await t.pumpAndSettle();
      await fillVitals(t, hr: '88', sys: '150', dia: '95');
      await toSymptoms(t);
      await t.tap(find.text('Moderate'));
      await t.pump();
      await pickAndSubmit(t, 'headache');
      expect(vitals.last, {
        'systolic': 150,
        'diastolic': 95,
        'heartRate': 88,
        'note': 'Symptom checker',
      });
      expect(repo.calls.single, {
        'symptoms': ['headache'],
        'severity': TriageSeverity.moderate,
        'heartRate': 88,
        'vitalReadingId': 'r1',
      });
      expect(find.byKey(const Key('triage-monitor_at_home')), findsOneWidget);
    });

    tallTest('a failed triage retry does not log the BP twice', (t) async {
      repo.error = ApiException('NETWORK_ERROR', 'down');
      await t.pumpWidget(checkerApp(repo, vitals));
      await t.pumpAndSettle();
      await fillVitals(t, sys: '150', dia: '95');
      await toSymptoms(t);
      await pickAndSubmit(t, 'fatigue');
      expect(find.textContaining('call 999'), findsOneWidget);
      vitals.last = null;
      repo.error = null;
      await t.tap(find.byKey(const Key('sc-submit')));
      await t.pumpAndSettle();
      expect(vitals.last, isNull); // reused the saved reading
      expect(repo.calls.last['vitalReadingId'], 'r1');
    });
  });

  group('Fig 4.3.8.2 triage result', () {
    TriageResult result(TriageOutcome o, {List<String> missing = const []}) => TriageResult(
      id: 't1',
      outcome: o,
      reason: 'Chest Pain can be a sign of a serious problem.',
      symptoms: testCatalog.take(2).toList(),
      systolic: 150,
      diastolic: 95,
      heartRate: 88,
      missingInputs: missing,
      doctorNotified: o != TriageOutcome.monitorAtHome,
    );

    tallTest('emergency: 999 (not 911), red flags, numbered actions, call button', (t) async {
      final dialed = <String>[];
      await t.pumpWidget(resultApp(result(TriageOutcome.seekEmergencyCare), dialed: dialed));
      expect(find.text('Seek Emergency Care'), findsOneWidget);
      expect(find.textContaining('911'), findsNothing);
      expect(find.text('Critical symptoms reported'), findsOneWidget);
      expect(find.text('Call 999'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('heart rate 88 bpm (camera estimate)'), findsOneWidget);
      expect(find.byKey(const Key('triage-doctor-notified')), findsOneWidget);
      expect(find.byKey(const Key('triage-disclaimer')), findsOneWidget);
      await t.tap(find.byKey(const Key('triage-call-999')));
      await t.pump();
      expect(dialed, ['999']);
    });

    tallTest('contact doctor: no call button, doctor notified', (t) async {
      await t.pumpWidget(resultApp(result(TriageOutcome.contactDoctor)));
      expect(find.text('Contact Your Doctor'), findsOneWidget);
      expect(find.byKey(const Key('triage-call-999')), findsNothing);
      expect(find.byKey(const Key('triage-doctor-notified')), findsOneWidget);
    });

    tallTest('UC14.1 E1 monitor at home notes missing inputs', (t) async {
      await t.pumpWidget(
        resultApp(result(TriageOutcome.monitorAtHome, missing: ['heart_rate', 'risk_score'])),
      );
      expect(find.text('Monitor at Home'), findsOneWidget);
      expect(find.text('Checked without heart rate, a risk assessment.'), findsOneWidget);
      expect(find.byKey(const Key('triage-doctor-notified')), findsNothing);
    });
  });

  test('TriageResult parses the API response', () {
    final r = TriageResult.fromApi({
      'id': 't9',
      'outcome': 'contact_doctor',
      'reason': 'High BP.',
      'severity': 'mild',
      'symptoms': [
        {'id': 'headache', 'name': 'Headache', 'isRedFlag': false},
      ],
      'systolic': 150,
      'diastolic': 92,
      'heartRate': null,
      'missingInputs': ['heart_rate'],
      'doctorNotified': true,
    });
    expect(r.outcome, TriageOutcome.contactDoctor);
    expect(r.symptoms.single.name, 'Headache');
    expect(r.missingInputs, ['heart_rate']);
  });

  test('triage quick replies follow the reported symptoms', () {
    final r = TriageResult(
      id: 't',
      outcome: TriageOutcome.monitorAtHome,
      reason: '',
      symptoms: const [
        SymptomOption(id: 'blurred_vision', name: 'Blurred Vision', category: 'common'),
      ],
    );
    expect(TriageResultPage.quickReplies(r), [
      'Explain my symptom check result',
      'What can I do about blurred vision?',
      'When should I check my blood pressure again?',
      'What warning signs should I watch for?',
    ]);
  });
}
