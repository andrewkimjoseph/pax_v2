import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class WalletEncryption {
  static const int version = 1;
  static const int _saltLength = 32;
  static const int _nonceLength = 12;
  static const int _macSizeBits = 128;
  static const int _defaultIterations = 100000;
  static const int _fastIterations = 20000;
  static const int _keyLength = 32;

  static Uint8List _secureBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  String encrypt(String plaintext, String participantId) {
    if (kDebugMode) debugPrint('WalletEncryption: encrypting backup');
    const iterations = _fastIterations;
    final salt = _secureBytes(_saltLength);
    final nonce = _secureBytes(_nonceLength);
    final key = _deriveKey(participantId, salt, iterations);
    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final cipher = GCMBlockCipher(AESEngine())..init(
      true,
      AEADParameters(KeyParameter(key), _macSizeBits, nonce, Uint8List(0)),
    );
    final ciphertext = cipher.process(plainBytes);
    return jsonEncode({
      'version': version,
      'ciphertext': base64Encode(ciphertext),
      'salt': base64Encode(salt),
      'iv': base64Encode(nonce),
      'iterations': iterations,
    });
  }

  String decrypt(String encryptedJson, String participantId) {
    if (kDebugMode) {
      debugPrint('WalletEncryption: decrypting backup');
    }
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if ((map['version'] as int?) != version) {
      throw ArgumentError('Unsupported backup format version');
    }
    final salt = base64Decode(map['salt'] as String);
    final nonce = base64Decode(map['iv'] as String);
    final ciphertext = base64Decode(map['ciphertext'] as String);
    final iterations = map['iterations'] as int? ?? _defaultIterations;
    final key = _deriveKey(participantId, salt, iterations);
    final cipher = GCMBlockCipher(AESEngine())..init(
      false,
      AEADParameters(KeyParameter(key), _macSizeBits, nonce, Uint8List(0)),
    );
    try {
      final plainBytes = cipher.process(ciphertext);
      return utf8.decode(plainBytes);
    } on InvalidCipherTextException catch (e) {
      if (kDebugMode) {
        debugPrint('WalletEncryption: decrypt failed (GCM auth): ${e.message}');
      }
      throw ArgumentError(
        'Decryption failed. The backup may be from a different Google account or the file may be corrupted.',
      );
    }
  }

  Uint8List _deriveKey(String participantId, Uint8List salt, int iterations) {
    final kd = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyLength));
    return kd.process(Uint8List.fromList(utf8.encode(participantId)));
  }
}
