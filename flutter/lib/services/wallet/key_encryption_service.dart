import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class KeyEncryptionService {
  static const int version = 1;
  static const int _saltLength = 32;
  static const int _nonceLength = 12;
  static const int _macSizeBits = 128;
  static const int _sessionIterations = 20000;
  static const int _keyLength = 32;

  static Uint8List _secureBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  String encryptPrivateKey(String privateKeyHex, String sessionKey) {
    if (kDebugMode) debugPrint('KeyEncryptionService: encrypting private key');
    final normalizedKey = privateKeyHex.startsWith('0x')
        ? privateKeyHex.substring(2)
        : privateKeyHex;

    const iterations = _sessionIterations;
    final salt = _secureBytes(_saltLength);
    final nonce = _secureBytes(_nonceLength);
    final key = _deriveKey(sessionKey, salt, iterations);
    final plainBytes = Uint8List.fromList(utf8.encode(normalizedKey));

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

  String decryptPrivateKey(String encryptedJson, String sessionKey) {
    if (kDebugMode) {
      debugPrint('KeyEncryptionService: decrypting private key');
    }
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if ((map['version'] as int?) != version) {
      throw ArgumentError('Unsupported encryption format version');
    }

    final salt = base64Decode(map['salt'] as String);
    final nonce = base64Decode(map['iv'] as String);
    final ciphertext = base64Decode(map['ciphertext'] as String);
    final iterations = map['iterations'] as int? ?? _sessionIterations;
    final key = _deriveKey(sessionKey, salt, iterations);

    final cipher = GCMBlockCipher(AESEngine())..init(
      false,
      AEADParameters(KeyParameter(key), _macSizeBits, nonce, Uint8List(0)),
    );

    try {
      final plainBytes = cipher.process(ciphertext);
      return utf8.decode(plainBytes);
    } on InvalidCipherTextException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'KeyEncryptionService: decrypt failed (GCM auth): ${e.message}',
        );
      }
      throw ArgumentError(
        'Decryption failed. The encrypted key may be from a different session or corrupted.',
      );
    }
  }

  Uint8List _deriveKey(String sessionKey, Uint8List salt, int iterations) {
    final kd = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyLength));
    return kd.process(Uint8List.fromList(utf8.encode(sessionKey)));
  }
}
