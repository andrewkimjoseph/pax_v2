import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/services/donation/donation_service.dart';

final donationServiceProvider = Provider<DonationService>((ref) {
  return DonationService(
    paxAccountRepository: ref.watch(paxAccountRepositoryProvider),
  );
});
