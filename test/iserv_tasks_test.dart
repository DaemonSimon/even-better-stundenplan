import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:better_stundenplan/services/iserv_session.dart';
import 'package:better_stundenplan/services/iserv_tasks.dart';

String _fixtureHtml() => File('test/fixtures/aufgaben_page.html').readAsStringSync();

List<int> utf8Bytes(String text) => utf8.encode(text);

void main() {
  group('fetchTasks', () {
    test('findet das Modul über die Dashboard-Links', () async {
      final session = IservSession(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/iserv/')) {
            return http.Response(
              '''
              <html><body>
              <a href="/iserv/messages">Nachrichten</a>
              <a href="/iserv/aufgaben">Aufgaben</a>
              <a href="/iserv/files">Dateien</a>
              </body></html>''',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          if (request.url.path.endsWith('/aufgaben')) {
            return http.Response(_fixtureHtml(), 200,
              headers: {'content-type': 'text/html; charset=utf-8'});
          }
          return http.Response('not found', 404);
        }),
        baseUrl: 'https://schule.example.de/iserv',
      );

      final tasks = await fetchTasks(session);
      expect(tasks, hasLength(4));
    });

    test('wirft mit allen versuchten Pfaden, wenn nichts existiert',
        () async {
      final session = IservSession(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/iserv/')) {
            return http.Response(
              '<html><body><a href="/iserv/files">Dateien</a></body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          return http.Response('not found', 404);
        }),
        baseUrl: 'https://schule.example.de/iserv',
      );

      await expectLater(
        fetchTasks(session),
        throwsA(
          isA<IservException>().having(
            (e) => e.message,
            'message',
            contains('versuchte Pfade'),
          ),
        ),
      );
    });
  });

  group('parseTasksPage', () {
    test('extrahiert alle Felder und de-dupliziert', () {
      final tasks = parseTasksPage(
        _fixtureHtml(),
        baseUrl: 'https://schule.example.de',
      );
      expect(tasks, hasLength(4));

      final math = tasks.firstWhere(
        (t) => t.title.contains('Quadratische'),
      );
      expect(math.subject, 'Mathematik');
      expect(math.teacher, 'Frau Muster');
      expect(math.dueDate, '2026-08-17T08:00');
      expect(math.description, contains('Buch S. 45'));
      expect(
        math.links,
        contains('https://schule.example.de/files/uebungsblatt7.pdf'),
      );
      expect(math.key, startsWith('iserv:'));

      final english = tasks.firstWhere((t) => t.title.contains('Vokabeln'));
      expect(english.subject, 'Englisch');
      expect(english.teacher, 'Mr Smith');
      expect(english.dueDate, '2026-08-18T16:30');

      final art = tasks.firstWhere((t) => t.title.contains('Kunst'));
      expect(art.subject, 'Kunst');
      expect(art.dueDate, startsWith(DateTime.now().toIso8601String().substring(0, 10)));
      expect(art.links, isEmpty);
    });

    test('leeres HTML liefert keine Aufgaben', () {
      expect(parseTasksPage('<html><body><p>keine</p></body></html>'), isEmpty);
    });
  });

  group('parseTasksPage (echte IServ-Tabelle)', () {
    final tableHtml = File(
      'test/fixtures/iserv_exercise_table.html',
    ).readAsStringSync();

    test('liest Titel, Abgabetermin, Tags und Link aus #crud-table', () {
      final tasks = parseTasksPage(
        tableHtml,
        baseUrl: 'https://schule.example.de/iserv',
      );

      expect(tasks, hasLength(2));
      expect(tasks[0].title, 'Projekt Netzteil');
      expect(tasks[0].dueDate, '2026-12-15T15:00');
      expect(tasks[0].subject, ''); // Tags "keine"
      expect(tasks[0].links, [
        'https://schule.example.de/iserv/exercise/show/101',
      ]);

      // Ohne data-date: Termin aus dem Listentext.
      expect(tasks[1].title, 'Referat Energiewende');
      expect(tasks[1].dueDate, '2026-12-01T08:00');
      expect(tasks[1].subject, 'Politik');
      expect(tasks[1].links.single, endsWith('/iserv/exercise/show/102'));
    });

    test('leere Tabelle bedeutet keine Aufgaben', () {
      final empty = tableHtml.replaceAll(
        RegExp(r'<tbody>.*</tbody>', dotAll: true),
        '<tbody></tbody>',
      );

      expect(parseTasksPage(empty), isEmpty);
    });

    test('fetchPastTasks liest /exercise/past/exercise', () async {
      final session = IservSession(
        client: MockClient((request) async {
          if (request.url.path == '/iserv/exercise/past/exercise') {
            return http.Response.bytes(
              utf8Bytes(tableHtml),
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          return http.Response('not found', 404);
        }),
        baseUrl: 'https://schule.example.de/iserv',
      );

      final tasks = await fetchPastTasks(session);

      expect(tasks, hasLength(2));
      expect(tasks.first.title, 'Projekt Netzteil');
    });

    test('fetchTasks liest die Tabelle von /exercise/enter', () async {
      final session = IservSession(
        client: MockClient((request) async {
          if (request.url.path == '/iserv/exercise/enter') {
            return http.Response.bytes(
              utf8Bytes(tableHtml),
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          if (request.url.path == '/iserv/') {
            return http.Response('<html><body></body></html>', 200);
          }
          return http.Response('not found', 404);
        }),
        baseUrl: 'https://schule.example.de/iserv',
      );

      final tasks = await fetchTasks(session);

      expect(tasks.map((t) => t.title), [
        'Projekt Netzteil',
        'Referat Energiewende',
      ]);
    });
  });

  group('parseDueDate', () {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    final todayIso = today.toIso8601String().substring(0, 10);
    final tomorrowIso = tomorrow.toIso8601String().substring(0, 10);

    test('relative und deutsche Formate', () {
      expect(parseDueDate('Heute, 12:00'), '${todayIso}T12:00');
      expect(parseDueDate('Morgen, 08:00'), '${tomorrowIso}T08:00');
      expect(parseDueDate('Mo., 17.08.2026, 08:00'), '2026-08-17T08:00');
      expect(parseDueDate('17.08.2026'), '2026-08-17');
      expect(parseDueDate('5.9.26'), '2026-09-05');
      expect(parseDueDate('2026-08-18T16:30'), '2026-08-18T16:30');
    });

    test('Datumsteil zählt nicht als Uhrzeit', () {
      expect(parseDueDate('17.08.2026 08:00'), '2026-08-17T08:00');
    });

    test('unbekannte Eingaben liefern null', () {
      expect(parseDueDate('Abgabe nächste Woche'), isNull);
      expect(parseDueDate(''), isNull);
    });
  });
}