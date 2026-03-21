import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/models/remote_config/goodcollective_config.dart';
import 'package:pax/providers/local/donation_context_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider, Consumer;

class SelectGoodCollectiveView extends ConsumerWidget {
  const SelectGoodCollectiveView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donationContext = ref.watch(donationContextProvider);
    final selected = donationContext?.selectedGoodCollective;

    return Scaffold(
      headers: [
        AppBar(
          padding: const EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: context.pop,
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
            ],
          ),
        ).withPadding(top: 16),
        const Divider(color: PaxColors.lightGrey),
      ],
      child: Column(
        children: [
          ref
              .watch(goodCollectiveConfigProvider)
              .when(
                data: (config) {
                  if (config.goodcollectives.isEmpty) {
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
                        ...config.goodcollectives.map(
                          (collective) => _GoodCollectiveTile(
                            collective: collective,
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
                const Divider().withPadding(top: 10, bottom: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: PrimaryButton(
                    enabled: selected != null,
                    onPressed:
                        selected == null
                            ? null
                            : () => context.push(
                              '/wallet/donate/select-goodcollective/review-summary',
                            ),
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
  });

  final GoodCollective collective;

  void _toggleSelection(WidgetRef ref, bool isSelected) {
    if (isSelected) {
      ref.read(donationContextProvider.notifier).setSelectedGoodCollective(null);
    } else {
      ref
          .read(donationContextProvider.notifier)
          .setSelectedGoodCollective(collective);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final donationContext = ref.watch(donationContextProvider);
        final isSelected =
            donationContext?.selectedGoodCollective?.donationContract ==
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if ((collective.coverURI ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      collective.coverURI!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
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
          ),
        );
      },
    );
  }
}
