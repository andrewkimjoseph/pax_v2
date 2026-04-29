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
    this.debugWalletAddress,
  });

  final String address;
  final String? gasBalanceText;
  final String? debugWalletAddress;

  String _truncateAddress(String value) {
    return value.length > 14
        ? '${value.substring(0, 14)}...${value.substring(value.length - 4)}'
        : value;
  }

  Widget _buildCopyableAddress({required String value}) {
    return InkWell(
      onTap: () => Clipboard.setData(ClipboardData(text: value)),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              _truncateAddress(value),
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
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useDebugAddress =
        debugWalletAddress != null && debugWalletAddress!.isNotEmpty;
    final displayAddress = useDebugAddress ? debugWalletAddress! : address;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildCopyableAddress(value: displayAddress)),
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
