/// Utility functions for handling version comparisons
class VersionUtil {
  /// Checks if the current version is lower than the minimum required version.
  ///
  /// [currentVersion] - The version of the app currently installed (e.g. '1.0.0')
  /// [minimumVersion] - The minimum version required to run the app (e.g. '1.1.0')
  ///
  /// Returns true if the current version is lower than the minimum required version,
  /// indicating that an update is needed.
  ///
  /// Example:
  /// ```dart
  /// // Current app version is 1.0.0, minimum required is 1.1.0
  /// VersionUtil.isVersionLower('1.0.0', '1.1.0') // returns true (update needed)
  ///
  /// // Current app version is 1.1.0, minimum required is 1.0.0
  /// VersionUtil.isVersionLower('1.1.0', '1.0.0') // returns false (no update needed)
  ///
  /// // Current app version is 1.0.0, minimum required is 1.0.0
  /// VersionUtil.isVersionLower('1.0.0', '1.0.0') // returns false (no update needed)
  /// ```
  static bool isVersionLower(String currentVersion, String minimumVersion) {
    final currentParts = currentVersion.split('.');
    final minimumParts = minimumVersion.split('.');

    for (int i = 0; i < 3; i++) {
      final currentNum = int.tryParse(currentParts[i]);
      final minimumNum = int.tryParse(minimumParts[i]);

      if (currentNum == null || minimumNum == null) {
        throw Exception('Invalid version format');
      }

      if (currentNum < minimumNum) return true;
      if (currentNum > minimumNum) return false;
    }

    return false;
  }

  /// Returns true if the two versions are not the same.
  ///
  /// This uses semantic comparison rather than simple string equality, so that:
  /// - '1.0.0' and '1.0.0' are considered the same
  /// - '1.0.0' and '1.0.1' are considered different
  /// - '1.1.0' and '1.0.0' are considered different
  static bool isVersionNotTheSame(
    String currentVersion,
    String minimumVersion,
  ) {
    // Different if current is lower OR minimum is lower (i.e. they are not equal)
    return isVersionLower(currentVersion, minimumVersion) ||
        isVersionLower(minimumVersion, currentVersion);
  }
}
