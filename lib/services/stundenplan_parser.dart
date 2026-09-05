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

  // Spalten der Wochen-Tabelle: Std. | Mo | Di | Mi | Do | Fr | Sa | So
  // Wir lesen Mo (Index 1) bis Fr (Index 5), Sa/So (Index 6/7) entfallen.
  static const int _firstDayColumn = 1;
  static const int _dayCount = 5;

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

  /// Parst die Wochen-Antwort in die Unterrichtsstunden von Mo bis Fr.
  ///
  /// Die LK-Tabelle ist selbsterklärend – jede Zelle enthält
  /// `LEHRER, RAUM (FACH)` (z. B. `HSWT, A101 (L02T)`), ein Raum ohne
  /// Fach ist erlaubt (`SWET, B004`), mehrere parallele Kurse werden per
  /// `<br>` getrennt, und `-`/leere Zellen bleiben frei.
  ///
  /// Liefert 5 Listen von [TimeSlot] (Mo, Di, Mi, Do, Fr). Die Datums-
  /// Zuordnung übernimmt der Aufrufer (Repository).
  List<List<TimeSlot>> parseWeeklyTimetable(String htmlString) {
    // Ein Eintrag je Wochentag (Mo=0 .. Fr=4).
    final week = List.generate(_dayCount, (_) => <TimeSlot>[]);

    try {
      final document = html.parse(htmlString);

      final teacherTable = _findTable(document, _teacherSelectors);
      final lessonTable = _findTable(document, _lessonSelectors);
      final roomTable = _findTable(document, _roomSelectors);

      // Ohne LK-Tabelle (oder irgendeine Tabelle) gibt es keine Daten.
      if (teacherTable == null && lessonTable == null && roomTable == null) {
        return week;
      }

      final teachers = _extractTableCells(teacherTable);
      final lessons = _extractTableCells(lessonTable);
      final rooms = _extractTableCells(roomTable);

      final maxRows = [
        teachers.length,
        lessons.length,
        rooms.length,
      ].reduce((a, b) => a > b ? a : b);

      if (maxRows == 0) return week;

      // Daten zeilenweise (pro Stunde) und spaltenweise (pro Wochentag)
      // kombinieren.
      for (int i = 0; i < maxRows; i++) {
        for (int day = 0; day < _dayCount; day++) {
          final row = _combineTableCell(
            board: teachers, row: i, day: day,
          );
          final rowLessons = _combineTableCell(
            board: lessons, row: i, day: day,
          );
          final rowRooms = _combineTableCell(
            board: rooms, row: i, day: day,
          );

          final lessonEntries = _buildLessons(row, rowLessons, rowRooms);
          if (lessonEntries.isNotEmpty) {
            week[day].add(TimeSlot(period: i + 1, lessons: lessonEntries));
          }
        }
      }
    } catch (_) {
      // Bei Parse-Fehlern leere Woche zurückgeben.
    }

    return week;
  }

  /// Holt für eine Tabellen-"Spalte" (Wochentag) einer Zeile (Stunde) die
  /// einzelnen Einträge (durch `<br>` getrennt).
  List<String> _combineTableCell({
    required List<List<List<String>>> board,
    required int row,
    required int day,
  }) {
    if (row >= board.length) return const [];
    final days = board[row];
    final dayIndex = day + _firstDayColumn;
    if (dayIndex >= days.length) return const [];
    return days[dayIndex];
  }

  /// Baut aus Lehrer-/Fach-/Raum-Einträgen einer Stunde die LessonEntrys.
  /// Bevorzugt die selbsterklärende LK-Tabelle (`LEHRER, RAUM (FACH)`).
  /// Fehlt die LK-Infos (z. B. nur Fächer/Räume), werden die Werte der
  /// getrennten Tabellen zeilenweise kombiniert.
  List<LessonEntry> _buildLessons(
    List<String> teachers,
    List<String> lessons,
    List<String> rooms,
  ) {
    final result = <LessonEntry>[];

    // Fall 1: Lehrkraft-Zellen (selbsterklärend oder einzeln).
    var usedTeacher = false;
    for (int j = 0; j < teachers.length; j++) {
      final lesson = j < lessons.length ? lessons[j] : '';
      final room = j < rooms.length ? rooms[j] : '';
      final entry = _fromTeacherCell(teachers[j], lesson, room);
      if (entry != null) {
        result.add(entry);
        usedTeacher = true;
      }
    }
    if (usedTeacher) return result;

    // Fall 2: getrennte Fächer-/Räume-Tabellen kombinieren.
    final max = [
      teachers.length,
      lessons.length,
      rooms.length,
    ].reduce((a, b) => a > b ? a : b);
    for (int j = 0; j < max; j++) {
      final lesson = j < lessons.length ? lessons[j] : '';
      final teacher = j < teachers.length ? teachers[j] : '';
      final room = j < rooms.length ? rooms[j] : '';
      final entry = LessonEntry(
        lesson: lesson.isEmpty ? ' ' : lesson,
        teacher: teacher.isEmpty ? ' ' : teacher,
        room: room.isEmpty ? ' ' : room,
      );
      if (!entry.isEmpty) result.add(entry);
    }
    return result;
  }

  /// Zerlegt eine Lehrkraft-Zelle der Form `LEHRER, RAUM (FACH)`.
  /// Liefert null, wenn die Zelle leer ist.
  LessonEntry? _fromTeacherCell(String raw, String lesson, String room) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final open = trimmed.lastIndexOf('(');
    final close = trimmed.lastIndexOf(')');

    // "Lehrer, Raum (Fach)"
    if (open > 0 && close > open) {
      final teacherRoom = trimmed.substring(0, open).trim();
      final embeddedLesson = trimmed.substring(open + 1, close).trim();
      final parts = _splitTeacherRoom(teacherRoom);
      return LessonEntry(
        lesson: embeddedLesson.isEmpty ? ' ' : embeddedLesson,
        teacher: parts.teacher,
        room: parts.room.isEmpty ? ' ' : parts.room,
      );
    }

    // "Lehrer, Raum" (ohne Fach) oder reine Lehrkraft.
    final parts = _splitTeacherRoom(trimmed);
    return LessonEntry(
      lesson: lesson.isEmpty ? ' ' : lesson,
      teacher: parts.teacher,
      room: (parts.room.isNotEmpty && parts.room != ' ')
          ? parts.room
          : (room.isEmpty ? ' ' : room),
    );
  }

  /// Trennt den Vorderteil `LEHRER, RAUM` in zwei Teile.
  ({String teacher, String room}) _splitTeacherRoom(String value) {
    final comma = value.indexOf(',');
    if (comma <= 0) {
      return (teacher: value.trim(), room: ' ');
    }
    return (
      teacher: value.substring(0, comma).trim(),
      room: value.substring(comma + 1).trim(),
    );
  }

  /// Findet die passende Tabelle anhand mehrerer Selektoren.
  dom.Element? _findTable(dom.Document document, List<String> selectors) {
    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null) return element;
    }
    return null;
  }

  /// Extrahiert pro Datenzeile (Stunde) eine Liste von Spalten; jede
  /// Spalte ist eine Liste von Einträgen (durch `<br>` getrennt).
  List<List<List<String>>> _extractTableCells(dom.Element? table) {
    final result = <List<List<String>>>[];

    if (table == null) return result;

    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return result;

    // Header-Zeile (Index 0) überspringen.
    for (int i = 1; i < rows.length; i++) {
      final cells = rows[i].querySelectorAll('td');
      if (cells.isEmpty) continue;

      final columns = <List<String>>[];
      for (final cell in cells) {
        columns.add(_extractCellValues(cell));
      }
      result.add(columns);
    }

    return result;
  }

  /// Extrahiert Textwerte aus einer Tabellenzelle.
  /// Entity-Dekodierung (z. B. &nbsp;) übernimmt der HTML-Parser bereits,
  /// wenn über [dom.Node.text] zugegriffen wird.
  List<String> _extractCellValues(dom.Element cell) {
    final cellValues = <String>[];

    void addPart(String raw) {
      final cleanText = _normalizeText(raw);
      if (cleanText.trim().isNotEmpty) {
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
    // Bindestriche in reinen Bereichs-/Platzhalterangaben
    if (RegExp(r'^[-–—]+$').hasMatch(text.trim())) return ' ';
    return text.replaceAll('+ ', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
