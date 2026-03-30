// lib/providers/withdraw/withdraw_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pax/models/local/withdrawal_state_model.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/providers/local/pax_wallet_view_provider.dart';
import 'package:pax/providers/local/withdrawal_service_provider.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart';
import 'package:pax/providers/withdrawal_method_connection/withdrawal_method_connection_provider.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/services/withdrawal/withdrawal_service.dart';
import 'package:pax/services/wallet/smart_account_service.dart';
import 'package:pax/services/withdrawal/withdrawal_method_connection_service.dart';
import 'package:pax/services/notifications/notification_service.dart';
import 'package:pax/providers/fcm/fcm_provider.dart';
import 'package:pax/utils/currency_symbol.dart';
import 'package:pax/models/firestore/withdrawal/withdrawal_model.dart';
import 'package:pax/services/blockchain/blockchain_service.dart';
import 'package:pax/utils/error_message_util.dart';

class WithdrawNotifier extends Notifier<WithdrawStateModel> {
  late final WithdrawalService _withdrawalService;
  late final WithdrawalMethodConnectionService _withdrawalMethodService;
  final NotificationService _notificationService = NotificationService();

  @override
  WithdrawStateModel build() {
    _withdrawalService = ref.watch(withdrawalServiceProvider);
    _withdrawalMethodService = ref.watch(withdrawalMethodConnectionProvider);
    return WithdrawStateModel();
  }

