import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';
import '../domain/keyword_scanner.dart';
import 'message_crypto.dart';

/// The other person in a conversation (a patient's assigned doctor, or a doctor's patient).
class Contact {
  const Contact({required this.uid, required this.name, this.subtitle, this.publicKey});

  final String uid;
  final String name;
  final String? subtitle; // specialty / "Patient"

  /// Null until that user has opened CareFlow once (D-42): no messages can be sent yet.
  final String? publicKey;

  factory Contact.fromUser(String uid, Map<String, dynamic> d) => Contact(
    uid: uid,
    name: d['name'] as String? ?? 'Unknown',
    subtitle: d['role'] == 'doctor' ? (d['specialty'] as String? ?? 'Doctor') : 'Patient',
    publicKey: d['publicKey'] as String?,
  );
}

/// One decrypted message (Table 4.2.3.13 + D-42 key fields).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.isFlagged,
    required this.sentAt,
    this.pending = false,
  });

  final String id;
  final bool fromMe;

  /// Null when it was encrypted for an earlier device of mine (D-42).
  final String? text;
  final bool isFlagged;
  final DateTime sentAt;

  /// Written locally, not yet stored on the server (offline queue, UC10.1 E1).
  final bool pending;
}

/// Raw stored message before decryption.
class StoredMessage {
  const StoredMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.encryptedText,
    required this.senderPublicKey,
    required this.recipientPublicKey,
    required this.isFlagged,
    required this.sentAt,
    required this.pending,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String encryptedText;
  final String senderPublicKey;
  final String recipientPublicKey;
  final bool isFlagged;
  final DateTime sentAt;
  final bool pending;

  factory StoredMessage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return StoredMessage(
      id: d.id,
      senderId: m['senderId'] as String,
      recipientId: m['recipientId'] as String,
      encryptedText: m['encryptedText'] as String? ?? '',
      senderPublicKey: m['senderPublicKey'] as String? ?? '',
      recipientPublicKey: m['recipientPublicKey'] as String? ?? '',
      isFlagged: m['isFlagged'] as bool? ?? false,
      // A local write has no server time yet; show it as "now".
      sentAt: (m['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pending: d.metadata.hasPendingWrites,
    );
  }
}

/// FR-10.1 secure messaging (Fig 4.1.1.10 MessagingCtrl). Messages go straight to
/// Firestore under Security Rules (the server cannot read them); FastAPI is only told
/// afterwards so it can push the recipient and escalate flagged messages.
abstract interface class MessagingRepository {
  /// Publishes this device's public key on users/{uid}.publicKey if it changed (D-07).
  Future<void> publishKey(String uid);

  Stream<Contact?> contact(String uid);

  /// Both directions of one conversation, oldest first, decrypted.
  Stream<List<ChatMessage>> thread(String me, String other);

  /// Scans, encrypts and stores [text]; returns true when the keyword scan flagged it.
  Future<bool> send({required String me, required Contact to, required String text});

  /// UC10.3 E1: the doctor clears a false-positive flag.
  Future<void> clearFlag(String messageId);
}

class FirestoreMessagingRepository implements MessagingRepository {
  FirestoreMessagingRepository(this._db, this._api, this._crypto, this._scanner);

  final FirebaseFirestore _db;
  final ApiClient _api;
  final MessageCrypto _crypto;
  final Future<KeywordScanner> _scanner;

  @override
  Future<void> publishKey(String uid) async {
    final key = await _crypto.publicKey(uid);
    final ref = _db.collection(Collections.users).doc(uid);
    final current = (await ref.get()).data()?['publicKey'];
    if (current != key) await ref.update({'publicKey': key});
  }

  @override
  Stream<Contact?> contact(String uid) => _db
      .collection(Collections.users)
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? Contact.fromUser(s.id, s.data()!) : null);

  Stream<List<StoredMessage>> _direction(String from, String to) => _db
      .collection(Collections.messages)
      .where('senderId', isEqualTo: from)
      .where('recipientId', isEqualTo: to)
      .orderBy('sentAt')
      .limitToLast(100)
      .snapshots(includeMetadataChanges: true)
      .map((s) => [for (final d in s.docs) StoredMessage.fromFirestore(d)]);

  @override
  Stream<List<ChatMessage>> thread(String me, String other) =>
      _combine(_direction(me, other), _direction(other, me)).asyncMap((all) async {
        final sorted = [...all]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
        return [for (final m in sorted) await decryptFor(_crypto, me, m)];
      });

  @override
  Future<bool> send({required String me, required Contact to, required String text}) async {
    final key = to.publicKey;
    if (key == null) throw const RecipientNotReadyException();
    final flagged = (await _scanner).isHighRisk(text);
    final sealed = await _crypto.encrypt(
      text: text,
      senderId: me,
      recipientId: to.uid,
      recipientPublicKey: key,
    );
    final ref = _db.collection(Collections.messages).doc();
    // Not awaited: offline, the write is queued and shows at once (UC10.1 E1). Once the
    // server has it, FastAPI pushes the recipient (and escalates if flagged).
    unawaited(
      ref
          .set({
            'senderId': me,
            'recipientId': to.uid,
            'encryptedText': sealed.encryptedText,
            'isFlagged': flagged,
            'sentAt': FieldValue.serverTimestamp(),
            'senderPublicKey': sealed.senderPublicKey,
            'recipientPublicKey': key,
          })
          .then((_) => _api.notifyMessage(ref.id))
          .catchError((Object _) {}),
    );
    return flagged;
  }

  @override
  Future<void> clearFlag(String messageId) =>
      _db.collection(Collections.messages).doc(messageId).update({'isFlagged': false});
}

class RecipientNotReadyException implements Exception {
  const RecipientNotReadyException();
}

Future<ChatMessage> decryptFor(MessageCrypto crypto, String me, StoredMessage m) async {
  String? text;
  try {
    text = await crypto.decrypt(
      me: me,
      senderId: m.senderId,
      recipientId: m.recipientId,
      encryptedText: m.encryptedText,
      senderPublicKey: m.senderPublicKey,
      recipientPublicKey: m.recipientPublicKey,
    );
  } catch (_) {
    text = null; // earlier device or damaged: shown as a notice, never as garbage
  }
  return ChatMessage(
    id: m.id,
    fromMe: m.senderId == me,
    text: text,
    isFlagged: m.isFlagged,
    sentAt: m.sentAt,
    pending: m.pending,
  );
}

/// Latest values of two list streams, concatenated (no extra package needed).
Stream<List<T>> _combine<T>(Stream<List<T>> a, Stream<List<T>> b) {
  late StreamController<List<T>> controller;
  List<T>? lastA;
  List<T>? lastB;
  StreamSubscription<List<T>>? subA;
  StreamSubscription<List<T>>? subB;
  void emit() {
    if (lastA != null && lastB != null) controller.add([...lastA!, ...lastB!]);
  }

  controller = StreamController<List<T>>(
    onListen: () {
      subA = a.listen((v) {
        lastA = v;
        emit();
      }, onError: controller.addError);
      subB = b.listen((v) {
        lastB = v;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}
