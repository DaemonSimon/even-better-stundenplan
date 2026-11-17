import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/services/iserv_calendar.dart';
import 'package:better_stundenplan/services/iserv_session.dart';

void main() {
  group('Klausuren', () {
    test('erkennt Klausuren an Titel oder Kalendername', () {
      final byTitle = IservCalendarEvent(
        id: 'a',
        title: 'Klausur Deutsch (Klausur) - ITA26-1',
        start: DateTime(2026, 11, 23, 8, 10),
      );
      final byCalendar = IservCalendarEvent(
        id: 'b',
        title: 'Deutsch',
        start: DateTime(2026, 11, 23, 8, 10),
        calendar: 'Klausurplan',
      );
      final other = IservCalendarEvent(
        id: 'c',
        title: 'Elternabend',
        start: DateTime(2026, 11, 23, 18),
        calendar: 'Öffentlich',
      );

      expect(byTitle.isExam, isTrue);
      expect(byCalendar.isExam, isTrue);
      expect(other.isExam, isFalse);
    });

    test('Kalendername übersteht Speichern und Laden', () {
      final event = IservCalendarEvent(
        id: 'a',
        title: 'Deutsch',
        start: DateTime(2026, 11, 23, 8, 10),
        calendar: 'Klausurplan',
      );

      final restored = IservCalendarEvent.fromJson(event.toJson());

      expect(restored.calendar, 'Klausurplan');
      expect(restored.isExam, isTrue);
    });

    test('Feed-Einträge bekommen den Namen der Kalenderquelle', () {
      final events = parseIservCalendarJson(
        [
          {
            'id': '1',
            'title': 'Deutsch',
            'start': '2026-11-23T08:10:00+01:00',
            'end': '2026-11-23T09:40:00+01:00',
            'description': 'Erörterung',
          },
        ],
        idPrefix: 'exams',
        calendar: 'Klausurplan',
      );

      expect(events.single.calendar, 'Klausurplan');
      expect(events.single.description, 'Erörterung');
      expect(events.single.isExam, isTrue);
    });
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('parst Klausurtermine aus einem iCalendar-Feed', () {
    const feed = r'''
BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:Klausur Mathematik
DTSTART;TZID=Europe/Berlin:20261112T100000
DTEND;TZID=Europe/Berlin:20261112T113000
DESCRIPTION:Kapitel 3\n\,\;
END:VEVENT
END:VCALENDAR
''';

    final events = parseIcalendar(feed);

    expect(events, hasLength(1));
    expect(events.single.title, 'Klausur Mathematik');
    expect(events.single.start, DateTime(2026, 11, 12, 10));
    expect(events.single.end, DateTime(2026, 11, 12, 11, 30));
    expect(events.single.description, 'Kapitel 3\n,;');
  });

  test('parst FullCalendar-Termine aus HTML', () {
    final events = parseIservCalendarHtml('''
      <div class="fc-event" data-title="Klausur Physik"
        data-start="2026-11-13T08:00:00" data-end="2026-11-13T09:30:00"></div>
    ''');

    expect(events, hasLength(1));
    expect(events.single.title, 'Klausur Physik');
    expect(events.single.start, DateTime(2026, 11, 13, 8));
  });

  test('konvertiert UTC-Zeitstempel als absoluten Zeitpunkt', () {
    final events = parseIcalendar(
      'BEGIN:VEVENT\n'
      'SUMMARY:Klausur Englisch\n'
      'DTSTART:20261112T100000Z\n'
      'END:VEVENT\n',
    );

    expect(events.single.start.toUtc(), DateTime.utc(2026, 11, 12, 10));
  });

  test('Kalendertermine bleiben lokal zwischengespeichert', () async {
    final store = IservCalendarStore();
    final event = IservCalendarEvent(
      id: 'exam-1',
      title: 'Klausur Deutsch',
      start: DateTime(2026, 11, 14, 9),
    );

    await store.save([event]);

    final loaded = await IservCalendarStore().load();
    expect(loaded.single.title, 'Klausur Deutsch');
    expect(loaded.single.start, event.start);
  });

  test(
    'lädt den Kalender über eine gültige IServ-Session und ICS-Link',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/iserv/') {
          return http.Response('<html><body>Dashboard</body></html>', 200);
        }
        if (request.url.path == '/iserv/calendar/') {
          return http.Response(
            '<a href="/iserv/calendar/export.ics">iCalendar</a>',
            200,
          );
        }
        if (request.url.path == '/iserv/calendar/export.ics') {
          return http.Response(
            'BEGIN:VCALENDAR\n'
            'BEGIN:VEVENT\n'
            'SUMMARY:Klausur Chemie\n'
            'DTSTART:20261116T090000\n'
            'END:VEVENT\n'
            'END:VCALENDAR\n',
            200,
          );
        }
        return http.Response('', 404);
      });
      final session = IservSession(
        client: client,
        baseUrl: 'https://example.test/iserv',
      );

      final events = await fetchIservCalendar(session);

      expect(events, hasLength(1));
      expect(events.single.title, 'Klausur Chemie');
    },
  );

  test('lädt Kalendertermine über den IServ Kalender-JSON-Feed', () async {
    Uri? calendarRequest;
    final client = MockClient((request) async {
      if (request.url.path == '/iserv/') {
        return http.Response('<html><body>Dashboard</body></html>', 200);
      }
      if (request.url.path == '/iserv/calendar/feed/calendar-multi') {
        calendarRequest = request.url;
        return http.Response(
          '''
          [
            {
              "uid": "math-exam",
              "title": "Klausur Mathematik",
              "start": "2026-11-12T10:00:00",
              "end": "2026-11-12T11:30:00"
            }
          ]
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('', 404);
    });
    final session = IservSession(
      client: client,
      baseUrl: 'https://example.test/iserv',
    );

    final events = await fetchIservCalendar(session);

    expect(calendarRequest, isNotNull);
    expect(
      calendarRequest!.queryParameters.keys,
      containsAll(['start', 'end']),
    );
    expect(events, hasLength(1));
    expect(events.single.id, 'math-exam');
    expect(events.single.title, 'Klausur Mathematik');
    expect(events.single.start, DateTime(2026, 11, 12, 10));
  });

  test('lädt Termine aus allen IServ-Kalendergruppen', () async {
    final requestedFeeds = <String>{};
    final client = MockClient((request) async {
      if (request.url.path == '/iserv/') {
        return http.Response('<html><body>Dashboard</body></html>', 200);
      }
      if (request.url.path == '/iserv/calendar/api/eventsources') {
        return http.Response(
          jsonEncode([
            {'id': 'class', 'url': '/iserv/calendar/feed/class'},
            {'id': 'school', 'url': '/iserv/calendar/feed/school'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.startsWith('/iserv/calendar/feed/')) {
        requestedFeeds.add(request.url.path);
        return http.Response(
          jsonEncode([
            {
              'uid': 'same-id',
              'title': request.url.path.endsWith('/class')
                  ? 'Klassenkalender'
                  : 'Schulkalender',
              'start': '2026-11-12T10:00:00',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('', 404);
    });
    final session = IservSession(
      client: client,
      baseUrl: 'https://example.test/iserv',
    );

    final events = await fetchIservCalendar(session);

    expect(requestedFeeds, {
      '/iserv/calendar/feed/class',
      '/iserv/calendar/feed/school',
    });
    expect(events.map((event) => event.title).toSet(), {
      'Klassenkalender',
      'Schulkalender',
    });
    expect(events.map((event) => event.id).toSet(), {
      'class:same-id',
      'school:same-id',
    });
  });

  test('löst relative ICS-Links relativ zur Kalenderseite auf', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/iserv/') {
        return http.Response('<html><body>Dashboard</body></html>', 200);
      }
      if (request.url.path == '/iserv/calendar/') {
        return http.Response('<a href="export.ics">iCalendar</a>', 200);
      }
      if (request.url.path == '/iserv/calendar/export.ics') {
        return http.Response(
          'BEGIN:VCALENDAR\n'
          'BEGIN:VEVENT\n'
          'SUMMARY:Klausur Biologie\n'
          'DTSTART:20261117T090000\n'
          'END:VEVENT\n'
          'END:VCALENDAR\n',
          200,
        );
      }
      return http.Response('', 404);
    });
    final session = IservSession(
      client: client,
      baseUrl: 'https://example.test/iserv',
    );

    final events = await fetchIservCalendar(session);

    expect(events, hasLength(1));
    expect(events.single.title, 'Klausur Biologie');
  });
}
