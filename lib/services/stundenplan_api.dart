import 'package:http/http.dart' as http;

/// HTTP-Schicht für virtueller-stundenplan.org.
/// Kümmert sich nur um Requests; Parsing passiert im StundenplanParser.
class StundenplanApi {
  StundenplanApi({http.Client? client, String? userAgent})
    : _client = client ?? http.Client(),
      _userAgent =
          userAgent ??
          'BetterStundenplan/1.3.1 (+https://github.com/LarvenStein/better-stundenplan)';

  final http.Client _client;
  final String _userAgent;

  static const String _baseUrl =
      'https://virtueller-stundenplan.org/page2/index.php';

  /// Lädt die Tagesansicht für ein Datum (Format dd.MM.yyyy).
  /// Redirects werden nicht verfolgt, damit abgelaufene Sitzungen
  /// (Weiterleitung zur Login-Seite) erkannt werden können.
  Future<http.Response> fetchDay(String sessionId, String dateString) async {
    final request = http.Request(
      'GET',
      Uri.parse(
        '$_baseUrl?KlaBuDatum=$dateString&HideChangesOff=1&CompactOff=1',
      ),
    );
    request.followRedirects = false;
    request.headers['Cookie'] = 'PHPSESSID=$sessionId';
    request.headers['User-Agent'] = _userAgent;

    final streamedResponse = await _client.send(request);
    return http.Response.fromStream(streamedResponse);
  }

  void close() => _client.close();
}