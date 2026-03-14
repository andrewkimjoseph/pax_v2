import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/models/auth/auth_state_model.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart'
    show withdrawalMethodsProvider;
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/remote_config_constants.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Dashboard banner when the user has no linked withdrawal methods.
/// Shown for everyone except V2 (PaxWallet flow). Note: [AccountType.v1] is
/// `contractAddress != null` only — V1_legacy users with no wallets are often
/// [AccountType.unknown], so we must not require `v1` here.
class WithdrawalMethodPromptBanner extends ConsumerStatefulWidget {
  const WithdrawalMethodPromptBanner({super.key});

  static const String _route = '/withdrawal-methods';

  @override
  ConsumerState<WithdrawalMethodPromptBanner> createState() =>
      _WithdrawalMethodPromptBannerState();
}

class _WithdrawalMethodPromptBannerState
    extends ConsumerState<WithdrawalMethodPromptBanner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider);
      if (auth.state == AuthState.authenticated && mounted) {
        ref
            .read(withdrawalMethodsProvider.notifier)
            .fetchPaymentMethods(auth.user.uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountType = ref.watch(accountTypeProvider);
    if (accountType == AccountType.v2) {
      return const SizedBox.shrink();
    }

    final withdrawalState = ref.watch(withdrawalMethodsProvider);
    if (withdrawalState.withdrawalMethods.isNotEmpty) {
      return const SizedBox.shrink();
    }

    final featureFlags = ref.watch(featureFlagsProvider);
    return featureFlags.when(
      // Do not hide while RC loads — same default as withdrawal screen (allow in debug; else assume available).
      loading: () => _WithdrawalMethodPromptBannerState._banner(context, ref),
      error: (_, __) => _WithdrawalMethodPromptBannerState._banner(context, ref),
      data: (flags) {
        final available =
            flags[RemoteConfigKeys.isWithdrawalMethodConnectionAvailable] ??
                true;
        if (!kDebugMode && available != true) {
          return const SizedBox.shrink();
        }

        return _WithdrawalMethodPromptBannerState._banner(context, ref);
      },
    );
  }

  static Widget _banner(BuildContext context, WidgetRef ref) {
    final child = InkWell(
          onTap: () {
            ref.read(analyticsProvider).setUpWithdrawalMethodTapped({
              'source': 'dashboard_banner',
            });
            context.push(WithdrawalMethodPromptBanner._route);
          },
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  PaxColors.deepPurple.withValues(alpha: 0.1),
                  PaxColors.lilac.withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: PaxColors.deepPurple.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                FaIcon(
                  FontAwesomeIcons.wallet,
                  color: PaxColors.deepPurple,
                  size: 24,
                ).withPadding(right: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect a withdrawal method',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: PaxColors.deepPurple,
                        ),
                      ).withPadding(bottom: 2),
                      Text(
                        'Link MiniPay or GoodWallet so you can receive payouts.',
                        style: TextStyle(
                          fontSize: 13,
                          color: PaxColors.darkGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                FaIcon(
                  FontAwesomeIcons.chevronRight,
                  color: PaxColors.deepPurple,
                  size: 16,
                ),
              ],
            ),
          ),
        );
    return child;
  }
}
