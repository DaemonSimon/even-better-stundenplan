import 'package:http/http.dart' as http;

import 'demo_mode.dart';
import 'http_timeout.dart';

/// HTTP-Schicht für virtueller-stundenplan.org.
/// Kümmert sich nur um Requests; Parsing passiert im StundenplanParser.
class StundenplanApi {
  StundenplanApi({http.Client? client, String? userAgent})
    : _client = client ?? DemoAwareClient(),
      _userAgent =
          userAgent ??
          'BetterStundenplan/1.5.1 (+https://github.com/LarvenStein/better-stundenplan)';

  final http.Client _client;
  final String _userAgent;

  static const String _baseUrl =
      'https://virtueller-stundenplan.org/page-5/index.php';

  /// Lädt die komplette Woche für ein Datum (Format dd.MM.yyyy).
  /// Die Seite liefert die ganze Woche (Mo–So) als eine Tabelle; das
  /// Datum bestimmt nur, welche Woche angezeigt wird.
  /// Redirects werden nicht verfolgt, damit abgelaufene Sitzungen
  /// (Weiterleitung zur Login-Seite) erkannt werden können.
  Future<http.Response> fetchWeek(String sessionId, String dateString) async {
    final request = http.Request(
      'GET',
      Uri.parse('$_baseUrl?KlaBuDatum=$dateString&RES='),
    );
    request.followRedirects = false;
    request.headers['Cookie'] = 'PHPSESSID=$sessionId';
    request.headers['User-Agent'] = _userAgent;

    return sendWithTimeout(_client, request);
  }

  void close() => _client.close();
}