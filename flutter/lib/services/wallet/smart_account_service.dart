import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:web3dart/web3dart.dart';
import 'package:pax/services/wallet/key_encryption_service.dart';

class SmartAccountService {
  final FirebaseFunctions _functions;
  final KeyEncryptionService _keyEncryption;

  SmartAccountService({
    FirebaseFunctions? functions,
    KeyEncryptionService? keyEncryption,
  }) : _functions = functions ?? FirebaseFunctions.instance,
       _keyEncryption = keyEncryption ?? KeyEncryptionService();

  Future<String> createSmartAccount({
    required Credentials credentials,
    required String sessionKey,
  }) async {
    try {
      if (kDebugMode) debugPrint('[SmartAccountService] SmartAccountService: Creating smart account');

      final privateKeyHex = _extractPrivateKeyHex(credentials);

      final testCredentials = EthPrivateKey.fromHex(privateKeyHex);
      final derivedAddress = testCredentials.address.with0x;
      final providedAddress = credentials.address.with0x;

      if (derivedAddress.toLowerCase() != providedAddress.toLowerCase()) {
        throw Exception(
          'Private key does not match address! '
          'Derived: $derivedAddress, Provided: $providedAddress',
        );
      }

      final eoaAddress = providedAddress;

      final encryptedPrivateKey = _keyEncryption.encryptPrivateKey(
        privateKeyHex,
        sessionKey,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception(
          'Firebase Auth user is not authenticated. '
          'Please sign in before creating a smart account.',
        );
      }

      final refreshedToken = await user.getIdToken(true);
      if (refreshedToken == null) {
        throw Exception('Failed to get Firebase Auth token');
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Firebase Auth user became null');
      }

      final callable = _functions.httpsCallable(
        'createSmartAccountForPaxV2User',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      final result = await callable.call({
        'encryptedPrivateKey': encryptedPrivateKey,
        'eoWalletAddress': eoaAddress,
        'sessionKey': sessionKey,
      });

      final data = result.data as Map<String, dynamic>;
      final smartAccountAddress = data['smartAccountAddress'] as String;

      if (kDebugMode) {
        debugPrint(
          'SmartAccountService: Smart account created: $smartAccountAddress',
        );
      }

      return smartAccountAddress;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SmartAccountService] SmartAccountService: Error creating smart account: $e');
      }
      rethrow;
    }
  }

  String _extractPrivateKeyHex(Credentials credentials) {
    if (credentials is EthPrivateKey) {
      final privateKeyBytes = credentials.privateKey;
      final hex = bytesToHex(privateKeyBytes, include0x: false);
      if (hex.length > 64) {
        return hex.substring(hex.length - 64);
      }
      return hex.padLeft(64, '0');
    }
    throw ArgumentError(
      'Unsupported credentials type. Expected EthPrivateKey.',
    );
  }

  /// Builds the encrypted key params for V2 cloud function calls (screening, reward, withdraw).
  /// [sessionKey] should be the Firebase Auth ID token from [user.getIdToken(true)].
  Map<String, String> getV2EncryptedParamsForBackend({
    required Credentials credentials,
    required String sessionKey,
  }) {
    final privateKeyHex = _extractPrivateKeyHex(credentials);
    final encryptedPrivateKey = _keyEncryption.encryptPrivateKey(
      privateKeyHex,
      sessionKey,
    );
    final eoWalletAddress = credentials.address.with0x;
    return {
      'encryptedPrivateKey': encryptedPrivateKey,
      'sessionKey': sessionKey,
      'eoWalletAddress': eoWalletAddress,
    };
  }
}
