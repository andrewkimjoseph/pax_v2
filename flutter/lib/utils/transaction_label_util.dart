/// Human-friendly labels for wallet transactions (Etherscan-style tx maps).
/// Use for UI only; only shows Sent / Received (or "Transaction" when unknown).
library;

import 'package:flutter/material.dart' show IconData;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class TransactionLabelUtil {
  TransactionLabelUtil._();

  /// Keys used in the tx map (Etherscan txlist result).
  static const String _kFrom = 'from';
  static const String _kTo = 'to';
  static const String _kValue = 'value';

  /// Returns a friendly label: "Sent", "Received", or "Transaction" only when
  /// direction cannot be determined. Does not use functionName (e.g. no "Swapped").
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

    // Sent / Received whenever we can tell direction.
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

    // Only use "Transaction" when we truly can't determine direction.
    return 'Transaction';
  }

  /// Icon for the given label (e.g. for use on transaction cards).
  static IconData getIconForLabel(String label) {
    switch (label) {
      case 'Sent':
        return FontAwesomeIcons.circleArrowUp;
      case 'Received':
        return FontAwesomeIcons.circleArrowDown;
      default:
        return FontAwesomeIcons.receipt;
    }
  }

  static String _norm(String? s) => (s ?? '').toLowerCase().trim();
}
