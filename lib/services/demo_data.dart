import 'dart:convert';

import 'package:http/http.dart' as http;

/// Alle Inhalte sind erfunden. Die Seiten sind so aufgebaut, wie die Parser
/// der App sie von den echten Seiten erwarten.
const String kDemoPhotoHost = 'demo.invalid';

http.StreamedResponse demoResponse(http.BaseRequest request) {
  final url = request.url;
  final path = url.path;

  http.StreamedResponse reply(
    String body, {
    int status = 200,
    String type = 'text/html',
    Map<String, String> headers = const {},
  }) {
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      contentLength: bytes.length,
      headers: {'content-type': '$type; charset=utf-8', ...headers},
      request: request,
    );
  }

  if (url.host == 'virtueller-stundenplan.org') {
    if (path == '/index.php') {
      return reply('', headers: {'set-cookie': 'PHPSESSID=demo; path=/'});
    }
    return reply(_week);
  }
  if (path.endsWith('/kollegium.php')) return reply(_teachers);

  // Ab hier IServ.
  if (path.endsWith('/login')) {
    if (request.method != 'POST') return reply(_loginForm);
    final fields = request is http.Request
        ? Uri.splitQueryString(request.body)
        : const <String, String>{};
    if (fields['_username']?.toLowerCase() != 'demo' ||
        fields['_password'] != 'demo') {
      return reply(_loginForm);
    }
    return reply(
      '<html><body>Demo</body></html>',
      headers: {'set-cookie': 'IServSession=demo; Path=/'},
    );
  }
  final loggedIn =
      request.headers['cookie']?.contains('IServSession=demo') ?? false;
  if (!loggedIn) return reply(_loginForm);

  if (path.endsWith('/exercise/past/exercise')) {
    return reply(_taskTable([(3, 'Protokoll Messübung', -6)]));
  }
  if (path.contains('/exercise/') && path.contains('/show/')) {
    return reply(_taskDetail(int.tryParse(url.pathSegments.last) ?? 1));
  }
  if (path.contains('/fs/')) {
    return reply(
      'Dies ist eine Beispieldatei aus dem Demo-Modus.\n',
      type: 'text/plain',
    );
  }
  if (path.endsWith('/tasks')) {
    return reply(
      _taskTable([
        (1, 'Netzwerkplan zeichnen', 3),
        (2, 'Referat Energiewende', 9),
      ]),
    );
  }
  if (path.endsWith('/calendar/api/eventsources')) {
    return reply(
      jsonEncode([
        {'id': 'demo', 'label': 'Schule', 'url': '/iserv/calendar/demo'},
      ]),
      type: 'application/json',
    );
  }
  if (path.endsWith('/calendar/demo')) {
    return reply(
      jsonEncode([
        {
          'id': 'k1',
          'title': 'Klausur Mathematik',
          'start': _inDays(5, 8),
          'end': _inDays(5, 10),
        },
        {
          'id': 'k2',
          'title': 'Projekttag',
          'start': _inDays(2, 9),
          'end': _inDays(2, 13),
        },
      ]),
      type: 'application/json',
    );
  }
  if (path.endsWith('/iserv/') || path.endsWith('/iserv')) {
    return reply('<html><body>Demo</body></html>');
  }
  return reply('', status: 404);
}

const _loginForm =
    '<html><body><form><input name="_username">'
    '<input name="_password"></form></body></html>';

DateTime _day(int offset, int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset, hour);
}

String _inDays(int offset, int hour) => _day(offset, hour).toIso8601String();

String _german(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:00';

String _taskTable(List<(int, String, int)> tasks) {
  final rows = [
    for (final (id, title, offset) in tasks)
      '<tr><td><a href="/iserv/exercise/show/$id">$title</a></td>'
          '<td><span data-date="${_inDays(offset, 15)}">'
          '${_german(_day(offset, 15))}</span></td><td>keine</td></tr>',
  ].join();
  return '<html><body><table id="crud-table"><thead><tr><th>Aufgabe</th>'
      '<th>Abgabetermin</th><th>Tags</th></tr></thead>'
      '<tbody>$rows</tbody></table></body></html>';
}

String _taskDetail(int id) {
  final (title, offset) = switch (id) {
    2 => ('Referat Energiewende', 9),
    3 => ('Protokoll Messübung', -6),
    _ => ('Netzwerkplan zeichnen', 3),
  };
  return '<html><body><div class="panel">'
      '<h3 class="panel-title">Aufgabe - $title</h3>'
      '<div class="text-break-word"><p>Beispielaufgabe im Demo-Modus.</p>'
      '</div><table class="table-condensed"><tbody><tr>'
      '<td><a class="mailto" data-name="Erika Beispiel">Erika Beispiel</a></td>'
      '<td>${_german(_day(offset - 7, 8))}</td>'
      '<td><span data-date="${_inDays(offset, 15)}"></span>'
      '${_german(_day(offset, 15))}</td></tr></tbody></table>'
      '<form name="iserv_exercise_attachment"><table><tr><td>'
      '<a href="/iserv/fs/file/demo/$id/Arbeitsblatt.txt">Arbeitsblatt.txt</a>'
      '<span class="text-muted">1 KB</span></td></tr></table></form></div>'
      '</body></html>';
}

String _teacher(String code, String name) =>
    '<article class="bb-person"><img src="https://$kDemoPhotoHost/$code.png">'
    '<h3>$name</h3><span class="kol-kuerzel">$code</span></article>';

final _teachers =
    '<html><body>${_teacher('BEIE', 'Erika Beispiel')}'
    '${_teacher('MUSM', 'Max Muster')}'
    '${_teacher('TESF', 'Frida Test')}</body></html>';

/// Eine Wochentabelle (Mo–Fr, Stunden 1–8); je Tag ein Eintrag pro Stunde.
String _table(String title, List<List<String>> days) {
  final rows = [
    for (var period = 0; period < 8; period++)
      '<tr><td>${period + 1}</td>'
          '${[for (final day in days) '<td>${day[period ~/ 2]}</td>'].join()}'
          '</tr>',
  ].join();
  return '<div data-title="$title"><table id="editableTable">'
      '<tr><th>Std.</th></tr>$rows</table></div>';
}

// Je Tag vier Doppelstunden. Dienstag mit Vertretung, Mittwoch mit Gruppen.
final _week =
    '<html><body>'
    '${_table('LK', [
      ['BEIE', 'MUSM', 'TESF', '-'],
      ['<del>MUSM</del><b> + TESF</b>', 'BEIE', 'MUSM', '-'],
      ['TESF', 'A:BEIE<br>B:MUSM', 'BEIE', 'MUSM'],
      ['MUSM', 'TESF', 'BEIE', '-'],
      ['BEIE', 'TESF', '-', '-'],
    ])}'
    '${_table('Fach', [
      ['MA', 'DE', 'EN', '-'],
      ['PO', 'MA', 'DE', '-'],
      ['SP', 'A:L01P<br>B:L02P', 'EN', 'PH'],
      ['DE', 'PH', 'MA', '-'],
      ['EN', 'PO', '-', '-'],
    ])}'
    '${_table('Raum', [
      ['A101', 'A102', 'B007', '-'],
      ['C119', 'A101', 'A102', '-'],
      ['T1', 'A:C003<br>B:C008', 'B007', 'A301'],
      ['A102', 'A301', 'A101', '-'],
      ['B007', 'C119', '-', '-'],
    ])}'
    '</body></html>';
