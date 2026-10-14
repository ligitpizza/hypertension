import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/messaging/data/message_crypto.dart';

// NFR-2.1 / D-42 key vault: one key pair per user, even when asked for at the same time
// (key publishing and the inbox both ask at start-up), and recovery from an unreadable key.

class MemoryStore implements SecretStore {
  final values = <String, String>{};
  int writes = 0;
  Object? readError;
  bool failWrites = false;

  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(Duration.zero); // let concurrent callers interleave
    if (readError != null) throw readError!;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    await Future<void>.delayed(Duration.zero);
    if (failWrites) throw StateError('storage unavailable');
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

Future<String> publicKeyOf(SecureStorageKeyVault v, String uid) async =>
    (await (await v.keyPair(uid)).extractPublicKey()).bytes.join(',');

void main() {
  setUp(SecureStorageKeyVault.resetForTest);

  test('simultaneous first use creates one key pair, stored once', () async {
    final store = MemoryStore();
    final a = SecureStorageKeyVault(store);
    final b = SecureStorageKeyVault(store); // another provider instance
    final keys = await Future.wait([
      publicKeyOf(a, 'u1'),
      publicKeyOf(b, 'u1'),
      publicKeyOf(a, 'u1'),
    ]);
    expect(keys.toSet(), hasLength(1));
    expect(store.writes, 1);
  });

  test('the stored key is reused after a restart', () async {
    final store = MemoryStore();
    final first = await publicKeyOf(SecureStorageKeyVault(store), 'u1');
    SecureStorageKeyVault.resetForTest(); // app restart
    expect(await publicKeyOf(SecureStorageKeyVault(store), 'u1'), first);
  });

  test('different users get different keys', () async {
    final v = SecureStorageKeyVault(MemoryStore());
    expect(await publicKeyOf(v, 'patient'), isNot(await publicKeyOf(v, 'doctor')));
  });

  test('an unreadable saved key is replaced instead of failing for ever', () async {
    final store = MemoryStore()
      ..values['careflow_x25519_u1'] = 'old'
      ..readError = StateError('OperationError');
    final key = await publicKeyOf(SecureStorageKeyVault(store), 'u1');
    expect(key, isNotEmpty);
    expect(store.values['careflow_x25519_u1'], isNot('old'));
  });

  test('a corrupt saved value is replaced', () async {
    final store = MemoryStore()..values['careflow_x25519_u1'] = '%%%not-base64%%%';
    expect(await publicKeyOf(SecureStorageKeyVault(store), 'u1'), isNotEmpty);
    expect(store.writes, 1);
  });

  test('a failed load can be retried', () async {
    final store = MemoryStore()..failWrites = true;
    final v = SecureStorageKeyVault(store);
    await expectLater(v.keyPair('u1'), throwsStateError);
    store.failWrites = false;
    expect(await publicKeyOf(v, 'u1'), isNotEmpty);
  });
}
