import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/providers/api_providers.dart';
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
