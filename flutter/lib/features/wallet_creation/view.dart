import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/local/wallet_creation_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/services/wallet/smart_account_service.dart';
import 'package:pax/services/wallet/wallet_registry_service.dart';
import 'package:pax/services/wallet/gooddollar_identity_service.dart';
import 'package:pax/services/wallet/wallet_restore_helper.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class WalletCreationView extends ConsumerStatefulWidget {
  const WalletCreationView({super.key});

  @override
  ConsumerState<WalletCreationView> createState() => _WalletCreationViewState();
}

class _WalletCreationViewState extends ConsumerState<WalletCreationView> {
  bool? _isWhitelisted;
  bool _isRegisteringWallet = false;
  String? _registryErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkWhitelistIfNeeded(),
    );
  }

  Future<void> _checkWhitelistIfNeeded() async {
    if (_isWhitelisted != null) return;
    final wallet = ref.read(paxWalletProvider).wallet;
    final eoAddress = wallet?.eoAddress;
    if (eoAddress == null || eoAddress.isEmpty) {
      if (mounted) setState(() => _isWhitelisted = false);
      return;
    }
    try {
      final whitelisted = await GoodDollarIdentityService.isWhitelisted(
        eoAddress,
      );
      if (mounted) setState(() => _isWhitelisted = whitelisted);
    } catch (_) {
      if (mounted) setState(() => _isWhitelisted = false);
    }
  }

  Future<void> _startWalletCreation() async {
    final viewModel = ref.read(walletCreationProvider.notifier);
    final analytics = ref.read(analyticsProvider);
    viewModel.setStep(WalletCreationStep.creating);
    analytics.v2WalletCreationInitiated();

    try {
      // Sign in with Drive scopes (shared instance so restore uses same account)
      final driveAccount = await driveSignInForWallet.signIn();
      if (driveAccount == null) {
        viewModel.setError('Google Sign-In cancelled');
        return;
      }

      final driveAuth = await driveAccount.authentication;
      final accessToken = driveAuth.accessToken;
      if (accessToken == null) {
        viewModel.setError('Failed to get Drive access token');
        return;
      }

      // Create wallet
      await ref
          .read(walletCredentialsProvider.notifier)
          .createWallet(accessToken: accessToken, accountId: driveAccount.id);

      final walletState = ref.read(walletCredentialsProvider);
      if (walletState.status == WalletCredentialsStatus.error) {
        ref.read(walletCredentialsProvider.notifier).clearCredentials();
        viewModel.setError(
          walletState.errorMessage ?? 'Wallet creation failed',
        );
        return;
      }

      final eoAddress = walletState.eoAddress!;
      final credentials = walletState.credentials!;
      final authState = ref.read(authProvider);
      final participantId = authState.user.uid;

      // Create pax_wallets document
      await ref
          .read(paxWalletProvider.notifier)
          .createWalletDocument(
            participantId: participantId,
            eoAddress: eoAddress,
          );

      // Create smart account
      final smartAccountService = SmartAccountService();
      final sessionKey = driveAccount.id;
      final smartAccountAddress = await smartAccountService.createSmartAccount(
        credentials: credentials,
        sessionKey: sessionKey,
      );

      // Save smart account address to pax_wallets document
      final currentWalletState = ref.read(paxWalletProvider);
      if (currentWalletState.wallet?.id != null) {
        await ref
            .read(paxWalletProvider.notifier)
            .updateSmartAccountAddress(
              walletId: currentWalletState.wallet!.id!,
              smartAccountAddress: smartAccountAddress,
            );
      }

      // Update PaxAccount
      await ref.read(paxAccountProvider.notifier).updateAccount({
        'eoWalletAddress': eoAddress,
        'smartAccountWalletAddress': smartAccountAddress,
      });

      await ref.read(participantProvider.notifier).updateProfile({
        'accountType': 'v2',
      });

      // Register wallet on-chain via Cloud Function
      final registryService = WalletRegistryService();
      try {
        final registryResult = await registryService.logWallet(
          eoWalletAddress: eoAddress,
        );
        final walletState = ref.read(paxWalletProvider);
        if (walletState.wallet?.id != null) {
          await ref
              .read(paxWalletProvider.notifier)
              .updateWithLogData(
                walletId: walletState.wallet!.id!,
                logTxnHash: registryResult.txnHash,
                logTimeCreated: registryResult.logTimeCreated,
              );
        }
      } catch (e) {
        // Surface registration failure so user can retry
        if (kDebugMode) {
          debugPrint('Registry log failed (non-blocking): $e');
        }
        viewModel.setError(
          'Wallet was created but could not be registered on-chain. '
          'You can try again from the next screen.',
        );
        return;
      }

      viewModel.setStep(WalletCreationStep.success);
      analytics.v2WalletCreationSuccess({
        'eoAddress': eoAddress,
      });

      // Register Pax Wallet as withdrawal method (before face verification)
      await ref
          .read(paxWalletProvider.notifier)
          .registerPaxWalletAsWithdrawalMethod();

      // Navigate to face verification after a brief delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        context.go(
          Routes.completeGoodDollarFaceVerification,
          extra: 'wallet_creation',
        );
      }
    } catch (e) {
      // Do not use ref here: widget may be unmounted after await (ref is invalid).
      viewModel.setError(e.toString());
      analytics.v2WalletCreationFailed({
        'error': e.toString().substring(0, e.toString().length.clamp(0, 99)),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(walletCreationProvider);
    final paxWalletState = ref.watch(paxWalletProvider);
    final hasWallet =
        paxWalletState.state == PaxWalletState.loaded &&
        paxWalletState.wallet != null &&
        paxWalletState.wallet!.eoAddress != null;

    if (hasWallet && _isWhitelisted == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkWhitelistIfNeeded(),
      );
    }
    if (!hasWallet && _isWhitelisted != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isWhitelisted = null);
      });
    }

    // Need verification if we have a wallet and it's not whitelisted (null = not checked yet, treat as needing verification)
    final hasWalletNeedingVerification = hasWallet && _isWhitelisted != true;

    return Scaffold(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              if (!hasWalletNeedingVerification)
                SvgPicture.asset(
                  'lib/assets/svgs/wallets/pax_wallet.svg',
                  width: 120,
                  height: 120,
                ).withPadding(bottom: 32),
              if (hasWalletNeedingVerification)
                _buildWalletAlreadyExistsContent()
              else
                _buildContent(state),
              const Spacer(),
              if (hasWalletNeedingVerification)
                _buildContinueToFaceVerificationButton().withPadding(bottom: 16)
              else
                _buildButton(state).withPadding(bottom: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWalletAlreadyExistsContent() {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            SvgPicture.asset(
              'lib/assets/svgs/wallets/pax_wallet.svg',
              width: 120,
              height: 120,
            ),
            Positioned(
              right: -8,
              top: -8,
              child: Container(
                decoration: BoxDecoration(
                  color: PaxColors.white,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(4),
                child: FaIcon(
                  FontAwesomeIcons.solidCircleCheck,
                  color: PaxColors.green,
                  size: 40,
                ),
              ),
            ),
          ],
        ).withPadding(bottom: 32),
        Text(
          'You now have a PaxWallet',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: PaxColors.deepPurple,
          ),
          textAlign: TextAlign.center,
        ).withPadding(bottom: 16),
        Text(
          'Complete face verification to add it as a withdrawal method and use it for payouts.',
          style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildContinueToFaceVerificationButton() {
    final wallet = ref.read(paxWalletProvider).wallet;
    final eoAddress = wallet?.eoAddress;
    final alreadyLogged = (wallet?.logTxnHash ?? '').isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_registryErrorMessage != null)
          Text(
            _registryErrorMessage!,
            style: TextStyle(fontSize: 14, color: PaxColors.red),
            textAlign: TextAlign.center,
          ).withPadding(bottom: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: PrimaryButton(
            onPressed: _isRegisteringWallet
                ? null
                : () async {
                    if (eoAddress == null) return;
                    if (alreadyLogged) {
                      context.go(
                        Routes.completeGoodDollarFaceVerification,
                        extra: 'wallet_creation',
                      );
                      return;
                    }
                    setState(() {
                      _isRegisteringWallet = true;
                      _registryErrorMessage = null;
                    });
                    try {
                      final registryService = WalletRegistryService();
                      final registryResult = await registryService.logWallet(
                        eoWalletAddress: eoAddress,
                      );
                      final walletState = ref.read(paxWalletProvider);
                      if (walletState.wallet?.id != null && mounted) {
                        await ref
                            .read(paxWalletProvider.notifier)
                            .updateWithLogData(
                              walletId: walletState.wallet!.id!,
                              logTxnHash: registryResult.txnHash,
                              logTimeCreated: registryResult.logTimeCreated,
                            );
                      }
                      if (mounted) {
                        setState(() => _isRegisteringWallet = false);
                        context.go(
                          Routes.completeGoodDollarFaceVerification,
                          extra: 'wallet_creation',
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          _isRegisteringWallet = false;
                          _registryErrorMessage =
                              'Could not register wallet. Please try again.';
                        });
                      }
                    }
                  },
            child: _isRegisteringWallet
                ? const CircularProgressIndicator(onSurface: true)
                : const Text('Continue to Face Verification'),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(WalletCreationState state) {
    switch (state.step) {
      case WalletCreationStep.info:
        return Column(
          children: [
            Text(
              'Create Your PaxWallet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: PaxColors.deepPurple,
              ),
              textAlign: TextAlign.center,
            ).withPadding(bottom: 16),
            Text(
              'Your PaxWallet is a secure wallet that stores your earnings. '
              'It will be backed up to your Google Drive for safekeeping.',
              style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case WalletCreationStep.creating:
        return Column(
          children: [
            const CircularProgressIndicator().withPadding(bottom: 24),
            Text(
              'Creating your wallet...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: PaxColors.deepPurple,
              ),
            ).withPadding(bottom: 8),
            Text(
              'This may take a moment. Please do not close the app.',
              style: TextStyle(fontSize: 14, color: PaxColors.darkGrey),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case WalletCreationStep.success:
        return Column(
          children: [
            FaIcon(
              FontAwesomeIcons.solidCircleCheck,
              color: PaxColors.green,
              size: 64,
            ).withPadding(bottom: 24),
            Text(
              'Wallet Created!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: PaxColors.deepPurple,
              ),
            ).withPadding(bottom: 8),
            Text(
              'Your PaxWallet has been created and backed up successfully.',
              style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
              textAlign: TextAlign.center,
            ).withPadding(bottom: 24),
            Image.asset(
              'lib/assets/images/goodid_fv_lady.png',
              height: 200,
              fit: BoxFit.contain,
            ).withPadding(bottom: 16),
            Text(
              'Next, you will complete a quick Face Verification with GoodDollar to secure your identity.',
              style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case WalletCreationStep.error:
        return Column(
          children: [
            FaIcon(
              FontAwesomeIcons.circleExclamation,
              color: PaxColors.red,
              size: 64,
            ).withPadding(bottom: 24),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: PaxColors.deepPurple,
              ),
            ).withPadding(bottom: 8),
            Text(
              state.errorMessage ?? 'An unexpected error occurred.',
              style: TextStyle(fontSize: 14, color: PaxColors.darkGrey),
              textAlign: TextAlign.center,
            ),
          ],
        );
    }
  }

  Widget _buildButton(WalletCreationState state) {
    switch (state.step) {
      case WalletCreationStep.info:
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: PrimaryButton(
            onPressed: _startWalletCreation,
            child: const Text('Create Wallet'),
          ),
        );
      case WalletCreationStep.creating:
      case WalletCreationStep.success:
        return const SizedBox.shrink();
      case WalletCreationStep.error:
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: PrimaryButton(
            onPressed: () {
              ref.read(walletCreationProvider.notifier).reset();
            },
            child: const Text('Try Again'),
          ),
        );
    }
  }
}
