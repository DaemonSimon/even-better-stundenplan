import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/components/iserv_tasks_view.dart';
import 'package:better_stundenplan/services/iserv_calendar.dart';
import 'package:better_stundenplan/services/iserv_session.dart';

const _emptyPage = '<html><body>Dashboard</body></html>';
const _loginPage = '''
<html><body><form action="/login" method="post">
<input type="text" name="_username">
<input type="password" name="_password">
</form></body></html>
''';

IservSession _session(MockClient client) => IservSession(
  client: client,
  baseUrl: 'https://schule.example.de/iserv',
);

/// Session, deren Login mit einer Nicht-IServ-Exception scheitert.
class _ExplodingLoginSession extends IservSession {
  _ExplodingLoginSession()
    : super(
        client: MockClient((_) async => http.Response(_loginPage, 200)),
        baseUrl: 'https://schule.example.de/iserv',
      );

  @override
  Future<bool> login(String username, String password) async =>
      throw StateError('kaputt');
}

Future<void> _settle(WidgetTester tester) async {
  // Asynchrone Lade-Kette (restore -> isAuthenticated -> fetchTasks).
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<void> _pump(WidgetTester tester, IservSession session) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: IservTasksView(session: session))),
  );
  await _settle(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets(
    'alter Freitext-Termin ("morgen") bringt die Liste nicht zum Absturz',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'iserv_temp_assignments': jsonEncode([
          {
            'id': 1,
            'title': 'Referat',
            'subject': '',
            'teacher': '',
            'due_date': 'morgen',
            'description': '',
            'links': <String>[],
          },
        ]),
      });
      final session = _session(
        MockClient((request) async => http.Response(_emptyPage, 200)),
      );

      await _pump(tester, session);

      expect(tester.takeException(), isNull);
      expect(find.text('Referat'), findsOneWidget);
    },
  );

  testWidgets(
    'unerwarteter Fehler beim Aufgaben-Abruf beendet den Ladezustand',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final session = _session(
        MockClient((request) async {
          // Startseite ok (angemeldet), Aufgaben-Abruf wirft eine
          // Nicht-IServ-Exception.
          if (request.url.path == '/iserv/') {
            return http.Response(_emptyPage, 200);
          }
          throw http.ClientException('Verbindung abgebrochen');
        }),
      );

      await _pump(tester, session);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('IServ nicht erreichbar'), findsOneWidget);
    },
  );

  testWidgets('ohne IServ-Anmeldung erscheint ein deutlicher Hinweis', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = _session(
      MockClient((request) async => http.Response(_loginPage, 200)),
    );

    await _pump(tester, session);

    expect(find.textContaining('Nicht bei IServ angemeldet'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Anmelden'));
    await tester.pump();
    expect(find.text('IServ-Anmeldung'), findsOneWidget);
  });

  testWidgets('angemeldet: kein Anmelde-Hinweis', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = _session(
      MockClient((request) async => http.Response(_emptyPage, 200)),
    );

    await _pump(tester, session);

    expect(find.textContaining('Nicht bei IServ angemeldet'), findsNothing);
  });

  testWidgets('Klausuren und vergangene Aufgaben haben eigene Bereiche', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final table = File(
      'test/fixtures/iserv_exercise_table.html',
    ).readAsStringSync();
    final session = _session(
      MockClient((request) async {
        if (request.url.path == '/iserv/exercise/past/exercise') {
          return http.Response.bytes(
            utf8.encode(table),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        if (request.url.path == '/iserv/exercise/enter') {
          return http.Response('<html><body></body></html>', 200);
        }
        if (request.url.path == '/iserv/') {
          return http.Response(_emptyPage, 200);
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IservTasksView(
            session: session,
            upcomingEvents: [
              IservCalendarEvent(
                id: 'exam',
                title: 'Klausur Deutsch (Klausur) - ITA26-1',
                start: DateTime(2026, 11, 23, 8, 10),
                description: 'Erörterung',
                calendar: 'Klausurplan',
              ),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);

    // Reihenfolge: Termine -> offene Aufgaben -> vergangene Aufgaben.
    final termine = tester.getTopLeft(find.text('Termine (nächste 2 Wochen)'));
    final offen = tester.getTopLeft(find.text('Offene Aufgaben (0)'));
    final vergangen = tester.getTopLeft(find.text('Vergangene Aufgaben (2)'));
    expect(termine.dy, lessThan(offen.dy));
    expect(offen.dy, lessThan(vergangen.dy));

    // Klausur genau einmal, mit Kennzeichnung und Beschreibung.
    expect(find.text('Klausur Deutsch (Klausur) - ITA26-1'), findsOneWidget);
    expect(find.text('Klausur'), findsOneWidget);
    expect(find.text('Erörterung'), findsOneWidget);

    // Vergangene Aufgaben sind eingeklappt.
    expect(find.text('Projekt Netzteil'), findsNothing);
    await tester.tap(find.text('Vergangene Aufgaben (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Projekt Netzteil'), findsOneWidget);

    // Abmelden steht unten statt als Symbol oben.
    expect(find.text('Von IServ abmelden'), findsOneWidget);
  });

  testWidgets(
    'unerwarteter Fehler beim Login beendet den Ladezustand',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, _ExplodingLoginSession());

      await tester.tap(find.widgetWithText(TextButton, 'Anmelden'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Account'), 'a');
      await tester.enterText(find.widgetWithText(TextField, 'Passwort'), 'b');
      await tester.tap(find.text('Anmelden'));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Anmeldung fehlgeschlagen'), findsOneWidget);
    },
  );
}
