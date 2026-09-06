import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

import '../models/timetable.dart';

/// Ein Text-Bestandteil einer Tabellenzelle (durch `<br>` getrennt).
///
/// `struck` = durchgestrichen (z. B. `<del>BSMT</del>`), `substitute` =
/// Text beginnt mit `+` (Vertretungslehrkraft).
class _Run {
  const _Run({
    required this.text,
    this.struck = false,
    this.substitute = false,
  });

  final String text;
  final bool struck;
  final bool substitute;
}

/// Eine "Zelle" (parallelisierter Eintrag innerhalb einer Tabellenzelle)
/// aus einem oder mehreren Text-Runs.
///
/// Eine Vertretung besteht aus mindestens zwei Runs: dem durchgestrichenen
/// Original (`struck`) und dem Vertretungslehrer (`substitute`, beginnt
/// mit `+`).
class _Cell {
  const _Cell({required this.runs});

  final List<_Run> runs;

  bool get isEmpty => runs.isEmpty;

  /// Zusammenhängender Text der Zelle (ohne Format-Markierungen).
  String get plainText => runs.map((r) => r.text).join('').trim();

  /// Erster durchgestrichener Text (der eigentliche Lehrer vor der
  /// Vertretung) oder null.
  String? get originalText {
    for (final run in runs) {
      if (run.struck) return run.text;
    }
    return null;
  }

  /// Erster Vertretungslehrer (Plus-Text, `+ ` bereits entfernt) oder null.
  String? get substituteText {
    for (final run in runs) {
      if (run.substitute) return run.text;
    }
    return null;
  }

