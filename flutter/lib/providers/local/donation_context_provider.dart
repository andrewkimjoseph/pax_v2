import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/remote_config/goodcollective_config.dart';

class DonationContext {
  final int tokenId;
  final num balance;
  final num? amountToDonate;
  final GoodCollective? selectedGoodCollective;

  DonationContext({
    required this.tokenId,
    required this.balance,
    this.amountToDonate,
    this.selectedGoodCollective,
  });

  DonationContext copyWith({
    int? tokenId,
    num? balance,
    num? amountToDonate,
    GoodCollective? selectedGoodCollective,
  }) {
    return DonationContext(
      tokenId: tokenId ?? this.tokenId,
      balance: balance ?? this.balance,
      amountToDonate: amountToDonate ?? this.amountToDonate,
      selectedGoodCollective:
          selectedGoodCollective ?? this.selectedGoodCollective,
    );
  }
}

class DonationContextNotifier extends Notifier<DonationContext?> {
  @override
  DonationContext? build() => null;

  void setDonationContext(int tokenId, num balance) {
    state = DonationContext(tokenId: tokenId, balance: balance);
  }

  void setAmountToDonate(num amount) {
    if (state == null) return;
    state = state!.copyWith(amountToDonate: amount);
  }

  void setSelectedGoodCollective(GoodCollective? collective) {
    if (state == null) return;
    state = DonationContext(
      tokenId: state!.tokenId,
      balance: state!.balance,
      amountToDonate: state!.amountToDonate,
      selectedGoodCollective: collective,
    );
  }

  void clear() {
    state = null;
  }
}

final donationContextProvider =
    NotifierProvider<DonationContextNotifier, DonationContext?>(
      DonationContextNotifier.new,
    );
