import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' show InkWell;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Wallet address + gas balance/refill control for [PaxWalletBalanceCard].
class PaxWalletAddressAndExchangeRow extends ConsumerWidget {
  const PaxWalletAddressAndExchangeRow({
    super.key,
    required this.address,
    this.gasBalanceText,
  });

  final String address;
  final String? gasBalanceText;

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
        if (gasBalanceText != null)
          Text(
            gasBalanceText!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PaxColors.white.withValues(alpha: 0.95),
            ),
          ),
        FaIcon(
          FontAwesomeIcons.gasPump,
          size: 11,
          color: PaxColors.white,
        ).withPadding(left: 8),
      ],
    ).withPadding(top: 12);
  }
}
