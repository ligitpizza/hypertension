import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/messaging/data/message_crypto.dart';

// NFR-2.1 end-to-end encryption (docs/06 section I; D-42).

/// Separate in-memory vault per "device".
class MemoryKeyVault implements KeyVault {
  final _pairs = <String, SimpleKeyPair>{};

  @override
  Future<SimpleKeyPair> keyPair(String uid) async => _pairs[uid] ??= await X25519().newKeyPair();

  void forget(String uid) => _pairs.remove(uid);
}

void main() {
  late MemoryKeyVault patientPhone;
  late MemoryKeyVault doctorBrowser;
  late MessageCrypto patient;
  late MessageCrypto doctor;

  setUp(() {
    patientPhone = MemoryKeyVault();
    doctorBrowser = MemoryKeyVault();
    patient = MessageCrypto(patientPhone);
    doctor = MessageCrypto(doctorBrowser);
  });

  Future<Map<String, String>> send(String text) async {
    final doctorKey = await doctor.publicKey('d1');
    final out = await patient.encrypt(
      text: text,
      senderId: 'p1',
      recipientId: 'd1',
      recipientPublicKey: doctorKey,
    );
    return {
      'encryptedText': out.encryptedText,
      'senderPublicKey': out.senderPublicKey,
      'recipientPublicKey': doctorKey,
    };
  }

  Future<String> read(MessageCrypto who, String me, Map<String, String> m) => who.decrypt(
    me: me,
    senderId: 'p1',
    recipientId: 'd1',
    encryptedText: m['encryptedText']!,
    senderPublicKey: m['senderPublicKey']!,
    recipientPublicKey: m['recipientPublicKey']!,
  );

  test('the stored text is unreadable; both ends can decrypt it', () async {
    final m = await send('My BP was 158/95 this morning');
    expect(
      utf8.decode(base64Decode(m['encryptedText']!), allowMalformed: true),
      isNot(contains('158')),
    );
    expect(await read(doctor, 'd1', m), 'My BP was 158/95 this morning');
    expect(await read(patient, 'p1', m), 'My BP was 158/95 this morning'); // sender's own copy
  });

  test('each message gets a fresh nonce', () async {
    final a = await send('same text');
    final b = await send('same text');
    expect(a['encryptedText'], isNot(b['encryptedText']));
  });

  test('D-42 a key lost on reinstall gives the earlier-device notice', () async {
    final m = await send('hello');
    doctorBrowser.forget('d1'); // browser storage cleared: a new key is created
    expect(() => read(doctor, 'd1', m), throwsA(isA<EarlierDeviceException>()));
  });

  test('a tampered message is rejected', () async {
    final m = await send('hello');
    final bytes = base64Decode(m['encryptedText']!)..[20] ^= 1;
    final tampered = {...m, 'encryptedText': base64Encode(bytes)};
    expect(() => read(doctor, 'd1', tampered), throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('a third party with its own key cannot read it', () async {
    final m = await send('private');
    final intruder = MessageCrypto(MemoryKeyVault());
    expect(() => read(intruder, 'd1', m), throwsA(isA<EarlierDeviceException>()));
  });
}
