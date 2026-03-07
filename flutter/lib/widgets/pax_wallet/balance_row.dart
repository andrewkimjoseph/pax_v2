import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Single balance row (e.g. G$ hero row) for [PaxWalletBalanceRows].
class PaxWalletBalanceRow extends ConsumerWidget {
  const PaxWalletBalanceRow({
    super.key,
    required this.label,
    required this.amount,
    required this.assetPath,
    required this.isPrimary,
  });

  final String label;
  final num amount;
  final String assetPath;
  final bool isPrimary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSize = isPrimary ? 40.0 : 24.0;
    final iconSize = isPrimary ? 40.0 : 24.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${TokenBalanceUtil.getLocaleFormattedAmountTwoDecimals(amount)} $label',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isPrimary ? FontWeight.bold : FontWeight.w600,
            color:
                isPrimary
                    ? PaxColors.white
                    : PaxColors.white.withValues(alpha: 0.9),
          ),
        ).withPadding(right: 8),
        SvgPicture.asset(assetPath, width: iconSize, height: iconSize),
      ],
    );
  }
}
