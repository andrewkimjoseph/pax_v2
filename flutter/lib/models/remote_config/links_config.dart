import 'package:pax/utils/remote_config_constants.dart';
import 'package:pax/utils/secret_constants.dart' as secret_constants;

class LinksConfig {
  final String telegramChannelLink;
  final String whatsappChannelLink;
  final String minipayInviteLink;
  final String minipayInviteCode;
  final String goodWalletInviteLink;
  final String goodWalletInviteCode;
  final String goodPaxAppLink;
  final String drpcReferralLink;
  final String paxAppLinkFromSite;
  final String esiRegistrationLink;

  const LinksConfig({
    required this.telegramChannelLink,
    required this.whatsappChannelLink,
    required this.minipayInviteLink,
    required this.minipayInviteCode,
    required this.goodWalletInviteLink,
    required this.goodWalletInviteCode,
    required this.goodPaxAppLink,
    required this.drpcReferralLink,
    required this.paxAppLinkFromSite,
    required this.esiRegistrationLink,
  });

  factory LinksConfig.defaults() {
    return LinksConfig(
      telegramChannelLink: secret_constants.telegramChannelLink,
      whatsappChannelLink: secret_constants.whatsappChannelLink,
      minipayInviteLink: secret_constants.minipayInviteLink,
      minipayInviteCode: secret_constants.minipayInviteCode,
      goodWalletInviteLink: secret_constants.goodWalletInviteLink,
      goodWalletInviteCode: secret_constants.goodWalletInviteCode,
      goodPaxAppLink: secret_constants.goodPaxAppLink,
      drpcReferralLink: secret_constants.drpcReferralLink,
      paxAppLinkFromSite: secret_constants.paxAppLinkFromSite,
      esiRegistrationLink: secret_constants.esiRegistrationLink,
    );
  }

  factory LinksConfig.fromJson(Map<String, dynamic> json) {
    final defaults = LinksConfig.defaults();
    return LinksConfig(
      telegramChannelLink:
          _readString(json[RemoteConfigKeys.telegramChannelLink]) ??
          defaults.telegramChannelLink,
      whatsappChannelLink:
          _readString(json[RemoteConfigKeys.whatsappChannelLink]) ??
          defaults.whatsappChannelLink,
      minipayInviteLink:
          _readString(json[RemoteConfigKeys.minipayInviteLink]) ??
          defaults.minipayInviteLink,
      minipayInviteCode:
          _readString(json[RemoteConfigKeys.minipayInviteCode]) ??
          defaults.minipayInviteCode,
      goodWalletInviteLink:
          _readString(json[RemoteConfigKeys.goodWalletInviteLink]) ??
          defaults.goodWalletInviteLink,
      goodWalletInviteCode:
          _readString(json[RemoteConfigKeys.goodWalletInviteCode]) ??
          defaults.goodWalletInviteCode,
      goodPaxAppLink:
          _readString(json[RemoteConfigKeys.goodPaxAppLink]) ??
          defaults.goodPaxAppLink,
      drpcReferralLink:
          _readString(json[RemoteConfigKeys.drpcReferralLink]) ??
          defaults.drpcReferralLink,
      paxAppLinkFromSite:
          _readString(json[RemoteConfigKeys.paxAppLinkFromSite]) ??
          defaults.paxAppLinkFromSite,
      esiRegistrationLink:
          _readString(json[RemoteConfigKeys.esiRegistrationLink]) ??
          defaults.esiRegistrationLink,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      RemoteConfigKeys.telegramChannelLink: telegramChannelLink,
      RemoteConfigKeys.whatsappChannelLink: whatsappChannelLink,
      RemoteConfigKeys.minipayInviteLink: minipayInviteLink,
      RemoteConfigKeys.minipayInviteCode: minipayInviteCode,
      RemoteConfigKeys.goodWalletInviteLink: goodWalletInviteLink,
      RemoteConfigKeys.goodWalletInviteCode: goodWalletInviteCode,
      RemoteConfigKeys.goodPaxAppLink: goodPaxAppLink,
      RemoteConfigKeys.drpcReferralLink: drpcReferralLink,
      RemoteConfigKeys.paxAppLinkFromSite: paxAppLinkFromSite,
      RemoteConfigKeys.esiRegistrationLink: esiRegistrationLink,
    };
  }

  static String? _readString(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }
}
