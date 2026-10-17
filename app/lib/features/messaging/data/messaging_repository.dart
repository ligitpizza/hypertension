import 'dart:async';

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

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

  /// Null until that user has opened Harvey once (D-42): no messages can be sent yet.
  final String? publicKey;

  factory Contact.fromUser(String uid, Map<String, dynamic> d) => Contact(
    uid: uid,
    name: d['name'] as String? ?? 'Unknown',
    subtitle: d['role'] == 'doctor' ? (d['specialty'] as String? ?? 'Doctor') : 'Patient',
    publicKey: d['publicKey'] as String?,
  );
}

/// D-52 attachment kinds.
enum AttachmentType {
  image('image'),
  pdf('pdf');

  const AttachmentType(this.value);
  final String value;

  static AttachmentType? fromValue(Object? v) => values.where((e) => e.value == v).firstOrNull;
}

/// Largest attachment accepted (D-52), before encryption.
const maxAttachmentBytes = 10 * 1024 * 1024;

class AttachmentTooLargeException implements Exception {
  const AttachmentTooLargeException();
}

/// An encrypted file in Storage plus what is needed to decrypt it (D-52).
class ChatAttachment {
  const ChatAttachment({
    required this.path,
    required this.type,
    required this.size,
    required this.name,
    required this.senderId,
    required this.recipientId,
    required this.senderPublicKey,
    required this.recipientPublicKey,
  });

  final String path;
  final AttachmentType type;
  final int size;

  /// Decrypted file name; null when it could not be decrypted (earlier device).
  final String? name;
  final String senderId;
  final String recipientId;
  final String senderPublicKey;
  final String recipientPublicKey;

  // One file per storage path; lets providers cache by attachment.
  @override
  bool operator ==(Object other) => other is ChatAttachment && other.path == path;

  @override
  int get hashCode => path.hashCode;
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
    this.attachment,
  });

  /// D-52; the text is then an optional caption.
  final ChatAttachment? attachment;

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
    this.attachmentPath,
    this.attachmentType,
    this.attachmentSize,
    this.attachmentName,
  });

  /// D-52 (all null for a text message); [attachmentName] is encrypted.
  final String? attachmentPath;
  final AttachmentType? attachmentType;
  final int? attachmentSize;
  final String? attachmentName;

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
      attachmentPath: m['attachmentPath'] as String?,
      attachmentType: AttachmentType.fromValue(m['attachmentType']),
      attachmentSize: (m['attachmentSize'] as num?)?.toInt(),
      attachmentName: m['attachmentName'] as String?,
    );
  }
}

/// D-76: a Harvey AI note in the patient-doctor chat (agent_messages, kind "chat_alert").
/// Written by FastAPI when the patient's phone flags a message; both sides read it.
class AgentNote {
  const AgentNote({required this.id, required this.text, required this.sentAt});

  final String id;
  final String text;
  final DateTime sentAt;
}

/// D-76: true when the text contains a blood pressure in the crisis range (180/120 or
/// above), e.g. "my bp was 200/150" or "bp 190 over 100". Mirrors the server's check.
bool hasCrisisBp(String text) {
  final re = RegExp(r'\b(\d{2,3})\s*(?:/|over)\s*(\d{2,3})\b', caseSensitive: false);
  for (final m in re.allMatches(text)) {
    final sys = int.parse(m.group(1)!);
    final dia = int.parse(m.group(2)!);
    final plausible = sys >= 60 && sys <= 300 && dia >= 30 && dia <= 200 && sys > dia;
    if (plausible) return sys >= 180 || dia >= 120;
  }
  return false;
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
  /// D-76: with [aiReview] (the patient's side) a flagged message is also sent to the
  /// AI Health Agent, which posts a Harvey AI note in the chat and alerts the doctor.
  Future<bool> send({
    required String me,
    required Contact to,
    required String text,
    bool aiReview = false,
  });

  /// D-76: Harvey AI notes in this patient's chat with their doctor, oldest first.
  Stream<List<AgentNote>> chatAlerts(String patientId);

  /// UC10.3 E1: the doctor clears a false-positive flag.
  Future<void> clearFlag(String messageId);

  /// D-52: encrypt and upload a photo or PDF (needs a connection), then store the message.
  /// Throws [AttachmentTooLargeException] above 10 MB. Returns true when the caption was
  /// flagged by the keyword scan.
  Future<bool> sendAttachment({
    required String me,
    required Contact to,
    required Uint8List bytes,
    required String fileName,
    required AttachmentType type,
    String caption = '',
  });

  /// D-52: download and decrypt an attachment for [me].
  Future<Uint8List> openAttachment(String me, ChatAttachment attachment);
}

class FirestoreMessagingRepository implements MessagingRepository {
  FirestoreMessagingRepository(
    this._db,
    this._api,
    this._crypto,
    this._scanner, {
    FirebaseStorage? storage,
  }) : _storageOverride = storage;

