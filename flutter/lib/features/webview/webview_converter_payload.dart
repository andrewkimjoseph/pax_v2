/// Payload for the G$ converter WebView route.
/// Passed as [GoRouterState.extra] when pushing [Routes.webviewConverter].
class WebViewConverterPayload {
  const WebViewConverterPayload({
    required this.url,
    required this.valueToInject,
    this.selector = '#base',
  });

  final String url;
  final num valueToInject;
  final String selector;
}
