import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:better_stundenplan/pages/homework_list_page.dart';
import 'package:better_stundenplan/services/klassenbuch_api.dart';

String _fixtureHtml() =>
    File('test/fixtures/klassenbuch.html').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('in.eike.better_stundenplan/homework'),
      (methodCall) async {
        if (methodCall.method == 'getHomework') {
          final subject = (methodCall.arguments as Map)['subject'];
          if (subject == 'DE') {
            return <dynamic>[
              <String, dynamic>{'content': 'Geteilte Nutzeraufgabe', 'author_id': 'max@example.de'},
            ];
          }
          return <dynamic>[];
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('in.eike.better_stundenplan/homework'),
      null,
    );
  });

  KlassenbuchApi buildKlassenbuchApi() => KlassenbuchApi(
    client: MockClient(
      (request) async => http.Response(_fixtureHtml(), 200),
    ),
  );

  Future<void> pumpPage(WidgetTester tester, String subject) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeworkListPage(
          subject: subject,
          sessionId: 'valid-session',
          klassenbuchApi: buildKlassenbuchApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('zeigt Klassenbuch-Hausaufgaben oben und Nutzer-Hausaufgaben unten', (
    tester,
  ) async {
    await pumpPage(tester, 'DE');

    expect(find.textContaining('Fünf-Schritt-Lesemethode'), findsOneWidget);
    expect(find.textContaining('AB04 Die Arbeitswelt im Wandel'), findsOneWidget);
    expect(find.text('Geteilte Nutzeraufgabe'), findsOneWidget);

    final webY = tester.getTopLeft(
      find.textContaining('Fünf-Schritt-Lesemethode'),
    ).dy;
    final userY = tester.getTopLeft(
      find.text('Geteilte Nutzeraufgabe'),
    ).dy;
    expect(userY, greaterThan(webY));
  });

  testWidgets('ohne Klassenbuch-Einträge bleibt nur die Nutzer-Hausaufgabe', (
    tester,
  ) async {
    await pumpPage(tester, 'MA');

    expect(find.textContaining('Formel AB'), findsOneWidget);
    expect(find.text('Geteilte Nutzeraufgabe'), findsNothing);
  });

  testWidgets('ohne Sitzungs-ID werden nur geteilte Hausaufgaben gezeigt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeworkListPage(
          subject: 'DE',
          klassenbuchApi: buildKlassenbuchApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Geteilte Nutzeraufgabe'), findsOneWidget);
  });

  testWidgets('leere Anzeige zeigt Meldung', (tester) async {
    await pumpPage(tester, 'PH');

    expect(find.text('keine eingetragenen Hausaufgaben'), findsOneWidget);
  });
}
