/// Human-friendly labels for wallet transactions (Etherscan-style tx maps).
/// Use for UI only; never exposes raw function names or technical jargon.
library;

import 'package:flutter/material.dart' show IconData;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class TransactionLabelUtil {
  TransactionLabelUtil._();

  /// Keys used in the tx map (Etherscan txlist result).
  static const String _kFrom = 'from';
  static const String _kTo = 'to';
  static const String _kValue = 'value';
  static const String _kFunctionName = 'functionName';

  /// Known function name substrings (lowercased) mapped to a friendly label.
  static bool _matchesAny(String fn, Iterable<String> keys) {
    for (final k in keys) {
      if (fn.contains(k)) return true;
    }
    return false;
  }

  static const _approveKeys = [
    'approve',
    'increaseallowance',
    'decreaseallowance',
  ];
  static const _swapKeys = [
    'swap',
    'swapexact',
    'multihop',
    'exactinput',
    'exactoutput',
  ];

  /// Returns a friendly label: "Approved", "Swapped", "Sent", "Received", or
  /// "Transaction" only when direction cannot be determined.
  ///
  /// [tx] is the raw transaction map (e.g. from Etherscan txlist).
  /// [myAddress] is the current user's wallet address (EOA). Case-insensitive.
  static String getLabel(Map<String, dynamic> tx, String? myAddress) {
    final from = _norm(tx[_kFrom]?.toString());
    final to = _norm(tx[_kTo]?.toString());
    final valueWei = tx[_kValue]?.toString();
    final hasValue =
        valueWei != null &&
        valueWei != '0' &&
        (BigInt.tryParse(valueWei) ?? BigInt.zero) > BigInt.zero;
    final me = _norm(myAddress);

    // 1. Approved / Swapped when we recognize the function (keep these).
    final functionName = tx[_kFunctionName]?.toString().trim();
    if (functionName != null && functionName.isNotEmpty) {
      final fn =
          functionName.toLowerCase().replaceAll(' ', '').split('(').first;
      if (_matchesAny(fn, _approveKeys)) return 'Approved';
      if (_matchesAny(fn, _swapKeys)) return 'Swapped';
    }

    // 2. Sent / Received whenever we can tell direction (no "Transaction" here).
    if (me.isNotEmpty && from.isNotEmpty && to.isNotEmpty) {
      final fromMe = from == me;
      final toMe = to == me;
      if (fromMe && !toMe) return 'Sent';
      if (toMe && !fromMe) return 'Received';
    }

    if (me.isNotEmpty && hasValue) {
      final fromMe = from == me;
      final toMe = to == me;
      if (fromMe && !toMe) return 'Sent';
      if (toMe && !fromMe) return 'Received';
    }

    // 3. Only use "Transaction" when we truly can't determine anything.
    return 'Transaction';
  }

  /// Icon for the given label (e.g. for use on transaction cards).
  static IconData getIconForLabel(String label) {
    switch (label) {
      case 'Sent':
        return FontAwesomeIcons.circleArrowUp;
      case 'Received':
        return FontAwesomeIcons.circleArrowDown;
      case 'Swapped':
        return FontAwesomeIcons.retweet;
      case 'Approved':
        return FontAwesomeIcons.circleCheck;
      default:
        return FontAwesomeIcons.receipt;
    }
  }

  static String _norm(String? s) => (s ?? '').toLowerCase().trim();
}
