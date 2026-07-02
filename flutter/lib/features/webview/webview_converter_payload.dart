/// Payload for the G$ converter WebView route.
/// Passed as [GoRouterState.extra] when pushing [Routes.webviewConverter].
class WebViewConverterPayload {
  const WebViewConverterPayload({required this.url});

  final String url;
}
