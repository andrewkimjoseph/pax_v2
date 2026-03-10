import 'package:flutter/material.dart' show Divider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/widgets/pax_wallet/recent_transactions_section.dart';
import 'package:pax/providers/local/pax_wallet_view_provider.dart';
import 'package:pax/providers/local/wallet_transactions_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/widgets/pax_wallet/balance_card.dart';
import 'package:pax/extensions/tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class PaxWalletView extends ConsumerStatefulWidget {
  const PaxWalletView({super.key, this.embedded = false});

  /// When true, only the body content is built (no Scaffold/AppBar).
  /// Used when embedded inside [WalletAndAppsView].
  final bool embedded;

  @override
  ConsumerState<PaxWalletView> createState() => _PaxWalletViewState();
}

class _PaxWalletViewState extends ConsumerState<PaxWalletView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewState = ref.read(paxWalletViewProvider);
      final walletState = ref.read(paxWalletProvider);
      final eoAddress = walletState.wallet?.eoAddress;
      if (eoAddress != null) {
        // Only show loading on first load or after error; otherwise refresh in background
        final hasCachedData = viewState.state == PaxWalletViewState.loaded;
        ref
            .read(paxWalletViewProvider.notifier)
            .fetchBalance(eoAddress, silent: hasCachedData);
      }
      ref.read(walletTransactionsProvider.notifier).load(eoAddress);
      ref.read(analyticsProvider).v2PaxWalletRouteVisited();
    });
  }

  void _loadBalance() {
    ref.read(analyticsProvider).refreshBalancesTapped({
      'source': 'pax_wallet_card',
    });
    final walletState = ref.read(paxWalletProvider);
    final eoAddress = walletState.wallet?.eoAddress;
    if (eoAddress != null) {
      ref.read(paxWalletViewProvider.notifier).fetchBalance(eoAddress, forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(paxWalletProvider);
    final viewState = ref.watch(paxWalletViewProvider);
    final txState = ref.watch(walletTransactionsProvider);
    final wallet = walletState.wallet;
    final eoAddress = wallet?.eoAddress;

    ref.listen(paxWalletProvider, (prev, next) {
      final addr = next.wallet?.eoAddress;
      if (addr != null && addr != prev?.wallet?.eoAddress) {
        ref.read(walletTransactionsProvider.notifier).load(addr);
      }
    });

    // When balance card updates (e.g. after miniapp tx or pull-to-refresh), refresh transaction list.
    ref.listen(paxWalletViewProvider, (prev, next) {
      final addr = ref.read(paxWalletProvider).wallet?.eoAddress;
      if (addr == null) return;
      if (next.state != PaxWalletViewState.loaded) return;
      final prevLoaded = prev?.state == PaxWalletViewState.loaded;
      final justLoaded = !prevLoaded;
      final balancesChanged =
          prevLoaded &&
          prev != null &&
          (prev.gdBalance != next.gdBalance ||
              prev.cusdBalance != next.cusdBalance ||
              prev.usdtBalance != next.usdtBalance);
      if (justLoaded || balancesChanged) {
        ref.read(walletTransactionsProvider.notifier).refresh(addr);
      }
    });

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Locked: wallet card + network label (no scroll)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PaxWalletBalanceCard(
              viewState: viewState,
              address: wallet?.eoAddress,
              networkLabel: viewState.networkLabel,
              onRefresh: () {
                _loadBalance();
              },
              canRefresh: viewState.state != PaxWalletViewState.loading,
              refreshTooltip: 'Refresh balances',
              onBeforeOpenConverter: (gdBalance) {
                ref.read(analyticsProvider).gdConverterOpened({
                  'gd_balance': gdBalance,
                });
              },
            ),
            // Sticky: "Recent transactions" + refresh (when wallet present)
            if (eoAddress != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your transactions (${txState.transactions.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: PaxColors.black,
                    ),
                  ),
                  IconButton.outline(
                    onPressed:
                        txState.isRefreshing
                            ? null
                            : () => ref
                                .read(walletTransactionsProvider.notifier)
                                .refresh(eoAddress),
                    density: ButtonDensity.icon,
                    icon:
                        txState.isRefreshing
                            ? CircularProgressIndicator(size: 25)
                            : FaIcon(FontAwesomeIcons.arrowsRotate),
                  ).withToolTip(
                    'Refresh transactions',
                    showTooltip: !txState.isRefreshing,
                  ),
                ],
              ).withPadding(top: 12),
          ],
        ).withPadding(left: 8, right: 8),
        // Scrollable: transaction list only
        if (eoAddress != null)
          Expanded(
            child: SingleChildScrollView(
              child: RecentTransactionsContent(eoAddress: eoAddress),
            ).withPadding(left: 8, right: 8, bottom: 8, top: 8),
          )
        else
          Expanded(child: const SizedBox.shrink()),
      ],
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),
          height: 50,
          backgroundColor: PaxColors.white,
          header: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Wallet',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                  color: PaxColors.black,
                ),
              ),
            ],
          ),
        ),
        Divider(color: PaxColors.lightGrey),
      ],
      child: body,
    );
  }
}
