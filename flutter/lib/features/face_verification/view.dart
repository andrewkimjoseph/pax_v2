import 'package:flutter/material.dart' show Divider, InkWell, PopScope;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pax/providers/local/face_verification_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/services/wallet/wallet_restore_helper.dart';
import 'package:pax/utils/user_property_constants.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/widgets/face_verification_webview.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class FaceVerificationView extends ConsumerStatefulWidget {
  const FaceVerificationView({super.key, this.source});

  /// Optional entrypoint identifier to control post-verification navigation.
  /// When null or unrecognized, the view falls back to the legacy behavior
  /// of returning to the complete profile flow.
  final String? source;

  @override
  ConsumerState<FaceVerificationView> createState() =>
      _FaceVerificationViewState();
}

class _FaceVerificationViewState extends ConsumerState<FaceVerificationView> {
  bool _restoreAttempted = false;
  bool _hasLoggedVerificationStarted = false;

  /// Guards so we only trigger gas sponsorship and registration once per session.
  bool _hasTriggeredGasSponsorship = false;
  final GlobalKey _webViewKey = GlobalKey();

  Future<void> _restoreWallet() async {
    if (!mounted) return;
    _restoreAttempted = true;
    await restoreWalletIfNeeded(ref, silentOnly: false);
  }

  Future<void> _onVerificationResult({
    required bool verified,
    required String chain,
  }) async {
    if (kDebugMode) {
      debugPrint(
        'FaceVerificationView: _onVerificationResult called (verified=$verified, chain=$chain)',
      );
    }
    final viewModel = ref.read(faceVerificationProvider.notifier);
    if (verified) {
      if (_hasTriggeredGasSponsorship) {
        if (kDebugMode) {
          debugPrint(
            'FaceVerificationView: skipping duplicate verification flow (already triggered gas sponsorship)',
          );
        }
        viewModel.setSuccess(chain);
        if (!mounted) return;
        _showResultDialog(verified: true, chain: chain);
        return;
      }
      _hasTriggeredGasSponsorship = true;
      viewModel.setSuccess(chain);
      ref.read(analyticsProvider).v2FaceVerificationSuccess({'chain': chain});
      ref.read(analyticsProvider).identifyUser({
        UserPropertyConstants.goodDollarIdentityTimeLastAuthenticated:
            DateTime.now().toIso8601String(),
      });
      try {
        await ref
            .read(participantProvider.notifier)
            .updateGoodDollarLastAuthTime(Timestamp.now());
        await ref
            .read(paxWalletProvider.notifier)
            .registerPaxWalletAfterFaceVerification();
        if (!mounted) return;
        _showResultDialog(verified: true, chain: chain);
      } catch (e) {
        if (!mounted) return;
        _hasTriggeredGasSponsorship = false;
        viewModel.setFailed();
        ref.read(analyticsProvider).v2FaceVerificationFailed();
        _showResultDialog(verified: false, chain: chain);
      }
    } else {
      viewModel.setFailed();
      ref.read(analyticsProvider).v2FaceVerificationFailed();
      _showResultDialog(verified: false, chain: chain);
    }
  }

  void _navigateAfterFlow() {
    if (!mounted) return;
    final source = widget.source;
    if (source == 'wallet_and_apps') {
      context.pop();
    } else if (source == 'dashboard') {
      context.pop();
    } else if (source == 'task_summary') {
      context.go(Routes.home);
    } else if (source == 'wallet_creation') {
      context.go(Routes.completeProfile);
    } else {
      context.go(Routes.completeProfile);
    }
  }

  void _showResultDialog({required bool verified, required String chain}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: widget.source == 'dashboard' ? true : false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FaIcon(
                  verified
                      ? FontAwesomeIcons.solidCircleCheck
                      : FontAwesomeIcons.circleInfo,
                  color: verified ? PaxColors.green : PaxColors.orange,
                  size: 56,
                ).withPadding(bottom: 16),
                Text(
                  verified ? 'Verified!' : 'Verification Incomplete',
                  style: TextStyle(
                    color: PaxColors.deepPurple,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ).withPadding(bottom: 12),
                Text(
                  verified
                      ? 'Your identity has been verified successfully.'
                      : 'Face verification was not completed. You can try again later.',
                  style: TextStyle(
                    color: PaxColors.darkGrey,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ).withPadding(bottom: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: PrimaryButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _navigateAfterFlow();
                    },
                    child: Text(verified ? 'Continue' : 'Skip for Now'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletCredentialsProvider);
    final paxWalletState = ref.watch(paxWalletProvider);
    ref.watch(faceVerificationProvider);

    final hasPaxWallet =
        paxWalletState.state == PaxWalletState.loaded &&
        paxWalletState.wallet != null;

    if (!walletState.isLoaded || walletState.credentials == null) {
      if (walletState.status == WalletCredentialsStatus.initial &&
          hasPaxWallet &&
          !_restoreAttempted) {
        _restoreAttempted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _restoreWallet();
        });
      }

      if (walletState.status == WalletCredentialsStatus.error) {
        return Scaffold(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  walletState.errorMessage ?? 'Could not load wallet',
                  style: TextStyle(color: PaxColors.darkGrey, fontSize: 16),
                  textAlign: TextAlign.center,
                ).withPadding(bottom: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {
                        _restoreAttempted = false;
                        _restoreWallet();
                      },
                      child: const Text('Retry'),
                    ).withPadding(right: 16),
                    TextButton(
                      onPressed: () {
                        _navigateAfterFlow();
                      },
                      child: const Text('Go back'),
                    ),
                  ],
                ),
              ],
            ),
          ).withPadding(all: 24),
        );
      }

      if (walletState.status == WalletCredentialsStatus.initial &&
          !hasPaxWallet) {
        return Scaffold(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Set up your wallet first to continue.',
                  style: TextStyle(color: PaxColors.darkGrey, fontSize: 16),
                  textAlign: TextAlign.center,
                ).withPadding(bottom: 24),
                TextButton(
                  onPressed: () {
                    _navigateAfterFlow();
                  },
                  child: const Text('Go back'),
                ),
              ],
            ),
          ).withPadding(all: 24),
        );
      }

      return Scaffold(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator().withPadding(bottom: 16),
              Text(
                'Loading wallet...',
                style: TextStyle(color: PaxColors.darkGrey),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasLoggedVerificationStarted) {
      _hasLoggedVerificationStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(analyticsProvider).v2FaceVerificationStarted();
        }
      });
    }

    return Scaffold(
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  _navigateAfterFlow();
                },
                child: FaIcon(
                  FontAwesomeIcons.arrowLeftLong,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ),
              Spacer(),
              Text(
                'Face Verification',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20),
              ).withPadding(right: 16),
              Spacer(),
              IconButton(
                onPressed: () {
                  final currentState = _webViewKey.currentState;
                  if (currentState is FaceVerificationWebViewState) {
                    currentState.reload();
                  }
                },
                variance: const ButtonStyle.outline(
                  density: ButtonDensity.icon,
                ),
                icon: const FaIcon(FontAwesomeIcons.rotate, size: 20),
              ),
            ],
          ),
        ).withPadding(top: 16),
        Divider(),
      ],
      child: FaceVerificationWebView(
        key: _webViewKey,
        credentials: walletState.credentials!,
        onVerificationResult: _onVerificationResult,
      ),
    );
  }
}
