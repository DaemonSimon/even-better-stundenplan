import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'demo_mode.dart';
import 'http_timeout.dart';

/// Ein Eintrag des Kollegiums: Kürzel, voller Name, Foto-URL.
class TeacherEntry {
  const TeacherEntry({
    required this.kuerzel,
    required this.fullName,
    this.photoUrl,
  });

  final String kuerzel;
  final String fullName;

  /// Absoluter URL des Portrait-Fotos (oder null, wenn keins existiert).
  final String? photoUrl;

  Map<String, dynamic> toJson() => {
    'kuerzel': kuerzel,
    'fullName': fullName,
    'photoUrl': photoUrl,
  };

  /// Liest beide Cache-Formate: das aktuelle mit vollen Schlüsseln sowie
  /// das alte mit gekürzten Schlüsseln (k/n/p).
  factory TeacherEntry.fromJson(Map<String, dynamic> json) => TeacherEntry(
    kuerzel: (json['kuerzel'] ?? json['k']) as String,
    fullName: (json['fullName'] ?? json['n']) as String,
    photoUrl: (json['photoUrl'] ?? json['p']) as String?,
  );
}

/// Nachschlage-Funktion: Kürzel -> Kollegiums-Eintrag (oder null).
typedef TeacherLookup = TeacherEntry? Function(String kuerzel);

/// Zerlegt einen Lehrkraft-Eintrag mit optionalem Präfix (z. B. "A:KREP")
/// in Präfix ("A") und Kürzel ("KREP"). Ohne Doppelpunkt ist [prefix]
/// null und [kuerzel] der komplette Eintrag.
({String? prefix, String kuerzel}) splitTeacherPrefix(String raw) {
  final trimmed = raw.trim();
  final colon = trimmed.indexOf(':');
  if (colon <= 0 || colon >= trimmed.length - 1) {
    return (prefix: null, kuerzel: trimmed);
  }
  return (
    prefix: trimmed.substring(0, colon).trim(),
    kuerzel: trimmed.substring(colon + 1).trim(),
  );
}

/// Scraped die Kollegiums-Seite der BBS Papenburg
/// (https://start.bbs-papenburg.de/kollegium.php) und bildet die
/// Lehrkraft-Kürzel auf die vollen Namen ab.
class TeacherDirectory {
  TeacherDirectory({http.Client? client, String? baseUrl})
    : _client = client ?? DemoAwareClient(),
      _baseUrl = baseUrl ?? 'https://start.bbs-papenburg.de/kollegium.php',
      _origin = Uri.parse(
        baseUrl ?? 'https://start.bbs-papenburg.de/kollegium.php',
      ).origin;

  static const String _userAgent =
      'BetterStundenplan/1.5.2 (+https://github.com/LarvenStein/better-stundenplan)';

  final http.Client _client;
  final String _baseUrl;
  final String _origin;

  /// Lädt die Seite und parst alle Lehrkräfte.
  Future<Map<String, TeacherEntry>> fetch() async {
    final request = http.Request('GET', Uri.parse(_baseUrl));
    request.headers['User-Agent'] = _userAgent;

    final response = await sendWithTimeout(_client, request);

    if (response.statusCode != 200) {
      throw http.ClientException(
        'Kollegium-Seite antwortete mit HTTP ${response.statusCode}',
      );
    }
    return parse(response.body, origin: _origin);
  }

  /// Parst die Kollegiums-Seite. Unterstützt das aktuelle Layout
  /// (`article.bb-person` mit `<span class="kol-kuerzel">`, seit 11/2026)
  /// und das alte (`.lehrer-card` mit "Kürzel: <strong>…").
  static Map<String, TeacherEntry> parse(
    String htmlString, {
    String origin = '',
  }) {
    final entries = <String, TeacherEntry>{};
    final document = html.parse(htmlString);

    for (final card in document.querySelectorAll(
      '.bb-person, [data-bb-eintrag], .lehrer-card',
    )) {
      final name = card.querySelector('h3')?.text.trim() ?? '';
      if (name.isEmpty) continue;

      final kuerzel = _kuerzelOf(card);
      if (kuerzel == null || kuerzel.isEmpty) continue;

      final src = card.querySelector('img')?.attributes['src']?.trim() ?? '';
      final photoUrl = src.isEmpty ? null : _absoluteUrl(origin, src);

      entries.putIfAbsent(
        kuerzel.toUpperCase(),
        () =>
            TeacherEntry(kuerzel: kuerzel, fullName: name, photoUrl: photoUrl),
      );
    }

    return entries;
  }

  /// Kürzel einer Karte: eigenes Element, sonst "Kürzel: <strong>…",
  /// sonst die Element-ID (`kuerzel-ATWT`).
  static String? _kuerzelOf(Element card) {
    final tagged = card.querySelector('.kol-kuerzel')?.text.trim();
    if (tagged != null && tagged.isNotEmpty) return tagged;

    for (final paragraph in card.querySelectorAll('p')) {
      if (!paragraph.text.contains('Kürzel')) continue;
      final marked = paragraph.querySelector('strong, span, b')?.text.trim();
      if (marked != null && marked.isNotEmpty) return marked;
      final match = RegExp(r'Kürzel:\s*(\S+)').firstMatch(paragraph.text);
      if (match != null) return match.group(1);
    }

    final id = card.id;
    if (id.startsWith('kuerzel-') && id.length > 8) return id.substring(8);
    return null;
  }

  /// Macht aus einem relativen Pfad (z. B. "images/.../x.jpg") eine
  /// absolute URL.
  static String? _absoluteUrl(String origin, String src) {
    if (src.startsWith('http://') || src.startsWith('https://')) return src;
    if (origin.isEmpty) return null;
    return '$origin/${src.replaceFirst(RegExp(r'^/+'), '')}';
  }
}
