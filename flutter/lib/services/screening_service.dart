// This service manages the participant screening process:
// - Handles participant screening through Firebase Functions
// - Manages screening state and context through Riverpod providers
// - Updates activity feed after successful screening
// - Provides error handling and state management for the screening process

// lib/services/screening_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/firestore/screening/screening_model.dart';
import 'package:pax/utils/error_message_util.dart';
import 'package:pax/models/firestore/task_completion/task_completion_model.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/tasks/task_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/providers/local/screening_state_provider.dart';
import 'package:pax/providers/local/screenings_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/local/screening_context/screening_context_provider.dart';
import 'package:pax/providers/withdrawal_method_connection/withdrawal_method_connection_provider.dart';
import 'package:pax/services/notifications/notification_service.dart';

class ScreeningService {
  final Ref ref;

  ScreeningService(this.ref);

  /// Checks if a participant has already been screened for a specific task.
  /// Returns a ScreeningResult if a completed screening exists, null otherwise.
  Future<ScreeningResult?> checkIfParticipantIsAlreadyScreenedForTask({
    required String participantId,
    required String taskId,
  }) async {
    // Check if screening already exists in Firestore
    final existingScreeningQuery =
        await FirebaseFirestore.instance
            .collection('screenings')
            .where('participantId', isEqualTo: participantId)
            .where('taskId', isEqualTo: taskId)
            .limit(1)
            .get();

    if (existingScreeningQuery.docs.isEmpty) {
      return null;
    }

    final existingScreeningDoc = existingScreeningQuery.docs.first;
    final existingScreening = Screening.fromFirestore(existingScreeningDoc);

    // Check if the screening is completed (has txnHash, signature, and nonce)
    if (!existingScreening.isCompleted() ||
        !existingScreening.hasValidSignature()) {
      return null;
    }

    // Fetch the related task completion
    final taskCompletionQuery =
        await FirebaseFirestore.instance
            .collection('task_completions')
            .where('screeningId', isEqualTo: existingScreening.id)
            .limit(1)
            .get();

    String? taskCompletionId;
    if (taskCompletionQuery.docs.isNotEmpty) {
      final taskCompletion = TaskCompletion.fromFirestore(
        taskCompletionQuery.docs.first,
      );
      taskCompletionId = taskCompletion.id;
    }

    // Create ScreeningResult from existing screening data
    // Note: participantProxy is not stored in Firestore, so we use an empty string
    // as a placeholder. The actual proxy address can be derived from serverWalletId
    // if needed in the future.
    return ScreeningResult(
      participantProxy: '', // Not stored in Firestore, using placeholder
      taskId: existingScreening.taskId ?? taskId,
      signature: existingScreening.signature ?? '',
      nonce: existingScreening.nonce ?? '',
      txnHash: existingScreening.txnHash ?? '',
      screeningId: existingScreening.id,
      taskCompletionId: taskCompletionId ?? '',
    );
  }

  /// Ensures the participant has at least one GoodDollar-verified withdrawal method
  /// (face verification). Call this before starting screening.
  /// Throws if no verified method exists.
  Future<void> ensureHasVerifiedWithdrawalMethod(String participantId) async {
    await ref.read(withdrawalMethodsProvider.notifier).refresh(participantId);

    final withdrawalMethods =
        ref.read(withdrawalMethodsProvider).withdrawalMethods;

    final withdrawalService = ref.read(withdrawalMethodConnectionProvider);
    bool hasVerifiedMethod = false;

    for (final withdrawalMethod in withdrawalMethods) {
      final isVerified = await withdrawalService.isGoodDollarVerified(
        withdrawalMethod.walletAddress,
        true, // checkWhitelist = true
      );
      if (isVerified) {
        hasVerifiedMethod = true;
        break;
      }
    }

    if (!hasVerifiedMethod) {
      final paxAccount = ref.read(paxAccountProvider).account;
      final isV2 = paxAccount?.isV2 ?? false;
      final faceVerificationMessage =
          isV2
              ? 'You need to complete face verification in PaxWallet.'
              : 'You need to complete face verification in MiniPay or GoodWallet.';
      throw Exception(faceVerificationMessage);
    }
  }

