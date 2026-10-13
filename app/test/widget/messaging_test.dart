import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/messaging/data/messaging_repository.dart';
import 'package:hypertension/features/messaging/presentation/chat_thread_page.dart';
import 'package:hypertension/features/messaging/presentation/inbox_pages.dart';
import 'package:hypertension/features/messaging/state/messaging_providers.dart';
import 'package:hypertension/features/staff_shell/staff_shell.dart';
import 'package:hypertension/shared/models/health_models.dart';

import '../helpers/fakes.dart';

// Module 10 messaging UI (FR-10.1, FR-10.2, FR-10.3; UC10.1, UC10.2, UC10.3; D-42).
final now = DateTime(2026, 10, 14, 10);

class FakeMessagingRepository implements MessagingRepository {
  final contacts = <String, Contact>{
    'd1': const Contact(uid: 'd1', name: 'Dr John', subtitle: 'Cardiology', publicKey: 'k'),
  };
  final threads = <String, StreamController<List<ChatMessage>>>{};
  List<ChatMessage> history = const [];
  final sent = <String>[];
  final cleared = <String>[];
  bool flagNext = false;

  @override
  Future<void> publishKey(String uid) async {}

  @override
  Stream<Contact?> contact(String uid) => Stream.value(contacts[uid]);

  @override
  Stream<List<ChatMessage>> thread(String me, String other) => Stream.value(history);

  @override
  Future<bool> send({required String me, required Contact to, required String text}) async {
    sent.add(text);
    return flagNext;
  }

  @override
  Future<void> clearFlag(String messageId) async => cleared.add(messageId);
}

ChatMessage msg(String id, String text, {bool mine = false, bool flagged = false, int min = 0}) =>
    ChatMessage(
      id: id,
      fromMe: mine,
      text: text,
      isFlagged: flagged,
      sentAt: now.subtract(Duration(minutes: min)),
    );

AppUser user(UserRole role, {String? doctor}) => AppUser(
  uid: role == UserRole.doctor ? 'd1' : 'p1',
  email: 'x@y.my',
  name: role == UserRole.doctor ? 'Dr John' : 'Siti',
  role: role,
  isActive: true,
  onboardingComplete: true,
  assignedDoctorId: doctor,
);

Widget chatApp(FakeMessagingRepository repo, AppUser me, String location) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/chat', builder: (_, _) => const PatientInboxPage()),
      GoRoute(
        path: '/chat/:id',
        builder: (_, s) => ChatThreadPage(otherId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/ai-agent', builder: (_, _) => const Text('ROUTE /ai-agent')),
    ],
  );
  return ProviderScope(
    overrides: [
      messagingRepositoryProvider.overrideWithValue(repo),
      authUidProvider.overrideWith((ref) => Stream.value(me.uid)),
      currentUserProvider.overrideWith((ref) => Stream.value(me)),
      carePlanProvider.overrideWith(
        (ref) => Stream.value(CarePlan(content: 'Walk 20 minutes daily', updatedAt: now)),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late FakeMessagingRepository repo;
  setUp(() {
    repo = FakeMessagingRepository();
    SharedPreferences.setMockInitialValues({}); // per-device unread state (D-42)
  });

  group('Fig 4.3.15.1 inbox', () {
    tallTest('patient sees the assigned doctor and the AI assistant', (t) async {
      repo.history = [msg('m1', 'Your BP looks stable', min: 5)];
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat'));
      await t.pumpAndSettle();
      expect(find.text('Dr John'), findsOneWidget);
      expect(find.textContaining('Your BP looks stable'), findsOneWidget);
      expect(find.byKey(const Key('unread-d1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-ai-agent')), findsOneWidget);
    });

    tallTest('no assigned doctor shows an explanation', (t) async {
      await t.pumpWidget(chatApp(repo, user(UserRole.patient), '/chat'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('inbox-no-doctor')), findsOneWidget);
    });
  });

  group('Fig 4.3.15.2 / 4.3.15.3 thread', () {
    tallTest('UC10.1 sends a message; encryption notice is shown', (t) async {
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat/d1'));
      await t.pumpAndSettle();
      expect(find.text('Messages are end-to-end encrypted'), findsOneWidget);
      await t.enterText(find.byKey(const Key('chat-input')), 'Good morning doctor');
      await t.tap(find.byKey(const Key('chat-send')));
      await t.pumpAndSettle();
      expect(repo.sent, ['Good morning doctor']);
    });

    tallTest('UC10.3 the patient sees the flagged banner with 999', (t) async {
      repo.history = [msg('m1', 'I have chest pain', mine: true, flagged: true)];
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat/d1'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('chat-flagged-banner')), findsOneWidget);
      expect(find.textContaining('call 999'), findsOneWidget);
      expect(find.textContaining('911'), findsNothing);
    });

    tallTest('UC10.3 E1 the doctor sees the flag and can dismiss it', (t) async {
      repo.contacts['p1'] = const Contact(
        uid: 'p1',
        name: 'Siti',
        subtitle: 'Patient',
        publicKey: 'k',
      );
      repo.history = [msg('m1', 'I have chest pain', flagged: true)];
      await t.pumpWidget(chatApp(repo, user(UserRole.doctor), '/chat/p1'));
      await t.pumpAndSettle();
      expect(find.text('Flagged: high-risk words'), findsOneWidget);
      expect(find.byKey(const Key('chat-flagged-banner')), findsNothing);
      await t.tap(find.byKey(const Key('dismiss-flag-m1')));
      await t.pump();
      expect(repo.cleared, ['m1']);
    });

    tallTest('D-42 a message for an earlier device shows a notice, not garbage', (t) async {
      repo.history = [
        ChatMessage(id: 'old', fromMe: false, text: null, isFlagged: false, sentAt: now),
      ];
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat/d1'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('earlier-device-old')), findsOneWidget);
    });

    tallTest('UC10.1 E1 a queued offline message says it will send when online', (t) async {
      repo.history = [
        ChatMessage(
          id: 'q1',
          fromMe: true,
          text: 'hello',
          isFlagged: false,
          sentAt: now,
          pending: true,
        ),
      ];
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat/d1'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pending-q1')), findsOneWidget);
    });

    tallTest('the recipient without a key cannot be messaged yet', (t) async {
      repo.contacts['d1'] = const Contact(uid: 'd1', name: 'Dr John', subtitle: 'Doctor');
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat/d1'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('chat-not-ready')), findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const Key('chat-send'))).onPressed, isNull);
    });

    tallTest('FR-10.2 the shared care plan opens from the chat', (t) async {
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat/d1'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('chat-care-plan-button')));
      await t.pumpAndSettle();
      expect(find.text('Walk 20 minutes daily'), findsOneWidget);
    });
  });

  test('staff nav picks the most specific destination', () {
    final d = staffDestinations(UserRole.doctor);
    expect(d[selectedDestination(d, '/doctor/messages/p1')].label, 'Messages');
    expect(d[selectedDestination(d, '/doctor/patient/p1')].label, 'Patients');
  });
}
