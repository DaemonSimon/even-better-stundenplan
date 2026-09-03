import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

/// Eine Hausaufgaben-Zeile aus dem Klassenbuch (page-24) von
/// virtueller-stundenplan.org.
class KlassenbuchHomework {
  const KlassenbuchHomework({
    required this.subject,
    required this.date,
    required this.period,
    required this.teacher,
    required this.content,
  });

  /// Fach-Kürzel aus der Spalte "Fach" (z. B. "MA", "DE"). Kann leer
  /// sein, wenn die Eintragung ohne Fach erfasst wurde.
  final String subject;

  /// Datum der Unterrichtsstunde (z. B. "Mo, 17.08.2026").
  final String date;

  /// Stunde/Block der Unterrichtsstunde (z. B. "1").
  final String period;

  /// Lehrkräfte-Kürzel aus der Spalte "LK" (z. B. "TUWT").
  final String teacher;

  /// Text der Hausaufgabe aus der Spalte "Hausaufgaben".
  final String content;

  bool get isEmpty =>
      subject.trim().isEmpty &&
      content.trim().isEmpty;

  Map<String, dynamic> toMap() => {
    'source': 'klassenbuch',
    'subject': subject.trim(),
    'date': date.trim(),
    'period': period.trim(),
    'teacher': teacher.trim(),
    'content': content.trim(),
  };
}

/// Parst die Klassenbuch-Seite (page-24) und extrahiert alle Zeilen mit
/// einer nicht-leeren Hausaufgabe. Enthält kein I/O und ist dadurch
/// vollständig unit-testbar.
class KlassenbuchParser {
  /// Standardspalten der Tabelle (Kopfzeile):
  /// Klasse, Kurs, Datum, Stunde, LK, Fach, Raum, Inhalte, Hausaufgaben.
  static const List<String> _tableSelectors = [
    'table',
    '.table',
  ];

  /// Erkennt, ob die Seite ein Klassenbuch mit Spalte "Hausaufgaben" enthält.
  bool hasKlassenbuchStructure(String htmlString) {
    try {
      final document = html.parse(htmlString);
      return _findHomeworkTable(document) != null;
    } catch (_) {
      return false;
    }
  }

  /// Parst die Klassenbuch-Seite und liefert alle Hausaufgaben-Zeilen.
  /// Leere, "-" oder "NA"-Einträge in der Hausaufgaben-Spalte werden
  /// ignoriert.
  List<KlassenbuchHomework> parseHomework(String htmlString) {
    final result = <KlassenbuchHomework>[];
    try {
      final document = html.parse(htmlString);
      final table = _findHomeworkTable(document);
      if (table == null) return result;

      final rows = table.querySelectorAll('tr');
      if (rows.isEmpty) return result;

      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 9) continue;

        final content = _clean(cells[8].text);
        if (_isEmptyValue(content)) continue;

        result.add(
          KlassenbuchHomework(
            subject: _clean(cells[5].text),
            date: _clean(cells[2].text),
            period: _clean(cells[3].text),
            teacher: _clean(cells[4].text),
            content: content,
          ),
        );
      }
    } catch (_) {
      // Bei Parse-Fehlern leere Liste zurückgeben.
    }
    return result;
  }

  /// Findet die Tabelle, deren Kopfzeile eine Spalte "Hausaufgaben" enthält.
  dom.Element? _findHomeworkTable(dom.Document document) {
    for (final selector in _tableSelectors) {
      for (final table in document.querySelectorAll(selector)) {
        final headers = table.querySelectorAll('th');
        for (final header in headers) {
          if (_clean(header.text).toLowerCase() == 'hausaufgaben') {
            return table;
          }
        }
      }
    }
    return null;
  }

  /// Gibt an, ob eine Hausaufgaben-Zelle als "leer" gilt.
  bool _isEmptyValue(String text) {
    final t = text.trim().toUpperCase();
    return t.isEmpty || t == '-' || t == 'NA' || t == '&nbsp;';
  }

  String _clean(String text) {
    return text.replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
