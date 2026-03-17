import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/theming/colors.dart' show PaxColors;
import 'package:shadcn_flutter/shadcn_flutter.dart';

class ReferralView extends ConsumerStatefulWidget {
  const ReferralView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ReferralViewState();
}

class _ReferralViewState extends ConsumerState<ReferralView> {
  final StepperController controller = StepperController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
                child: FaIcon(
                  FontAwesomeIcons.arrowLeftLong,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ).withPadding(right: 8),
              Spacer(),
              Text(
                'Refer a Person to Pax V2',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22),
              ).withPadding(right: 16),
              Spacer(),
            ],
          ),
        ).withPadding(top: 16),
        Divider().withPadding(top: 8),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,

              child: SvgPicture.asset(
                'lib/assets/svgs/pax_v2_referral.svg',
                fit: BoxFit.fitHeight,
              ),
            ),
            ValueListenableBuilder<StepperValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                const stepCount = 4;
                if (value.currentStep >= stepCount) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "You're all set!",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: PaxColors.black,
                        ),
                      ).withPadding(bottom: 8),
                      Text(
                        "You've seen how the V2 referral program works: share your link, and you're rewarded when your referral completes in-app face verification. Share your invite link from the Account screen when you're ready.",
                        style: TextStyle(
                          fontSize: 16,
                          color: PaxColors.darkGrey,
                          height: 1.5,
                        ),
                      ).withPadding(bottom: 16),
                      PrimaryButton(
                        onPressed: () => controller.jumpToStep(0),
                        child: const Text(
                          'Start over',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  );
                }
                return Stepper(
                  controller: controller,
                  direction: Axis.vertical,
                  steps: [
                    Step(
                      title:
                          const Text(
                            'Share your unique invite link',
                            style: TextStyle(fontSize: 18),
                          ).expanded(),
                      contentBuilder: (context) {
                        return StepContainer(
                          actions: [
                            const OutlineButton(child: Text('Prev')),
                            PrimaryButton(
                              child: const Text('Next'),
                              onPressed: () => controller.nextStep(),
                            ),
                          ],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'This referral program is for bringing new users to Pax V2. You get a unique invite link from the Referral Program card on your Account screen. Share it with people you trust via the share icon.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: PaxColors.darkGrey,
                                ),
                              ),
                              Text(
                                'V2 users are those who, during onboarding, selected "Heard of it, haven\'t used it" or "No, first time" for G\$ or UBI payouts, or "No / Not sure" for wallet access (if they already receive G\$).',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: PaxColors.darkGrey,
                                ),
                              ).withPadding(top: 12),
                            ],
                          ),
                        );
                      },
                    ),
                    Step(
                      title:
                          const Text(
                            'They sign up for V2 and verify',
                            style: TextStyle(fontSize: 18),
                          ).expanded(),
                      contentBuilder: (context) {
                        return StepContainer(
                          actions: [
                            OutlineButton(
                              child: const Text('Prev'),
                              onPressed: () => controller.previousStep(),
                            ),
                            PrimaryButton(
                              child: const Text('Next'),
                              onPressed: () => controller.nextStep(),
                            ),
                          ],
                          child: Text(
                            'When someone uses your link to sign up for Pax V2 and completes in-app face verification, they become your referral.',
                            style: TextStyle(
                              fontSize: 16,
                              color: PaxColors.darkGrey,
                            ),
                          ),
                        );
                      },
                    ),
                    Step(
                      title:
                          const Text(
                            'Unlock rewards',
                            style: TextStyle(fontSize: 18),
                          ).expanded(),
                      contentBuilder: (context) {
                        return StepContainer(
                          actions: [
                            OutlineButton(
                              child: const Text('Prev'),
                              onPressed: () => controller.previousStep(),
                            ),
                            PrimaryButton(
                              child: const Text('Next'),
                              onPressed: () => controller.nextStep(),
                            ),
                          ],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'You are rewarded when your referral completes in-app face verification. Referrals can also unlock eligibility in future Pax programs.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: PaxColors.darkGrey,
                                ),
                              ),
                              Text(
                                'Note: V1 referrals will not be rewarded.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: PaxColors.darkGrey,
                                ),
                              ).withPadding(top: 12),
                            ],
                          ),
                        );
                      },
                    ),
                    Step(
                      title:
                          const Text(
                            'Use responsibly',
                            style: TextStyle(fontSize: 18),
                          ).expanded(),
                      contentBuilder: (context) {
                        return StepContainer(
                          actions: [
                            OutlineButton(
                              child: const Text('Prev'),
                              onPressed: () => controller.previousStep(),
                            ),
                            PrimaryButton(
                              child: const Text('Finish'),
                              onPressed: () => controller.nextStep(),
                            ),
                          ],
                          child: Text(
                            'Please don’t spam or mislead people—only share your link with real humans who want to participate.',
                            style: TextStyle(
                              fontSize: 16,
                              color: PaxColors.darkGrey,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ).withPadding(all: 8),
      ),
    );
  }
}
