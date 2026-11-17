import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:better_stundenplan/pages/iserv_task_page.dart';
import 'package:better_stundenplan/services/iserv_session.dart';
import 'package:better_stundenplan/services/iserv_task_detail.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

const _base = 'https://schule.example.de/iserv';

void main() {
  group('parseTaskDetail', () {
    test('laufende Aufgabe: alle Felder, Dateien und Abgabestatus', () {
      final detail = parseTaskDetail(
        _fixture('iserv_exercise_show.html'),
        baseUrl: _base,
      );

      expect(detail.title, 'Projekt Netzteil');
      expect(detail.status, '');
      expect(
        detail.description,
        'Hallo Klasse,\n\n'
        'bitte bearbeitet die Arbeitsblätter.\nAbgabe als PDF.\n\n'
        '• Deckblatt\n\n• Ergebnisse',
      );
      expect(detail.author, 'Max Muster');
      expect(detail.authorEmail, 'max.muster@schule.example.de');
      expect(detail.start, '10.11.2026 13:45');
      expect(detail.due, '15.12.2026 15:00');
      expect(
        detail.dueDate,
        DateTime.parse('2026-12-15T15:00:00+01:00').toLocal(),
      );

      expect(detail.attachments.map((a) => a.name), [
        '1.0 Schaltplan.pdf',
        'Bild.jpg',
      ]);
      expect(detail.attachments.first.size, '58.36 KB');
      expect(
        detail.attachments.first.downloadUrl,
        'https://schule.example.de/iserv/fs/download/exercise-dl/111/'
        '1.0%20Schaltplan.pdf',
      );

      expect(
        detail.submissionStatus,
        'Es wurden noch keine Dateien eingereicht.',
      );
      expect(detail.submittedFiles, isEmpty);
    });

    test('beendete Aufgabe: Status-Hinweis und Anhang', () {
      final detail = parseTaskDetail(
        _fixture('iserv_exercise_show_past.html'),
        baseUrl: _base,
      );

      expect(detail.title, 'Bruchterme');
      expect(detail.status, 'Die Aufgabe ist beendet.');
      expect(detail.description, 'Hallo Klasse,\n\nAufgabe 1 und 2 komplett.');
      expect(detail.author, 'Erika Beispiel');
      expect(detail.attachments.single.name, 'Bruchterme.pdf');
    });

    test('erkennt Detail-Links laufender und vergangener Aufgaben', () {
      expect(isTaskDetailUrl('$_base/exercise/show/22419'), isTrue);
      expect(isTaskDetailUrl('$_base/exercise/past/exercise/show/22265'), isTrue);
      expect(isTaskDetailUrl('$_base/exercise'), isFalse);
    });
  });

  testWidgets('Detailseite zeigt Aufgabe im App-Stil', (tester) async {
    final session = IservSession(
      client: MockClient((_) async => http.Response('', 404)),
      baseUrl: _base,
    );
    final detail = parseTaskDetail(
      _fixture('iserv_exercise_show.html'),
      baseUrl: _base,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: IservTaskPage(
          url: '$_base/exercise/show/101',
          session: session,
          loader: () async => detail,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Projekt Netzteil'), findsOneWidget);
    expect(find.text('Max Muster'), findsOneWidget);
    expect(find.textContaining('15.12.2026 15:00'), findsOneWidget);
    expect(find.textContaining('Abgabe als PDF.'), findsOneWidget);
    final list = find.byType(ListView);
    await tester.dragUntilVisible(
      find.text('1.0 Schaltplan.pdf'),
      list,
      const Offset(0, -200),
    );
    expect(find.text('Dateien (2)'), findsOneWidget);
    expect(find.text('1.0 Schaltplan.pdf'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('In IServ abgeben'),
      list,
      const Offset(0, -200),
    );
    expect(find.text('Es wurden noch keine Dateien eingereicht.'), findsOneWidget);
    expect(find.text('In IServ abgeben'), findsOneWidget);
  });
}
