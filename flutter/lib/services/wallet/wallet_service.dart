import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wallet/wallet.dart';
import 'package:web3dart/web3dart.dart';

class WalletService {
  WalletService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _mnemonicKey = 'wallet_mnemonic';
  final FlutterSecureStorage _storage;
  static const String _ethPath = "m/44'/60'/0'/0/0";

  Future<WalletResult> createWallet() async {
    if (kDebugMode) debugPrint('WalletService: creating new wallet');
    final mnemonic = generateMnemonic(strength: 128);
    final seed = mnemonicToSeed(mnemonic);
    final root = ExtendedPrivateKey.master(seed, xprv);
    final extended = root.forPath(_ethPath) as ExtendedPrivateKey;
    final privateKeyHex = _bigIntToHex32(extended.key);
    final credentials = EthPrivateKey.fromHex(privateKeyHex);
    final phrase = mnemonic.join(' ');
    await _storage.write(key: _mnemonicKey, value: phrase);
    if (kDebugMode) {
      debugPrint('WalletService: wallet created');
    }
    return WalletResult(credentials: credentials, mnemonic: phrase);
  }

  Future<Credentials> restoreFromMnemonic(
    String mnemonicPhrase, {
    bool saveToStorage = false,
  }) async {
    if (kDebugMode) {
      debugPrint('WalletService: restoring from mnemonic');
    }
    final words = mnemonicPhrase.trim().split(RegExp(r'\s+'));
    if (!validateMnemonic(words)) {
      throw ArgumentError('Invalid mnemonic phrase');
    }
    final seed = mnemonicToSeed(words);
    final root = ExtendedPrivateKey.master(seed, xprv);
    final extended = root.forPath(_ethPath) as ExtendedPrivateKey;
    final privateKeyHex = _bigIntToHex32(extended.key);
    final credentials = EthPrivateKey.fromHex(privateKeyHex);
    if (saveToStorage) {
      await _storage.write(key: _mnemonicKey, value: mnemonicPhrase.trim());
    }
    if (kDebugMode) {
      debugPrint('WalletService: wallet restored');
    }
    return credentials;
  }

  Future<String?> getStoredMnemonic() async {
    return _storage.read(key: _mnemonicKey);
  }

  String _bigIntToHex32(BigInt value) {
    final hex = value.toRadixString(16);
    final padded = hex.padLeft(64, '0');
    if (padded.length > 64) {
      return padded.substring(padded.length - 64);
    }
    return padded;
  }
}

class WalletResult {
  const WalletResult({required this.credentials, required this.mnemonic});
  final Credentials credentials;
  final String mnemonic;
}