  final FirebaseFirestore _db;
  final FirebaseStorage? _storageOverride;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  static const _filePurpose = '|file';
  static const _namePurpose = '|name';
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
  Stream<List<AgentNote>> chatAlerts(String patientId) => _db
      .collection(Collections.agentMessages)
      .where('patientId', isEqualTo: patientId)
      .where('kind', isEqualTo: 'chat_alert')
      .orderBy('sentAt')
      .limitToLast(50)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            AgentNote(
              id: d.id,
              text: d.data()['text'] as String? ?? '',
              sentAt: (d.data()['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            ),
        ],
      );

  @override
  Future<bool> send({
    required String me,
    required Contact to,
    required String text,
    bool aiReview = false,
  }) async {
    final key = to.publicKey;
    if (key == null) throw const RecipientNotReadyException();
    // D-76: a crisis-range blood pressure in the text also flags it.
    final flagged = (await _scanner).isHighRisk(text) || hasCrisisBp(text);
    final sealed = await _crypto.encrypt(
      text: text,
      senderId: me,
      recipientId: to.uid,
      recipientPublicKey: key,
    );
    final ref = _db.collection(Collections.messages).doc();
    // Not awaited: offline, the write is queued and shows at once (UC10.1 E1). Once the
    // server has it, FastAPI pushes the recipient (and escalates if flagged).
    Future<void> store() async {
      await ref.set({
        'senderId': me,
        'recipientId': to.uid,
        'encryptedText': sealed.encryptedText,
        'isFlagged': flagged,
        'sentAt': FieldValue.serverTimestamp(),
        'senderPublicKey': sealed.senderPublicKey,
        'recipientPublicKey': key,
      });
      await _api.notifyMessage(ref.id);
      // D-76: only this flagged message's text goes to the AI; others stay private.
      if (flagged && aiReview) await _api.aiReviewMessage(ref.id, text);
    }

    unawaited(store().catchError((Object _) {}));
    return flagged;
  }

  @override
  Future<void> clearFlag(String messageId) =>
      _db.collection(Collections.messages).doc(messageId).update({'isFlagged': false});

  @override
  Future<bool> sendAttachment({
    required String me,
    required Contact to,
    required Uint8List bytes,
    required String fileName,
    required AttachmentType type,
    String caption = '',
  }) async {
    final key = to.publicKey;
    if (key == null) throw const RecipientNotReadyException();
    if (bytes.length > maxAttachmentBytes) throw const AttachmentTooLargeException();
    final flagged = caption.trim().isNotEmpty && (await _scanner).isHighRisk(caption);
    final text = await _crypto.encrypt(
      text: caption.trim(),
      senderId: me,
      recipientId: to.uid,
      recipientPublicKey: key,
    );
    final file = await _crypto.encryptBytes(
      bytes: bytes,
      senderId: me,
      recipientId: to.uid,
      recipientPublicKey: key,
      purpose: _filePurpose,
    );
    final name = await _crypto.encryptBytes(
      bytes: utf8.encode(fileName),
      senderId: me,
      recipientId: to.uid,
      recipientPublicKey: key,
      purpose: _namePurpose,
    );
    final ref = _db.collection(Collections.messages).doc();
    final path = 'message_attachments/$me/${to.uid}/${ref.id}';
    // Opaque bytes: Storage never sees the file type or contents.
    await _storage
        .ref(path)
        .putData(file.bytes, SettableMetadata(contentType: 'application/octet-stream'));
    await ref.set({
      'senderId': me,
      'recipientId': to.uid,
      'encryptedText': text.encryptedText,
      'isFlagged': flagged,
      'sentAt': FieldValue.serverTimestamp(),
      'senderPublicKey': text.senderPublicKey,
      'recipientPublicKey': key,
      'attachmentPath': path,
      'attachmentType': type.value,
      'attachmentSize': bytes.length,
      'attachmentName': base64Encode(name.bytes),
    });
    unawaited(_api.notifyMessage(ref.id).catchError((Object _) {}));
    return flagged;
  }

  @override
  Future<Uint8List> openAttachment(String me, ChatAttachment a) async {
    final data = await _storage.ref(a.path).getData(maxAttachmentBytes + 1024);
    if (data == null) throw StateError('Attachment not found');
    return Uint8List.fromList(
      await _crypto.decryptBytes(
        me: me,
        senderId: a.senderId,
        recipientId: a.recipientId,
        bytes: data,
        senderPublicKey: a.senderPublicKey,
        recipientPublicKey: a.recipientPublicKey,
        purpose: _filePurpose,
      ),
    );
  }
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
  ChatAttachment? attachment;
  if (m.attachmentPath != null && m.attachmentType != null) {
    String? name;
    try {
      name = utf8.decode(
        await crypto.decryptBytes(
          me: me,
          senderId: m.senderId,
          recipientId: m.recipientId,
          bytes: base64Decode(m.attachmentName ?? ''),
          senderPublicKey: m.senderPublicKey,
          recipientPublicKey: m.recipientPublicKey,
          purpose: FirestoreMessagingRepository._namePurpose,
        ),
      );
    } catch (_) {
      name = null;
    }
    attachment = ChatAttachment(
      path: m.attachmentPath!,
      type: m.attachmentType!,
      size: m.attachmentSize ?? 0,
      name: name,
      senderId: m.senderId,
      recipientId: m.recipientId,
      senderPublicKey: m.senderPublicKey,
      recipientPublicKey: m.recipientPublicKey,
    );
  }
  return ChatMessage(
    id: m.id,
    fromMe: m.senderId == me,
    text: text,
    isFlagged: m.isFlagged,
    sentAt: m.sentAt,
    pending: m.pending,
    attachment: attachment,
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
