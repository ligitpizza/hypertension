import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/ai_agent/data/agent_repository.dart';
import 'package:hypertension/features/ai_agent/presentation/agent_page.dart';
import 'package:hypertension/features/ai_agent/presentation/agent_update_card.dart';
import 'package:hypertension/features/ai_agent/state/agent_providers.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';

// FR-14.1 AI Health Agent (UC2.6, UC2.6 E1, UC2.7, UC-14.1.3; Fig 4.3.7.1; D-34).

class FakeAgentRepository implements AgentRepository {
  final history = StreamController<List<AgentMessage>>.broadcast();
  List<AgentMessage> current = const [];
  final sent = <String>[];
  AgentReply reply = const AgentReply(reply: 'Your last reading was 128/82.');
  Object? sendError;
  Future<ProactiveUpdate> Function() onProactive = () async =>
      const ProactiveUpdate(text: 'Your reading is fine.', riskLevel: RiskLevel.low);

  void emit(List<AgentMessage> m) {
    current = m;
    history.add(m);
  }

  @override
  Stream<List<AgentMessage>> messages(String patientId) async* {
    yield current;
    yield* history.stream;
  }

  @override
  Future<AgentReply> send(String message) async {
    sent.add(message);
    if (sendError != null) throw sendError!;
    if (!reply.fallback) {
      emit([
        ...current,
        AgentMessage(id: 'p${current.length}', fromPatient: true, text: message),
        AgentMessage(id: 'a${current.length}', fromPatient: false, text: reply.reply),
      ]);
    }
    return reply;
  }

  @override
  Future<ProactiveUpdate> proactive() => onProactive();
}

Widget agentApp(FakeAgentRepository repo, {Widget home = const AgentPage()}) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (_, _) => Scaffold(body: home),
      ),
      for (final p in ['/appointments', '/medications', '/ai-agent', '/dashboard'])
        GoRoute(path: p, builder: (_, _) => Text('ROUTE $p')),
    ],
  );
  return ProviderScope(
    overrides: [
      agentRepositoryProvider.overrideWithValue(repo),
      authUidProvider.overrideWith((ref) => Stream.value('p1')),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late FakeAgentRepository repo;
  setUp(() => repo = FakeAgentRepository());

  group('Fig 4.3.7.1 chat', () {
    tallTest('shows the not-a-doctor disclaimer and suggestions when empty', (t) async {
      await t.pumpWidget(agentApp(repo));
      await t.pumpAndSettle();
      expect(find.textContaining('not a substitute for a doctor'), findsOneWidget);
      expect(find.textContaining('call 999'), findsOneWidget);
      expect(find.byKey(Key('suggest-${AgentPage.suggestions.first}')), findsOneWidget);
    });

    tallTest('UC2.6 sends a question and shows the saved conversation', (t) async {
      await t.pumpWidget(agentApp(repo));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('agent-input')), 'What was my BP?');
      await t.tap(find.byKey(const Key('agent-send')));
      await t.pumpAndSettle();
      expect(repo.sent, ['What was my BP?']);
      expect(find.text('What was my BP?'), findsOneWidget);
      expect(find.text('Your last reading was 128/82.'), findsOneWidget);
      expect(find.byKey(const Key('agent-typing')), findsNothing);
    });

    tallTest('a suggestion chip asks that question', (t) async {
      await t.pumpWidget(agentApp(repo));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('suggest-${AgentPage.suggestions[1]}')));
      await t.pumpAndSettle();
      expect(repo.sent, [AgentPage.suggestions[1]]);
    });

    tallTest('UC2.6 E1 fallback reply is shown but not as a saved answer', (t) async {
      repo.reply = const AgentReply(
        reply: 'Sorry, try later. Call 999 in an emergency.',
        fallback: true,
      );
      await t.pumpWidget(agentApp(repo));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('agent-input')), 'hi');
      await t.tap(find.byKey(const Key('agent-send')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agent-notice')), findsOneWidget);
    });

    tallTest('network error shows the care-team fallback', (t) async {
      repo.sendError = ApiException('NETWORK_ERROR', 'down');
      await t.pumpWidget(agentApp(repo));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('agent-input')), 'hi');
      await t.tap(find.byKey(const Key('agent-send')));
      await t.pumpAndSettle();
      expect(find.textContaining('contact your doctor or care team'), findsOneWidget);
    });

    tallTest('UC-14.1.3 emergency reply shows the 999 card', (t) async {
      repo.reply = const AgentReply(reply: 'Please call 999 now.', emergency: true);
      await t.pumpWidget(agentApp(repo));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('agent-input')), 'I have chest pain');
      await t.tap(find.byKey(const Key('agent-send')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agent-emergency')), findsOneWidget);
    });
  });

  group('UC2.7 proactive update card', () {
    Widget card() => agentApp(repo, home: const SingleChildScrollView(child: AgentUpdateCard()));

    tallTest('high risk shows the text and booking + medication buttons', (t) async {
      repo.onProactive = () async => ProactiveUpdate.fromApi({
        'text': 'Your risk is high. Please book an appointment.',
        'riskLevel': 'high',
        'actions': ['book_appointment', 'view_medications'],
        'fallback': false,
      });
      await t.pumpWidget(card());
      expect(find.text('Preparing your update...'), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.text('Your risk is high. Please book an appointment.'), findsOneWidget);
      expect(find.text('High Risk'), findsOneWidget);
      expect(find.text('Book appointment'), findsOneWidget);
      expect(find.text('View medications'), findsOneWidget);
      await t.tap(find.text('Book appointment'));
      await t.pumpAndSettle();
      expect(find.text('ROUTE /appointments'), findsOneWidget);
    });

    tallTest('critical shows the emergency booking button; family actions wait for FR-14.2', (
      t,
    ) async {
      repo.onProactive = () async => ProactiveUpdate.fromApi({
        'text': 'Call 999 if you feel unwell.',
        'riskLevel': 'critical',
        'actions': ['book_emergency_appointment', 'call_emergency_contact', 'alert_family'],
      });
      await t.pumpWidget(card());
      await t.pumpAndSettle();
      expect(find.text('Book emergency appointment'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Ask the assistant'), findsOneWidget);
    });

    tallTest('failure leaves a calm note; the reading is still saved', (t) async {
      repo.onProactive = () async => throw ApiException('NETWORK_ERROR', 'down');
      await t.pumpWidget(card());
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agent-update-error')), findsOneWidget);
    });
  });

  test('UC2.7 unknown action values are ignored', () {
    final u = ProactiveUpdate.fromApi({
      'text': 't',
      'riskLevel': null,
      'actions': ['book_appointment', 'something_new'],
    });
    expect(u.actions, [AgentAction.bookAppointment]);
    expect(u.riskLevel, isNull);
  });
}
