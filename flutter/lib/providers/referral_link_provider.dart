import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/services/branch_service.dart';

/// Single source of truth for the current user's referral link.
/// Generated once per participant; display and share should both use this value.
final referralLinkProvider = FutureProvider<String?>((ref) async {
  final participant = ref.watch(participantProvider).participant;
  if (participant == null || participant.id.isEmpty) return null;

  final response = await BranchService().generateReferralLink(
    referringParticipantId: participant.id,
    displayName: participant.displayName,
  );

  if (response.success && response.result is String) {
    return response.result as String;
  }
  return null;
});
