import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pointycastle/export.dart';

class LocalWalletCache {
  static const String _cacheKey = 'wallet_backup_encrypted';
  static const String _saltKey = 'wallet_cache_salt';
  static const String _metadataKey = 'wallet_cache_metadata';
  static const int version = 1;
  static const int _saltLength = 32;
  static const int _nonceLength = 12;
  static const int _macSizeBits = 128;
  static const int _iterations = 100000;

  /// Lower iterations for new caches so restore is faster; old caches still read with stored iterations.
  static const int _iterationsFast = 15000;
  static const int _keyLength = 32;

  final FlutterSecureStorage _storage;
  final DeviceInfoPlugin _deviceInfo;

  LocalWalletCache({
    FlutterSecureStorage? storage,
    DeviceInfoPlugin? deviceInfo,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  static Uint8List _secureBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  Future<String> _getDeviceId() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidInfo = await _deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown-ios-device';
    } else {
      return 'unknown-device';
    }
  }

  Future<String> _getDerivationKey(String? accountId) async {
    final deviceId = await _getDeviceId();
    final user = FirebaseAuth.instance.currentUser;
    final accountIdentifier = user?.uid ?? accountId ?? 'unknown-account';
    final derivationKey = '$deviceId:$accountIdentifier';
    return derivationKey;
  }

  Uint8List _deriveKey(String derivationKey, Uint8List salt, int iterations) {
    final kd = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyLength));
    return kd.process(Uint8List.fromList(utf8.encode(derivationKey)));
  }

  Future<void> cacheWallet(String mnemonic, String accountId) async {
    if (kDebugMode) {
      debugPrint('[LocalWalletCache] LocalWalletCache: cacheWallet start');
    }
    try {
      if (kDebugMode) {
        debugPrint('[LocalWalletCache] LocalWalletCache: getting derivation key...');
      }
      final derivationKey = await _getDerivationKey(accountId);
      final salt = _secureBytes(_saltLength);
      final nonce = _secureBytes(_nonceLength);
      if (kDebugMode) {
        debugPrint('[LocalWalletCache] LocalWalletCache: deriving key ($_iterationsFast iterations)...');
      }
      final key = _deriveKey(derivationKey, salt, _iterationsFast);

      final plainBytes = Uint8List.fromList(utf8.encode(mnemonic));
      final cipher = GCMBlockCipher(AESEngine())..init(
        true,
        AEADParameters(KeyParameter(key), _macSizeBits, nonce, Uint8List(0)),
      );
      final ciphertext = cipher.process(plainBytes);

      final encryptedData = jsonEncode({
        'version': version,
        'ciphertext': base64Encode(ciphertext),
        'salt': base64Encode(salt),
        'iv': base64Encode(nonce),
        'iterations': _iterationsFast,
      });
      await _storage.write(key: _cacheKey, value: encryptedData);
      await _storage.write(key: _saltKey, value: base64Encode(salt));

      final timestamp = DateTime.now().toIso8601String();
      final metadata = jsonEncode({
        'version': version,
        'timestamp': timestamp,
        'accountIdHash': _hashAccountId(accountId),
      });
      await _storage.write(key: _metadataKey, value: metadata);
      if (kDebugMode) {
        debugPrint('[LocalWalletCache] LocalWalletCache: wallet cached successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalWalletCache] LocalWalletCache: failed to cache wallet: $e');
      }
      rethrow;
    }
  }

  Future<String?> getCachedWallet(String accountId) async {
    if (kDebugMode) {
      debugPrint('[LocalWalletCache] LocalWalletCache: getCachedWallet start (accountId: ${accountId.length} chars)');
    }
    try {
      final encryptedData = await _storage.read(key: _cacheKey);
      if (encryptedData == null) {
        if (kDebugMode) {
          debugPrint('[LocalWalletCache] LocalWalletCache: cache miss (no data)');
        }
        return null;
      }
      if (kDebugMode) {
        debugPrint('[LocalWalletCache] LocalWalletCache: cache data found, checking metadata');
      }

      final metadataJson = await _storage.read(key: _metadataKey);
      if (metadataJson != null) {
        final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
        final cachedAccountHash = metadata['accountIdHash'] as String?;
        if (cachedAccountHash != null &&
            cachedAccountHash != _hashAccountId(accountId)) {
          if (kDebugMode) {
            debugPrint('[LocalWalletCache] LocalWalletCache: account mismatch, invalidating');
          }
          await clearCache();
          return null;
        }
      }

      if (kDebugMode) {
        debugPrint('[LocalWalletCache] LocalWalletCache: deriving key...');
      }
      final derivationKey = await _getDerivationKey(accountId);
      final map = jsonDecode(encryptedData) as Map<String, dynamic>;

      if ((map['version'] as int?) != version) {
        if (kDebugMode) {
          debugPrint('[LocalWalletCache] LocalWalletCache: version mismatch');
        }
        await clearCache();
        return null;
      }

      final salt = Uint8List.fromList(base64Decode(map['salt'] as String));
      final nonce = Uint8List.fromList(base64Decode(map['iv'] as String));
      final ciphertext = Uint8List.fromList(
        base64Decode(map['ciphertext'] as String),
      );
      final iterations = map['iterations'] as int? ?? _iterations;
      if (kDebugMode) {
        debugPrint('[LocalWalletCache] LocalWalletCache: decrypting (iterations: $iterations)...');
      }

      final key = _deriveKey(derivationKey, salt, iterations);
      final cipher = GCMBlockCipher(AESEngine())..init(
        false,
        AEADParameters(KeyParameter(key), _macSizeBits, nonce, Uint8List(0)),
      );

      String mnemonic;
      try {
        final plainBytes = cipher.process(ciphertext);
        mnemonic = utf8.decode(plainBytes);
      } on InvalidCipherTextException {
        if (kDebugMode) {
          debugPrint('[LocalWalletCache] LocalWalletCache: decryption failed, invalidating');
        }
        await clearCache();
        return null;
      }

      if (kDebugMode) {
        debugPrint('[LocalWalletCache] LocalWalletCache: cache hit, mnemonic restored');
      }
      // Migrate old high-iteration cache to fast iterations so next restore is quicker (non-blocking).
      if (iterations > _iterationsFast) {
        if (kDebugMode) {
          debugPrint(
            'LocalWalletCache: migration started (iterations $iterations > $_iterationsFast, rewriting in background)',
          );
        }
        cacheWallet(mnemonic, accountId).then((_) {
          if (kDebugMode) {
            debugPrint('[LocalWalletCache] LocalWalletCache: migration completed successfully');
          }
        }).catchError((e) {
          if (kDebugMode) {
            debugPrint(
              'LocalWalletCache: migration write failed (non-fatal): $e',
            );
          }
        });
      } else {
        if (kDebugMode) {
          debugPrint('[LocalWalletCache] LocalWalletCache: no migration needed (already fast iterations)');
        }
      }
      return mnemonic;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalWalletCache] LocalWalletCache: error retrieving cached wallet: $e');
      }
      await clearCache();
      return null;
    }
  }

  Future<void> clearCache() async {
    await _storage.delete(key: _cacheKey);
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _metadataKey);
    if (kDebugMode) {
      debugPrint('[LocalWalletCache] LocalWalletCache: cache cleared');
    }
  }

  Future<bool> hasCachedWallet() async {
    final encryptedData = await _storage.read(key: _cacheKey);
    return encryptedData != null;
  }

  String _hashAccountId(String accountId) {
    return accountId.hashCode.toString();
  }
}
