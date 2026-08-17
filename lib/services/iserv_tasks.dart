import 'package:html/parser.dart' as html;

import 'iserv_session.dart';

/// Eine Aufgabe von der IServ-Aufgaben-Seite.
class IservTask {
  const IservTask({
    required this.title,
    this.subject = '',
    this.teacher = '',
    this.dueDate,
    this.description = '',
    this.links = const [],
  });

  final String title;
  final String subject;
  final String teacher;
  final String? dueDate; // ISO-8601 oder null
  final String description;
  final List<String> links;

  /// Stabile Identität für Mapping-Overrides und De-Duplikation.
  String get key {
    final raw = '$title|$subject|${dueDate ?? ''}';
    return 'iserv:${raw.hashCode.toRadixString(16)}';
  }
}

/// CSS-Selektoren für die Aufgaben-Blöcke und Felder. IServ-Instanzen
/// unterscheiden sich im HTML – bei Bedarf hier ergänzen.
const _taskSelectors = [
  'li.task',
  '.task-item',
  'div.task',
  'tr.task',
  '.task',
];

const _titleSelectors = ['.task-name', '.task-title', 'h3', 'h4', '.title', 'strong'];
const _subjectSelectors = ['.task-subject', '.subject', '.badge', '.tag', '.subject-name'];
const _teacherSelectors = ['.task-teacher', '.teacher', '.author', '.task-author'];
const _dueSelectors = ['.task-due', '.due-date', '.due', '.date', 'time'];
const _descriptionSelectors = ['.task-description', '.task-text', '.description', '.text', 'p'];

final _dateDeRe = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{2,4})');
final _dateIsoRe = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})');
final _timeRe = RegExp(r'(\d{1,2})[.:](\d{2})');

/// Parst deutsche Abgabetermine ("Heute, 12:00", "Morgen, 08:00",
/// "Mo., 17.08.2026, 08:00", ISO-Formate) zu ISO-8601.
String? parseDueDate(String raw) {
  if (raw.isEmpty) return null;
  final text = raw
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[.,\-]+$'), '')
      .toLowerCase();
  if (text.isEmpty) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  DateTime day;
  if (text.startsWith('heute')) {
    day = today;
  } else if (text.startsWith('morgen')) {
    day = today.add(const Duration(days: 1));
  } else {
    final de = _dateDeRe.firstMatch(text);
    if (de != null) {
      var year = int.parse(de.group(3)!);
      if (year < 100) year += 2000;
      day = DateTime(year, int.parse(de.group(2)!), int.parse(de.group(1)!));
    } else {
      final iso = _dateIsoRe.firstMatch(text);
      if (iso == null) return null;
      day = DateTime(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
  }

  // Datums-Fragmente entfernen, damit "17.08" nicht als Uhrzeit gilt.
  final stripped = text
      .replaceAll(_dateDeRe, ' ')
      .replaceAll(_dateIsoRe, ' ');
  final t = _timeRe.firstMatch(stripped);
  if (t != null) {
    final hour = int.parse(t.group(1)!);
    final minute = int.parse(t.group(2)!);
    if (hour < 24 && minute < 60) {
      return DateTime(day.year, day.month, day.day, hour, minute)
          .toIso8601String()
          .substring(0, 16);
    }
  }
  return day.toIso8601String().substring(0, 10);
}

String? _firstText(dynamic block, List<String> selectors) {
  for (final selector in selectors) {
    final node = block.querySelector(selector);
    if (node == null) continue;
    final text = node.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isNotEmpty) return text;
  }
  return null;
}

List<String> _extractLinks(dynamic block, String baseUrl) {
  final links = <String>[];
  for (final anchor in block.querySelectorAll('a[href]')) {
    final href = (anchor.attributes['href'] ?? '').trim();
    if (href.isEmpty ||
        href.startsWith('#') ||
        href.startsWith('javascript:')) {
      continue;
    }
    final absolute = Uri.parse(baseUrl).resolve(href).toString();
    if (!links.contains(absolute)) links.add(absolute);
    if (links.length >= 10) break;
  }
  return links;
}

/// Parst die Aufgaben-Seite in eine de-duplizierte Aufgabenliste.
List<IservTask> parseTasksPage(String htmlText, {String baseUrl = ''}) {
  final doc = html.parse(htmlText);

  var blocks = <dynamic>[];
  for (final selector in _taskSelectors) {
    blocks = doc.querySelectorAll(selector);
    if (blocks.isNotEmpty) break;
  }

  final tasks = <IservTask>[];
  final seen = <String>{};
  for (final block in blocks) {
    final title = _firstText(block, _titleSelectors);
    if (title == null) continue;

    var due = _firstText(block, _dueSelectors);
    if (due == null) {
      final timeNode = block.querySelector('time');
      if (timeNode != null) {
        due = timeNode.attributes['datetime'] ??
            timeNode.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      }
    }

    final task = IservTask(
      title: title,
      subject: _firstText(block, _subjectSelectors) ?? '',
      teacher: _firstText(block, _teacherSelectors) ?? '',
      dueDate: due != null ? parseDueDate(due) : null,
      description: _firstText(block, _descriptionSelectors) ?? '',
      links: _extractLinks(block, baseUrl),
    );
    if (seen.add(task.key)) {
      tasks.add(task);
    }
  }
  return tasks;
}

/// Pfad-Kandidaten der Aufgaben-Seite – IServ-Versionen unterscheiden
/// sich (z. B. `/tasks` vs. `/app/tasks` vs. `/exercise/enter`).
const _tasksPathCandidates = [
  '/tasks',
  '/app/tasks',
  '/tasks/',
  '/exercise/enter',
  '/exercise/',
  '/exercise',
];

/// Holt und parst die Aufgaben-Seite über die Session. Probiert bekannte
/// Pfad-Kandidaten und findet den echten Modul-Pfad über die Links auf
/// der Dashboard-Seite, falls keiner der Kandidaten existiert.
Future<List<IservTask>> fetchTasks(IservSession session) async {
  final candidates = <String>[..._tasksPathCandidates];
  final discovered = await session.discoverModulePath(
    ['task', 'aufgabe', 'homework', 'exercise', 'uebung', 'übung'],
  );
  if (discovered != null && !candidates.contains(discovered)) {
    candidates.add(discovered);
  }
  final tried = <String>[];
  for (final path in candidates) {
    tried.add(path);
    final response = await session.get(path);
    if (response.statusCode == 200) {
      return parseTasksPage(response.body, baseUrl: session.baseUrl);
    }
  }
  final links = await session.discoverModuleLinks();
  final linksText = links.isEmpty
      ? 'keine gefunden (JS-Navigation?)'
      : links.join(', ');
  throw IservException(
    'Aufgaben-Modul nicht gefunden – '
    'versuchte Pfade: ${tried.join(', ')}\n'
    'Modul-Links auf der Startseite: $linksText',
  );
}