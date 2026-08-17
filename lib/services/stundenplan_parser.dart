import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

import '../models/timetable.dart';

/// Parsing-Logik für die Stundenplan-Seiten von virtueller-stundenplan.org.
/// Enthält kein I/O und ist dadurch vollständig unit-testbar.
class StundenplanParser {
  // Selektor-Varianten inklusive Fallbacks, falls sich das Seiten-Markup
  // leicht ändert (Anführungszeichen oder Teilstring-Attribute).
  static const List<String> _teacherSelectors = [
    'div[data-title=LK] #editableTable',
    'div[data-title="LK"] #editableTable',
    'div[data-title*="LK"] #editableTable',
  ];

  static const List<String> _lessonSelectors = [
    'div[data-title=Fach] #editableTable',
    'div[data-title="Fach"] #editableTable',
    'div[data-title*="Fach"] #editableTable',
  ];

  static const List<String> _roomSelectors = [
    'div[data-title=Raum] #editableTable',
    'div[data-title="Raum"] #editableTable',
    'div[data-title*="Raum"] #editableTable',
  ];

  /// Prüft, ob die Seite die für Stundenpläne erwartete Struktur enthält.
  bool hasTimetableStructure(String htmlString) {
    final document = html.parse(htmlString);
    return _findTable(document, _teacherSelectors) != null ||
        _findTable(document, _lessonSelectors) != null ||
        _findTable(document, _roomSelectors) != null;
  }

  /// Erkennt die Login-Seite, die bei abgelaufener Sitzung ausgeliefert wird.
  bool isLoginPage(String htmlString) {
    final lowered = htmlString.toLowerCase();
    return lowered.contains('schuelercode') && lowered.contains('formaction');
  }

  /// Parst die Antwort in Zeitfenster (Unterrichtsstunden).
  /// Liefert eine leere Liste, wenn keine Tabellen gefunden wurden.
  List<TimeSlot> parseDayTimetable(String htmlString) {
    final timeSlots = <TimeSlot>[];

    try {
      final document = html.parse(htmlString);

      final teacherTable = _findTable(document, _teacherSelectors);
      final lessonTable = _findTable(document, _lessonSelectors);
      final roomTable = _findTable(document, _roomSelectors);

      // Keine Tabelle gefunden -> leere Liste
      if (teacherTable == null && lessonTable == null && roomTable == null) {
        return timeSlots;
      }

      final teachers = _extractTableColumnData(teacherTable);
      final lessons = _extractTableColumnData(lessonTable);
      final rooms = _extractTableColumnData(roomTable);

      final maxRows = [
        teachers.length,
        lessons.length,
        rooms.length,
      ].reduce((a, b) => a > b ? a : b);

      if (maxRows == 0) {
        return timeSlots;
      }

      // Daten aus allen drei Tabellen zeilenweise kombinieren
      for (int i = 0; i < maxRows; i++) {
        final rowTeachers = i < teachers.length ? teachers[i] : [''];
        final rowLessons = i < lessons.length ? lessons[i] : [''];
        final rowRooms = i < rooms.length ? rooms[i] : [''];

        final lessonEntries = _combineLessonData(
          rowTeachers,
          rowLessons,
          rowRooms,
        );

        if (lessonEntries.isNotEmpty) {
          timeSlots.add(TimeSlot(period: i + 1, lessons: lessonEntries));
        }
      }
    } catch (_) {
      // Bei Parse-Fehlern leere Liste zurückgeben
    }

    return timeSlots;
  }

  /// Findet die passende Tabelle anhand mehrerer Selektoren.
  dom.Element? _findTable(dom.Document document, List<String> selectors) {
    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null) return element;
    }
    return null;
  }

  /// Extrahiert die Spaltendaten aus einer Tabelle (ab Zeile 1, Spalte 2).
  List<List<String>> _extractTableColumnData(dom.Element? table) {
    final columnData = <List<String>>[];

    if (table == null) return columnData;

    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return columnData;

    // Header-Zeile (Index 0) überspringen
    for (int i = 1; i < rows.length; i++) {
      final cells = rows[i].querySelectorAll('td');

      // Zweite Spalte (Index 1) verwenden, falls vorhanden
      if (cells.length > 1) {
        final cellValues = _extractCellValues(cells[1]);
        columnData.add(cellValues.isEmpty ? [''] : cellValues);
      }
    }

    return columnData;
  }

  /// Extrahiert Textwerte aus einer Tabellenzelle.
  /// Entity-Dekodierung (z. B. &nbsp;) übernimmt der HTML-Parser bereits,
  /// wenn über [dom.Node.text] zugegriffen wird.
  List<String> _extractCellValues(dom.Element cell) {
    final cellValues = <String>[];

    void addPart(String raw) {
      final cleanText = _normalizeText(raw);
      if (cleanText.isNotEmpty) {
        cellValues.add(cleanText);
      }
    }

    // Fett gedruckte Elemente (neue/geänderte Werte)
    final boldElements = cell.querySelectorAll('b');

    if (boldElements.isNotEmpty) {
      for (final bold in boldElements) {
        addPart(bold.text);
      }
    } else {
      final brTags = cell.querySelectorAll('br');

      if (brTags.isNotEmpty) {
        // Mehrere Einträge, durch <br>-Elemente getrennt.
        // Alle Varianten (<br>, <br/>, <br />) sind hier bereits
        // normale br-Elemente.
        final buffer = StringBuffer();
        for (final node in cell.nodes) {
          if (node is dom.Element && node.localName == 'br') {
            addPart(buffer.toString());
            buffer.clear();
          } else {
            buffer.write(node.text ?? '');
          }
        }
        addPart(buffer.toString());
      } else {
        // Einzelner Eintrag
        for (final node in cell.nodes) {
          addPart(node.text ?? '');
        }
      }
    }

    return cellValues;
  }

  /// Normalisiert Text: Striche werden zu Leerzeichen,
  /// überflüssige Leerzeichen werden zusammengefasst.
  String _normalizeText(String text) {
    if (text == '-') return ' ';
    return text.replaceAll('+ ', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Kombiniert Lehrer-, Fach- und Raumdaten zu Unterrichtseinträgen.
  List<LessonEntry> _combineLessonData(
    List<String> teachers,
    List<String> lessons,
    List<String> rooms,
  ) {
    final lessonEntries = <LessonEntry>[];

    final maxEntries = [
      teachers.length,
      lessons.length,
      rooms.length,
    ].reduce((a, b) => a > b ? a : b);

    if (maxEntries == 0) return lessonEntries;

    for (int j = 0; j < maxEntries; j++) {
      final lesson = j < lessons.length ? lessons[j] : '';
      final teacher = j < teachers.length ? teachers[j] : '';
      final room = j < rooms.length ? rooms[j] : '';

      final entry = LessonEntry(
        lesson: lesson.isEmpty ? ' ' : lesson,
        teacher: teacher.isEmpty ? ' ' : teacher,
        room: room.isEmpty ? ' ' : room,
      );

      if (!entry.isEmpty) {
        lessonEntries.add(entry);
      }
    }

    return lessonEntries;
  }
}
