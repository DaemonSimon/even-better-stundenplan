import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path_provider/path_provider.dart';

import 'iserv_session.dart';

/// Datei-Anhang einer IServ-Aufgabe.
class IservAttachment {
  const IservAttachment({
    required this.name,
    required this.url,
    this.size = '',
  });

  final String name;
  final String size;

  /// Absoluter Link zum Öffnen der Datei.
  final String url;

  /// Link zum Herunterladen (IServ: `/fs/download/` statt `/fs/file/`).
  String get downloadUrl => url.replaceFirst('/fs/file/', '/fs/download/');
}

/// Detailansicht einer IServ-Aufgabe (`/iserv/exercise/show/<id>`).
class IservTaskDetail {
  const IservTaskDetail({
    required this.title,
    this.status = '',
    this.description = '',
    this.author = '',
    this.authorEmail = '',
    this.start = '',
    this.due = '',
    this.dueDate,
    this.attachments = const [],
    this.submissionStatus = '',
    this.submittedFiles = const [],
  });

  final String title;

  /// Hinweis wie "Die Aufgabe ist beendet." (leer, wenn keiner).
  final String status;
  final String description;
  final String author;
  final String authorEmail;

  /// Starttermin wie angezeigt, z. B. "10.11.2026 13:45".
  final String start;

  /// Abgabetermin wie angezeigt, z. B. "15.12.2026 15:00".
  final String due;

  /// Abgabetermin als Zeitpunkt (aus `data-date`), falls vorhanden.
  final DateTime? dueDate;
  final List<IservAttachment> attachments;

  /// Abgabe-Hinweis, z. B. "Es wurden noch keine Dateien eingereicht."
  final String submissionStatus;
  final List<IservAttachment> submittedFiles;
}

String _clean(String text) =>
    text.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Wandelt den Beschreibungs-HTML-Block in Text mit Absätzen um.
String _paragraphs(dom.Element element) {
  final parts = <String>[];
  for (final child in element.children) {
    if (child.localName == 'ul' || child.localName == 'ol') {
      for (final item in child.querySelectorAll('li')) {
        final text = _clean(item.text);
        if (text.isNotEmpty) parts.add('• $text');
      }
      continue;
    }
    // Zeilenumbrüche innerhalb eines Absatzes erhalten.
    final lines = child.innerHtml
        .split(RegExp(r'<br\s*/?>', caseSensitive: false))
        .map((line) => _clean(html.parseFragment(line).text ?? ''))
        .where((line) => line.isNotEmpty);
    final text = lines.join('\n');
    if (text.isNotEmpty) parts.add(text);
  }
  if (parts.isEmpty) return _clean(element.text);
  return parts.join('\n\n');
}

List<IservAttachment> _attachments(dom.Element? scope, Uri base) {
  if (scope == null) return const [];
  final result = <IservAttachment>[];
  final seen = <String>{};
  for (final row in scope.querySelectorAll('tr')) {
    final link = row.querySelector('a[href*="/fs/file/"]');
    if (link == null) continue;
    final url = base.resolve(link.attributes['href']!).toString();
    if (!seen.add(url)) continue;
    result.add(
      IservAttachment(
        name: _clean(link.text),
        url: url,
        size: _clean(row.querySelector('.text-muted')?.text ?? ''),
      ),
    );
  }
  return result;
}

/// Liest die IServ-Detailseite einer Aufgabe.
IservTaskDetail parseTaskDetail(String source, {String baseUrl = ''}) {
  final doc = html.parse(source);
  final base = Uri.parse(baseUrl.isEmpty ? 'https://localhost/' : baseUrl);

  final panels = doc.querySelectorAll('.panel');
  dom.Element? panelTitled(bool Function(String title) test) {
    for (final panel in panels) {
      final title = panel.querySelector('.panel-title');
      if (title != null && test(_clean(title.text))) return panel;
    }
    return null;
  }

  final taskPanel = panelTitled((t) => t.startsWith('Aufgabe'));
  final submissionPanel = panelTitled((t) => t == 'Abgabe');
  final rawTitle = _clean(taskPanel?.querySelector('.panel-title')?.text ?? '');
  final title = rawTitle.replaceFirst(RegExp(r'^Aufgabe\s*-\s*'), '');

  final description = taskPanel?.querySelector('.text-break-word');
  final metaCells = taskPanel?.querySelectorAll('table.table-condensed tbody td') ??
      const <dom.Element>[];
  final authorLink = metaCells.isNotEmpty
      ? metaCells[0].querySelector('a.mailto')
      : null;
  final dueCell = metaCells.length > 2 ? metaCells[2] : null;
  final dueIso = dueCell
      ?.querySelector('[data-date]')
      ?.attributes['data-date'];

  // Anhänge stehen im Formular "iserv_exercise_attachment" (bei beendeten
  // Aufgaben im selben Panel, bei laufenden im Nachbar-Panel).
  final attachmentForm = doc.querySelector(
    'form[name="iserv_exercise_attachment"]',
  );

  return IservTaskDetail(
    title: title.isEmpty ? _clean(doc.querySelector('h1')?.text ?? '') : title,
    status: _clean(taskPanel?.querySelector('.alert')?.text ?? ''),
    description: description == null ? '' : _paragraphs(description),
    author: _clean(
      authorLink?.attributes['data-name'] ?? authorLink?.text ?? '',
    ),
    authorEmail: (authorLink?.attributes['href'] ?? '')
        .replaceFirst('mailto:', '')
        .split('?')
        .first,
    start: metaCells.length > 1 ? _clean(metaCells[1].text) : '',
    due: _clean(dueCell?.querySelector('li')?.text ?? dueCell?.text ?? ''),
    dueDate: dueIso == null ? null : DateTime.tryParse(dueIso)?.toLocal(),
    attachments: _attachments(attachmentForm, base),
    submissionStatus: _clean(
      submissionPanel?.querySelector('.p-3')?.text ?? '',
    ),
    submittedFiles: _attachments(submissionPanel, base),
  );
}

/// Lädt die Detailseite einer Aufgabe über die IServ-Session.
Future<IservTaskDetail> fetchTaskDetail(
  IservSession session,
  String url,
) async {
  final response = await session.get(url);
  if (response.statusCode != 200) {
    throw IservException('Aufgabe lieferte HTTP ${response.statusCode}');
  }
  return parseTaskDetail(response.body, baseUrl: session.baseUrl);
}

/// Lädt einen Anhang mit der IServ-Session in den Cache-Ordner.
Future<File> downloadAttachment(
  IservSession session,
  IservAttachment attachment,
) async {
  final response = await session.get(attachment.downloadUrl);
  if (response.statusCode != 200) {
    throw IservException('Datei lieferte HTTP ${response.statusCode}');
  }
  final dir = Directory('${(await getTemporaryDirectory()).path}/iserv');
  await dir.create(recursive: true);
  final safeName = attachment.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(response.bodyBytes);
  return file;
}

/// Ist [url] die Detailseite einer IServ-Aufgabe?
bool isTaskDetailUrl(String url) =>
    RegExp(r'/exercise/(past/exercise/)?show/\d+').hasMatch(url);