  Future<void> screenParticipant({
    String? serverWalletId,
    required String taskId,
    required String participantId,
    Map<String, String>? v2EncryptedParams,
  }) async {
    try {
      // Update state to loading
      ref.read(screeningProvider.notifier).startScreening();

      // Check if screening already exists in Firestore
      final existingScreeningResult =
          await checkIfParticipantIsAlreadyScreenedForTask(
            participantId: participantId,
            taskId: taskId,
          );

      if (existingScreeningResult != null) {
        await ref
            .read(screeningContextProvider.notifier)
            .fetchScreeningById(existingScreeningResult.screeningId);

        final screening = ref.read(screeningContextProvider)?.screening;
        if (screening?.timeCreated != null) {
          await NotificationService().scheduleTaskCooldownReminders(
            screening!.timeCreated!.toDate(),
          );
        }

        ref
            .read(screeningContextProvider.notifier)
            .setScreeningResult(existingScreeningResult);

        // Update state to complete with the result
        ref
            .read(screeningProvider.notifier)
            .completeScreening(existingScreeningResult);

        ref.invalidate(activityRepositoryProvider);
        ref.invalidate(participantScreeningsStreamProvider);
        ref.invalidate(availableTasksStreamProvider(participantId));

        ref.read(analyticsProvider).screeningComplete({
          "taskId": taskId,
          "screeningId": existingScreeningResult.screeningId,
          "txnHash": existingScreeningResult.txnHash,
          "signature": existingScreeningResult.signature,
          "nonce": existingScreeningResult.nonce,
          "taskCompletionId": existingScreeningResult.taskCompletionId,
        });

        return; // Early return with existing screening data
      }

      // Call the Firebase function
      final httpsCallable = FirebaseFunctions.instance.httpsCallable(
        'screenParticipantProxy',
      );
      final payload = <String, dynamic>{
        'taskId': taskId,
        'participantId': participantId,
      };
      if (v2EncryptedParams != null) {
        payload['encryptedPrivateKey'] =
            v2EncryptedParams['encryptedPrivateKey'];
        payload['sessionKey'] = v2EncryptedParams['sessionKey'];
        payload['eoWalletAddress'] = v2EncryptedParams['eoWalletAddress'];
      } else if (serverWalletId != null && serverWalletId.isNotEmpty) {
        payload['serverWalletId'] = serverWalletId;
      } else {
        throw Exception(
          'Either serverWalletId (V1) or v2EncryptedParams (V2) is required.',
        );
      }
      final result = await httpsCallable.call(payload);

      // Extract data from the result
      final data = result.data as Map<String, dynamic>;

      // Create ScreeningResult object
      final screeningResult = ScreeningResult(
        participantProxy: data['participantProxy'],
        taskId: data['taskId'],
        signature: data['signature'],
        nonce: data['nonce'],
        txnHash: data['txnHash'],
        screeningId: data['screeningId'],
        taskCompletionId: data['taskCompletionId'],
      );

      await ref
          .read(screeningContextProvider.notifier)
          .fetchScreeningById(screeningResult.screeningId);

      final screening = ref.read(screeningContextProvider)?.screening;
      if (screening?.timeCreated != null) {
        await NotificationService().scheduleTaskCooldownReminders(
          screening!.timeCreated!.toDate(),
        );
      }

      ref
          .read(screeningContextProvider.notifier)
          .setScreeningResult(screeningResult);

      // Update state to complete with the result
      ref.read(screeningProvider.notifier).completeScreening(screeningResult);

      ref.invalidate(activityRepositoryProvider);
      ref.invalidate(participantScreeningsStreamProvider);
      ref.invalidate(availableTasksStreamProvider(participantId));

      ref.read(analyticsProvider).screeningComplete({
        "taskId": taskId,
        "taskManagerContractAddress": "CanvassingTaskManager",
        "screeningId": screeningResult.screeningId,
        "txnHash": screeningResult.txnHash,
        "signature": screeningResult.signature,
        "nonce": screeningResult.nonce,
        "taskCompletionId": screeningResult.taskCompletionId,
      });
    } catch (e) {
      // Update state to error with error message
      ref
          .read(screeningProvider.notifier)
          .setError(
            ErrorMessageUtil.userFacing(
              e is FirebaseFunctionsException
                  ? e.message ?? e.toString()
                  : e.toString(),
            ),
          );
      rethrow;
    }
  }
}

final screeningServiceProvider = Provider<ScreeningService>((ref) {
  return ScreeningService(ref);
});
