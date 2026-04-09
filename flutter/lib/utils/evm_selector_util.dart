import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/keccak.dart';

class EvmSelectorUtil {
  EvmSelectorUtil._();

  /// Computes the 4-byte ABI selector for a function signature.
  /// Example: isWalletLogged(address) -> 0x91cb5ac8
  static String computeSelector(String signature) {
    final normalized = signature.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Function signature cannot be empty.');
    }

    final digest = KeccakDigest(256);
    final hash = digest.process(Uint8List.fromList(utf8.encode(normalized)));
    final selectorHex = _bytesToHex(hash).substring(0, 8);
    return '0x$selectorHex';
  }

  /// Returns true if [selector] matches the [signature] selector.
  static bool verifySelector({
    required String signature,
    required String selector,
  }) {
    final normalizedSelector = _normalizeSelector(selector);
    if (normalizedSelector == null) return false;
    return computeSelector(signature) == normalizedSelector;
  }

  static String? _normalizeSelector(String selector) {
    final trimmed = selector.trim().toLowerCase();
    final withPrefix =
        trimmed.startsWith('0x') ? trimmed : '0x$trimmed';
    final body = withPrefix.substring(2);
    final validHex = RegExp(r'^[0-9a-f]{8}$');
    if (!validHex.hasMatch(body)) {
      return null;
    }
    return withPrefix;
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