  /// Enthält die Zelle eine Vertretung (`+`-Vertreter UND durchgestrichenes
  /// Original)?
  bool get hasSubstitution =>
      substituteText != null && substituteText!.isNotEmpty && originalText != null;
}

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
  /// Die LK-Tabelle liefert pro Zelle das Lehrkraft-Kürzel (oder
  /// selbsterklärend `LEHRER, RAUM (FACH)`); Vertretungen erscheinen als
  /// durchgestrichenes Original und `+ Vertretelehrkraft` (z. B.
  /// `<del>BSMT</del><b> + BDET</b>`). Fach und Raum werden aus den
  /// separaten Fach-/Raum-Tabellen indexiert kombiniert, mehrere parallele
  /// Kurse werden per `<br>` getrennt, und `-`/leere Zellen bleiben frei.
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
  List<_Cell> _combineTableCell({
    required List<List<List<_Cell>>> board,
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
  ///
  /// Bevorzugt die LK-Tabelle. Vertretungen (`+`-Vertreter mit durch-
  /// gestrichenem Original) werden zu EINEM LessonEntry zusammengeführt:
  /// [LessonEntry.teacher] bleibt der eigentliche Lehrer,
  /// [LessonEntry.substituteTeacher] die Vertretungslehrkraft.
  List<LessonEntry> _buildLessons(
    List<_Cell> teachers,
    List<_Cell> lessons,
    List<_Cell> rooms,
  ) {
    final result = <LessonEntry>[];

    // Fall 1: Lehrkraft-Zellen (selbsterklärend oder einzeln).
    var usedTeacher = false;
    for (int j = 0; j < teachers.length; j++) {
      final lesson = j < lessons.length ? lessons[j].plainText : '';
      final room = j < rooms.length ? rooms[j].plainText : '';
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
      final lesson = j < lessons.length ? lessons[j].plainText : '';
      final teacher = j < teachers.length ? teachers[j].plainText : '';
      final room = j < rooms.length ? rooms[j].plainText : '';
      final entry = LessonEntry(
        lesson: lesson.isEmpty ? ' ' : lesson,
        teacher: teacher.isEmpty ? ' ' : teacher,
        room: room.isEmpty ? ' ' : room,
      );
      if (!entry.isEmpty) result.add(entry);
    }
    return result;
  }

  /// Baut einen [LessonEntry] aus einer Lehrkraft-Zelle.
  ///
  /// Vertretungen (`<del>Original</del> … + Vertreter`) werden zu einem
  /// Eintrag zusammengeführt: der eigentliche Lehrer landet in
  /// [LessonEntry.teacher], der Vertreter in
  /// [LessonEntry.substituteTeacher].
  LessonEntry? _fromTeacherCell(_Cell cell, String lesson, String room) {
    if (cell.hasSubstitution) {
      final originalRaw = cell.originalText ?? '';
      final substituteRaw = cell.substituteText ?? '';

      final original = _teacherParts(originalRaw);
      final substitute = _teacherParts(substituteRaw);

      final embeddedLesson = substitute.lesson ?? original.lesson;
      final lessonOut = (embeddedLesson ?? lesson).isEmpty
          ? ' '
          : (embeddedLesson ?? lesson);

      final roomOut = _preferRoom([
        substitute.room,
        original.room,
        room,
      ]);

      return LessonEntry(
        lesson: lessonOut,
        teacher: original.teacher.isNotEmpty
            ? original.teacher
            : substitute.teacher,
        room: roomOut,
        substituteTeacher: substitute.teacher,
      );
    }

    final raw = cell.plainText.trim();
    if (raw.isEmpty) return null;

    final parts = _teacherParts(raw);
    final lessonOut = (parts.lesson ?? lesson).isEmpty ? ' ' : (parts.lesson ?? lesson);
    final roomOut = _preferRoom([parts.room, room]);
    return LessonEntry(
      lesson: lessonOut,
      teacher: parts.teacher,
      room: roomOut,
    );
  }

  /// Erste nicht-leere Option aus [candidates] (Raum mit Fallback).
  String _preferRoom(List<String> candidates) {
    for (final candidate in candidates) {
      if (candidate.trim().isNotEmpty) return candidate;
    }
    return ' ';
  }

  /// Zerlegt einen Lehrkraft-Eintrag: wahlweise selbsterklärend
  /// `LEHRER, RAUM (FACH)` oder nur `LEHRER`.
  /// Liefert Lehrkraft, Raum und ggf. das eingebettete Fach.
  ({String teacher, String room, String? lesson}) _teacherParts(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return (teacher: '', room: ' ', lesson: null);

    final open = trimmed.lastIndexOf('(');
    final close = trimmed.lastIndexOf(')');

    // "Lehrer, Raum (Fach)"
    if (open > 0 && close > open) {
      final teacherRoom = trimmed.substring(0, open).trim();
      final embeddedLesson = trimmed.substring(open + 1, close).trim();
      final parts = _splitTeacherRoom(teacherRoom);
      return (
        teacher: parts.teacher,
        room: parts.room,
        lesson: embeddedLesson.isEmpty ? null : embeddedLesson,
      );
    }

    // "Lehrer, Raum" oder nur "Lehrer".
    final parts = _splitTeacherRoom(trimmed);
    return (teacher: parts.teacher, room: parts.room, lesson: null);
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
  /// Spalte ist eine Liste von Zellen (durch `<br>` getrennt).
  List<List<List<_Cell>>> _extractTableCells(dom.Element? table) {
    final result = <List<List<_Cell>>>[];

    if (table == null) return result;

    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return result;

    // Header-Zeile (Index 0) überspringen.
    for (int i = 1; i < rows.length; i++) {
      final cells = rows[i].querySelectorAll('td');
      if (cells.isEmpty) continue;

      final columns = <List<_Cell>>[];
      for (final cell in cells) {
        columns.add(_extractCellValues(cell));
      }
      result.add(columns);
    }

    return result;
  }

  /// Extrahiert die Zellen (durch `<br>` getrennt) aus einer Tabellenzelle.
  ///
  /// Statt wie früher "nur die fetten Teile" zu nehmen, werden alle
  /// Text-Runs mit ihren Format-Flags erfasst – dadurch bleiben
  /// durchgestrichene Originale und normale Parallelkurse in gemischten
  /// Zellen erhalten.
  List<_Cell> _extractCellValues(dom.Element cell) {
    final cells = <_Cell>[];
    final runs = <_Run>[];

    void flush() {
      if (runs.isNotEmpty) {
        cells.add(_Cell(runs: List.unmodifiable(runs)));
        runs.clear();
      }
    }

    void visit(dom.Node node) {
      if (node is dom.Element && node.localName == 'br') {
        flush();
        return;
      }
      if (node is dom.Text) {
        final raw = node.text;
        if (raw.trim().isEmpty) return;
        runs.add(
          _Run(
            text: _normalizeRunText(raw),
            struck: _hasStrikeAncestor(node, cell),
            substitute: raw.trimLeft().startsWith('+'),
          ),
        );
        return;
      }
      if (node is dom.Element) {
        for (final child in node.nodes) {
          visit(child);
        }
      }
    }

    for (final node in cell.nodes) {
      visit(node);
    }
    flush();
    // Leere Zellen als leere Liste zurückgeben (entspricht einer freien
    // Stunde); mehere aufeinanderfolgende leere Segmente entfallen.
    return cells;
  }

  /// Wandelt `-`/Platzhalter in Leerzeichen um, entfernt ein vorangestelltes
  /// `+` (Vertretungs-Kennzeichen) und faltet Leerzeichen zusammen.
  String _normalizeRunText(String text) {
    if (text == '-') return ' ';
    if (RegExp(r'^[-–—]+$').hasMatch(text.trim())) return ' ';
    var result = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (result.startsWith('+')) result = result.substring(1).trim();
    return result;
  }

  /// Liegt ein Text-Knoten innerhalb eines durchgestrichenen Elements
  /// (`del`, `s`, `strike` oder `text-decoration: line-through`)?
  bool _hasStrikeAncestor(dom.Node node, dom.Element root) {
    var parent = node.parent;
    while (parent != null && parent != root) {
      final name = parent.localName;
      if (name == 'del' || name == 's' || name == 'strike') return true;
      final style = parent.attributes['style'] ?? '';
      if (style.toLowerCase().contains('line-through')) return true;
      parent = parent.parent;
    }
    return false;
  }
}