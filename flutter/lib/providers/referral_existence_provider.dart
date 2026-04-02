import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';

/// Whether the current user appears as `referredParticipantId` on a referral doc.
final referralExistsForReferredParticipantProvider = FutureProvider<bool>((
  ref,
) async {
  final participant = ref.watch(participantProvider).participant;
  if (participant == null || participant.id.isEmpty) {
    if (kDebugMode) {
      debugPrint(
        '[ReferralExists] no participant — returning false',
      );
    }
    return false;
  }

  final repo = ref.watch(referralRepositoryProvider);
  return repo.referralExistsForReferredParticipant(participant.id);
});
