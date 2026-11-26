import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/demo_mode.dart';
import '../services/iserv_session.dart';

/// webview_flutter kodiert Cookie-Werte beim Setzen per
/// `Uri.encodeComponent`. IServ-Cookies sind aber schon kodiert
/// (z. B. `%3A` für ":") – ohne vorheriges Dekodieren käme `%253A` an und
/// IServ lehnt die Session ab ("Missing colon in cookie").
String webViewCookieValue(String rawValue) {
  try {
    return Uri.decodeComponent(rawValue);
  } on ArgumentError {
    return rawValue;
  }
}

/// Zeigt eine IServ-Seite (z. B. eine Aufgabe) direkt in der App – mit
/// der bestehenden IServ-Anmeldung, ohne in eine andere App zu wechseln.
class IservWebPage extends StatefulWidget {
  const IservWebPage({
    super.key,
    required this.url,
    required this.session,
    this.title = 'IServ',
  });

  final String url;
  final IservSession session;
  final String title;

  @override
  State<IservWebPage> createState() => _IservWebPageState();
}

class _IservWebPageState extends State<IservWebPage> {
  late final WebViewController _controller;
  int _progress = 0;

  /// Im Demo-Modus gibt es keine echte IServ-Seite zum Anzeigen.
  final bool _demo = DemoMode.active.value;

  @override
  void initState() {
    super.initState();
    if (_demo) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          // Innerhalb von IServ bleiben; fremde Links im Browser öffnen.
          onNavigationRequest: (request) {
            if (widget.session.isIservUrl(request.url)) {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
        ),
      );
    _load();
  }

  /// Übernimmt die IServ-Session der App, damit kein zweiter Login nötig ist.
  Future<void> _load() async {
    final host = Uri.parse(widget.session.baseUrl).host;
    final cookieManager = WebViewCookieManager();
    for (final cookie in widget.session.cookies.entries) {
      await cookieManager.setCookie(
        WebViewCookie(
          name: cookie.key,
          value: webViewCookieValue(cookie.value),
          domain: host,
          path: '/',
        ),
      );
    }
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    if (_demo) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Demo-Modus: Hier würde die IServ-Seite angezeigt, auf der du '
              'zum Beispiel Dateien abgibst.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return PopScope(
      // Zurück-Geste blättert erst innerhalb von IServ zurück.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, overflow: TextOverflow.ellipsis),
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress / 100),
                )
              : null,
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
