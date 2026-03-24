import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/local/v2_eligibility_provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class V2EligibilityView extends ConsumerWidget {
  const V2EligibilityView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligibilityAsync = ref.watch(v2EligibilityProvider);

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
                child: FaIcon(FontAwesomeIcons.arrowLeftLong, size: 20, color: PaxColors.deepPurple),
              ),
              Spacer(),
              Text(
                'V2 Upgrade',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20),
              ),
              Spacer(),
            ],
          ),
        ).withPadding(top: 16, horizontal: 8),
        Divider(color: PaxColors.lightGrey),
      ],
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: eligibilityAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (error, _) => _buildError(context, ref, error.toString()),
            data:
                (result) =>
                    result == V2EligibilityResult.eligible
                        ? _buildEligible(context)
                        : _buildNotEligible(context),
          ),
        ),
      ),
    );
  }

  Widget _buildEligible(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FaIcon(
          FontAwesomeIcons.arrowUpFromBracket,
          size: 64,
          color: PaxColors.green,
        ).withPadding(bottom: 24),
        Text(
          'You\'re Eligible!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: PaxColors.deepPurple,
          ),
        ).withPadding(bottom: 16),
        Text(
          'You can upgrade to V2 and get your own PaxWallet with enhanced features.',
          style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
          textAlign: TextAlign.center,
        ).withPadding(bottom: 32),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: PrimaryButton(
            onPressed: () => context.go(Routes.createV2Wallet),
            child: const Text('Upgrade to V2'),
          ),
        ),
      ],
    );
  }

  Widget _buildNotEligible(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FaIcon(FontAwesomeIcons.solidClock, size: 64, color: PaxColors.orange)
            .withPadding(bottom: 24),
        Text(
          'Not Yet Eligible',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: PaxColors.deepPurple,
          ),
        ).withPadding(bottom: 16),
        Text(
          'One of your withdrawal method(s) is still verified. You can upgrade to V2 once your GoodDollar identity expires.',
          style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
          textAlign: TextAlign.center,
        ).withPadding(bottom: 32),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlineButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
            child: const Text('Go Back'),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String errorMessage) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FaIcon(
          FontAwesomeIcons.circleExclamation,
          size: 64,
          color: PaxColors.red,
        ).withPadding(bottom: 24),
        Text(
          'Something went wrong',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: PaxColors.deepPurple,
          ),
        ).withPadding(bottom: 16),
        Text(
          errorMessage,
          style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
          textAlign: TextAlign.center,
        ).withPadding(bottom: 32),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlineButton(
            onPressed: () => ref.invalidate(v2EligibilityProvider),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