  Future<void> withdrawToWithdrawalMethod({
    required String paymentMethodId,
    required double amountToWithdraw,
    required int tokenId,
    required String currencyAddress,
    required String selectedWalletAddress,
    required int predefinedId,
    required String walletName,
    int decimals = 18,
  }) async {
    if (state.isSubmitting) return; // Prevent multiple submissions

    state = state.copyWith(
      state: WithdrawState.submitting,
      isSubmitting: true,
      errorMessage: null,
    );

    try {
      final auth = ref.read(authProvider);
      final userId = auth.user.uid;
      final paxAccountState = ref.read(paxAccountProvider);
      final paxAccount = paxAccountState.account;

      if (kDebugMode) {
        debugPrint(
          '[WithdrawNotifier] Withdrawing: $amountToWithdraw tokens to payment method $paymentMethodId',
        );
        debugPrint(
          '[WithdrawNotifier] Using currency address: $currencyAddress with $decimals decimals',
        );
      }

      // Check if account has a payout wallet (V1: contract; V2: smart account or EOA)
      if (paxAccount?.payoutWalletAddress == null) {
        throw Exception('Pax account wallet address not found');
      }

      final hasBalance = await BlockchainService.hasSufficientBalance(
        paxAccount!.payoutWalletAddress!,
        currencyAddress,
        amountToWithdraw,
        decimals,
      );

      if (!hasBalance) {
        throw Exception('Insufficient contract balance for withdrawal');
      }

      // Check if at least one withdrawal method is GoodDollar verified
      final withdrawalMethods =
          ref.read(withdrawalMethodsProvider).withdrawalMethods;
      bool hasVerifiedMethod = false;

      for (final withdrawalMethod in withdrawalMethods) {
        final isVerified = await _withdrawalMethodService.isGoodDollarVerified(
          withdrawalMethod.walletAddress,
          true, // checkWhitelist = true
        );
        if (isVerified) {
          hasVerifiedMethod = true;
          break;
        }
      }

      // If no withdrawal method is verified, fail the withdrawal
      if (!hasVerifiedMethod) {
        final isV2 = paxAccount.isV2;
        final faceVerificationMessage =
            isV2
                ? 'You need to complete face verification in PaxWallet.'
                : 'You need to complete face verification in MiniPay or GoodWallet.';
        throw Exception(faceVerificationMessage);
      }

      // Call the withdrawal service
      Map<String, String>? v2EncryptedParams;
      String? paymentMethodAddressParam;
      final isV2 = paxAccount.isV2;
      if (isV2) {
        final credState = ref.read(walletCredentialsProvider);
        final credentials = credState.credentials;
        if (credentials == null) {
          throw Exception(
            'Pax Wallet not loaded. Please open Pax Wallet or restore from backup and try again.',
          );
        }
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('Not signed in');
        final sessionKey = await user.getIdToken(true);
        if (sessionKey == null) throw Exception('Failed to get session token');
        final smartAccountService = SmartAccountService();
        v2EncryptedParams = smartAccountService.getV2EncryptedParamsForBackend(
          credentials: credentials,
          sessionKey: sessionKey,
        );
        paymentMethodAddressParam = selectedWalletAddress;
      }

      final result = await _withdrawalService.withdrawToPaymentMethod(
        userId: userId,
        paymentMethodId: paymentMethodId,
        amountToWithdraw: amountToWithdraw,
        tokenId: tokenId,
        currencyAddress: currencyAddress,
        decimals: decimals,
        predefinedId: predefinedId,
        paymentMethodAddress: paymentMethodAddressParam,
        v2EncryptedParams: v2EncryptedParams,
      );

      if (kDebugMode) {
        debugPrint(
          '[WithdrawNotifier] Withdrawal transaction successful: ${result['txnHash']}',
        );
      }

      // Update state to success
      state = state.copyWith(
        state: WithdrawState.success,
        isSubmitting: false,
        txnHash: result['txnHash'],
        withdrawalId: result['withdrawalId'],
      );

      ref.read(analyticsProvider).withdrawalComplete({
        "amount": amountToWithdraw,
        "tokenId": tokenId,
        "selectedPaymentMethodId": paymentMethodId,
        "contractAddress": paxAccount.payoutWalletAddress,
        "currencyAddress": currencyAddress,
        "selectedWalletAddress": selectedWalletAddress,
      });

      // Send notification about successful withdrawal
      final fcmToken = await ref.read(fcmTokenProvider.future);
      if (fcmToken != null) {
        final currencyName = CurrencySymbolUtil.getNameForCurrency(tokenId);
        final currencySymbol = CurrencySymbolUtil.getSymbolForCurrency(
          currencyName,
        );

        await _notificationService.sendWithdrawalSuccessNotification(
          token: fcmToken,
          withdrawalData: {
            'amount': amountToWithdraw,
            'currencySymbol': currencySymbol,
            'txnHash': result['txnHash'],
          },
          wallet: walletName,
        );
      }

      // Refresh activities to show the new withdrawal
      ref.invalidate(activityRepositoryProvider);
      await ref.read(paxAccountProvider.notifier).syncBalancesFromBlockchain();
      // If wallet is PaxWallet then refresh balance
      if (isV2 && walletName.toLowerCase().contains('paxwallet')) {
        await ref
            .read(paxWalletViewProvider.notifier)
            .fetchBalance(selectedWalletAddress, forceRefresh: true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Error] Error withdrawing tokens: $e');
      }

      ref.read(analyticsProvider).withdrawalFailed({
        "errorMessage": e.toString().substring(
          0,
          e.toString().length.clamp(0, 99),
        ),
      });

      state = state.copyWith(
        state: WithdrawState.error,
        errorMessage: ErrorMessageUtil.userFacing(e.toString()),
        isSubmitting: false,
      );
    }
  }

  void resetState() {
    state = WithdrawStateModel();
  }
}

final withdrawProvider = NotifierProvider<WithdrawNotifier, WithdrawStateModel>(
  () {
    return WithdrawNotifier();
  },
);

// Stream provider for withdrawals
final withdrawalsStreamProvider = StreamProvider.family
    .autoDispose<List<Withdrawal>, String?>((ref, participantId) {
      final withdrawalRepository = ref.watch(withdrawalRepositoryProvider);

      return withdrawalRepository.streamWithdrawalsForParticipant(
        participantId,
      );
    });
