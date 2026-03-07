import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' show InkWell;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/url_handler.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Wallet address + "Check G$ exchange rate" link for [PaxWalletBalanceCard].
class PaxWalletAddressAndExchangeRow extends ConsumerWidget {
  const PaxWalletAddressAndExchangeRow({
    super.key,
    required this.address,
    required this.gdBalance,
    required this.showExchangeLink,
    this.onBeforeOpenConverter,
  });

  final String address;
  final num gdBalance;
  final bool showExchangeLink;

  /// Called when "Check G$ exchange rate" is tapped, before opening the converter (e.g. for analytics).
  final void Function(num gdBalance)? onBeforeOpenConverter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final truncated =
        address.length > 14
            ? '${address.substring(0, 14)}...${address.substring(address.length - 4)}'
            : address;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: InkWell(
            onTap: () => Clipboard.setData(ClipboardData(text: address)),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    truncated,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: PaxColors.white.withValues(alpha: 0.75),
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FaIcon(
                  FontAwesomeIcons.copy,
                  size: 12,
                  color: PaxColors.white.withValues(alpha: 0.6),
                ).withPadding(left: 8),
              ],
            ),
          ),
        ),
        if (showExchangeLink)
          InkWell(
            onTap: () {
              onBeforeOpenConverter?.call(gdBalance);
              UrlHandler.launchGdConverterWebView(
                context,
                coinbaseGdConverterUrl,
                gdBalance,
              );
            },
            borderRadius: BorderRadius.circular(4),
            child: Text(
              'Check G\$ exchange rate',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: PaxColors.white.withValues(alpha: 0.95),
                decoration: TextDecoration.underline,
                decorationColor: PaxColors.white.withValues(alpha: 0.95),
              ),
            ).withPadding(horizontal: 4, vertical: 2),
          ),
      ],
    ).withPadding(top: 12);
  }
}
