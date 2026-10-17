import '../../../shared/services/api/api_client.dart';

/// D-76 team and admin-opened chats. Everything goes through FastAPI (who may talk to
/// whom, unread counts, pushes); not end-to-end encrypted, like the pharmacy chat.

class ChatPerson {
  const ChatPerson({required this.uid, required this.name, this.role, this.email});

  final String uid;
  final String name;
  final String? role;
  final String? email;

  factory ChatPerson.fromApi(Map<String, dynamic> j) => ChatPerson(
    uid: '${j['uid']}',
    name: j['name'] as String? ?? 'Unknown',
    role: j['role'] as String?,
    email: j['email'] as String?,
  );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.participants,
    required this.other,
    required this.observer,
    required this.openedByAdmin,
    required this.lastText,
    required this.unread,
    this.openedBy,
    this.lastSenderId,
    this.lastMessageAt,
  });

  final String id;
  final List<ChatPerson> participants;

  /// The other person; null for an admin looking at a chat they opened for two others.
  final ChatPerson? other;
  final bool observer;
  final bool openedByAdmin;
  final ChatPerson? openedBy;
  final String lastText;
  final String? lastSenderId;
  final DateTime? lastMessageAt;
  final int unread;

  /// "Dr Tan" or, for an observer, "Aisyah and Siti".
  String get title => other?.name ?? participants.map((p) => p.name).join(' and ');

  factory Conversation.fromApi(Map<String, dynamic> j) => Conversation(
    id: '${j['id']}',
    participants: [
      for (final p in j['participants'] as List<dynamic>? ?? const [])
        ChatPerson.fromApi(p as Map<String, dynamic>),
    ],
    other: j['other'] == null ? null : ChatPerson.fromApi(j['other'] as Map<String, dynamic>),
    observer: j['observer'] as bool? ?? false,
    openedByAdmin: j['openedByAdmin'] as bool? ?? false,
    openedBy: j['openedBy'] == null
        ? null
        : ChatPerson.fromApi(j['openedBy'] as Map<String, dynamic>),
    lastText: j['lastText'] as String? ?? '',
    lastSenderId: j['lastSenderId'] as String?,
    lastMessageAt: DateTime.tryParse('${j['lastMessageAt']}'),
    unread: (j['unread'] as num?)?.toInt() ?? 0,
  );
}

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.senderName,
    required this.text,
    this.sentAt,
  });

  final String id;
  final String senderId;
  final String? senderRole;
  final String senderName;
  final String text;
  final DateTime? sentAt;

  bool get isSystem => senderRole == 'system';

  factory ConversationMessage.fromApi(Map<String, dynamic> j) => ConversationMessage(
    id: '${j['id']}',
    senderId: '${j['senderId']}',
    senderRole: j['senderRole'] as String?,
    senderName: j['senderName'] as String? ?? '',
    text: j['text'] as String? ?? '',
    sentAt: DateTime.tryParse('${j['sentAt']}'),
  );
}

class ConversationThread {
  const ConversationThread(this.conversation, this.messages);
  final Conversation conversation;
  final List<ConversationMessage> messages;
}

abstract interface class ConversationsRepository {
  Future<List<Conversation>> mine();

  Future<List<ChatPerson>> contacts(String query);

  Future<Conversation> start(String userId);

  /// Admin: open a chat between two people.
  Future<Conversation> pair(String userA, String userB);

  Future<ConversationThread> thread(String id);

  Future<void> send(String id, String text);

  Future<void> markRead(String id);
}

class ApiConversationsRepository implements ConversationsRepository {
  ApiConversationsRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Conversation>> mine() async => [
    for (final c in (await _api.conversations())['conversations'] as List<dynamic>? ?? const [])
      Conversation.fromApi(c as Map<String, dynamic>),
  ];

  @override
  Future<List<ChatPerson>> contacts(String query) async => [
    for (final c
        in (await _api.conversationContacts(query))['contacts'] as List<dynamic>? ?? const [])
      ChatPerson.fromApi(c as Map<String, dynamic>),
  ];

  @override
  Future<Conversation> start(String userId) async =>
      Conversation.fromApi(await _api.startConversation(userId));

  @override
  Future<Conversation> pair(String userA, String userB) async =>
      Conversation.fromApi(await _api.pairConversation(userA, userB));

  @override
  Future<ConversationThread> thread(String id) async {
    final j = await _api.conversationThread(id);
    return ConversationThread(Conversation.fromApi(j['conversation'] as Map<String, dynamic>), [
      for (final m in j['messages'] as List<dynamic>? ?? const [])
        ConversationMessage.fromApi(m as Map<String, dynamic>),
    ]);
  }

  @override
  Future<void> send(String id, String text) => _api.sendConversationMessage(id, text);

  @override
  Future<void> markRead(String id) => _api.markConversationRead(id);
}
