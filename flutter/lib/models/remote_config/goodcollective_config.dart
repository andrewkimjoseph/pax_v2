import 'package:flutter/foundation.dart';

@immutable
class GoodCollective {
  final int id;
  final String name;
  final bool isGoodcollectiveAvailable;
  final String donationContract;
  final String? coverURI;

  const GoodCollective({
    required this.id,
    required this.name,
    required this.isGoodcollectiveAvailable,
    required this.donationContract,
    this.coverURI,
  });

  factory GoodCollective.fromJson(Map<String, dynamic> json) {
    return GoodCollective(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: (json['name'] as String?) ?? '',
      isGoodcollectiveAvailable: json['is_goodcollective_available'] == true,
      donationContract: (json['donationContract'] as String?) ?? '',
      coverURI: (json['coverURI'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_goodcollective_available': isGoodcollectiveAvailable,
      'donationContract': donationContract,
      'coverURI': coverURI,
    };
  }
}

@immutable
class GoodCollectiveConfig {
  final bool isDonationAvailable;
  final List<GoodCollective> goodcollectives;

  const GoodCollectiveConfig({
    required this.isDonationAvailable,
    required this.goodcollectives,
  });

  factory GoodCollectiveConfig.fromJson(Map<String, dynamic> json) {
    final rawList = json['goodcollectives'];
    final List<GoodCollective> list = [];

    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          final collective = GoodCollective.fromJson(item);
          if (collective.isGoodcollectiveAvailable &&
              collective.donationContract.isNotEmpty) {
            list.add(collective);
          }
        }
      }
    }

    return GoodCollectiveConfig(
      isDonationAvailable: json['is_donation_available'] == true,
      goodcollectives: list,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_donation_available': isDonationAvailable,
      'goodcollectives': goodcollectives.map((e) => e.toJson()).toList(),
    };
  }
}
