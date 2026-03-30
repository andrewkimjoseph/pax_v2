import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/services/branch_service.dart';

/// Single source of truth for the current user's referral link.
/// Generated once per participant; display and share should both use this value.
final referralLinkProvider = FutureProvider<String?>((ref) async {
  final participant = ref.watch(participantProvider).participant;
  if (participant == null || participant.id.isEmpty) {
    if (kDebugMode) {
      debugPrint('[ReferralLink] participant is null or has empty id — returning null');
    }
    return null;
  }

  if (kDebugMode) {
    debugPrint('[ReferralLink] Requesting referral link for participant ${participant.id}');
  }

  try {
    final response = await BranchService().generateReferralLink(
      referringParticipantId: participant.id,
    );

    if (kDebugMode) {
      debugPrint('[ReferralLink] BranchResponse — success: ${response.success}, '
          'result type: ${response.result?.runtimeType}, result: ${response.result}');
    }

    if (response.success && response.result is String) {
      return response.result as String;
    }

    if (kDebugMode) {
      debugPrint('[ReferralLink] Response was unsuccessful or result is not a String — returning null');
    }
    return null;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[ReferralLink] Exception during generateReferralLink: $e');
      debugPrint('[ReferralLink] Stack trace: $st');
    }
    rethrow;
  }
});
