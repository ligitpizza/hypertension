import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/messaging/data/attachment_picker.dart';
import 'package:hypertension/features/messaging/data/messaging_repository.dart';
import 'package:hypertension/features/messaging/presentation/chat_thread_page.dart';
import 'package:hypertension/features/messaging/presentation/inbox_pages.dart';
import 'package:hypertension/features/messaging/state/messaging_providers.dart';
import 'package:hypertension/features/settings/data/settings_repository.dart';
import 'package:hypertension/features/settings/state/settings_providers.dart';
import 'package:hypertension/features/staff_shell/staff_shell.dart';
import 'package:hypertension/shared/models/health_models.dart';

import 'package:hypertension/features/ai_agent/data/agent_repository.dart';
import 'package:hypertension/features/ai_agent/state/agent_providers.dart';
import 'package:hypertension/features/messaging/data/conversations_repository.dart';
import 'package:hypertension/features/messaging/presentation/conversation_pages.dart';
import 'package:hypertension/features/orders/data/order_models.dart';
import 'package:hypertension/features/orders/state/orders_providers.dart';

import '../helpers/conversation_fakes.dart';
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

  final reviewed = <String>[];
  List<AgentNote> notes = const [];

  @override
  Future<bool> send({
    required String me,
    required Contact to,
    required String text,
    bool aiReview = false,
  }) async {
    sent.add(text);
    final flagged = flagNext || hasCrisisBp(text);
    if (flagged && aiReview) reviewed.add(text);
    return flagged;
  }

  @override
  Stream<List<AgentNote>> chatAlerts(String patientId) => Stream.value(notes);

  @override
  Future<void> clearFlag(String messageId) async => cleared.add(messageId);

  final attachments = <(String name, AttachmentType type, String caption)>[];
  Uint8List fileBytes = Uint8List.fromList(_png);

  @override
  Future<bool> sendAttachment({
    required String me,
    required Contact to,
    required Uint8List bytes,
    required String fileName,
    required AttachmentType type,
    String caption = '',
  }) async {
    if (bytes.length > maxAttachmentBytes) throw const AttachmentTooLargeException();
    attachments.add((fileName, type, caption));
    return false;
  }

  @override
  Future<Uint8List> openAttachment(String me, ChatAttachment attachment) async => fileBytes;
}

/// A 1x1 transparent PNG, so Image.memory can decode it in tests.
const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

class FakePicker implements AttachmentPicker {
  PickedAttachment? next;

  @override
  bool get hasCamera => true;

  @override
  Future<PickedAttachment?> photo({required bool camera}) async => next;

  @override
  Future<PickedAttachment?> pdf() async => next;
}

class FakeSharer implements FileSharer {
  final shared = <String>[];

  @override
  Future<void> share(Uint8List bytes, {required String fileName, required String mimeType}) async =>
      shared.add('$fileName|$mimeType');
}

final picker = FakePicker();
final sharer = FakeSharer();

ChatAttachment attachment(String path, AttachmentType type, {String? name = 'lab.pdf'}) =>
    ChatAttachment(
      path: path,
      type: type,
      size: 52000,
      name: name,
      senderId: 'd1',
      recipientId: 'p1',
      senderPublicKey: 'a',
      recipientPublicKey: 'b',
    );

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

