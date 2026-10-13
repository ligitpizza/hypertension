import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// NFR-2.1 end-to-end message encryption (docs/06 section I; D-42).
///
/// Each user has an X25519 key pair; the private key never leaves the device (Android
/// Keystore / browser storage via flutter_secure_storage); the public key is published on
/// `users/{uid}.publicKey`. A conversation key = X25519 shared secret -> HKDF-SHA256 ->
/// AES-256-GCM. `encryptedText` = base64(nonce | ciphertext | tag).

/// The message was encrypted for a key this device no longer has (reinstall, new phone,
/// cleared browser). Accepted PoC limitation (D-42).
class EarlierDeviceException implements Exception {
  const EarlierDeviceException();
}

/// Holds the user's key pair. Per user id, so a shared phone keeps keys apart.
abstract interface class KeyVault {
  /// The user's key pair, created and stored on first use.
  Future<SimpleKeyPair> keyPair(String uid);
}

class SecureStorageKeyVault implements KeyVault {
  SecureStorageKeyVault([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final _algorithm = X25519();

  @override
  Future<SimpleKeyPair> keyPair(String uid) async {
    final storageKey = 'careflow_x25519_$uid';
    final saved = await _storage.read(key: storageKey);
    if (saved != null) {
      return _algorithm.newKeyPairFromSeed(base64Decode(saved));
    }
    final pair = await _algorithm.newKeyPair();
    await _storage.write(key: storageKey, value: base64Encode(await pair.extractPrivateKeyBytes()));
    return pair;
  }
}

class MessageCrypto {
  MessageCrypto(this._vault);

  final KeyVault _vault;
  final _x25519 = X25519();
  final _aes = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static const _info = 'careflow-chat-v1';

  /// The base64 public key to publish on `users/{uid}.publicKey`.
  Future<String> publicKey(String uid) async {
    final pair = await _vault.keyPair(uid);
    return base64Encode((await pair.extractPublicKey()).bytes);
  }

  Future<SecretKey> _conversationKey(
    SimpleKeyPair mine,
    String otherPublicKey,
    String userA,
    String userB,
  ) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(base64Decode(otherPublicKey), type: KeyPairType.x25519),
    );
    // Salt binds the key to this pair of users, in a stable order.
    final pair = ([userA, userB]..sort()).join('|');
    return _hkdf.deriveKey(secretKey: shared, nonce: utf8.encode(pair), info: utf8.encode(_info));
  }

  /// Encrypts [text] from [senderId] to [recipientId]. Returns the stored fields.
  Future<({String encryptedText, String senderPublicKey})> encrypt({
    required String text,
    required String senderId,
    required String recipientId,
    required String recipientPublicKey,
  }) async {
    final mine = await _vault.keyPair(senderId);
    final key = await _conversationKey(mine, recipientPublicKey, senderId, recipientId);
    final box = await _aes.encrypt(
      utf8.encode(text),
      secretKey: key,
      aad: utf8.encode('$senderId>$recipientId'),
    );
    final packed = Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
    return (encryptedText: base64Encode(packed), senderPublicKey: await publicKey(senderId));
  }

  /// Decrypts a stored message for [me] (sender or recipient). Throws
  /// [EarlierDeviceException] if it was encrypted for a key this device no longer holds.
  Future<String> decrypt({
    required String me,
    required String senderId,
    required String recipientId,
    required String encryptedText,
    required String senderPublicKey,
    required String recipientPublicKey,
  }) async {
    final mine = await _vault.keyPair(me);
    final myPublic = base64Encode((await mine.extractPublicKey()).bytes);
    final iAmSender = me == senderId;
    if (myPublic != (iAmSender ? senderPublicKey : recipientPublicKey)) {
      throw const EarlierDeviceException();
    }
    final other = iAmSender ? recipientPublicKey : senderPublicKey;
    final key = await _conversationKey(mine, other, senderId, recipientId);
    final bytes = base64Decode(encryptedText);
    final nonceLength = _aes.nonceLength;
    final box = SecretBox(
      bytes.sublist(nonceLength, bytes.length - 16),
      nonce: bytes.sublist(0, nonceLength),
      mac: Mac(bytes.sublist(bytes.length - 16)),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode('$senderId>$recipientId'),
    );
    return utf8.decode(clear);
  }
}
