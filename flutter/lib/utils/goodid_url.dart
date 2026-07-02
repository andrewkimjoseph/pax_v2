bool isGoodIdUrl(String? url, String hostLinkPrefix) {
  if (url == null || hostLinkPrefix.isEmpty) return false;
  final prefix =
      hostLinkPrefix.endsWith('/') ? hostLinkPrefix : '$hostLinkPrefix/';
  return url.startsWith(prefix);
}
