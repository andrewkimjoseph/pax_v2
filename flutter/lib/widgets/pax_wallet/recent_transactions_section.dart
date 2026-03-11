import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pax/providers/local/wallet_transactions_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/currency_symbol.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:pax/utils/transaction_label_util.dart';
import 'package:pax/utils/url_handler.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const String celoscanTxUrl = 'https://celoscan.io/tx/';

/// Scrollable recent-transactions body. Watches [walletTransactionsProvider].
/// Header "Recent transactions" + refresh is in the parent [PaxWalletView].
class RecentTransactionsContent extends ConsumerWidget {
  const RecentTransactionsContent({super.key, required this.eoAddress});

  final String eoAddress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txState = ref.watch(walletTransactionsProvider);

    if (txState.errorMessage != null && txState.transactions.isNotEmpty) {
      return Text(
        "Couldn't refresh",
        style: TextStyle(fontSize: 12, color: PaxColors.red),
      ).withPadding(top: 4, bottom: 8);
    }
    if (txState.transactions.isEmpty && !txState.isRefreshing) {
      return Text(
        'No transactions yet. Tap refresh to load.',
        style: TextStyle(
          fontSize: 14,
          color: PaxColors.black.withValues(alpha: 0.6),
        ),
      ).withPadding(top: 8);
    }
    if (txState.transactions.isEmpty && txState.isRefreshing) {
      return const Center(
        child: CircularProgressIndicator(onSurface: true),
      ).withPadding(top: 16);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          txState.transactions.asMap().entries.map<Widget>((entry) {
            final index = entry.key;
            final tx = entry.value;
            final tile = WalletTransactionTile(tx: tx, myAddress: eoAddress);
            final isLast = index == txState.transactions.length - 1;
            return isLast ? tile.withPadding(bottom: 8) : tile;
          }).toList(),
    );
  }
}

/// Single transaction card: icon, label, date, status. Tappable to open CeloScan.
class WalletTransactionTile extends ConsumerWidget {
  const WalletTransactionTile({
    super.key,
    required this.tx,
    required this.myAddress,
  });

  final Map<String, dynamic> tx;
  final String? myAddress;

  static String _statusLabel(bool isError) =>
      isError ? "Didn't go through" : "Done";

  /// Title is the action label only; amount is shown on the right to avoid duplication.
  String _title() {
    return TransactionLabelUtil.getLabel(tx, myAddress);
  }

  /// Resolves token decimals from tx (tokenDecimal from API) or by contract address via TokenBalanceUtil.
  /// Tether/USDC use 6 dp; G$/CELO/USDm use 18. Ensures 6-dp tokens like Tether display correctly (e.g. 0.079).
  static int _decimalsForTx(Map<String, dynamic> tx) {
    final tokenDecimalRaw = tx['tokenDecimal'];
    if (tokenDecimalRaw != null) {
      final d = int.tryParse(tokenDecimalRaw.toString());
      if (d != null) return d;
    }
    final contractAddress = tx['contractAddress']?.toString();
    if (contractAddress != null && contractAddress.isNotEmpty) {
      final tokenId = TokenBalanceUtil.getTokenIdByAddress(contractAddress);
      if (tokenId != null) return TokenBalanceUtil.getTokenDecimals(tokenId);
    }
    return 18;
  }

  /// Formats raw token value using [decimals] from TokenBalanceUtil / API (6 for Tether/USDC, 18 for others).
  static String? _formatValue(dynamic valueWei, {required int decimals}) {
    String? str;
    if (valueWei is String) {
      str = valueWei.trim();
    } else if (valueWei is num) {
      if (valueWei <= 0) return null;
      str = valueWei.toInt().toString();
    }
    if (str == null || str.isEmpty || str == '0') return null;
    final wei = BigInt.tryParse(str);
    if (wei == null || wei == BigInt.zero) return null;
    final divisor = BigInt.from(10).pow(decimals);
    final whole = wei ~/ divisor;
    final frac = wei % divisor;
    final fracStr = frac.toString().padLeft(decimals, '0');
    final trimmed = fracStr.replaceFirst(RegExp(r'0+$'), '');
    final numStr = trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
    final parsed = double.tryParse(numStr);
    if (parsed == null) return numStr;
    if (parsed >= 1000) return NumberFormat('#,###').format(parsed);
    if (parsed >= 1) return NumberFormat('#,##0.00').format(parsed);
    // Small amounts: show up to 5 decimal places, then trim trailing zeros
    return NumberFormat('#,##0.#####')
        .format(parsed)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeStamp = tx['timeStamp'];
    DateTime? date;
    if (timeStamp != null) {
      final sec = int.tryParse(timeStamp.toString());
      if (sec != null) date = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    }
    final dateStr =
        date != null ? DateFormat('MMM d, y • h:mm a').format(date) : '—';
    final isError = tx['isError'] == '1' || tx['isError'] == true;
    final rawValue = tx['value'] ?? tx['Value'];
    final decimals = _decimalsForTx(tx);
    final displayAmount = _formatValue(rawValue, decimals: decimals);
    final tokenSymbol = tx['tokenSymbol']?.toString().trim();
    final displaySymbol = CurrencySymbolUtil.getDisplaySymbolForTokenSymbol(
      tokenSymbol,
    );
    final amountWithSymbol =
        displayAmount != null && displaySymbol.isNotEmpty
            ? '$displayAmount $displaySymbol'
            : displayAmount;
    final currencyAssetPath =
        CurrencySymbolUtil.getCurrencyAssetPathForTokenContract(
          tx['contractAddress']?.toString(),
        ) ??
        CurrencySymbolUtil.getCurrencyAssetPathForTokenSymbol(tokenSymbol);
    final hash = tx['hash']?.toString();
    final label = TransactionLabelUtil.getLabel(tx, myAddress);
    final iconData = TransactionLabelUtil.getIconForLabel(label);

    return InkWell(
      onTap:
          hash != null
              ? () =>
                  UrlHandler.launchInAppWebView(context, '$celoscanTxUrl$hash')
              : null,
      child: Container(
        height: 85,
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: PaxColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PaxColors.lightLilac, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FaIcon(
              iconData,
              size: 24,
              color:
                  isError
                      ? PaxColors.red.withValues(alpha: 0.9)
                      : PaxColors.deepPurple.withValues(alpha: 0.85),
            ).withPadding(right: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title(),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: PaxColors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).withPadding(bottom: 4),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 13,
                      color: PaxColors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            if (amountWithSymbol != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currencyAssetPath != null) ...[
                    SvgPicture.asset(
                      currencyAssetPath,
                      width: currencyAssetPath.endsWith('usdm.svg') ? 30 : 20,
                      height: currencyAssetPath.endsWith('usdm.svg') ? 30 : 20,
                    ).withPadding(right: 6),
                  ],
                  Flexible(
                    child: Text(
                      amountWithSymbol,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: PaxColors.black.withValues(alpha: 0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ).withPadding(right: 10),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color:
                    isError
                        ? PaxColors.red.withValues(alpha: 0.12)
                        : PaxColors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusLabel(isError),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isError ? PaxColors.red : PaxColors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    ).withPadding(top: 8);
  }
}
