import 'package:flutter/material.dart' show Divider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class OnboardingQuestionnaireView extends ConsumerStatefulWidget {
  const OnboardingQuestionnaireView({super.key});

  @override
  ConsumerState<OnboardingQuestionnaireView> createState() =>
      _OnboardingQuestionnaireViewState();
}

enum _GdUsageAnswer { alreadyReceive, heardOfIt, firstTime }

enum _WalletAccessAnswer { canAccess, cannotAccess }

class _OnboardingQuestionnaireViewState
    extends ConsumerState<OnboardingQuestionnaireView> {
  _GdUsageAnswer? _usageAnswer;
  _WalletAccessAnswer? _walletAccessAnswer;

  bool get _isComplete {
    if (_usageAnswer == null) return false;
    if (_usageAnswer == _GdUsageAnswer.alreadyReceive &&
        _walletAccessAnswer == null) {
      return false;
    }
    return true;
  }

  String _computeOnboardingType() {
    switch (_usageAnswer) {
      case _GdUsageAnswer.firstTime:
        return 'v2_native';
      case _GdUsageAnswer.alreadyReceive:
        if (_walletAccessAnswer == _WalletAccessAnswer.canAccess) {
          return 'v1_legacy';
        }
        return 'mixed';
      case _GdUsageAnswer.heardOfIt:
      default:
        return 'mixed';
    }
  }

  Future<void> _onContinue() async {
    if (!_isComplete) return;

    final onboardingType = _computeOnboardingType();

    await ref.read(participantProvider.notifier).updateProfile({
      'onboardingType': onboardingType,
    });

    await ref.read(analyticsProvider).onboardingQuestionnaireCompleted({
      'onboardingType': onboardingType,
      'usageAnswer': _usageAnswer.toString().split('.').last,
      'walletAccessAnswer': _walletAccessAnswer?.toString().split('.').last,
    });

    if (!mounted) return;

    switch (onboardingType) {
      case 'v2_native':
      case 'mixed':
        context.go(Routes.createV2Wallet);
        break;
      case 'v1_legacy':
        context.go(Routes.home);
        break;
      default:
        context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final participantState = ref.watch(participantProvider);
    final isSaving = participantState.state == ParticipantState.loading;

    return Scaffold(
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              const Spacer(),
              Text(
                'Welcome to Pax',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, color: PaxColors.deepPurple),
              ),
              const Spacer(),
            ],
          ),
        ).withPadding(top: 16),
        Divider(color: PaxColors.lightGrey),
      ],
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Image.asset(
                      'lib/assets/logos/main.png',
                      height: 64,
                      fit: BoxFit.contain,
                    ),
                  ).withPadding(bottom: 24),
                  Text(
                    'Let’s get to know you',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: PaxColors.deepPurple,
                    ),
                  ).withPadding(bottom: 8),
                  Text(
                    'A couple of questions to personalize your experience.',
                    style: TextStyle(fontSize: 14, color: PaxColors.darkGrey),
                  ).withPadding(bottom: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        'lib/assets/images/good_dollar.png',
                        height: 18,
                        width: 18,
                        fit: BoxFit.contain,
                      ).withPadding(right: 12),
                      Expanded(
                        child: Text(
                          'Have you used G\$ or UBI payouts before?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: PaxColors.deepPurple,
                          ),
                        ),
                      ),
                    ],
                  ).withPadding(bottom: 16),
                  RadioGroup<_GdUsageAnswer>(
                    value: _usageAnswer,
                    onChanged: (value) {
                      setState(() {
                        _usageAnswer = value;
                        if (value != _GdUsageAnswer.alreadyReceive) {
                          _walletAccessAnswer = null;
                        }
                      });
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioItem(
                          value: _GdUsageAnswer.alreadyReceive,
                          trailing: const Text('Yes, I receive G\$'),
                        ),
                        const Gap(12),
                        RadioItem(
                          value: _GdUsageAnswer.heardOfIt,
                          trailing: const Text("Heard of it, haven't used it"),
                        ),
                        const Gap(12),
                        RadioItem(
                          value: _GdUsageAnswer.firstTime,
                          trailing: const Text('No, first time'),
                        ),
                      ],
                    ),
                  ),
                  if (_usageAnswer == _GdUsageAnswer.alreadyReceive) ...[
                    Text(
                      'Still have access to that wallet?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ).withPadding(top: 24, bottom: 16),
                    RadioGroup<_WalletAccessAnswer>(
                      value: _walletAccessAnswer,
                      onChanged: (value) {
                        setState(() => _walletAccessAnswer = value);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RadioItem(
                            value: _WalletAccessAnswer.canAccess,
                            trailing: const Text('Yes, I can access it'),
                          ),
                          const Gap(12),
                          RadioItem(
                            value: _WalletAccessAnswer.cannotAccess,
                            trailing: const Text('No / Not sure'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Divider().withPadding(top: 10, bottom: 20),
          SafeArea(
            bottom: true,
            left: false,
            right: false,
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: PrimaryButton(
                onPressed: !_isComplete || isSaving ? null : _onContinue,
                child:
                    isSaving
                        ? const CircularProgressIndicator(onSurface: true)
                        : const Text('Continue'),
              ),
            ).withPadding(left: 24, right: 24, bottom: 32),
          ),
        ],
      ),
    );
  }
}
