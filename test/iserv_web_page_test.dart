import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/pages/iserv_web_page.dart';

void main() {
  test('Cookie-Wert kommt nach der Kodierung durch das Plugin unverändert an', () {
    // So kodiert webview_flutter_android den Wert beim Setzen.
    String plugin(String value) => Uri.encodeComponent(value);

    const raw = 'abc123%3Adef456%3A789';
    expect(plugin(webViewCookieValue(raw)), raw);
    expect(plugin(webViewCookieValue('a1b2-c3d4-e5')), 'a1b2-c3d4-e5');
  });

  test('ungültige Kodierung wird unverändert übernommen', () {
    expect(webViewCookieValue('50%'), '50%');
  });
}
