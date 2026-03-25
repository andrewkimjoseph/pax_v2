import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/models/remote_config/goodcollective_config.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/local/claim_payout_context_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/url_handler.dart';
import 'package:pax/widgets/about_goodcollective_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider, Consumer;

class ClaimSelectGoodCollectiveView extends ConsumerWidget {
  const ClaimSelectGoodCollectiveView({super.key});

  void _showAboutGoodCollectiveDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AboutGoodCollectiveDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claimContext = ref.watch(claimPayoutContextProvider);
    final selected = claimContext?.selectedGoodCollective;

    return Scaffold(
      headers: [
        AppBar(
          padding: const EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  ref
                      .read(analyticsProvider)
                      .claimSelectGoodcollectiveBackTapped({
                        "claimKind": claimContext?.claimKind.name,
                      });
                  context.pop();
                },
                child: const FaIcon(
                  FontAwesomeIcons.arrowLeftLong,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ),
              const Spacer(),
              const Text(
                'Select GoodCollective',
                style: TextStyle(fontSize: 20),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  ref
                      .read(analyticsProvider)
                      .claimSelectGoodcollectiveInfoTapped({
                        "claimKind": claimContext?.claimKind.name,
                      });
                  _showAboutGoodCollectiveDialog(context, ref);
                },
                child: const FaIcon(
                  FontAwesomeIcons.circleQuestion,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ),
            ],
          ),
        ).withPadding(top: 16, horizontal: 8),
        const Divider(color: PaxColors.lightGrey),
      ],
      child: Column(
        children: [
          ref
              .watch(goodCollectiveConfigProvider)
              .when(
                data: (config) {
                  final collectives =
                      kDebugMode && config.goodcollectives.isEmpty
                          ? const [
                            GoodCollective(
                              id: -1,
                              name: 'Debug Collective',
                              isGoodcollectiveAvailable: true,
                              donationContract:
                                  '0x0000000000000000000000000000000000000000',
                            ),
                          ]
                          : config.goodcollectives;

                  if (!kDebugMode && collectives.isEmpty) {
                    return const Center(
                      child: Text('No GoodCollectives available'),
                    ).withPadding(top: 24);
                  }

                  return Container(
                    padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: PaxColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: PaxColors.lightLilac, width: 1),
                    ),
                    child: Column(
                      children: [
                        ...collectives.map(
                          (collective) => _GoodCollectiveTile(
                            collective: collective,
                            claimKind: claimContext?.claimKind.name,
                          ).withPadding(bottom: 8),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (_, __) => const Center(
                      child: Text('Unable to load GoodCollectives'),
                    ),
              ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              children: [
                if (selected != null)
                  InkWell(
                    onTap:
                        () => UrlHandler.launchCustomTab(
                          context,
                          'https://goodcollective.xyz/collective/${selected.donationContract}',
                        ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'View selected pool details',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: PaxColors.lilac,
                            decoration: TextDecoration.underline,
                            decorationColor: PaxColors.lilac,
                          ),
                        ),
                        SizedBox(width: 4),
                        FaIcon(
                          FontAwesomeIcons.arrowUpRightFromSquare,
                          size: 10,
                          color: PaxColors.lilac,
                        ),
                      ],
                    ).withPadding(bottom: 10),
                  ),
                const Divider().withPadding(top: 10, bottom: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: PrimaryButton(
                    enabled: selected != null,
                    onPressed:
                        selected == null
                            ? null
                            : () {
                              ref
                                  .read(analyticsProvider)
                                  .claimSelectGoodcollectiveContinueTapped({
                                    "claimKind": claimContext?.claimKind.name,
                                    "selectedDonationContract":
                                        selected.donationContract,
                                    "selectedCollectiveName": selected.name,
                                  });
                              context.push(
                                '/claim-reward/claim-payout/select-wallet/select-goodcollective/impact-review-summary',
                              );
                            },
                    child: Text(
                      'Continue',
                      style: Theme.of(context).typography.base.copyWith(
                        fontWeight: FontWeight.normal,
                        fontSize: 14,
                        color: PaxColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ).withMargin(bottom: 32),
        ],
      ).withPadding(horizontal: 8, bottom: 8),
    );
  }
}

class _GoodCollectiveTile extends StatelessWidget {
  const _GoodCollectiveTile({
    required this.collective,
    required this.claimKind,
  });

  final GoodCollective collective;
  final String? claimKind;

  void _toggleSelection(WidgetRef ref, bool isSelected) {
    ref.read(analyticsProvider).claimSelectGoodcollectiveOptionTapped({
      "claimKind": claimKind,
      "collectiveName": collective.name,
      "collectiveDonationContract": collective.donationContract,
      "selected": !isSelected,
    });
    if (isSelected) {
      ref
          .read(claimPayoutContextProvider.notifier)
          .setSelectedGoodCollective(null);
    } else {
      ref
          .read(claimPayoutContextProvider.notifier)
          .setSelectedGoodCollective(collective);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final claimContext = ref.watch(claimPayoutContextProvider);
        final isSelected =
            claimContext?.selectedGoodCollective?.donationContract ==
            collective.donationContract;

        return InkWell(
          onTap: () => _toggleSelection(ref, isSelected),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PaxColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PaxColors.lightLilac, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    if ((collective.coverURI ?? '').isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: collective.coverURI!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) {
                            return SvgPicture.asset(
                              'lib/assets/svgs/goodcollective.svg',
                              width: 48,
                              height: 48,
                            );
                          },
                          placeholder: (context, url) {
                            return SvgPicture.asset(
                              'lib/assets/svgs/goodcollective.svg',
                              width: 48,
                              height: 48,
                            );
                          },
                        ),
                      )
                    else
                      SvgPicture.asset(
                        'lib/assets/svgs/goodcollective.svg',
                        width: 48,
                        height: 48,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collective.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                              color: PaxColors.black,
                            ),
                          ).withPadding(bottom: 8),
                          Text(
                            '${collective.donationContract.substring(0, 20)}...',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: PaxColors.lilac,
                            ),
                          ).withPadding(bottom: 8),
                        ],
                      ),
                    ),
                    Checkbox(
                      state:
                          isSelected
                              ? CheckboxState.checked
                              : CheckboxState.unchecked,
                      onChanged: (_) => _toggleSelection(ref, isSelected),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
