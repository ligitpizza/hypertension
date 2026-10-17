import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/providers/api_providers.dart';
import '../data/attachment_picker.dart';
import '../data/conversations_repository.dart';
import '../data/message_crypto.dart';
import '../data/messaging_repository.dart';
import '../domain/keyword_scanner.dart';

Duration? _noRetry(int _, Object _) => null;

/// FR-14.4 keyword list from the shared JSON asset.
final keywordScannerProvider = FutureProvider<KeywordScanner>(
  (ref) async => KeywordScanner.fromJson(await rootBundle.loadString(KeywordScanner.assetPath)),
);

final messageCryptoProvider = Provider<MessageCrypto>(
  (ref) => MessageCrypto(SecureStorageKeyVault()),
);

final messagingRepositoryProvider = Provider<MessagingRepository>(
  (ref) => FirestoreMessagingRepository(
    FirebaseFirestore.instance,
    ref.watch(apiClientProvider),
    ref.watch(messageCryptoProvider),
    ref.watch(keywordScannerProvider.future),
  ),
);

/// D-52 photo / PDF chooser.
final attachmentPickerProvider = Provider<AttachmentPicker>((ref) => DeviceAttachmentPicker());

/// (me, attachment) -> decrypted bytes; kept while shown so scrolling doesn't re-download.
final attachmentBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, (String, ChatAttachment)>(
      (ref, key) => ref.watch(messagingRepositoryProvider).openAttachment(key.$1, key.$2),
      retry: _noRetry,
    );

final contactProvider = StreamProvider.family<Contact?, String>(
  (ref, uid) => ref.watch(messagingRepositoryProvider).contact(uid),
  retry: _noRetry,
);

/// (me, other) -> decrypted conversation, oldest first.
final threadProvider = StreamProvider.family<List<ChatMessage>, (String, String)>(
  (ref, ids) => ref.watch(messagingRepositoryProvider).thread(ids.$1, ids.$2),
  retry: _noRetry,
);

/// D-42: unread state is per device: the last time this conversation was opened here.
class ChatSeenStore {
  static String _key(String me, String other) => 'chat_seen_${me}_$other';

  Future<DateTime?> lastSeen(String me, String other) async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(_key(me, other));
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  Future<void> markSeen(String me, String other, DateTime at) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(
        _key(me, other),
        at.millisecondsSinceEpoch,
      );
    } catch (_) {
      // Unread badges are a convenience; never fail the chat because of them.
    }
  }
}

final chatSeenStoreProvider = Provider<ChatSeenStore>((ref) => ChatSeenStore());

/// Messages from [other] newer than when this conversation was last opened on this device.
final unreadCountProvider = FutureProvider.family<int, (String, String)>((ref, ids) async {
  final messages = ref.watch(threadProvider(ids)).value ?? const <ChatMessage>[];
  final seen = await ref.watch(chatSeenStoreProvider).lastSeen(ids.$1, ids.$2);
  return messages.where((m) => !m.fromMe && (seen == null || m.sentAt.isAfter(seen))).length;
});

/// D-76: Harvey AI notes in a patient's chat with their doctor (patient uid).
final chatAlertsProvider = StreamProvider.family<List<AgentNote>, String>(
  (ref, patientId) => ref.watch(messagingRepositoryProvider).chatAlerts(patientId),
  retry: _noRetry,
);

/// D-76 team and admin-opened chats.
final conversationsRepositoryProvider = Provider<ConversationsRepository>(
  (ref) => ApiConversationsRepository(ref.watch(apiClientProvider)),
);

final myConversationsProvider = FutureProvider.autoDispose<List<Conversation>>(
  (ref) => ref.watch(conversationsRepositoryProvider).mine(),
  retry: _noRetry,
);

final conversationThreadProvider = FutureProvider.autoDispose.family<ConversationThread, String>(
  (ref, id) => ref.watch(conversationsRepositoryProvider).thread(id),
  retry: _noRetry,
);

final chatContactsProvider = FutureProvider.autoDispose.family<List<ChatPerson>, String>(
  (ref, q) => ref.watch(conversationsRepositoryProvider).contacts(q),
  retry: _noRetry,
);

/// D-76: the patient's weekly summary, asked for once when the inbox first opens.
final weeklySummaryRequestProvider = FutureProvider<void>((ref) async {
  try {
    await ref.watch(apiClientProvider).ensureWeeklySummary();
  } catch (_) {
    // The summary is a convenience; the inbox works without it.
  }
}, retry: _noRetry);

/// When (me, key) was last opened on this device: key is the other uid, "pharmacy",
/// "pharmacy_{patientId}" (pharmacist side) or "assistant" (D-42 / D-76).
final seenAtProvider = FutureProvider.family<DateTime?, (String, String)>(
  (ref, ids) => ref.watch(chatSeenStoreProvider).lastSeen(ids.$1, ids.$2),
  retry: _noRetry,
);

/// Marks (me, key) seen at [at] and refreshes the badges that depend on it.
Future<void> markChatSeen(WidgetRef ref, String me, String key, DateTime at) async {
  final seen = await ref.read(seenAtProvider((me, key)).future).catchError((Object _) => null);
  if (seen != null && !at.isAfter(seen)) return;
  await ref.read(chatSeenStoreProvider).markSeen(me, key, at);
  ref.invalidate(seenAtProvider((me, key)));
}
