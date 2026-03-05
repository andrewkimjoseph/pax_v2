/// Utilities for formatting error messages for user-facing display.
class ErrorMessageUtil {
  ErrorMessageUtil._();

  /// Prefixes that are stripped from exception messages so the UI shows
  /// only the message content (e.g. "You need to complete face verification"
  /// instead of "Exception: You need to complete face verification").
  static const List<String> _prefixes = ['Exception:', 'Error:'];

  /// Returns a user-facing error string by stripping common exception/error
  /// prefixes. Pass the result of [error.toString()] or [FirebaseFunctionsException.message].
  static String userFacing(String message) {
    if (message.isEmpty) return message;
    String msg = message.trim();
    for (final prefix in _prefixes) {
      if (msg.length >= prefix.length &&
          msg.substring(0, prefix.length).toLowerCase() == prefix.toLowerCase()) {
        msg = msg.substring(prefix.length).trim();
        break;
      }
    }
    return msg;
  }
}
