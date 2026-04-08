/// Utility functions for handling version comparisons
class VersionUtil {
  /// Strips build metadata (+...) and pre-release tags (-...) from a version
  /// string, then splits into numeric parts, padding to at least 3 segments.
  static List<int> _parseVersion(String version) {
    final semverOnly = version.split('+').first.split('-').first;
    final parts = semverOnly.split('.');
    return List.generate(3, (i) {
      if (i < parts.length) return int.tryParse(parts[i]) ?? 0;
      return 0;
    });
  }

  /// Checks if the current version is lower than the minimum required version.
  ///
  /// [currentVersion] - The version of the app currently installed (e.g. '1.0.0')
  /// [minimumVersion] - The minimum version required to run the app (e.g. '1.1.0')
  ///
  /// Handles versions with build metadata (e.g. '1.0.0+42') and pre-release
  /// suffixes (e.g. '1.0.0-beta') by comparing only the numeric semver parts.
  ///
  /// Returns true if the current version is lower than the minimum required version,
  /// indicating that an update is needed.
  static bool isVersionLower(String currentVersion, String minimumVersion) {
    final current = _parseVersion(currentVersion);
    final minimum = _parseVersion(minimumVersion);

    for (int i = 0; i < 3; i++) {
      if (current[i] < minimum[i]) return true;
      if (current[i] > minimum[i]) return false;
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
    return isVersionLower(currentVersion, minimumVersion) ||
        isVersionLower(minimumVersion, currentVersion);
  }
}
