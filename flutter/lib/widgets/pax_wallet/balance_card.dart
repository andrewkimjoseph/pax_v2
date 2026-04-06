import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_flip_card/flutter_flip_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pax/extensions/tooltip.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/local/pax_wallet_view_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/widgets/pax_wallet/address_exchange_row.dart';
import 'package:pax/widgets/pax_wallet/balance_rows.dart';
import 'package:pax/widgets/pax_wallet/card_header.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Pax Wallet balance card: flippable front (balances) and back (blank placeholder).
class PaxWalletBalanceCard extends ConsumerStatefulWidget {
  const PaxWalletBalanceCard({
    super.key,
    required this.viewState,
    required this.address,
    required this.onRefresh,
    required this.canRefresh,
    required this.refreshTooltip,
    this.onBeforeOpenConverter,
    this.networkLabel,
  });

  final PaxWalletViewStateModel viewState;
  final String? address;
  final VoidCallback onRefresh;
  final bool canRefresh;
  final String refreshTooltip;
  final String? networkLabel;

  /// Called when "Check G$ exchange rate" is tapped before opening (e.g. analytics). Receives gdBalance.
  final void Function(num gdBalance)? onBeforeOpenConverter;

  @override
  ConsumerState<PaxWalletBalanceCard> createState() =>
      _PaxWalletBalanceCardState();
}

class _PaxWalletBalanceCardState extends ConsumerState<PaxWalletBalanceCard>
    with SingleTickerProviderStateMixin {
  late final FlipCardController _controller;
  bool _isRefillingGas = false;

  @override
  void initState() {
    super.initState();
    _controller = FlipCardController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(paxWalletProvider.notifier).refreshNativeCeloBalance());
    });
  }

  @override
  void didUpdateWidget(covariant PaxWalletBalanceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.address != widget.address) {
      unawaited(ref.read(paxWalletProvider.notifier).refreshNativeCeloBalance());
    }
  }

  Future<void> _triggerGasRefill() async {
    if (_isRefillingGas) return;
    final nativeCeloBalance = ref.read(paxWalletProvider).nativeCeloBalance;
    ref.read(analyticsProvider).refillGasTapped({
      'source': 'pax_wallet_balance_card',
      'hasAddress': widget.address != null && widget.address!.isNotEmpty,
      if (nativeCeloBalance != null) 'nativeCeloBalance': nativeCeloBalance,
      'thresholdCelo': PaxWalletNotifier.autoTopUpThresholdCelo,
    });
    if (mounted) {
      setState(() => _isRefillingGas = true);
    }
    try {
      final didRefill = await ref.read(paxWalletProvider.notifier).topUpGasIfNeeded();
      if (didRefill && widget.address != null && widget.address!.isNotEmpty) {
        await ref.read(paxWalletViewProvider.notifier).fetchBalance(
          widget.address!,
          silent: true,
          forceRefresh: true,
        );
      }
      await ref.read(paxWalletProvider.notifier).refreshNativeCeloBalance();
    } finally {
      if (mounted) {
        setState(() => _isRefillingGas = false);
      }
    }
  }

  String _formatNativeCeloBalance(double value) {
    final formatter = NumberFormat('#,##0.####');
    return formatter.format(value);
  }

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: PaxColors.deepPurple,
        boxShadow: [
          BoxShadow(
            color: PaxColors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nativeCeloBalance = ref.watch(paxWalletProvider).nativeCeloBalance;
    final isLoading = widget.viewState.state == PaxWalletViewState.loading;
    final shouldShowRefillGas =
        kDebugMode ||
        (nativeCeloBalance != null &&
            nativeCeloBalance < PaxWalletNotifier.autoTopUpThresholdCelo);

    return AspectRatio(
      aspectRatio: 1.58,
      child: FlipCard(
        axis: FlipAxis.horizontal,
        disableSplashEffect: true,
        controller: _controller,
        rotateSide: RotateSide.bottom,
        onTapFlipping: false,
        frontWidget: _buildCardContainer(
          child: Stack(
            children: [
              if (!isLoading)
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: 400,
                      height: 253,
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          PaxWalletCardHeader(
                            onRefresh: () {
                              widget.onRefresh();
                              unawaited(
                                ref
                                    .read(paxWalletProvider.notifier)
                                    .refreshNativeCeloBalance(),
                              );
                            },
                            canRefresh: widget.canRefresh,
                            isFetching: false,
                            refreshTooltip: widget.refreshTooltip,
                            onRefillGas:
                                shouldShowRefillGas ? _triggerGasRefill : null,
                            canRefillGas:
                                !_isRefillingGas &&
                                widget.address != null &&
                                widget.address!.isNotEmpty,
                            isRefillingGas: _isRefillingGas,
                            onFlip: () => _controller.flipcard(),
                          ),
                          Expanded(
                            child: PaxWalletBalanceRows(
                              viewState: widget.viewState,
                            ),
                          ),
                          if (widget.networkLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SvgPicture.asset(
                                    'lib/assets/svgs/celo.svg',
                                    width: 16,
                                    height: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Connected to ${widget.networkLabel}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: PaxColors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (widget.address != null)
                            PaxWalletAddressAndExchangeRow(
                              address: widget.address!,
                              gasBalanceText:
                                  nativeCeloBalance != null
                                      ? _formatNativeCeloBalance(
                                        nativeCeloBalance,
                                      )
                                      : null,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (isLoading)
                const Center(child: CircularProgressIndicator(onSurface: true)),
            ],
          ),
        ),
        backWidget: _buildCardContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Spacer(),
                  IconButton.outline(
                    onPressed: () => _controller.flipcard(),
                    density: ButtonDensity.icon,
                    icon: FaIcon(
                      FontAwesomeIcons.rightLeft,
                      color: PaxColors.white,
                      size: 16,
                    ),
                  ).withToolTip('Flip card', showTooltip: true),
                ],
              ).withPadding(bottom: 20),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        FontAwesomeIcons.wandMagicSparkles,
                        size: 20,
                        color: PaxColors.white.withValues(alpha: 0.6),
                      ).withPadding(bottom: 16),
                      Text(
                        'You found the back!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: PaxColors.white.withValues(alpha: 0.95),
                        ),
                      ).withPadding(bottom: 8),
                      Text(
                        'Your wallet is safe.\nGo make the world a little better.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: PaxColors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).withPadding(top: 0);
  }
}
