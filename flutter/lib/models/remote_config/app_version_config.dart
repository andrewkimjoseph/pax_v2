import 'package:flutter/foundation.dart';

@immutable
class AppVersionConfig {
  final String currentVersion;
  final bool forceUpdate;
  final String updateMessage;
  final String updateUrl;

  const AppVersionConfig({
    required this.currentVersion,
    required this.forceUpdate,
    required this.updateMessage,
    required this.updateUrl,
  });

  factory AppVersionConfig.fromJson(Map<String, dynamic> json) {
    return AppVersionConfig(
      currentVersion: json['current_version'] as String,
      forceUpdate: json['force_update'] as bool,
      updateMessage: json['update_message'] as String,
      updateUrl: json['update_url'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_version': currentVersion,
      'force_update': forceUpdate,
      'update_message': updateMessage,
      'update_url': updateUrl,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppVersionConfig &&
        other.currentVersion == currentVersion &&
        other.forceUpdate == forceUpdate &&
        other.updateMessage == updateMessage &&
        other.updateUrl == updateUrl;
  }

  @override
  int get hashCode {
    return Object.hash(
      currentVersion,
      forceUpdate,
      updateMessage,
      updateUrl,
    );
  }
}
