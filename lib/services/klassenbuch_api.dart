import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// HTTP-Schicht für das Klassenbuch (page-24) von
/// virtueller-stundenplan.org. Kümmert sich nur um Requests;
/// Parsing passiert im [KlassenbuchParser].
class KlassenbuchApi {
  KlassenbuchApi({http.Client? client, String? userAgent})
    : _client = client ?? http.Client(),
      _userAgent =
          userAgent ??
          'BetterStundenplan/1.3.1 (+https://github.com/LarvenStein/better-stundenplan)';

  final http.Client _client;
  final String _userAgent;

  static const String _baseUrl =
      'https://virtueller-stundenplan.org/page2/page-24/index.php';

  /// Lädt das Klassenbuch für einen Datumsbereich.
  /// Redirects werden nicht verfolgt, damit abgelaufene Sitzungen
  /// (Weiterleitung zur Login-Seite) erkannt werden können.
  Future<http.Response> fetchKlassenbuch(
    String sessionId, {
    DateTime? von,
    DateTime? bis,
  }) async {
    final vonDate = von ?? DateTime.now();
    // Ein breites Zeitfenster, damit auch bereits vergangene und
    // kommende Hausaufgaben erfasst werden.
    final bisDate = bis ?? vonDate.add(const Duration(days: 180));

    final request = http.Request(
      'GET',
      Uri.parse(
        '$_baseUrl'
        '?KlaBuDatumVon=${DateFormat('dd.MM.yyyy').format(vonDate)}'
        '&KlaBuDatumBis=${DateFormat('dd.MM.yyyy').format(bisDate)}'
        '&ref=',
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
