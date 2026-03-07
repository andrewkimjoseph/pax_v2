import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Single balance pill (e.g. USDm, USDT) for [PaxWalletBalanceRows].
class PaxWalletBalancePill extends ConsumerWidget {
  const PaxWalletBalancePill({
    super.key,
    required this.label,
    required this.amount,
    required this.assetPath,
  });

  final String label;
  final num amount;
  final String assetPath;

  static const double _fontSize = 17.0;
  static const double _iconSize = 20.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PaxColors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            assetPath,
            width: _iconSize,
            height: _iconSize,
          ).withPadding(right: 8),
          Text(
            '${TokenBalanceUtil.getLocaleFormattedAmountTwoDecimals(amount)} $label',
            style: TextStyle(
              fontSize: _fontSize,
              fontWeight: FontWeight.w600,
              color: PaxColors.white,
            ),
          ),
        ],
      ),
    );
  }
}