// D-76 inbox sources.
var convRepo = FakeConversationsRepository();
List<PharmacyMessage> pharmacyChat = const [];
List<AgentMessage> agentHistory = const [];

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
      GoRoute(path: '/pharmacy-chat', builder: (_, _) => const Text('ROUTE /pharmacy-chat')),
      GoRoute(
        path: '/conversation/:id',
        builder: (_, s) => PatientConversationPage(conversationId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin/messages',
        builder: (_, _) => const Scaffold(body: AdminMessagesPage()),
      ),
      GoRoute(
        path: '/admin/messages/:id',
        builder: (_, s) => Text('ROUTE /admin/messages/${s.pathParameters['id']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      conversationsRepositoryProvider.overrideWithValue(convRepo),
      myPharmacyChatProvider.overrideWith((ref) async => pharmacyChat),
      agentMessagesProvider.overrideWith((ref) => Stream.value(agentHistory)),
      weeklySummaryRequestProvider.overrideWith((ref) async {}),
      messagingRepositoryProvider.overrideWithValue(repo),
      attachmentPickerProvider.overrideWithValue(picker),
      fileSharerProvider.overrideWithValue(sharer),
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
    convRepo = FakeConversationsRepository();
    pharmacyChat = const [];
    agentHistory = const [];
    picker.next = null;
    sharer.shared.clear();
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

  group('D-52 attachments', () {
    Future<void> openChat(WidgetTester t) async {
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat/d1'));
      await t.pumpAndSettle();
    }

    tallTest('a photo is sent with the typed text as its caption', (t) async {
      picker.next = PickedAttachment(
        bytes: Uint8List.fromList(_png),
        name: 'rash.jpg',
        type: AttachmentType.image,
      );
      await openChat(t);
      await t.enterText(find.byKey(const Key('chat-input')), 'Is this a reaction?');
      await t.tap(find.byKey(const Key('chat-attach')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('attach-camera')), findsOneWidget);
      await t.tap(find.byKey(const Key('attach-gallery')));
      await t.pumpAndSettle();
      expect(repo.attachments, [('rash.jpg', AttachmentType.image, 'Is this a reaction?')]);
      expect(find.widgetWithText(TextField, 'Is this a reaction?'), findsNothing);
    });

    tallTest('a PDF over 10 MB is refused with a clear message', (t) async {
      picker.next = PickedAttachment(
        bytes: Uint8List(maxAttachmentBytes + 1),
        name: 'scan.pdf',
        type: AttachmentType.pdf,
      );
      await openChat(t);
      await t.tap(find.byKey(const Key('chat-attach')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('attach-pdf')));
      await t.pumpAndSettle();
      expect(find.textContaining('larger than 10 MB'), findsOneWidget);
      expect(repo.attachments, isEmpty);
    });

    tallTest('cancelling the picker sends nothing', (t) async {
      await openChat(t);
      await t.tap(find.byKey(const Key('chat-attach')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('attach-gallery')));
      await t.pumpAndSettle();
      expect(repo.attachments, isEmpty);
      expect(find.byKey(const Key('chat-error')), findsNothing);
    });

    tallTest('received photos show in the thread; PDFs open with their name', (t) async {
      repo.history = [
        ChatMessage(
          id: 'm1',
          fromMe: false,
          text: '',
          isFlagged: false,
          sentAt: now,
          attachment: attachment('p/1', AttachmentType.image, name: 'xray.jpg'),
        ),
        ChatMessage(
          id: 'm2',
          fromMe: false,
          text: 'Your lab results',
          isFlagged: false,
          sentAt: now,
          attachment: attachment('p/2', AttachmentType.pdf),
        ),
      ];
      await openChat(t);
      expect(
        find.descendant(of: find.byKey(const Key('attachment-p/1')), matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(find.text('lab.pdf · 51 KB'), findsOneWidget);
      expect(find.text('Your lab results'), findsOneWidget);
      await t.tap(find.byKey(const Key('attachment-p/2')));
      await t.pumpAndSettle();
      expect(sharer.shared, ['lab.pdf|application/pdf']);
    });

    tallTest('a file for an earlier device says so', (t) async {
      repo.history = [
        ChatMessage(
          id: 'm1',
          fromMe: false,
          text: '',
          isFlagged: false,
          sentAt: now,
          attachment: attachment('p/1', AttachmentType.pdf, name: null),
        ),
      ];
      await openChat(t);
      expect(find.textContaining('encrypted for an earlier device'), findsOneWidget);
    });
  });

  group('D-76 messaging', () {
    tallTest('the inbox labels who is who and counts unread messages', (t) async {
      pharmacyChat = [
        PharmacyMessage(
          id: 'pm1',
          patientId: 'p1',
          senderRole: 'pharmacist',
          senderName: 'Harvey Pharmacy (Aisyah)',
          text: 'Your order is ready',
          sentAt: now,
        ),
      ];
      agentHistory = [
        AgentMessage(
          id: 'w1',
          fromPatient: false,
          text: 'Your weekly health summary...',
          sentAt: now,
          kind: 'weekly_summary',
        ),
      ];
      convRepo.list = [
        conversation(
          'c1',
          const ChatPerson(uid: 'a1', name: 'Admin Lee', role: 'admin'),
          lastText: 'Please update your IC',
          unread: 2,
        ),
      ];
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat'));
      await t.pumpAndSettle();
      for (final label in ['Doctor', 'Pharmacy', 'Admin', 'Assistant']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.byKey(const Key('unread-pharmacy')), findsOneWidget);
      expect(find.byKey(const Key('unread-assistant')), findsOneWidget);
      expect(find.text('Your weekly health summary is ready'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('team-unread-c1')), matching: find.text('2')),
        findsOneWidget,
      );
      await t.tap(find.text('Admin Lee'));
      await t.pumpAndSettle();
      expect(convRepo.calls, contains('read:c1'));
    });

    tallTest('the patient replies in a chat the admin opened', (t) async {
      convRepo.list = [
        conversation(
          'c1',
          const ChatPerson(uid: 'ph1', name: 'Aisyah', role: 'pharmacist'),
          byAdmin: true,
        ),
      ];
      convRepo.threads['c1'] = const [
        ConversationMessage(
          id: 'm0',
          senderId: 'a1',
          senderRole: 'system',
          senderName: 'Harvey',
          text: 'Admin Lee (admin) opened this chat between Aisyah and Siti.',
        ),
        ConversationMessage(
          id: 'm1',
          senderId: 'ph1',
          senderRole: 'pharmacist',
          senderName: 'Aisyah',
          text: 'Hello Siti',
        ),
      ];
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/conversation/c1'));
      await t.pumpAndSettle();
      expect(find.textContaining('Chat opened by Admin Lee'), findsOneWidget);
      expect(find.textContaining('opened this chat between'), findsOneWidget);
      expect(find.text('Pharmacy'), findsWidgets);
      await t.enterText(find.byKey(const Key('conversation-input')), 'Hi Aisyah');
      await t.tap(find.byKey(const Key('conversation-send')));
      await t.pumpAndSettle();
      expect(convRepo.calls, contains('send:c1:Hi Aisyah'));
    });

    tallTest('a crisis BP sent to the doctor brings in Harvey AI; its note shows', (t) async {
      repo.notes = [
        AgentNote(id: 'n1', text: 'Harvey AI here. 200/150 is very high.', sentAt: now),
      ];
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/chat/d1'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ai-note-n1')), findsOneWidget);
      expect(find.textContaining('not a substitute for a doctor'), findsOneWidget);
      await t.enterText(find.byKey(const Key('chat-input')), 'my bp was 200/150');
      await t.tap(find.byKey(const Key('chat-send')));
      await t.pumpAndSettle();
      expect(repo.reviewed, ['my bp was 200/150']);
    });

    tallTest('the doctor sees the Harvey AI note but never triggers a review', (t) async {
      repo.contacts['p1'] = const Contact(
        uid: 'p1',
        name: 'Siti',
        subtitle: 'Patient',
        publicKey: 'k',
      );
      repo.notes = [AgentNote(id: 'n1', text: 'Harvey AI here.', sentAt: now)];
      await t.pumpWidget(chatApp(repo, user(UserRole.doctor), '/chat/p1'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ai-note-n1')), findsOneWidget);
      await t.enterText(find.byKey(const Key('chat-input')), 'Your bp 200/150 is high');
      await t.tap(find.byKey(const Key('chat-send')));
      await t.pumpAndSettle();
      expect(repo.reviewed, isEmpty);
    });

    test('crisis BP is found in the message text', () {
      expect(hasCrisisBp('my bp was 200/150'), isTrue);
      expect(hasCrisisBp('BP 185 over 100'), isTrue);
      expect(hasCrisisBp('bp 150/95'), isFalse);
      expect(hasCrisisBp('see you 12/10'), isFalse);
    });

    tallTest('admin starts a chat and opens one between two people', (t) async {
      convRepo.people = const [
        ChatPerson(uid: 'ph1', name: 'Aisyah', role: 'pharmacist'),
        ChatPerson(uid: 'p1', name: 'Siti', role: 'patient'),
      ];
      final admin = AppUser(
        uid: 'a1',
        email: 'a@y.my',
        name: 'Admin Lee',
        role: UserRole.admin,
        isActive: true,
        onboardingComplete: true,
      );
      await t.pumpWidget(chatApp(repo, admin, '/admin/messages'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pair-chat')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pick-person-ph1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pick-person-ph1')), findsNothing); // can't pick twice
      await t.tap(find.byKey(const Key('pick-person-p1')));
      await t.pumpAndSettle();
      expect(convRepo.calls, contains('pair:ph1:p1'));
      expect(find.text('ROUTE /admin/messages/ph1__p1'), findsOneWidget);
    });

    tallTest('an admin watching a chat they opened cannot write in it', (t) async {
      convRepo.list = [
        conversation(
          'c9',
          null,
          observer: true,
          byAdmin: true,
          participants: const [
            ChatPerson(uid: 'ph1', name: 'Aisyah', role: 'pharmacist'),
            ChatPerson(uid: 'p1', name: 'Siti', role: 'patient'),
          ],
        ),
      ];
      await t.pumpWidget(chatApp(repo, user(UserRole.patient, doctor: 'd1'), '/conversation/c9'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('conversation-input')), findsNothing);
      expect(find.textContaining('Only the two people in it can write'), findsOneWidget);
    });
  });
}
