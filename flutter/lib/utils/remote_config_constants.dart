/// Constants for remote configuration keys to avoid typos and maintain consistency
class RemoteConfigKeys {
  // Feature flag keys
  /// Controls whether the wallet feature is available in the app.
  /// When false, all wallet-related functionality will be hidden.
  /// Key: 'is_wallet_available'
  static const String isWalletAvailable = 'is_wallet_available';

  /// Controls whether the achievements feature is available in the app.
  /// When false, the achievements tab and related functionality will be hidden.
  /// Key: 'are_achievements_available'
  static const String areAchievementsAvailable = 'are_achievements_available';

  /// Controls whether the tasks feature is available in the app.
  /// When false, the tasks tab and related functionality will be hidden.
  /// Key: 'are_tasks_available'
  static const String areTasksAvailable = 'are_tasks_available';

  /// Controls whether task completion tracking is available.
  /// When false, users won't be able to mark tasks as complete.
  /// Key: 'are_tasks_completions_available'
  static const String areTasksCompletionsAvailable =
      'are_tasks_completions_available';

  /// Controls whether the withdrawal method connection feature is available in the app.
  /// When false, users will not be able to connect or manage withdrawal methods.
  /// Key: 'is_withdrawal_method_connection_available'
  static const String isWithdrawalMethodConnectionAvailable =
      'is_withdrawal_method_connection_available';

  /// Controls whether the "V2 is Available" upgrade banner is shown to V1 users.
  /// When false, the banner is hidden.
  /// Key: 'is_v2_upgrade_available'
  static const String isV2UpgradeAvailable = 'is_v2_upgrade_available';

  /// Controls whether the "open custom app by URL" link in the Apps view is shown.
  /// When false, the link icon is hidden.
  /// Key: 'is_custom_app_access_feature_available'
  static const String isCustomAppAccessFeatureAvailable =
      'is_custom_app_access_feature_available';

  /// Controls whether the V2 referral program card is shown on the account screen.
  /// When false, the card is hidden (unless in debug mode).
  /// Key: 'is_v2_referral_feature_available'
  static const String isV2ReferralFeatureAvailable =
      'is_v2_referral_feature_available';

  /// Controls whether the "Vote for Canvassing" dashboard banner is shown.
  /// When false, the banner is hidden (unless in debug mode).
  /// Key: 'is_vote_for_canvassing_available'
  static const String isVoteForCanvassingAvailable =
      'is_vote_for_canvassing_available';

  /// Controls whether new users can create a V2 wallet during onboarding.
  /// When false, users are forced into the V1 onboarding path.
  /// Key: 'is_v2_wallet_creation_available'
  static const String isV2WalletCreationAvailable =
      'is_v2_wallet_creation_available';

  /// Controls whether the current balance card is shown in dashboard/account views.
  /// When false, the card is hidden (unless in debug mode).
  /// Key: 'is_current_balance_card_available'
  static const String isCurrentBalanceCardAvailable =
      'is_current_balance_card_available';

  /// Controls whether the engagement rewards card is shown.
  /// When false, the card is hidden (unless in debug mode).
  /// Key: 'is_engagement_reward_card_available'
  static const String isEngagementRewardCardAvailable =
      'is_engagement_reward_card_available';

  // App version config keys
  /// The current latest version of the app available in stores.
  /// Used to inform users about available updates.
  /// Key: 'current_version'
  static const String currentVersion = 'current_version';

  /// Whether users should be forced to update their app.
  /// When true, users cannot use the app until they update.
  /// Key: 'force_update'
  static const String forceUpdate = 'force_update';

  /// The message shown to users when an update is available.
  /// Can include information about new features or bug fixes.
  /// Key: 'update_message'
  static const String updateMessage = 'update_message';

  /// The URL where users can download the latest version of the app.
  /// Typically points to the app store listing.
  /// Key: 'update_url'
  static const String updateUrl = 'update_url';

  // Maintenance config keys
  /// Whether the app is currently under maintenance.
  /// When true, users will see a maintenance message and may have limited functionality.
  /// Key: 'is_under_maintenance'
  static const String isUnderMaintenance = 'is_under_maintenance';

  /// The message shown to users when the app is under maintenance.
  /// Should include information about when the app will be available again.
  /// Key: 'maintenance_message'
  static const String maintenanceMessage = 'maintenance_message';

