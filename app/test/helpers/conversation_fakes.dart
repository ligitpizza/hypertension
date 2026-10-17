import 'package:hypertension/features/messaging/data/conversations_repository.dart';

/// D-76 team and admin-opened chats, in memory.
class FakeConversationsRepository implements ConversationsRepository {
  List<Conversation> list = [];
  final threads = <String, List<ConversationMessage>>{};
  List<ChatPerson> people = const [];
  final calls = <String>[];

  @override
  Future<List<Conversation>> mine() async => list;

  @override
  Future<List<ChatPerson>> contacts(String query) async => [
    for (final p in people)
      if (query.isEmpty || p.name.toLowerCase().contains(query.toLowerCase())) p,
  ];

  @override
  Future<Conversation> start(String userId) async {
    calls.add('start:$userId');
    final person = people.firstWhere((p) => p.uid == userId);
    return conversation('me__$userId', person);
  }

  @override
  Future<Conversation> pair(String userA, String userB) async {
    calls.add('pair:$userA:$userB');
    return conversation('${userA}__$userB', null, observer: true);
  }

  @override
  Future<ConversationThread> thread(String id) async => ConversationThread(
    list.firstWhere(
      (c) => c.id == id,
      orElse: () => conversation(id, const ChatPerson(uid: 'x', name: 'Someone')),
    ),
    threads[id] ?? const [],
  );

  @override
  Future<void> send(String id, String text) async => calls.add('send:$id:$text');

  @override
  Future<void> markRead(String id) async => calls.add('read:$id');
}

Conversation conversation(
  String id,
  ChatPerson? other, {
  bool observer = false,
  bool byAdmin = false,
  String lastText = '',
  int unread = 0,
  List<ChatPerson> participants = const [],
}) => Conversation(
  id: id,
  participants: participants.isEmpty && other != null ? [other] : participants,
  other: other,
  observer: observer,
  openedByAdmin: byAdmin,
  openedBy: byAdmin ? const ChatPerson(uid: 'a1', name: 'Admin Lee', role: 'admin') : null,
  lastText: lastText,
  unread: unread,
  lastMessageAt: DateTime.utc(2026, 10, 16, 2),
);
