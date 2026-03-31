import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class FaceVerificationPromptBanner extends ConsumerWidget {
  const FaceVerificationPromptBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountType = ref.watch(accountTypeProvider);
    if (accountType != AccountType.v2) {
      return const SizedBox.shrink();
    }

    final needsVerification = ref.watch(paxWalletNeedsVerificationProvider);

    return needsVerification.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (show) {
        if (!show) {
          return const SizedBox.shrink();
        }

        ref.read(analyticsProvider).v2FaceVerificationPromptShown();

        return InkWell(
          onTap: () {
            ref.read(analyticsProvider).v2FaceVerificationPromptTapped({
              'source': 'dashboard',
            });
            context.push(
              Routes.completeGoodDollarFaceVerification,
              extra: 'dashboard',
            );
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
                  FontAwesomeIcons.userCheck,
                  color: PaxColors.deepPurple,
                  size: 24,
                ).withPadding(right: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Complete Face Verification',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: PaxColors.deepPurple,
                        ),
                      ).withPadding(bottom: 2),
                      Text(
                        'Verify your identity with GoodDollar to activate your PaxWallet.',
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
      },
    );
  }
}