  // Remote config parameter names
  /// The name of the remote config parameter containing app version configuration.
  /// Contains all version-related settings as a JSON string.
  /// Key: 'app_version_config'
  static const String appVersionConfig = 'app_version_config';

  /// The name of the remote config parameter containing maintenance configuration.
  /// Contains maintenance status and message as a JSON string.
  /// Key: 'maintenance_config'
  static const String maintenanceConfig = 'maintenance_config';

  /// The name of the remote config parameter containing feature flags.
  /// Contains boolean flags for enabling/disabling features as a JSON string.
  /// Key: 'feature_flags'
  static const String featureFlags = 'feature_flags';

  // Miniapps config keys
  /// The name of the remote config parameter containing miniapps configuration.
  /// Contains are_miniapps_available and miniapps array as a JSON string.
  /// Key: 'miniapps_config'
  static const String miniappsConfig = 'miniapps_config';

  /// The name of the remote config parameter containing GoodCollective donation configuration.
  /// Contains is_donation_available and goodcollectives array as a JSON string.
  /// Key: 'goodcollective_config'
  static const String goodcollectiveConfig = 'goodcollective_config';

  /// The name of the remote config parameter containing achievement reward amounts.
  /// Contains achievement amount overrides as a JSON string.
  /// Key: 'achievement_amounts'
  static const String achievementAmounts = 'achievement_amounts';

  /// The name of the remote config parameter containing Pax Wallet configuration.
  /// Contains wallet-specific settings (e.g. auto top-up threshold) as JSON.
  /// Key: 'pax_wallet_config'
  static const String paxWalletConfig = 'pax_wallet_config';

  /// The name of the remote config parameter containing external links config.
  /// Contains social/invite URLs and invite codes as JSON.
  /// Key: 'links_config'
  static const String linksConfig = 'links_config';

  /// Auto top-up threshold key inside pax_wallet_config JSON.
  /// Key: 'auto_topup_threshold'
  static const String autoTopupThreshold = 'auto_top_up_threshold';

  /// Version key inside pax_wallet_config JSON.
  /// Key: 'version'
  static const String paxWalletVersion = 'version';

  /// Chain id key inside pax_wallet_config JSON.
  /// Key: 'chain_id'
  static const String chainId = 'chain_id';

  /// RPC URL key inside pax_wallet_config JSON.
  /// Key: 'rpc_url'
  static const String rpcUrl = 'rpc_url';

  // links_config keys
  static const String telegramChannelLink = 'telegram_channel_link';
  static const String whatsappChannelLink = 'whatsapp_channel_link';
  static const String minipayInviteLink = 'minipay_invite_link';
  static const String minipayInviteCode = 'minipay_invite_code';
  static const String goodWalletInviteLink = 'goodwallet_invite_link';
  static const String goodWalletInviteCode = 'goodwallet_invite_code';
  static const String goodPaxAppLink = 'good_pax_app_link';
  static const String engagementRewardsLink = 'engagement_rewards_link';
  static const String faceVerificationLink = 'face_verification_link';
  static const String drpcReferralLink = 'drpc_referral_link';
  static const String paxAppLinkFromSite = 'pax_app_link_from_site';
  static const String esiRegistrationLink = 'esi_registration_link';

  /// Whether the miniapps feature is enabled for V2 users.
  /// Key: 'are_miniapps_available'
  static const String areMiniappsAvailable = 'are_miniapps_available';

  /// Array key inside miniapps_config JSON for the list of apps.
  /// Key: 'miniapps'
  static const String miniapps = 'miniapps';

  /// Per-app keys when parsing miniapps array items.
  static const String miniappId = 'id';
  static const String miniappName = 'name';
  static const String miniappTitle = 'title';
  static const String miniappImageURI = 'imageURI';
  static const String miniappUrl = 'url';
  static const String isMiniappAvailable = 'is_miniapp_available';

  // GoodCollective config keys
  static const String isDonationAvailable = 'is_donation_available';
  static const String goodcollectives = 'goodcollectives';
  static const String goodcollectiveId = 'id';
  static const String goodcollectiveName = 'name';
  static const String isGoodcollectiveAvailable = 'is_goodcollective_available';
  static const String donationContract = 'donationContract';
  static const String coverURI = 'coverURI';
}
