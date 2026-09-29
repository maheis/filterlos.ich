import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

abstract interface class JournalStore {
  Future<Map<String, dynamic>> loadState();
  Future<void> saveState(Map<String, dynamic> state);
  Future<bool> get hasPin;
  Future<void> setPin(String pin);
  Future<bool> verifyPin(String pin);
}

class PlatformSecretStore implements SecretStore {
  PlatformSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class EncryptedJournalStore implements JournalStore {
  EncryptedJournalStore({SecretStore? secrets, this.supportDirectory})
    : _secrets = secrets ?? PlatformSecretStore();

  static const _masterKeyStorageKey = 'filterlos.masterKey.v1';
  static const _pinSaltStorageKey = 'filterlos.timelinePinSalt.v1';
  static const _pinHashStorageKey = 'filterlos.timelinePinHash.v1';
  static const _pinIterations = 160000;
  static const _backupIterations = 200000;

  final SecretStore _secrets;
  final Directory? supportDirectory;
  final AesGcm _cipher = AesGcm.with256bits();
  late File _databaseFile;
  late SecretKey _masterKey;

  Future<void> initialize() async {
    final root = supportDirectory ?? await getApplicationSupportDirectory();
    final appDirectory = Directory(p.join(root.path, 'filterlos.ich'));
    await appDirectory.create(recursive: true);
    _databaseFile = File(p.join(appDirectory.path, 'journal.enc'));

    final storedKey = await _secrets.read(_masterKeyStorageKey);
    if (storedKey == null) {
      _masterKey = await _cipher.newSecretKey();
      await _secrets.write(
        _masterKeyStorageKey,
        base64Encode(await _masterKey.extractBytes()),
      );
    } else {
      final keyBytes = base64Decode(storedKey);
      if (keyBytes.length != 32) {
        throw const FormatException('Invalid local encryption key.');
      }
      _masterKey = SecretKey(keyBytes);
    }
  }

  Future<void> clearLocalData() async {
    if (await _databaseFile.exists()) await _databaseFile.delete();
    await _secrets.delete(_masterKeyStorageKey);
    await _secrets.delete(_pinSaltStorageKey);
    await _secrets.delete(_pinHashStorageKey);
  }

  Future<String> createPasswordBackup(String password) async {
    _validateBackupPassword(password);
    final salt = List<int>.generate(
      16,
      (_) => math.Random.secure().nextInt(256),
    );
    final key = await _deriveBackupKey(password, salt);
    final secretBox = await _cipher.encrypt(
      utf8.encode(jsonEncode(await loadState())),
      secretKey: key,
    );
    return jsonEncode({
      'format': 'filterlos.ich.backup',
      'version': 1,
      'iterations': _backupIterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  Future<void> restorePasswordBackup(String backup, String password) async {
    _validateBackupPassword(password);
    final envelope = jsonDecode(backup);
    if (envelope is! Map ||
        envelope['format'] != 'filterlos.ich.backup' ||
        envelope['version'] != 1 ||
        envelope['iterations'] != _backupIterations) {
      throw const FormatException('Unbekanntes Backup-Format.');
    }
    try {
      final salt = base64Decode(envelope['salt'] as String);
      final key = await _deriveBackupKey(password, salt);
      final secretBox = SecretBox(
        base64Decode(envelope['cipherText'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        mac: Mac(base64Decode(envelope['mac'] as String)),
      );
      final clearText = await _cipher.decrypt(secretBox, secretKey: key);
      final state = jsonDecode(utf8.decode(clearText));
      if (state is! Map<String, dynamic>) {
        throw const FormatException(
          'Das Backup enthält keinen gültigen Store.',
        );
      }
      await saveState(state);
    } on FormatException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Masterpasswort falsch oder Backup beschädigt.',
      );
    } catch (_) {
      throw const FormatException(
        'Masterpasswort falsch oder Backup beschädigt.',
      );
    }
  }

  Future<SecretKey> _deriveBackupKey(String password, List<int> salt) {
    final algorithm = Pbkdf2.hmacSha256(
      iterations: _backupIterations,
      bits: 256,
    );
    return algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  void _validateBackupPassword(String password) {
    if (password.trim().length < 8) {
      throw ArgumentError(
        'Das Masterpasswort muss mindestens 8 Zeichen haben.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> loadState() async {
    if (!await _databaseFile.exists()) {
      return <String, dynamic>{'entries': <dynamic>[], 'settings': null};
    }

    final envelope = jsonDecode(await _databaseFile.readAsString());
    if (envelope is! Map<String, dynamic> || envelope['version'] != 1) {
      throw const FormatException('Unsupported encrypted journal format.');
    }
    final secretBox = SecretBox(
      base64Decode(envelope['cipherText'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    );
    final clearText = await _cipher.decrypt(secretBox, secretKey: _masterKey);
    final decoded = jsonDecode(utf8.decode(clearText));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid journal payload.');
    }
    return decoded;
  }

  @override
  Future<void> saveState(Map<String, dynamic> state) async {
    final secretBox = await _cipher.encrypt(
      utf8.encode(jsonEncode(state)),
      secretKey: _masterKey,
    );
    final envelope = jsonEncode({
      'version': 1,
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
    final tempFile = File('${_databaseFile.path}.tmp');
    await tempFile.writeAsString(envelope, flush: true);
    await tempFile.rename(_databaseFile.path);
  }

  @override
  Future<bool> get hasPin async =>
      await _secrets.read(_pinSaltStorageKey) != null &&
      await _secrets.read(_pinHashStorageKey) != null;

  @override
  Future<void> setPin(String pin) async {
    if (pin.length < 6 || !RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('Die PIN muss mindestens 6 Ziffern enthalten.');
    }
    final random = math.Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await _derivePinHash(pin, salt);
    await _secrets.write(_pinSaltStorageKey, base64Encode(salt));
    await _secrets.write(_pinHashStorageKey, base64Encode(hash));
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final saltValue = await _secrets.read(_pinSaltStorageKey);
    final hashValue = await _secrets.read(_pinHashStorageKey);
    if (saltValue == null || hashValue == null) return false;
    final salt = base64Decode(saltValue);
    final expected = base64Decode(hashValue);
    final actual = await _derivePinHash(pin, salt);
    return _constantTimeEquals(actual, expected);
  }

  Future<List<int>> _derivePinHash(String pin, List<int> salt) async {
    final algorithm = Pbkdf2.hmacSha256(iterations: _pinIterations, bits: 256);
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
