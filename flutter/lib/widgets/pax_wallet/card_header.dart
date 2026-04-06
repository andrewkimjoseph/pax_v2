import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/extensions/tooltip.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Logo + "PaxWallet" + refresh button for [PaxWalletBalanceCard].
class PaxWalletCardHeader extends ConsumerWidget {
  const PaxWalletCardHeader({
    super.key,
    required this.onRefresh,
    required this.canRefresh,
    required this.isFetching,
    required this.refreshTooltip,
    this.onFlip,
    this.onRefillGas,
    this.canRefillGas = false,
    this.isRefillingGas = false,
  });

  final VoidCallback? onRefresh;
  final bool canRefresh;
  final bool isFetching;
  final String refreshTooltip;
  final VoidCallback? onFlip;
  final VoidCallback? onRefillGas;
  final bool canRefillGas;
  final bool isRefillingGas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        SvgPicture.asset(
          'lib/assets/svgs/wallets/pax_wallet_lilac.svg',
          width: 32,
          height: 32,
        ).withPadding(right: 12),

        Text(
          'PaxWallet',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: PaxColors.white,
          ),
        ),
        const Spacer(),
        if (onRefillGas != null)
          IconButton.outline(
                onPressed: !canRefillGas || isRefillingGas ? null : onRefillGas,
                density: ButtonDensity.icon,
                icon:
                    isRefillingGas
                        ? const CircularProgressIndicator(onSurface: true)
                        : const FaIcon(
                          FontAwesomeIcons.gasPump,
                          color: PaxColors.white,
                          size: 15,
                        ),
              )
              .withToolTip('Refill gas', showTooltip: canRefillGas)
              .withPadding(right: 8),
        if (onFlip != null)
          IconButton.outline(
            onPressed: onFlip,
            density: ButtonDensity.icon,
            icon: FaIcon(
              FontAwesomeIcons.rightLeft,
              color: PaxColors.white,
              size: 16,
            ),
          ).withToolTip('Flip card', showTooltip: true).withPadding(right: 8),
        IconButton.outline(
          onPressed: !canRefresh || isFetching ? null : onRefresh,
          density: ButtonDensity.icon,
          icon:
              isFetching
                  ? const CircularProgressIndicator(onSurface: true)
                  : const FaIcon(
                    FontAwesomeIcons.arrowsRotate,
                    color: PaxColors.white,
                    size: 16,
                  ),
        ).withToolTip(refreshTooltip, showTooltip: !canRefresh),
      ],
    ).withPadding(bottom: 20);
  }
}
