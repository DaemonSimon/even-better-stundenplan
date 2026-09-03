import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/services/klassenbuch_parser.dart';

void main() {
  final parser = KlassenbuchParser();

  String fixture() =>
      File('test/fixtures/klassenbuch.html').readAsStringSync();

  test('erkennt die Klassenbuch-Struktur', () {
    expect(parser.hasKlassenbuchStructure(fixture()), isTrue);
    expect(parser.hasKlassenbuchStructure('<html><body>Hi</body></html>'), isFalse);
  });

  test('extrahiert nur Zeilen mit echter Hausaufgabe', () {
    final entries = parser.parseHomework(fixture());

    // "-"/"NA"/leere Zeilen werden ignoriert: Reihen 1 und 5 fallen weg.
    expect(entries, hasLength(3));

    expect(entries[0].subject, 'DE');
    expect(entries[0].teacher, 'TUWT');
    expect(entries[0].date, 'Mo, 24.08.2026');
    expect(entries[0].period, '6');
    expect(
      entries[0].content,
      'Fünf-Schritt-Lesemethode, AB05 Die Arbeitswelt der Zukunft',
    );

    expect(entries[1].subject, 'DE');
    expect(entries[2].subject, 'MA');
    expect(entries[2].content, 'Formel AB: 7 u. 8');
  });

  test('filtern nach Fach (case-insensitive)', () {
    final entries = parser.parseHomework(fixture());
    final de = entries.where(
      (e) => e.subject.trim().toLowerCase() == 'de',
    );
    expect(de, hasLength(2));
  });

  test('leere Hausaufgaben werden überall als leer erkannt', () {
    expect(parser.parseHomework('<html></html>'), isEmpty);
  });
}
